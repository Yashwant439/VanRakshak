"""
VanRakshak TFLite Conversion Script

Converts a trained Keras model to TFLite with various quantization options.

Usage:
    python convert_tflite.py [options]

    --model_path   Path to trained Keras model (default: output/best_model.keras)
    --output_dir   Output directory (default: output/)
    --data_csv     Dataset CSV for representative dataset (default: data/dataset.csv)
    --data_dir     Root data directory (default: data)
    --quantize     Quantization mode: none, float16, int8, dynamic (default: float16)
"""

import os
import argparse
import numpy as np
import tensorflow as tf
import soundfile as sf
import librosa
import pandas as pd
from pathlib import Path
from tqdm import tqdm
import warnings

warnings.filterwarnings("ignore")

TARGET_SR = 16000
YAMNET_INPUT_SAMPLES = 15600


def load_audio_for_calibration(filepath, data_dir=""):
    """Load a single audio file for calibration."""
    full_path = os.path.join(data_dir, filepath) if data_dir else filepath
    try:
        audio, sr = sf.read(full_path, dtype="float32")
        if len(audio.shape) > 1:
            audio = np.mean(audio, axis=1)
        if sr != TARGET_SR:
            audio = librosa.resample(audio, orig_sr=sr, target_sr=TARGET_SR)
        if len(audio) >= YAMNET_INPUT_SAMPLES:
            start = (len(audio) - YAMNET_INPUT_SAMPLES) // 2
            audio = audio[start : start + YAMNET_INPUT_SAMPLES]
        else:
            pad = YAMNET_INPUT_SAMPLES - len(audio)
            audio = np.pad(audio, (0, pad), mode="constant")
        max_val = np.max(np.abs(audio))
        if max_val > 0:
            audio = audio / max_val
        return audio.astype(np.float32)
    except Exception:
        return None


def representative_dataset_gen(csv_path, data_dir, num_samples=200):
    """Generator for representative dataset used in full integer quantization."""
    df = pd.read_csv(csv_path)
    df = df[df["split"] == "train"].sample(n=min(num_samples, len(df)), random_state=42)

    def generator():
        for _, row in df.iterrows():
            audio = load_audio_for_calibration(row["filename"], data_dir)
            if audio is not None:
                yield [np.expand_dims(audio, axis=0)]

    return generator


def convert_to_tflite(model_path, output_dir, quantize="float16", csv_path=None, data_dir=None):
    """Convert Keras model to TFLite with specified quantization."""
    print(f"Loading model from: {model_path}")
    model = tf.keras.models.load_model(model_path)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    # Apply quantization
    if quantize == "none":
        print("Converting without quantization (float32)...")
        suffix = "f32"

    elif quantize == "float16":
        print("Converting with float16 quantization...")
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]
        suffix = "f16"

    elif quantize == "dynamic":
        print("Converting with dynamic range quantization...")
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        suffix = "dynamic"

    elif quantize == "int8":
        print("Converting with full integer (int8) quantization...")
        if csv_path is None:
            raise ValueError("int8 quantization requires --data_csv for calibration")

        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.representative_dataset = representative_dataset_gen(csv_path, data_dir or "data")
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type = tf.float32  # Keep float input for compatibility
        converter.inference_output_type = tf.float32
        suffix = "int8"

    else:
        raise ValueError(f"Unknown quantization mode: {quantize}")

    # Convert
    tflite_model = converter.convert()

    # Save
    output_path = Path(output_dir) / f"vanrakshak_model_{suffix}.tflite"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(tflite_model)

    # Also save as default name
    default_path = Path(output_dir) / "vanrakshak_model.tflite"
    with open(default_path, "wb") as f:
        f.write(tflite_model)

    # Report size
    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"\n✅ TFLite model saved:")
    print(f"   {output_path} ({size_mb:.2f} MB)")
    print(f"   {default_path} ({size_mb:.2f} MB)")

    # Verify the model
    verify_tflite(str(output_path))

    return str(output_path)


def verify_tflite(model_path):
    """Verify TFLite model by running a dummy inference."""
    print("\nVerifying TFLite model...")

    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    print(f"  Input:  {input_details[0]['shape']} ({input_details[0]['dtype'].__name__})")
    print(f"  Output: {output_details[0]['shape']} ({output_details[0]['dtype'].__name__})")

    # Run dummy inference
    dummy_input = np.random.randn(1, YAMNET_INPUT_SAMPLES).astype(np.float32)
    interpreter.set_tensor(input_details[0]["index"], dummy_input)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]["index"])

    print(f"  Output values (dummy): {output[0]}")
    print(f"  Sum of probabilities: {np.sum(output[0]):.4f} (should be ~1.0)")

    # Benchmark inference time
    import time
    times = []
    for _ in range(20):
        start = time.perf_counter()
        interpreter.set_tensor(input_details[0]["index"], dummy_input)
        interpreter.invoke()
        times.append(time.perf_counter() - start)

    avg_ms = np.mean(times) * 1000
    print(f"  Avg inference time (CPU): {avg_ms:.1f} ms")
    print(f"  ✅ Model verification passed!")


def main():
    parser = argparse.ArgumentParser(description="Convert VanRakshak model to TFLite")
    parser.add_argument("--model_path", default="output/best_model.keras")
    parser.add_argument("--output_dir", default="output")
    parser.add_argument("--data_csv", default="data/dataset.csv")
    parser.add_argument("--data_dir", default="data")
    parser.add_argument("--quantize", default="float16",
                        choices=["none", "float16", "dynamic", "int8"])
    args = parser.parse_args()

    print("=" * 60)
    print("VanRakshak TFLite Conversion")
    print("=" * 60)

    convert_to_tflite(
        model_path=args.model_path,
        output_dir=args.output_dir,
        quantize=args.quantize,
        csv_path=args.data_csv,
        data_dir=args.data_dir,
    )

    print(f"\n🚀 Next steps:")
    print(f"   1. Copy output/vanrakshak_model.tflite → Flutter assets/models/")
    print(f"   2. Copy output/vanrakshak_labels.csv → Flutter assets/labels/")
    print(f"   3. Update ml_service.dart to load the new model")
    print(f"   4. Build and test on device!")


if __name__ == "__main__":
    main()
