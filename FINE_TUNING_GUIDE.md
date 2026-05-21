# Fine-Tuning Whisper for Urdu/Roman Urdu

## Overview

Fine-tuning a smaller Whisper model (tiny or base) on Urdu/Punjabi/Roman Urdu data can provide:
- **4-10x faster** transcription than small/medium models
- **Better accuracy** for your specific use case (Urdu + code-switching)
- **Lower memory footprint** (~1-1.5GB vs 2-5GB)

## Recommended Approach: Fine-tune Base Model

**Why Base over Tiny?**
- Base: 74M parameters - good balance of speed and capacity
- Tiny: 39M parameters - very fast but may struggle with code-switching
- Base fine-tuned will likely outperform generic Small model

## Phase 1: Dataset Collection

### Required Data:
- **Minimum**: 10-20 hours of Urdu/Punjabi/Roman Urdu audio
- **Recommended**: 50-100 hours for production quality
- **Ideal**: 200+ hours for best results

### Data Sources:

#### 1. **Public Datasets** (Start here)
- **Mozilla Common Voice Urdu**: https://commonvoice.mozilla.org/ur
  - ~100+ hours of validated Urdu speech
  - Free, open-source
  - Download: `commonvoice-corpus-ur`

- **UrduSpeech**: https://github.com/urduspeech
  - Urdu speech corpus
  - Academic use

- **OpenSLR Urdu**: http://www.openslr.org/
  - Search for Urdu/Punjabi datasets

#### 2. **Create Your Own Dataset**
- Record yourself and team members
- Use the EchoSync app to collect real usage data (with consent)
- Transcribe using the current model, then manually correct

#### 3. **Augment with Roman Urdu**
- Take Urdu transcripts and transliterate to Roman Urdu
- Use tools like `urdu-roman-transliterator`
- Mix 70% Urdu script + 30% Roman Urdu in training

### Dataset Format:

```
dataset/
├── audio/
│   ├── clip_001.wav  (16kHz, mono)
│   ├── clip_002.wav
│   └── ...
└── metadata.csv
```

**metadata.csv:**
```csv
file_name,transcript,duration,language
clip_001.wav,"یہ ایک ٹیسٹ ہے",3.2,ur
clip_002.wav,"Task bana do kal ke liye",2.8,ur-roman
clip_003.wav,"Create a meeting tomorrow at 3pm",3.5,en
```

## Phase 2: Data Preprocessing

### Install Dependencies:
```bash
pip install datasets transformers accelerate evaluate jiwer tensorboard
pip install git+https://github.com/huggingface/transformers
```

### Preprocessing Script:

```python
# scripts/prepare_dataset.py
from datasets import Dataset, Audio
import pandas as pd
from pathlib import Path

def prepare_whisper_dataset(audio_dir: str, metadata_csv: str):
    """Prepare dataset for Whisper fine-tuning."""
    
    # Load metadata
    df = pd.read_csv(metadata_csv)
    
    # Create dataset
    dataset = Dataset.from_dict({
        "audio": [str(Path(audio_dir) / f) for f in df["file_name"]],
        "sentence": df["transcript"].tolist(),
    })
    
    # Cast audio column
    dataset = dataset.cast_column("audio", Audio(sampling_rate=16000))
    
    # Split train/validation (90/10)
    dataset = dataset.train_test_split(test_size=0.1, seed=42)
    
    return dataset

# Usage
dataset = prepare_whisper_dataset("dataset/audio", "dataset/metadata.csv")
dataset.save_to_disk("dataset/processed")
```

## Phase 3: Fine-Tuning

### Training Script:

