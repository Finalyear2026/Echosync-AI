# Dataset Backup and Transfer Guide

## Overview
This guide helps you backup the preprocessed dataset from your old Colab session and transfer it to continue training.

## Prerequisites
- Access to your old Colab session with the preprocessed dataset
- Google Drive account or local computer with sufficient storage (~2-3 GB)
- New Colab session or training environment ready

---

## Step 1: Backup Dataset from Old Colab Session

### 1.1 Find Your Dataset Location
First, locate where your preprocessed dataset is stored:

```python
import os

# Common locations to check
possible_paths = [
    '/content/processed_urdu',
    '/content/dataset/processed_urdu',
    '/content/echosync-desktop/dataset/processed_urdu',
    '/content/drive/MyDrive/processed_urdu',
]

print("Searching for dataset...")
dataset_path = None

for path in possible_paths:
    if os.path.exists(path):
        print(f"✓ Found dataset at: {path}")
        dataset_path = path
        break

if dataset_path is None:
    # Search in current directory
    print("\nSearching in /content...")
    for root, dirs, files in os.walk('/content'):
        if 'dataset_dict.json' in files:
            dataset_path = root
            print(f"✓ Found dataset at: {dataset_path}")
            break

if dataset_path:
    print(f"\nDataset location: {dataset_path}")
    print(f"Contents: {os.listdir(dataset_path)}")
else:
    print("✗ Dataset not found. Please check your notebook for the correct path.")
```

### 1.2 Connect to Google Drive (Recommended Method)
```python
from google.colab import drive
drive.mount('/content/drive')
```

### 1.3 Create Proper Tar Archive
```python
import os
import tarfile

# Use the dataset_path found in step 1.1
# If you skipped 1.1, manually set it here:
# dataset_path = '/your/actual/path/to/processed_urdu'

# Create tar.gz archive
output_file = '/content/drive/MyDrive/processed_urdu_backup.tar.gz'

print(f"Creating backup archive from: {dataset_path}")
print("This may take 5-10 minutes...")

with tarfile.open(output_file, 'w:gz') as tar:
    tar.add(dataset_path, arcname='processed_urdu')
    
print(f"Backup complete: {output_file}")
print(f"File size: {os.path.getsize(output_file) / (1024**3):.2f} GB")
```

### 1.4 Verify Archive Integrity
```python
# Verify the archive can be read
with tarfile.open(output_file, 'r:gz') as tar:
    members = tar.getmembers()
    print(f"Archive contains {len(members)} files")
    print("First 10 files:")
    for member in members[:10]:
        print(f"  - {member.name}")
```

---

## Step 2: Alternative - Download to Local Computer

If you prefer to download to your computer instead of Google Drive:

### 2.1 Create Archive
```python
import tarfile

dataset_path = '/content/processed_urdu'
output_file = '/content/processed_urdu_backup.tar.gz'

print("Creating backup archive...")
with tarfile.open(output_file, 'w:gz') as tar:
    tar.add(dataset_path, arcname='processed_urdu')
    
print("Backup complete!")
```

### 2.2 Download via Colab
```python
from google.colab import files
files.download('/content/processed_urdu_backup.tar.gz')
```

**Note**: Large files may timeout. If this happens, use the Google Drive method instead.

---

## Step 3: Transfer to New Environment

### Option A: From Google Drive to New Colab

```python
from google.colab import drive
import tarfile
import os

# Mount Drive
drive.mount('/content/drive')

# Extract dataset
archive_path = '/content/drive/MyDrive/processed_urdu_backup.tar.gz'
extract_to = '/content/'

print("Extracting dataset...")
with tarfile.open(archive_path, 'r:gz') as tar:
    tar.extractall(extract_to)
    
print("Extraction complete!")
print(f"Dataset available at: {extract_to}processed_urdu")

# Verify extraction
dataset_path = '/content/processed_urdu'
if os.path.exists(dataset_path):
    print("✓ Dataset successfully restored")
    print(f"Contents: {os.listdir(dataset_path)}")
else:
    print("✗ Dataset not found")
```

### Option B: From Local Computer to New Colab

1. Upload the tar.gz file to your Google Drive manually
2. Follow Option A above

---

