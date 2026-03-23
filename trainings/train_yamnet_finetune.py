"""
VanRakshak YAMNet Fine-Tuning Script

Transfer learning: freeze YAMNet feature extractor, replace classification
head with a 5-class dense network for forest threat detection.

Usage:
    python train_yamnet_finetune.py [options]

    --data_csv    Path to dataset CSV (default: data/dataset.csv)
    --epochs      Number of training epochs (default: 50)
    --batch_size  Batch size (default: 32)
    --lr          Learning rate (default: 0.001)
    --output_dir  Output directory for model (default: output/)
    --unfreeze    Unfreeze last N layers of YAMNet (default: 0 = fully frozen)
"""

import os
import argparse
import numpy as np
import pandas as pd
import tensorflow as tf
import tensorflow_hub as hub
import librosa
import soundfile as sf
from pathlib import Path
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.utils.class_weight import compute_class_weight
import matplotlib.pyplot as plt
from tqdm import tqdm
import warnings

warnings.filterwarnings("ignore")

# Constants
TARGET_SR = 16000
YAMNET_INPUT_SAMPLES = 15600  # 0.975s at 16kHz
CLASS_NAMES = ["gunshot", "chainsaw", "vehicle", "forest_ambient", "other"]
NUM_CLASSES = len(CLASS_NAMES)


def load_and_preprocess_audio(filepath, data_dir=""):
    """Load audio file, preprocess for YAMNet input."""
    full_path = os.path.join(data_dir, filepath) if data_dir else filepath

    try:
        audio, sr = sf.read(full_path, dtype="float32")
        if len(audio.shape) > 1:
            audio = np.mean(audio, axis=1)
        if sr != TARGET_SR:
            audio = librosa.resample(audio, orig_sr=sr, target_sr=TARGET_SR)

        # Pad or trim to exactly 0.975s
        if len(audio) >= YAMNET_INPUT_SAMPLES:
            start = (len(audio) - YAMNET_INPUT_SAMPLES) // 2
            audio = audio[start : start + YAMNET_INPUT_SAMPLES]
        else:
            pad = YAMNET_INPUT_SAMPLES - len(audio)
            audio = np.pad(audio, (0, pad), mode="constant")

        # Normalize
        max_val = np.max(np.abs(audio))
        if max_val > 0:
            audio = audio / max_val

        return audio.astype(np.float32)
    except Exception as e:
        print(f"Error loading {full_path}: {e}")
        return None


def create_dataset(csv_path, data_dir, split="train"):
    """Create TF dataset from CSV."""
    df = pd.read_csv(csv_path)
    df = df[df["split"] == split]

    if len(df) == 0:
        raise ValueError(f"No samples found for split '{split}'")

    print(f"  {split}: {len(df)} samples")

    audios = []
    labels = []
    label_to_idx = {name: i for i, name in enumerate(CLASS_NAMES)}

    for _, row in tqdm(df.iterrows(), total=len(df), desc=f"Loading {split}"):
        audio = load_and_preprocess_audio(row["filename"], data_dir)
        if audio is not None and row["label"] in label_to_idx:
            audios.append(audio)
            labels.append(label_to_idx[row["label"]])

    audios = np.array(audios, dtype=np.float32)
    labels = np.array(labels, dtype=np.int32)

    return audios, labels


def build_model(yamnet_model_handle="https://tfhub.dev/google/yamnet/1", unfreeze_layers=0):
    """
    Build transfer learning model:
    YAMNet (frozen) → Embeddings → Dense Head → 5 classes
    """
    # Load YAMNet from TF Hub
    yamnet_layer = hub.KerasLayer(
        yamnet_model_handle,
        trainable=unfreeze_layers > 0,
        name="yamnet",
    )

    # Input: raw waveform [batch, 15600]
    input_audio = tf.keras.Input(shape=(YAMNET_INPUT_SAMPLES,), dtype=tf.float32, name="audio_input")

    # YAMNet returns (scores, embeddings, log_mel_spectrogram)
    # We use embeddings for transfer learning
    scores, embeddings, log_mel = yamnet_layer(input_audio)

    # embeddings shape: [batch, num_frames, 1024]
    # Average across time frames
    avg_embedding = tf.keras.layers.GlobalAveragePooling1D(name="avg_pool")(embeddings)

    # Classification head
    x = tf.keras.layers.Dense(256, activation="relu", name="dense_1")(avg_embedding)
    x = tf.keras.layers.Dropout(0.3, name="dropout_1")(x)
    x = tf.keras.layers.Dense(128, activation="relu", name="dense_2")(x)
    x = tf.keras.layers.Dropout(0.2, name="dropout_2")(x)
    output = tf.keras.layers.Dense(NUM_CLASSES, activation="softmax", name="predictions")(x)

    model = tf.keras.Model(inputs=input_audio, outputs=output, name="vanrakshak_classifier")
    return model


