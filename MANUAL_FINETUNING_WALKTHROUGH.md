# Manual Fine-Tuning Walkthrough for EchoSync

## 🎯 Goal
Fine-tune `whisper-tiny` on Urdu data, convert to CTranslate2 INT8, and deploy to EchoSync.

**Expected Results:**
- Speed: 0.5-1s for 10s audio (6-10x faster than current)
- Accuracy: 12-18% WER on Urdu (better than generic small)
- Memory: ~1GB (vs 2GB current)

---

## ✅ Prerequisites Checklist

### 1. Install Fine-Tuning Dependencies
```bash
cd echosync-desktop/sidecar

# Install training dependencies
pip install datasets==2.14.0
pip install transformers==4.35.0
pip install accelerate==0.24.0
pip install evaluate==0.4.1
pip install jiwer==3.0.3
pip install tensorboard==2.15.0

# Install conversion tool
pip install ctranslate2==3.24.0
```

### 2. Check GPU Availability (Optional but Recommended)
```bash
python -c "import torch; print('GPU Available:', torch.cuda.is_available()); print('GPU Name:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'None')"
```

**If no GPU:**
- ⚠️ Training will be VERY slow on CPU (days instead of hours)
- 💡 Recommended: Use Google Colab (free GPU) or RunPod ($0.30/hour)

### 3. Verify Scripts Exist
```bash
ls scripts/prepare_dataset.py
ls scripts/finetune_whisper.py
```

---

## 📦 Step 1: Download Dataset (Choose One)

### Option A: Mozilla Common Voice Urdu (Recommended - Free, 100+ hours)

1. **Visit**: https://commonvoice.mozilla.org/en/datasets
2. **Select Language**: Urdu (اردو)
3. **Download**: Latest validated dataset (requires email signup)
4. **Extract**:
   ```bash
   # Create dataset directory
   mkdir -p dataset/common_voice_ur
   
   # Extract (adjust filename to your download)
   tar -xzf cv-corpus-*-ur.tar.gz -C dataset/common_voice_ur
   ```

5. **Verify structure**:
   ```bash
   ls dataset/common_voice_ur/cv-corpus-*/ur/
   # Should see: clips/ validated.tsv train.tsv dev.tsv test.tsv
   ```

### Option B: Create Custom Dataset (If you have your own recordings)

1. **Create structure**:
   ```bash
   mkdir -p dataset/custom_urdu/audio
   ```

2. **Add audio files** to `dataset/custom_urdu/audio/`
   - Format: WAV, MP3, or FLAC
   - Sample rate: Any (will be resampled to 16kHz)
   - Duration: 2-30 seconds per clip

3. **Create metadata.csv**:
   ```csv
   file_name,transcript
   clip_001.wav,یہ ایک ٹیسٹ ہے
   clip_002.wav,Task bana do kal ke liye
   clip_003.wav,Create a meeting tomorrow at 3pm
   ```

---

## 🔧 Step 2: Prepare Dataset

### For Common Voice:
```bash
cd echosync-desktop/sidecar

python scripts/prepare_dataset.py \
    --audio-dir dataset/common_voice_ur/cv-corpus-*/ur/clips \
    --metadata dataset/common_voice_ur/cv-corpus-*/ur/validated.tsv \
    --output-dir dataset/processed_urdu \
    --test-split 0.1 \
    --validation-split 0.05
```

### For Custom Dataset:
```bash
python scripts/prepare_dataset.py \
    --audio-dir dataset/custom_urdu/audio \
    --metadata dataset/custom_urdu/metadata.csv \
    --output-dir dataset/processed_urdu \
    --test-split 0.1 \
    --validation-split 0.05
```

**Expected Output:**
```
Loading metadata from ...
Found 5000 valid audio files
Processing audio files (resampling to 16kHz)...
Creating train/validation/test splits...
Dataset splits:
  Train: 4250 samples
  Validation: 250 samples
  Test: 500 samples
Saving dataset to dataset/processed_urdu
✓ Dataset preparation complete!
```

**⏱️ Time**: 10-30 minutes depending on dataset size

---

## 🎓 Step 3: Fine-Tune Model

### Local GPU (If you have NVIDIA GPU with 16GB+ VRAM):
```bash
python scripts/finetune_whisper.py \
    --dataset-dir dataset/processed_urdu \
    --model openai/whisper-tiny \
    --output-dir models/whisper-tiny-urdu \
    --language ur \
    --max-steps 5000 \
    --batch-size 16 \
    --learning-rate 1e-5
```

### Google Colab (Free GPU - Recommended if no local GPU):

1. **Go to**: https://colab.research.google.com/
2. **Create new notebook**
3. **Change runtime**: Runtime → Change runtime type → GPU (T4)
4. **Run these cells**:

