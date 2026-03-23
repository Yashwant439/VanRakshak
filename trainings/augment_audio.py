"""
VanRakshak Audio Data Augmentation Pipeline

Expands raw audio dataset ~10x using various augmentation techniques
optimized for forest threat detection.

Usage:
    python augment_audio.py [--input_dir data/raw] [--output_dir data/augmented] [--multiplier 10]
"""

import os
import argparse
import numpy as np
import soundfile as sf
import librosa
from pathlib import Path
from tqdm import tqdm
import warnings

warnings.filterwarnings("ignore")

# Target parameters
TARGET_SR = 16000
TARGET_DURATION = 1.0  # seconds
TARGET_SAMPLES = int(TARGET_SR * TARGET_DURATION)


def load_audio(filepath, sr=TARGET_SR):
    """Load audio file, resample to target SR, convert to mono."""
    try:
        audio, file_sr = sf.read(filepath, dtype="float32")
        if len(audio.shape) > 1:
            audio = np.mean(audio, axis=1)  # stereo to mono
        if file_sr != sr:
            audio = librosa.resample(audio, orig_sr=file_sr, target_sr=sr)
        return audio
    except Exception as e:
        print(f"Error loading {filepath}: {e}")
        return None


def pad_or_trim(audio, target_length=TARGET_SAMPLES):
    """Ensure audio is exactly target_length samples."""
    if len(audio) >= target_length:
        # Random crop
        start = np.random.randint(0, len(audio) - target_length + 1)
        return audio[start : start + target_length]
    else:
        # Zero-pad
        pad_length = target_length - len(audio)
        return np.pad(audio, (0, pad_length), mode="constant")


# --- Augmentation Functions ---


def add_noise(audio, snr_db=15):
    """Add Gaussian white noise at specified SNR."""
    signal_power = np.mean(audio ** 2)
    noise_power = signal_power / (10 ** (snr_db / 10))
    noise = np.random.normal(0, np.sqrt(noise_power), len(audio))
    return (audio + noise).astype(np.float32)


def add_background_noise(audio, noise_audio, snr_db=15):
    """Mix audio with a background noise sample at specified SNR."""
    noise = pad_or_trim(noise_audio, len(audio))
    signal_power = np.mean(audio ** 2) + 1e-10
    noise_power = np.mean(noise ** 2) + 1e-10
    target_noise_power = signal_power / (10 ** (snr_db / 10))
    noise_scaled = noise * np.sqrt(target_noise_power / noise_power)
    return (audio + noise_scaled).astype(np.float32)


def time_stretch(audio, rate=1.0):
    """Time-stretch audio without changing pitch."""
    return librosa.effects.time_stretch(audio, rate=rate)


def pitch_shift(audio, sr=TARGET_SR, n_steps=0):
    """Shift pitch without changing tempo."""
    return librosa.effects.pitch_shift(audio, sr=sr, n_steps=n_steps)


def random_gain(audio, min_db=-6, max_db=6):
    """Apply random gain in dB."""
    gain_db = np.random.uniform(min_db, max_db)
    gain_linear = 10 ** (gain_db / 20)
    return (audio * gain_linear).astype(np.float32)


def time_shift(audio, max_shift_samples=2000):
    """Randomly shift audio in time (circular)."""
    shift = np.random.randint(-max_shift_samples, max_shift_samples)
    return np.roll(audio, shift)


def add_reverb_simple(audio, sr=TARGET_SR, delay_ms=50, decay=0.3):
    """Add a simple reverb effect using delay lines."""
    delay_samples = int(sr * delay_ms / 1000)
    reverbed = np.copy(audio)
    for i in range(delay_samples, len(audio)):
        reverbed[i] += decay * audio[i - delay_samples]
    # Normalize
    max_val = np.max(np.abs(reverbed))
    if max_val > 0:
        reverbed = reverbed / max_val
    return reverbed.astype(np.float32)


def frequency_mask(audio, sr=TARGET_SR, num_masks=1, max_width=20):
    """Apply frequency masking (SpecAugment-style in time domain)."""
    stft = librosa.stft(audio)
    for _ in range(num_masks):
        f = np.random.randint(0, stft.shape[0])
        w = np.random.randint(1, min(max_width, stft.shape[0] - f))
        stft[f : f + w, :] = 0
    return librosa.istft(stft, length=len(audio)).astype(np.float32)


def time_mask(audio, num_masks=1, max_width=1600):
    """Apply time masking (zero out random segments)."""
    masked = np.copy(audio)
    for _ in range(num_masks):
        t = np.random.randint(0, len(audio))
        w = np.random.randint(1, min(max_width, len(audio) - t))
        masked[t : t + w] = 0
    return masked


