# Google Colab Fine-Tuning Setup (CORRECTED)

## Cell 1: Install Dependencies

```python
# Install all required packages
!pip install -q datasets transformers accelerate evaluate jiwer tensorboard ctranslate2
!pip install -q git+https://github.com/openai/whisper.git

print("✓ Dependencies installed")
```

## Cell 2: Mount Google Drive

```python
from google.colab import drive
drive.mount('/content/drive')

# Verify files exist
import os
print("\nChecking for uploaded files...")
print("Files in MyDrive:")
!ls -lh /content/drive/MyDrive/ | grep -E "(processed_urdu|finetune_whisper)"
```

## Cell 3: Copy and Extract Dataset

```python
import os
from pathlib import Path

# Copy files from Drive to Colab workspace
print("Copying files from Drive...")
!cp /content/drive/MyDrive/processed_urdu.zip /content/
!cp /content/drive/MyDrive/finetune_whisper.py /content/

# Verify files copied
print("\nFiles in /content:")
!ls -lh /content/*.zip /content/*.py

# Extract the ZIP file
print("\nExtracting dataset...")
!unzip -q processed_urdu.zip

# Verify extraction
print("\nDataset structure:")
!ls -la dataset/processed_urdu/

print("\nDataset splits:")
!ls -la dataset/processed_urdu/train/
!ls -la dataset/processed_urdu/validation/
!ls -la dataset/processed_urdu/test/

print("\n✓ Dataset ready!")
```

## Cell 4: Verify GPU and Test Script

```python
import torch

# Check GPU
if torch.cuda.is_available():
    print(f"✓ GPU: {torch.cuda.get_device_name(0)}")
    print(f"  Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f}GB")
else:
    print("⚠️  No GPU detected!")

# Verify script exists
import os
if os.path.exists("/content/finetune_whisper.py"):
    print("✓ Training script ready")
else:
    print("✗ Training script not found!")

# Verify dataset exists
if os.path.exists("/content/dataset/processed_urdu"):
    print("✓ Dataset ready")
    
    # Show dataset info
    from datasets import load_from_disk
    dataset = load_from_disk("/content/dataset/processed_urdu")
    print("\nDataset splits:")
    for split, data in dataset.items():
        print(f"  {split}: {len(data)} samples")
else:
    print("✗ Dataset not found!")
```

## Cell 5: Start Training

```python
# Run training with correct parameters
!python finetune_whisper.py \
    --dataset-dir dataset/processed_urdu \
    --model openai/whisper-base \
    --output-dir ./whisper-urdu-finetuned \
    --language ur \
    --max-steps 5000 \
    --batch-size 16 \
    --learning-rate 1e-5
```

## Cell 6: Monitor Training (Run in separate cell while training)

```python
# Load tensorboard
%load_ext tensorboard
%tensorboard --logdir ./whisper-urdu-finetuned
```

## Cell 7: After Training - Convert to CTranslate2

```python
# Convert to faster-whisper format
!ct2-transformers-converter \
    --model ./whisper-urdu-finetuned/final \
    --output_dir ./whisper-urdu-ct2 \
    --quantization int8

print("\n✓ Model converted!")
print("Download the model from: /content/whisper-urdu-ct2")
```

## Cell 8: Download Model to Your Computer

```python
# Zip the converted model for download
!zip -r whisper-urdu-ct2.zip whisper-urdu-ct2/

# Copy to Drive for easy download
!cp whisper-urdu-ct2.zip /content/drive/MyDrive/

print("\n✓ Model saved to Google Drive: whisper-urdu-ct2.zip")
print("You can now download it from your Drive")
```

---

## Troubleshooting

### If Cell 3 fails with "cannot find processed_urdu.zip":

```python
# Check what files are actually in Drive
!ls -la /content/drive/MyDrive/

# If files are in a subfolder, adjust the path:
# !cp /content/drive/MyDrive/YourFolder/processed_urdu.zip /content/
```

### If extraction shows "dataset/processed_urdu not found":

```python
# Check what was extracted
!ls -la

# If it extracted to a different location, move it:
# !mkdir -p dataset
# !mv processed_urdu dataset/
```

### If training fails with "No GPU":

1. Go to Runtime → Change runtime type
2. Select "T4 GPU" or "A100 GPU"
3. Click Save
4. Re-run all cells

---

## Expected Timeline

- **Cell 1-4**: 2-5 minutes (setup)
- **Cell 5**: 6-10 hours (training)
- **Cell 7-8**: 5-10 minutes (conversion and download)

**Total**: ~6-10 hours (mostly unattended training)