```python
# scripts/finetune_whisper.py
import torch
from transformers import (
    WhisperProcessor,
    WhisperForConditionalGeneration,
    Seq2SeqTrainingArguments,
    Seq2SeqTrainer,
)
from datasets import load_from_disk
import evaluate

# Load model and processor
model_name = "openai/whisper-base"  # or "openai/whisper-tiny"
processor = WhisperProcessor.from_pretrained(model_name, language="ur", task="transcribe")
model = WhisperForConditionalGeneration.from_pretrained(model_name)

# Force Urdu language and transcription task
model.config.forced_decoder_ids = processor.get_decoder_prompt_ids(
    language="ur", 
    task="transcribe"
)

# Load dataset
dataset = load_from_disk("dataset/processed")

# Preprocessing function
def prepare_dataset(batch):
    audio = batch["audio"]
    
    # Compute input features
    batch["input_features"] = processor(
        audio["array"], 
        sampling_rate=audio["sampling_rate"]
    ).input_features[0]
    
    # Encode target text
    batch["labels"] = processor.tokenizer(batch["sentence"]).input_ids
    
    return batch

# Apply preprocessing
dataset = dataset.map(
    prepare_dataset,
    remove_columns=dataset["train"].column_names,
    num_proc=4
)

# Metrics
wer_metric = evaluate.load("wer")

def compute_metrics(pred):
    pred_ids = pred.predictions
    label_ids = pred.label_ids
    
    # Replace -100 with pad token
    label_ids[label_ids == -100] = processor.tokenizer.pad_token_id
    
    # Decode
    pred_str = processor.tokenizer.batch_decode(pred_ids, skip_special_tokens=True)
    label_str = processor.tokenizer.batch_decode(label_ids, skip_special_tokens=True)
    
    # Compute WER
    wer = wer_metric.compute(predictions=pred_str, references=label_str)
    
    return {"wer": wer}

# Training arguments
training_args = Seq2SeqTrainingArguments(
    output_dir="./whisper-base-urdu-finetuned",
    per_device_train_batch_size=16,
    gradient_accumulation_steps=2,
    learning_rate=1e-5,
    warmup_steps=500,
    max_steps=5000,  # Adjust based on dataset size
    gradient_checkpointing=True,
    fp16=True,  # Use mixed precision for speed
    evaluation_strategy="steps",
    eval_steps=500,
    save_steps=500,
    logging_steps=100,
    report_to=["tensorboard"],
    load_best_model_at_end=True,
    metric_for_best_model="wer",
    greater_is_better=False,
    push_to_hub=False,
)

# Trainer
trainer = Seq2SeqTrainer(
    args=training_args,
    model=model,
    train_dataset=dataset["train"],
    eval_dataset=dataset["test"],
    tokenizer=processor.feature_extractor,
    compute_metrics=compute_metrics,
)

# Train
trainer.train()

# Save final model
model.save_pretrained("./whisper-base-urdu-final")
processor.save_pretrained("./whisper-base-urdu-final")
```

### Training Requirements:
- **GPU**: NVIDIA GPU with 16GB+ VRAM (RTX 3090, A100, etc.)
- **Time**: 4-12 hours depending on dataset size
- **Cost**: $20-50 if using cloud GPU (RunPod, Lambda Labs, Vast.ai)

### Cloud Training Options:
1. **Google Colab Pro** ($10/month) - T4/A100 GPU
2. **RunPod** (~$0.30-0.80/hour) - RTX 3090/4090
3. **Lambda Labs** (~$0.50-1.50/hour) - A100
4. **Vast.ai** (~$0.20-0.60/hour) - Various GPUs

## Phase 4: Integration

### Convert to faster-whisper Format:

```bash
# Install CT2 converter
pip install ctranslate2

# Convert fine-tuned model
ct2-transformers-converter \
    --model ./whisper-base-urdu-final \
    --output_dir ./whisper-base-urdu-ct2 \
    --quantization int8
```

### Update EchoSync to Use Fine-Tuned Model:

```python
# sidecar/stt/engine.py

def _load_model(self) -> None:
    try:
        from faster_whisper import WhisperModel
        
        # Check for fine-tuned model
        import os
        from pathlib import Path
        
        if os.name == 'nt':  # Windows
            appdata = os.environ.get("APPDATA", "")
            custom_model_path = Path(appdata) / "EchoSync" / "models" / "whisper-base-urdu-ct2"
        else:
            custom_model_path = Path.home() / ".echosync" / "models" / "whisper-base-urdu-ct2"
        
        if custom_model_path.exists():
            logger.info("Loading fine-tuned Urdu model from %s", custom_model_path)
            model_path = str(custom_model_path)
        else:
            logger.info("Fine-tuned model not found, using generic %s", self._model_size)
            model_path = self._model_size
        
        # ... rest of loading code
        self._model = WhisperModel(
            model_path,
            device=device,
            compute_type=compute_type,
            # ... other params
        )
```