# --- Augmentation Pipeline ---


def augment_single(audio, sr=TARGET_SR, background_noise=None):
    """Generate multiple augmented versions of a single audio clip."""
    augmented = []

    # 1. White noise at various SNRs
    for snr in [5, 10, 15, 20]:
        aug = add_noise(audio, snr_db=snr)
        augmented.append((aug, f"noise_snr{snr}"))

    # 2. Time stretching
    for rate in [0.85, 0.95, 1.05, 1.15]:
        aug = pad_or_trim(time_stretch(audio, rate=rate))
        augmented.append((aug, f"stretch_{rate}"))

    # 3. Pitch shifting
    for steps in [-2, -1, 1, 2]:
        aug = pitch_shift(audio, sr=sr, n_steps=steps)
        augmented.append((aug, f"pitch_{steps}"))

    # 4. Random gain
    for _ in range(2):
        aug = random_gain(audio, min_db=-8, max_db=8)
        augmented.append((aug, f"gain_{np.random.randint(1000)}"))

    # 5. Time shift
    aug = time_shift(audio)
    augmented.append((aug, "timeshift"))

    # 6. Simple reverb
    for delay in [30, 60]:
        aug = add_reverb_simple(audio, sr=sr, delay_ms=delay)
        augmented.append((aug, f"reverb_{delay}ms"))

    # 7. Frequency masking
    aug = frequency_mask(audio, sr=sr)
    augmented.append((aug, "freqmask"))

    # 8. Time masking
    aug = time_mask(audio)
    augmented.append((aug, "timemask"))

    # 9. Combined: noise + pitch
    aug = add_noise(pitch_shift(audio, sr=sr, n_steps=1), snr_db=15)
    augmented.append((aug, "noise_pitch"))

    # 10. Background noise mixing (if background samples available)
    if background_noise is not None and len(background_noise) > 0:
        for i, bg in enumerate(background_noise[:3]):
            for snr in [5, 10, 15]:
                aug = add_background_noise(audio, bg, snr_db=snr)
                augmented.append((aug, f"bg{i}_snr{snr}"))

    return augmented


def load_background_noise(noise_dir):
    """Load background noise samples for mixing."""
    noises = []
    if noise_dir and os.path.exists(noise_dir):
        for f in Path(noise_dir).glob("*.wav"):
            audio = load_audio(str(f))
            if audio is not None:
                noises.append(audio)
    return noises


def main():
    parser = argparse.ArgumentParser(description="Audio data augmentation for VanRakshak")
    parser.add_argument("--input_dir", default="data/raw", help="Input directory with class subdirectories")
    parser.add_argument("--output_dir", default="data/augmented", help="Output directory for augmented files")
    parser.add_argument("--noise_dir", default="data/raw/forest_ambient", help="Background noise directory")
    parser.add_argument("--max_per_file", type=int, default=10, help="Max augmented versions per file")
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)

    if not input_dir.exists():
        print(f"Input directory {input_dir} does not exist!")
        print("Please place audio files in data/raw/<class_name>/*.wav")
        return

    # Load background noise
    print("Loading background noise samples...")
    bg_noise = load_background_noise(args.noise_dir)
    print(f"Loaded {len(bg_noise)} background noise samples")

    # Process each class
    classes = [d for d in input_dir.iterdir() if d.is_dir()]
    total_generated = 0

    for class_dir in classes:
        class_name = class_dir.name
        class_output = output_dir / class_name
        class_output.mkdir(parents=True, exist_ok=True)

        audio_files = list(class_dir.glob("*.wav")) + list(class_dir.glob("*.mp3"))
        print(f"\nProcessing class '{class_name}': {len(audio_files)} files")

        for audio_file in tqdm(audio_files, desc=class_name):
            audio = load_audio(str(audio_file))
            if audio is None:
                continue

            audio = pad_or_trim(audio)

            augmented = augment_single(
                audio,
                background_noise=bg_noise if class_name != "forest_ambient" else None,
            )

            # Save augmented versions (limit to max_per_file)
            for i, (aug_audio, aug_name) in enumerate(augmented[: args.max_per_file]):
                aug_audio = pad_or_trim(aug_audio)
                aug_audio = np.clip(aug_audio, -1.0, 1.0)

                out_name = f"{audio_file.stem}_{aug_name}.wav"
                out_path = class_output / out_name
                sf.write(str(out_path), aug_audio, TARGET_SR, subtype="PCM_16")
                total_generated += 1

    print(f"\n✅ Augmentation complete! Generated {total_generated} augmented files")
    print(f"   Output directory: {output_dir}")


if __name__ == "__main__":
    main()
