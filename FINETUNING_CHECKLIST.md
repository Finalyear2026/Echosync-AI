# Fine-Tuning Checklist - Quick Reference

## 📋 Pre-Flight Checklist

### ☐ Environment Setup
```bash
cd echosync-desktop/sidecar
pip install datasets transformers accelerate evaluate jiwer tensorboard ctranslate2
```

### ☐ GPU Check (Optional but Recommended)
```bash
python -c "import torch; print('GPU:', torch.cuda.is_available())"
```
- ✅ GPU available → Continue locally
- ❌ No GPU → Use Google Colab (free) or RunPod ($0.30/hr)

### ☐ Dataset Ready
- [ ] Downloaded Mozilla Common Voice Urdu, OR
- [ ] Created custom dataset with metadata.csv

---

## 🚀 Execution Steps

### Step 1: Prepare Dataset (20 min)
```bash
python scripts/prepare_dataset.py \
    --audio-dir dataset/common_voice_ur/cv-corpus-*/ur/clips \
    --metadata dataset/common_voice_ur/cv-corpus-*/ur/validated.tsv \
    --output-dir dataset/processed_urdu
```

**✅ Success**: See "Dataset preparation complete!" with train/val/test counts

---

### Step 2: Fine-Tune (4-8 hours on GPU)

#### Local GPU:
```bash
python scripts/finetune_whisper.py \
    --dataset-dir dataset/processed_urdu \
    --model openai/whisper-tiny \
    --output-dir models/whisper-tiny-urdu \
    --max-steps 5000
```

#### Google Colab:
1. Go to https://colab.research.google.com/
2. Runtime → Change runtime type → GPU
3. Upload dataset or mount Drive
4. Run training script
5. Download trained model

**✅ Success**: See "Fine-tuning complete!" with Test WER < 20%

---

### Step 3: Convert to CTranslate2 (5 min)
```bash
ct2-transformers-converter \
    --model models/whisper-tiny-urdu/final \
    --output_dir models/whisper-tiny-urdu-ct2 \
    --quantization int8 \
    --force
```

**✅ Success**: See model.bin in output directory

---

### Step 4: Deploy (5 min)

#### Windows:
```powershell
$dest = "$env:APPDATA\EchoSync\models\whisper-base-urdu-ct2"
New-Item -ItemType Directory -Force -Path $dest
Copy-Item -Recurse -Force models\whisper-tiny-urdu-ct2\* $dest\
```

#### Linux/Mac:
```bash
mkdir -p ~/.echosync/models/whisper-base-urdu-ct2
cp -r models/whisper-tiny-urdu-ct2/* ~/.echosync/models/whisper-base-urdu-ct2/
```

**✅ Success**: model.bin exists in destination

---

### Step 5: Test (5 min)
```bash
# Restart sidecar
python main.py

# In another terminal
python test_transcription.py
```

**✅ Success**: 
- Logs show "Found fine-tuned Urdu model"
- Transcription < 1s for 10s audio
- Urdu in Arabic script

---

## 🎯 Expected Results

| Metric | Target | How to Check |
|--------|--------|--------------|
| Speed | 0.5-1s for 10s audio | test_transcription.py |
| WER | < 15% | Fine-tuning logs |
| Confidence | > 0.7 | test_transcription.py |
| Script | Urdu (Arabic) | Visual inspection |
| Memory | ~1GB | Task Manager/htop |

---

## 🐛 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| No GPU | Use Google Colab (free) |
| Out of memory | Reduce --batch-size to 8 or 4 |
| Model not found | Check path with `ls` or `dir` |
| Still slow | Verify model.bin exists in correct location |
| High WER (>20%) | Need more data or try base model |

---

## 📞 Need Help?

**Current Step**: _________________

**Error Message**: _________________

**What I've tried**: _________________

Refer to `MANUAL_FINETUNING_WALKTHROUGH.md` for detailed instructions.

---

## ✅ Completion Checklist

- [ ] Dataset prepared (train/val/test splits created)
- [ ] Model fine-tuned (WER < 20% on test set)
- [ ] Converted to CTranslate2 INT8 format
- [ ] Deployed to EchoSync models directory
- [ ] Tested and verified (speed + accuracy)
- [ ] Sidecar logs show "Found fine-tuned Urdu model"

**Status**: ☐ Not Started | ☐ In Progress | ☐ Complete

**Time Invested**: _______ hours

**Final WER**: _______%

**Speed Improvement**: _______x faster