## Phase 5: Evaluation

### Test Script:

```python
# scripts/evaluate_model.py
from faster_whisper import WhisperModel
import jiwer
from pathlib import Path

def evaluate_on_test_set(model_path: str, test_audio_dir: str, test_csv: str):
    """Evaluate WER on test set."""
    
    model = WhisperModel(model_path, device="cuda", compute_type="float16")
    
    import pandas as pd
    df = pd.read_csv(test_csv)
    
    predictions = []
    references = []
    
    for _, row in df.iterrows():
        audio_path = Path(test_audio_dir) / row["file_name"]
        segments, info = model.transcribe(str(audio_path), language="ur")
        
        pred_text = " ".join([s.text for s in segments])
        predictions.append(pred_text)
        references.append(row["transcript"])
    
    wer = jiwer.wer(references, predictions)
    print(f"Word Error Rate: {wer:.2%}")
    
    return wer

# Usage
wer = evaluate_on_test_set(
    "whisper-base-urdu-ct2",
    "dataset/test_audio",
    "dataset/test_metadata.csv"
)
```

## Expected Results

### Before Fine-Tuning (Generic Base):
- **Urdu WER**: 25-35%
- **Roman Urdu WER**: 40-50%
- **Code-switched WER**: 35-45%

### After Fine-Tuning (10-20 hours data):
- **Urdu WER**: 15-20% ✅
- **Roman Urdu WER**: 20-25% ✅
- **Code-switched WER**: 18-23% ✅

### After Fine-Tuning (50-100 hours data):
- **Urdu WER**: 8-12% ⭐
- **Roman Urdu WER**: 12-15% ⭐
- **Code-switched WER**: 10-14% ⭐

## Continuous Improvement

### Collect Real Usage Data:
```python
# Add to audio/service.py
def _finalize_segment(self, frames: list[np.ndarray]) -> None:
    wav_bytes = self._frames_to_wav(frames)
    result = self._stt.transcribe(wav_bytes)
    
    # Save for future fine-tuning (with user consent)
    if self._collect_training_data and result.confidence > 0.7:
        self._save_for_training(wav_bytes, result.text)
```

### Iterative Fine-Tuning:
1. Collect 1000+ real user transcriptions
2. Manually review and correct
3. Fine-tune again on new data
4. Deploy updated model
5. Repeat every 3-6 months

## Cost-Benefit Analysis

### One-Time Costs:
- Dataset collection: 20-40 hours of work
- Training: $20-50 (cloud GPU)
- Evaluation: 5-10 hours of work

### Benefits:
- **4-6x faster** transcription (base vs small)
- **10-20% better** accuracy for Urdu
- **50% lower** RAM usage
- **Better user experience** (real-time capable)

### ROI:
If you have 1000+ users, the improved UX and lower compute costs will pay back the investment within weeks.

## Recommendation

**Start with this approach:**

1. **Week 1-2**: Download Mozilla Common Voice Urdu dataset
2. **Week 3**: Preprocess and prepare training data
3. **Week 4**: Fine-tune base model on cloud GPU ($30-50)
4. **Week 5**: Evaluate and integrate into EchoSync
5. **Ongoing**: Collect real usage data for continuous improvement

**Quick Start Command:**
```bash
# Download Common Voice Urdu
wget https://mozilla-common-voice-datasets.s3.amazonaws.com/cv-corpus-XX.X-XXXX-XX-XX/ur.tar.gz
tar -xzf ur.tar.gz

# Start fine-tuning
python scripts/finetune_whisper.py
```

This approach will give you a **production-ready, fast, accurate Urdu STT model** that's perfectly tailored to your users' needs!
