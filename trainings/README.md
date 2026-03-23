# VanRakshak ML Training Pipeline

A complete training pipeline for fine-tuning YAMNet for forest threat detection.

## Quick Start

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Prepare dataset (see dataset_design.md)
# Place audio files in data/raw/<class_name>/*.wav
# Then generate the CSV manifest:
python prepare_dataset.py

# 3. Augment data (expands dataset ~10x)
python augment_audio.py

# 4. Train the model
python train_yamnet_finetune.py --epochs 50 --batch_size 32

# 5. Convert to TFLite
python convert_tflite.py --model_path output/best_model.keras

# 6. Deploy
# Copy output/vanrakshak_model.tflite → Flutter assets/models/
# Copy output/vanrakshak_labels.csv → Flutter assets/labels/
```

## Directory Structure

```
training/
├── README.md                    ← This file
├── requirements.txt             ← Python dependencies
├── dataset_design.md            ← Dataset sourcing & labeling guide
├── prepare_dataset.py           ← Generate CSV manifest from audio files
├── augment_audio.py             ← Data augmentation pipeline
├── train_yamnet_finetune.py     ← Transfer learning training script
├── convert_tflite.py            ← TFLite conversion + quantization
├── data/
│   ├── raw/                     ← Original audio files by class
│   │   ├── gunshot/
│   │   ├── chainsaw/
│   │   ├── vehicle/
│   │   ├── forest_ambient/
│   │   └── other/
│   ├── augmented/               ← Generated augmented files
│   └── dataset.csv              ← Master dataset manifest
└── output/
    ├── best_model.keras         ← Best trained model
    ├── vanrakshak_model.tflite  ← Quantized TFLite model
    └── vanrakshak_labels.csv    ← Labels for TFLite model
```

## Approach

### Two-Phase Strategy

**Phase 1 (Already Done): Stock YAMNet**
- The Flutter app already uses stock YAMNet with corrected output mapping
- This gives baseline detection for gunshots (index 421) and chainsaws (index 341)
- Good for clean audio, may struggle in noisy forest environments

**Phase 2 (This Pipeline): Fine-Tuned YAMNet**
- Freeze YAMNet's feature extractor (log-mel spectrogram → embeddings)
- Replace the classification head with a 5-class dense network
- Train on forest-specific audio data with heavy augmentation
- Produces a smaller, faster, more accurate model for our 5 classes

### Target Classes

| Class | Examples | Target Samples |
|-------|----------|----------------|
| `gunshot` | Gunshots, rifle fire, firearms | 2000+ |
| `chainsaw` | Chainsaws, power saws | 2000+ |
| `vehicle` | Cars, trucks, ATVs, motorcycles | 2000+ |
| `forest_ambient` | Birds, wind, rain, insects, streams | 2000+ |
| `other` | Speech, music, machinery, silence | 2000+ |