def plot_training_history(history, output_dir):
    """Plot and save training metrics."""
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    # Accuracy
    axes[0].plot(history.history["accuracy"], label="Train")
    axes[0].plot(history.history["val_accuracy"], label="Validation")
    axes[0].set_title("Model Accuracy")
    axes[0].set_xlabel("Epoch")
    axes[0].set_ylabel("Accuracy")
    axes[0].legend()
    axes[0].grid(True)

    # Loss
    axes[1].plot(history.history["loss"], label="Train")
    axes[1].plot(history.history["val_loss"], label="Validation")
    axes[1].set_title("Model Loss")
    axes[1].set_xlabel("Epoch")
    axes[1].set_ylabel("Loss")
    axes[1].legend()
    axes[1].grid(True)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "training_history.png"), dpi=150)
    plt.close()


def plot_confusion_matrix(y_true, y_pred, output_dir):
    """Plot and save confusion matrix."""
    cm = confusion_matrix(y_true, y_pred)
    fig, ax = plt.subplots(figsize=(8, 8))
    im = ax.imshow(cm, interpolation="nearest", cmap=plt.cm.Blues)
    ax.set(
        xticks=np.arange(NUM_CLASSES),
        yticks=np.arange(NUM_CLASSES),
        xticklabels=CLASS_NAMES,
        yticklabels=CLASS_NAMES,
        ylabel="True Label",
        xlabel="Predicted Label",
        title="Confusion Matrix",
    )
    plt.setp(ax.get_xticklabels(), rotation=45, ha="right")

    # Add text annotations
    thresh = cm.max() / 2.0
    for i in range(NUM_CLASSES):
        for j in range(NUM_CLASSES):
            ax.text(j, i, format(cm[i, j], "d"),
                    ha="center", va="center",
                    color="white" if cm[i, j] > thresh else "black")

    fig.colorbar(im)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "confusion_matrix.png"), dpi=150)
    plt.close()


def main():
    parser = argparse.ArgumentParser(description="Train VanRakshak sound classifier")
    parser.add_argument("--data_csv", default="data/dataset.csv")
    parser.add_argument("--data_dir", default="data", help="Root data directory")
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--batch_size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=0.001)
    parser.add_argument("--output_dir", default="output")
    parser.add_argument("--unfreeze", type=int, default=0, help="Unfreeze last N YAMNet layers")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("VanRakshak YAMNet Fine-Tuning")
    print("=" * 60)
    print(f"Classes: {CLASS_NAMES}")
    print(f"Epochs: {args.epochs}, Batch size: {args.batch_size}, LR: {args.lr}")
    print()

    # Load data
    print("Loading dataset...")
    train_X, train_y = create_dataset(args.data_csv, args.data_dir, split="train")
    val_X, val_y = create_dataset(args.data_csv, args.data_dir, split="val")
    test_X, test_y = create_dataset(args.data_csv, args.data_dir, split="test")

    print(f"\nDataset sizes: train={len(train_X)}, val={len(val_X)}, test={len(test_X)}")

    # Compute class weights to handle imbalance
    class_weights = compute_class_weight("balanced", classes=np.unique(train_y), y=train_y)
    class_weight_dict = {i: w for i, w in enumerate(class_weights)}
    print(f"Class weights: {class_weight_dict}")

    # Build model
    print("\nBuilding model...")
    model = build_model(unfreeze_layers=args.unfreeze)
    model.summary()

    # Compile
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=args.lr),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )

    # Callbacks
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_accuracy",
            patience=10,
            restore_best_weights=True,
            verbose=1,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=5,
            min_lr=1e-6,
            verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            str(output_dir / "best_model.keras"),
            monitor="val_accuracy",
            save_best_only=True,
            verbose=1,
        ),
    ]

    # Train
    print("\nTraining...")
    history = model.fit(
        train_X,
        train_y,
        validation_data=(val_X, val_y),
        epochs=args.epochs,
        batch_size=args.batch_size,
        class_weight=class_weight_dict,
        callbacks=callbacks,
        verbose=1,
    )

    # Evaluate on test set
    print("\n" + "=" * 60)
    print("Evaluation on Test Set")
    print("=" * 60)

    test_loss, test_acc = model.evaluate(test_X, test_y, verbose=0)
    print(f"Test Accuracy: {test_acc:.4f}")
    print(f"Test Loss: {test_loss:.4f}")

    # Detailed classification report
    test_pred = np.argmax(model.predict(test_X, verbose=0), axis=1)
    print("\nClassification Report:")
    print(classification_report(test_y, test_pred, target_names=CLASS_NAMES))

    # Save plots
    plot_training_history(history, str(output_dir))
    plot_confusion_matrix(test_y, test_pred, str(output_dir))

    # Save labels CSV
    labels_path = output_dir / "vanrakshak_labels.csv"
    with open(labels_path, "w") as f:
        f.write("index,label\n")
        for i, name in enumerate(CLASS_NAMES):
            f.write(f"{i},{name}\n")

    print(f"\n✅ Training complete!")
    print(f"   Best model: {output_dir / 'best_model.keras'}")
    print(f"   Labels: {labels_path}")
    print(f"   Training plots: {output_dir / 'training_history.png'}")
    print(f"   Confusion matrix: {output_dir / 'confusion_matrix.png'}")
    print(f"\nNext step: python convert_tflite.py --model_path {output_dir / 'best_model.keras'}")


if __name__ == "__main__":
    main()