```python
# Cell 1: Install dependencies
!pip install datasets transformers accelerate evaluate jiwer tensorboard

# Cell 2: Upload dataset or mount Google Drive
from google.colab import drive
drive.mount('/content/drive')

# If dataset is on your computer, upload it:
# from google.colab import files
# uploaded = files.upload()  # Upload the processed_urdu.zip

# Cell 3: Clone your repo or upload scripts
!git clone https://github.com/yourusername/echosync-desktop.git
# Or upload scripts manually

# Cell 4: Fine-tune
%cd echosync-desktop/sidecar
!python scripts/finetune_whisper.py \
    --dataset-dir /content/dataset/processed_urdu \
    --model openai/whisper-tiny \
    --output-dir /content/models/whisper-tiny-urdu \
    --language ur \
    --max-steps 5000 \
    --batch-size 16

# Cell 5: Download trained model
!zip -r whisper-tiny-urdu.zip /content/models/whisper-tiny-urdu/final
from google.colab import files
files.download('whisper-tiny-urdu.zip')
```

### RunPod (Cheap Cloud GPU - $0.30-0.50/hour):

1. **Sign up**: https://www.runpod.io/
2. **Deploy pod**: RTX 3090 or 4090
3. **SSH into pod**
4. **Run**:
   ```bash
   # Install dependencies
   pip install datasets transformers accelerate evaluate jiwer tensorboard
   
   # Upload dataset (use scp or wget from cloud storage)
   # scp -r dataset/processed_urdu user@pod-ip:/workspace/
   
   # Clone repo
   git clone https://github.com/yourusername/echosync-desktop.git
   cd echosync-desktop/sidecar
   
   # Fine-tune
   python scripts/finetune_whisper.py \
       --dataset-dir /workspace/dataset/processed_urdu \
       --model openai/whisper-tiny \
       --output-dir /workspace/models/whisper-tiny-urdu \
       --language ur \
       --max-steps 5000 \
       --batch-size 16
   
   # Download model (use scp or cloud storage)
   ```

**Expected Output:**
```
✓ Using GPU: Tesla T4 (15.0GB)
Loading model: openai/whisper-tiny
Loading dataset from dataset/processed_urdu
Dataset loaded:
  train: 4250 samples
  validation: 250 samples
  test: 500 samples
Preprocessing dataset...
Starting training...
Total steps: 5000
Effective batch size: 32

Step 100: loss=0.523, wer=0.342
Step 200: loss=0.412, wer=0.287
Step 500: loss=0.298, wer=0.213
...
Step 5000: loss=0.145, wer=0.128

Evaluating on test set...
Test WER: 13.2%
✓ Fine-tuning complete!
Model saved to: models/whisper-tiny-urdu/final
```

**⏱️ Time**: 
- GPU (T4/3090): 4-8 hours
- CPU: 3-5 days ❌ (not recommended)

---

## 🔄 Step 4: Convert to CTranslate2 Format

```bash
# Convert fine-tuned model to faster-whisper format
ct2-transformers-converter \
    --model models/whisper-tiny-urdu/final \
    --output_dir models/whisper-tiny-urdu-ct2 \
    --quantization int8 \
    --force

# Verify conversion
ls models/whisper-tiny-urdu-ct2/
# Should see: model.bin, vocabulary.txt, config.json
```

**Expected Output:**
```
Loading model from models/whisper-tiny-urdu/final...
Converting to CTranslate2 format...
Quantizing to int8...
Saving to models/whisper-tiny-urdu-ct2...
✓ Conversion complete!
Model size: 74MB (int8 quantized)
```

**⏱️ Time**: 2-5 minutes

---

## 📦 Step 5: Deploy to EchoSync

### Windows:
```powershell
# Create models directory
$modelsDir = "$env:APPDATA\EchoSync\models\whisper-base-urdu-ct2"
New-Item -ItemType Directory -Force -Path $modelsDir

# Copy converted model
Copy-Item -Recurse -Force models\whisper-tiny-urdu-ct2\* $modelsDir\

# Verify
Get-ChildItem $modelsDir
```

### Linux/Mac:
```bash
# Create models directory
mkdir -p ~/.echosync/models/whisper-base-urdu-ct2

# Copy converted model
cp -r models/whisper-tiny-urdu-ct2/* ~/.echosync/models/whisper-base-urdu-ct2/

# Verify
ls -lh ~/.echosync/models/whisper-base-urdu-ct2/
```

**Note**: We use `whisper-base-urdu-ct2` as the directory name because the STT engine is already configured to look for this path.

---

## ✅ Step 6: Test the Fine-Tuned Model

### Restart Sidecar:
```bash
cd echosync-desktop/sidecar

# Stop current process (Ctrl+C if running)

# Start with fine-tuned model
python main.py
```

**Expected Log Output:**
```
INFO - ✓ Found fine-tuned Urdu model at C:\Users\...\AppData\Roaming\EchoSync\models\whisper-base-urdu-ct2
INFO - Loading faster-whisper model: C:\Users\...\AppData\Roaming\EchoSync\models\whisper-base-urdu-ct2 (cpu, int8)
INFO - faster-whisper model loaded successfully.
```

### Quick Test:
```bash
# In another terminal
cd echosync-desktop/sidecar
python test_transcription.py
```

