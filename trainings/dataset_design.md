# Dataset Design for VanRakshak

## CSV Format

```csv
filename,label,duration_s,source,split,augmented
data/raw/gunshot/gunshot_001.wav,gunshot,1.0,esc50,train,false
data/raw/chainsaw/chainsaw_015.wav,chainsaw,1.0,freesound,train,false
data/augmented/gunshot/gunshot_001_noise_snr10.wav,gunshot,1.0,augmented,train,true
data/raw/forest_ambient/forest_003.wav,forest_ambient,1.0,field_recording,val,false
```

### Columns

| Column | Type | Description |
|--------|------|-------------|
| `filename` | string | Relative path to audio file |
| `label` | string | One of: `gunshot`, `chainsaw`, `vehicle`, `forest_ambient`, `other` |
| `duration_s` | float | Duration in seconds (should be ~1.0 for YAMNet) |
| `source` | string | Where the sample came from (see sources below) |
| `split` | string | One of: `train`, `val`, `test` (80/10/10 split) |
| `augmented` | bool | Whether this is an augmented version |

## Data Sources

### Free Datasets (Recommended)

1. **ESC-50** — 2000 clips, 50 classes, includes: chainsaw, engine, gunshot
   - Download: https://github.com/karolpiczak/ESC-50
   - License: CC BY-NC 3.0

2. **UrbanSound8K** — 8732 clips, 10 classes, includes: gun_shot, car_horn, engine_idling
   - Download: https://urbansounddataset.weebly.com/
   - License: CC BY-NC 4.0

3. **AudioSet** (Google) — Massive dataset, download via YouTube
   - Relevant ontology IDs:
     - `/m/032s66` = Gunshot, gunfire
     - `/m/01yg9g` = Chainsaw
     - `/m/07yv9` = Vehicle
     - `/t/dd00129` = Outside, rural or natural
   - Tool: https://github.com/audioset/ontology

4. **Freesound.org** — Creative commons clips
   - Search: "gunshot", "chainsaw forest", "jungle ambient"

5. **Xeno-canto** — Bird and wildlife sounds (for forest_ambient)
   - Download: https://xeno-canto.org/

### Field Recordings (Critical for Production)

Record audio at actual deployment sites to capture:
- Background noise profile (wind, insects, rain patterns)
- Device-specific microphone characteristics
- Acoustic environment (forest canopy, open field, near water)

**Recording guidelines:**
- Use the same device/microphone that will be deployed
- Record at 16kHz mono WAV
- Capture 1-minute segments, then split into 1-second clips
- Record at different times of day and weather conditions
- Target: 200+ clips per environment type

## Audio Requirements

| Parameter | Value | Notes |
|-----------|-------|-------|
| Sample rate | 16000 Hz | YAMNet requirement |
| Channels | 1 (mono) | Stereo will be averaged |
| Bit depth | 16-bit PCM | Standard WAV |
| Duration | 0.975s–1.0s | YAMNet input window |
| Format | WAV | Uncompressed |

## Labeling Guidelines

1. Each clip should contain **one dominant sound event**
2. If multiple sounds overlap, label with the **most important** sound
3. For ambiguous clips, use the `other` class
4. Ensure no silence-only clips in non-ambient classes
5. Verify labels with at least one listen-through
