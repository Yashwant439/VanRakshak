"""
VanRakshak Dataset Preparation Script

Scans raw audio files organized by class and generates a CSV manifest.
Also validates audio files and reports statistics.

Usage:
    python prepare_dataset.py [--data_dir data] [--output dataset.csv]

Expected directory structure:
    data/raw/
    ├── gunshot/
    │   ├── gunshot_001.wav
    │   └── ...
    ├── chainsaw/
    │   ├── chainsaw_001.wav
    │   └── ...
    ├── vehicle/
    ├── forest_ambient/
    └── other/
"""

import os
import argparse
import csv
import random
import soundfile as sf
from pathlib import Path
from collections import Counter

# Valid class labels
VALID_LABELS = {"gunshot", "chainsaw", "vehicle", "forest_ambient", "other"}
SPLIT_RATIOS = {"train": 0.8, "val": 0.1, "test": 0.1}


def get_audio_duration(filepath):
    """Get audio duration in seconds."""
    try:
        info = sf.info(filepath)
        return info.duration
    except Exception:
        return None


def scan_directory(data_dir):
    """Scan raw and augmented directories for audio files."""
    entries = []
    data_path = Path(data_dir)

    for subdir_name in ["raw", "augmented"]:
        subdir = data_path / subdir_name
        if not subdir.exists():
            continue

        is_augmented = subdir_name == "augmented"

        for class_dir in subdir.iterdir():
            if not class_dir.is_dir():
                continue

            class_name = class_dir.name
            if class_name not in VALID_LABELS:
                print(f"  ⚠️  Skipping unknown class: {class_name}")
                continue

            for audio_file in sorted(class_dir.glob("*.wav")):
                duration = get_audio_duration(str(audio_file))
                if duration is None:
                    print(f"  ⚠️  Could not read: {audio_file}")
                    continue

                relative_path = str(audio_file.relative_to(data_path))
                entries.append({
                    "filename": relative_path.replace("\\", "/"),
                    "label": class_name,
                    "duration_s": round(duration, 3),
                    "source": "augmented" if is_augmented else "original",
                    "augmented": str(is_augmented).lower(),
                })

    return entries


def assign_splits(entries):
    """Assign train/val/test splits stratified by class."""
    # Group by class
    by_class = {}
    for entry in entries:
        label = entry["label"]
        if label not in by_class:
            by_class[label] = []
        by_class[label].append(entry)

    # Shuffle and split each class
    for label, items in by_class.items():
        # Separate original and augmented
        originals = [e for e in items if e["augmented"] == "false"]
        augmented = [e for e in items if e["augmented"] == "true"]

        random.shuffle(originals)

        n = len(originals)
        n_val = max(1, int(n * SPLIT_RATIOS["val"]))
        n_test = max(1, int(n * SPLIT_RATIOS["test"]))
        n_train = n - n_val - n_test

        # Assign splits to originals
        for i, entry in enumerate(originals):
            if i < n_train:
                entry["split"] = "train"
            elif i < n_train + n_val:
                entry["split"] = "val"
            else:
                entry["split"] = "test"

        # Augmented data always goes to train
        for entry in augmented:
            entry["split"] = "train"

    return entries


def main():
    parser = argparse.ArgumentParser(description="Prepare dataset CSV for VanRakshak")
    parser.add_argument("--data_dir", default="data", help="Root data directory")
    parser.add_argument("--output", default="data/dataset.csv", help="Output CSV path")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for splits")
    args = parser.parse_args()

    random.seed(args.seed)

    print("Scanning audio files...")
    entries = scan_directory(args.data_dir)

    if not entries:
        print("❌ No audio files found!")
        print(f"   Expected structure: {args.data_dir}/raw/<class_name>/*.wav")
        print(f"   Valid classes: {VALID_LABELS}")
        return

    # Assign splits
    entries = assign_splits(entries)

    # Write CSV
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = ["filename", "label", "duration_s", "source", "split", "augmented"]
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(entries)

    # Print statistics
    print(f"\n✅ Dataset CSV written to: {output_path}")
    print(f"   Total samples: {len(entries)}")

    label_counts = Counter(e["label"] for e in entries)
    split_counts = Counter(e["split"] for e in entries)
    aug_counts = Counter(e["augmented"] for e in entries)

    print("\n   By class:")
    for label, count in sorted(label_counts.items()):
        print(f"     {label:20s} {count:5d}")

    print("\n   By split:")
    for split, count in sorted(split_counts.items()):
        print(f"     {split:10s} {count:5d}")

    print(f"\n   Original: {aug_counts.get('false', 0)}, Augmented: {aug_counts.get('true', 0)}")


if __name__ == "__main__":
    main()