## Step 4: Verify Dataset and Continue Training

### 4.1 Load and Verify Dataset
```python
from datasets import load_from_disk

# Load the dataset
dataset_path = '/content/processed_urdu'
dataset = load_from_disk(dataset_path)

print("Dataset loaded successfully!")
print(f"Train samples: {len(dataset['train'])}")
print(f"Validation samples: {len(dataset['validation'])}")
print(f"Test samples: {len(dataset['test'])}")

# Check a sample
print("\nSample from training set:")
print(dataset['train'][0])
```

### 4.2 Resume Training Setup
```python
# Your dataset is now ready at /content/processed_urdu
# Continue with your training script from COLAB_MINIMAL_GUIDE.md
# starting from the "Training Configuration" section

from transformers import WhisperForConditionalGeneration, Seq2SeqTrainingArguments, Seq2SeqTrainer

# Load model
model = WhisperForConditionalGeneration.from_pretrained("openai/whisper-small")

# Configure training
training_args = Seq2SeqTrainingArguments(
    output_dir="./whisper-urdu-finetuned",
    per_device_train_batch_size=8,
    # ... rest of your training configuration
)

# Start training
trainer = Seq2SeqTrainer(
    model=model,
    args=training_args,
    train_dataset=dataset['train'],
    eval_dataset=dataset['validation'],
)

trainer.train()
```

---

## Troubleshooting

### Archive Creation Fails
- **Error**: "No space left on device"
- **Solution**: Clean up temporary files first:
```python
!rm -rf /content/sample_data
!rm -rf ~/.cache/huggingface
```

### Archive is Corrupted
- **Symptom**: Cannot extract or "unexpected end of data"
- **Solution**: Recreate the archive with verification:
```python
import tarfile
import hashlib

def create_verified_archive(source, output):
    # Create archive
    with tarfile.open(output, 'w:gz') as tar:
        tar.add(source, arcname=os.path.basename(source))
    
    # Calculate checksum
    with open(output, 'rb') as f:
        checksum = hashlib.sha256(f.read()).hexdigest()
    
    print(f"Archive created: {output}")
    print(f"SHA256: {checksum}")
    return checksum

checksum = create_verified_archive('/content/processed_urdu', 
                                   '/content/drive/MyDrive/processed_urdu_backup.tar.gz')
```

### Google Drive Mount Fails
- **Solution**: Restart runtime and try again
- **Alternative**: Use local download method

### Extraction is Slow
- This is normal for large datasets. The extraction may take 5-10 minutes.
- Monitor progress:
```python
import tarfile
import sys

with tarfile.open(archive_path, 'r:gz') as tar:
    members = tar.getmembers()
    for i, member in enumerate(members):
        tar.extract(member, extract_to)
        if i % 100 == 0:
            print(f"Extracted {i}/{len(members)} files...", end='\r')
            sys.stdout.flush()
```

---

## Quick Reference Commands

### Backup to Google Drive
```python
from google.colab import drive
import tarfile

drive.mount('/content/drive')
with tarfile.open('/content/drive/MyDrive/processed_urdu_backup.tar.gz', 'w:gz') as tar:
    tar.add('/content/processed_urdu', arcname='processed_urdu')
```

### Restore from Google Drive
```python
from google.colab import drive
import tarfile

drive.mount('/content/drive')
with tarfile.open('/content/drive/MyDrive/processed_urdu_backup.tar.gz', 'r:gz') as tar:
    tar.extractall('/content/')
```

### Verify Dataset
```python
from datasets import load_from_disk
dataset = load_from_disk('/content/processed_urdu')
print(f"Train: {len(dataset['train'])}, Val: {len(dataset['validation'])}, Test: {len(dataset['test'])}")
```

---

## Next Steps

After successfully transferring your dataset:

1. ✓ Dataset is backed up and transferred
2. → Continue with training using `COLAB_MINIMAL_GUIDE.md`
3. → Start from "Step 3: Training Configuration" section
4. → Monitor training progress and save checkpoints regularly

**Estimated Time**: 
- Backup creation: 5-10 minutes
- Transfer (via Drive): Instant
- Extraction: 5-10 minutes
- **Total**: ~15-20 minutes to resume training
