# Quick Start: Fine-Tuning Whisper for Urdu

## TL;DR

Fine-tuning a smaller Whisper model (base) on Urdu data will give you:
- ✅ **4-6x faster** transcription
- ✅ **Better accuracy** for Urdu/Roman Urdu
- ✅ **Lower memory** usage (~1.5GB vs 2-5GB)

## Prerequisites

```bash
# Install fine-tuning dependencies
pip install datasets transformers accelerate evaluate jiwer tensorboard
pip install ctranslate2  # For conversion to faster-whisper format
```

## Step 1: Get Dataset (Choose One)

### Option A: Use Mozilla Common Voice Urdu (Recommended)

```bash
# Download Common Voice Urdu dataset
# Visit: https://commonvoice.mozilla.org/ur/datasets
# Download the latest validated dataset

# Extract
tar -xzf ur.tar.gz

# The dataset will have this structure:
# ur/
# ├── clips/          # Audio files
# ├── validated.tsv   # Metadata
# └── ...
```

### Option B: Create Your Own Dataset

Create a directory structure:
```
my_dataset/
├── audio/
│   ├── clip_001.wav
│   ├── clip_002.wav
│   └── ...
└── metadata.csv
```

**metadata.csv format:**
```csv
file_name,transcript,duration,language
clip_001.wav,"یہ ایک ٹیسٹ ہے",3.2,ur
clip_002.wav,"Task bana do kal ke liye",2.8,ur-roman
clip_003.wav,"Create a meeting tomorrow",3.5,en
```

**Requirements:**
- Audio: 16kHz, mono, WAV/MP3/FLAC
- Minimum: 10-20 hours
- Recommended: 50-100 hours

## Step 2: Prepare Dataset

```bash
cd echosync-desktop/sidecar

# For Common Voice
python scripts/prepare_dataset.py \
    --audio-dir /path/to/ur/clips \
    --metadata /path/to/ur/validated.tsv \
    --output-dir dataset/processed

# For custom dataset
python scripts/prepare_dataset.py \
    --audio-dir my_dataset/audio \
    --metadata my_dataset/metadata.csv \
    --output-dir dataset/processed
```

This will create train/validation/test splits (85%/5%/10%).

## Step 3: Fine-Tune Model

### Local GPU (if you have NVIDIA GPU with 16GB+ VRAM)

```bash
python scripts/finetune_whisper.py \
    --dataset-dir dataset/processed \
    --model openai/whisper-base \
    --output-dir models/whisper-urdu-finetuned \
    --max-steps 5000 \
    --batch-size 16
```

### Cloud GPU (Recommended for most users)

#### Option 1: Google Colab (Easiest)

1. Go to https://colab.research.google.com/
2. Create new notebook
3. Change runtime to GPU (Runtime → Change runtime type → GPU)
4. Upload your dataset or mount Google Drive
5. Run:

```python
# Install dependencies
!pip install datasets transformers accelerate evaluate jiwer

# Clone your repo or upload scripts
!git clone https://github.com/yourusername/echosync-desktop.git
%cd echosync-desktop/sidecar

# Upload dataset to Colab or mount from Drive
# from google.colab import drive
# drive.mount('/content/drive')

# Fine-tune
!python scripts/finetune_whisper.py \
    --dataset-dir /content/dataset/processed \
    --model openai/whisper-base \
    --output-dir /content/models/whisper-urdu-finetuned \
    --max-steps 5000
```

#### Option 2: RunPod (Cheapest)

1. Go to https://www.runpod.io/
2. Create account
3. Deploy a pod with RTX 3090 or 4090 (~$0.30-0.50/hour)
4. SSH into pod
5. Run training commands

#### Option 3: Lambda Labs (Fast GPUs)

1. Go to https://lambdalabs.com/
2. Rent an A100 instance (~$1.10/hour)
3. SSH and run training

**Training time:** 4-12 hours depending on dataset size and GPU.

## Step 4: Convert to faster-whisper Format

```bash
# After training completes
ct2-transformers-converter \
    --model models/whisper-urdu-finetuned/final \
    --output_dir models/whisper-urdu-ct2 \
    --quantization int8
```

## Step 5: Deploy to EchoSync

### Copy model to EchoSync models directory:

**Windows:**
```powershell
# Create models directory
mkdir "$env:APPDATA\EchoSync\models\whisper-base-urdu-ct2"

# Copy converted model
cp -r models/whisper-urdu-ct2/* "$env:APPDATA\EchoSync\models\whisper-base-urdu-ct2/"
```

**Linux/Mac:**
```bash
mkdir -p ~/.echosync/models/whisper-base-urdu-ct2
cp -r models/whisper-urdu-ct2/* ~/.echosync/models/whisper-base-urdu-ct2/
```

### Update STT Engine

The engine will automatically detect and use the fine-tuned model if it exists at the path above. No code changes needed!

## Step 6: Test

```bash
# Restart sidecar
cd echosync-desktop/sidecar
python main.py

# Or use test script
python test_transcription.py
```

You should see:
```
Loading fine-tuned Urdu model from C:\Users\...\AppData\Roaming\EchoSync\models\whisper-base-urdu-ct2
```

## Expected Results

### Before Fine-Tuning (Generic Small):
- Speed: 3-5s for 10s audio
- Urdu WER: 25-30%
- Roman Urdu WER: 40-50%

### After Fine-Tuning (Base model, 50 hours data):
- Speed: 1-2s for 10s audio ⚡ (2-3x faster)
- Urdu WER: 10-15% ✅ (2x better)
- Roman Urdu WER: 15-20% ✅ (2-3x better)

## Troubleshooting

### Out of Memory Error
```bash
# Reduce batch size
python scripts/finetune_whisper.py \
    --batch-size 8 \  # or 4
    --gradient-accumulation-steps 4  # compensate
```

### Training Too Slow
- Use cloud GPU (Colab, RunPod, Lambda)
- Use smaller model (tiny instead of base)
- Reduce max_steps

### Poor Accuracy After Fine-Tuning
- Need more training data (50-100 hours minimum)
- Increase max_steps (10000-20000)
- Use larger model (base → small)
- Check data quality (transcripts must be accurate)

## Cost Estimate

| Item | Cost |
|------|------|
| Dataset (Common Voice) | Free |
| Cloud GPU (RunPod, 8 hours) | $2.40-4.00 |
| Cloud GPU (Colab Pro, 1 month) | $10 |
| Total | **$2.40-10** |

**ROI:** If you have 100+ users, the improved UX pays back within days.

## Next Steps

1. **Collect real usage data** - Add data collection to EchoSync (with user consent)
2. **Iterative improvement** - Fine-tune again every 3-6 months with new data
3. **A/B testing** - Compare generic vs fine-tuned model performance
4. **Optimize further** - Try tiny model for even faster transcription

## Need Help?

- Check `FINE_TUNING_GUIDE.md` for detailed documentation
- Common Voice Urdu: https://commonvoice.mozilla.org/ur
- Whisper fine-tuning: https://huggingface.co/blog/fine-tune-whisper
- RunPod tutorial: https://docs.runpod.io/