**Speak in Urdu and check:**
- ✅ Transcription speed (should be 0.5-1s for 10s audio)
- ✅ Accuracy (Urdu script, not Hindi)
- ✅ Confidence score (should be > 0.7)

---

## 📊 Step 7: Evaluate Performance

### Create evaluation script:
```bash
# Create test_finetuned.py
cat > test_finetuned.py << 'EOF'
import time
from stt.engine import STTEngine
import sounddevice as sd
import numpy as np
import io
import wave

print("Testing fine-tuned model...")
stt = STTEngine()

# Record 5 seconds
duration = 5
sample_rate = 16000
print(f"\nRecording for {duration} seconds... Speak in Urdu!")
audio = sd.rec(int(duration * sample_rate), samplerate=sample_rate, channels=1, dtype='int16')
sd.wait()

# Convert to WAV
buf = io.BytesIO()
with wave.open(buf, 'wb') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(sample_rate)
    wf.writeframes(audio.tobytes())
wav_bytes = buf.getvalue()

# Transcribe
print("Transcribing...")
start = time.time()
result = stt.transcribe(wav_bytes, is_partial=False)
elapsed = time.time() - start

# Results
print("\n" + "="*60)
print("RESULTS")
print("="*60)
print(f"Transcript: {result.text}")
print(f"Confidence: {result.confidence:.2%}")
print(f"Language: {result.language_detected}")
print(f"Speed: {elapsed:.2f}s ({elapsed/duration:.2f}x real-time)")
print("="*60)

if elapsed < duration:
    print("✓ Faster than real-time!")
else:
    print("⚠️ Slower than real-time")

if result.confidence > 0.7:
    print("✓ High confidence")
else:
    print("⚠️ Low confidence")
EOF

python test_finetuned.py
```

### Compare Before/After:

| Metric | Before (Generic Small) | After (Fine-tuned Tiny) | Improvement |
|--------|------------------------|-------------------------|-------------|
| Speed | 3-5s | 0.5-1s | **3-6x faster** ⚡ |
| Urdu WER | 25-30% | 12-18% | **2x better** ✅ |
| Memory | 2GB | 1GB | **50% less** 💾 |
| Script | Hindi sometimes ❌ | Urdu always ✅ | **Fixed** ✅ |

---

## 🐛 Troubleshooting

### Issue: "No GPU detected"
**Solution**: Use Google Colab or RunPod for training

### Issue: "Out of memory"
**Solution**: Reduce batch size:
```bash
python scripts/finetune_whisper.py \
    --batch-size 8 \  # or 4
    --gradient-accumulation-steps 4
```

### Issue: "Model not found after deployment"
**Solution**: Check path:
```bash
# Windows
dir "$env:APPDATA\EchoSync\models\whisper-base-urdu-ct2"

# Linux/Mac
ls ~/.echosync/models/whisper-base-urdu-ct2/
```

### Issue: "Still using generic model"
**Solution**: Verify model.bin exists:
```bash
# Windows
Test-Path "$env:APPDATA\EchoSync\models\whisper-base-urdu-ct2\model.bin"

# Linux/Mac
ls ~/.echosync/models/whisper-base-urdu-ct2/model.bin
```

### Issue: "High WER (>20%) after fine-tuning"
**Possible causes**:
1. Not enough training data (need 50+ hours for tiny)
2. Poor quality transcripts in dataset
3. Need more training steps (try 10000 instead of 5000)
4. Tiny model too small for code-switching (try base instead)

---

## 📈 Next Steps

### If Results Are Good (WER < 15%):
1. ✅ Deploy to production
2. 📊 Monitor user feedback
3. 📦 Collect real usage data for next iteration

### If Results Are Mediocre (WER 15-20%):
1. 🔄 Train longer (10000 steps)
2. 📚 Add more training data
3. 🎯 Fine-tune hyperparameters

### If Results Are Poor (WER > 20%):
1. 🔼 Try base model instead of tiny
2. 🔍 Check dataset quality
3. 📊 Analyze error patterns

---

## 💰 Cost Summary

| Item | Cost |
|------|------|
| Common Voice Dataset | Free |
| Google Colab (free tier) | Free (limited hours) |
| Google Colab Pro | $10/month |
| RunPod (8 hours) | $2.40-4.00 |
| **Total** | **$0-10** |

---

## ⏱️ Time Summary

| Phase | Time |
|-------|------|
| Dataset download | 30 min |
| Dataset preparation | 20 min |
| Fine-tuning (GPU) | 4-8 hours |
| Conversion | 5 min |
| Deployment | 5 min |
| Testing | 15 min |
| **Total** | **~6-10 hours** |

---

## 🎉 Success Criteria

You'll know it worked when:
- ✅ Logs show "Found fine-tuned Urdu model"
- ✅ Transcription is 3-6x faster
- ✅ Urdu text in Arabic script (not Devanagari)
- ✅ Confidence scores > 0.7
- ✅ WER < 15% on your test cases

**Ready to start? Let me know which step you're on and I'll help you through it!**
