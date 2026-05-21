#!/usr/bin/env python3
"""
Fine-tune Whisper model on Urdu/Roman Urdu dataset.
Requires GPU with 16GB+ VRAM.
"""

import argparse
import logging
from pathlib import Path
import torch
from transformers import (
    WhisperProcessor,
    WhisperForConditionalGeneration,
    Seq2SeqTrainingArguments,
    Seq2SeqTrainer,
)
from datasets import load_from_disk, DatasetDict
import evaluate
from dataclasses import dataclass
from typing import Any, Dict, List, Union

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class DataCollatorSpeechSeq2SeqWithPadding:
    """Data collator for Whisper fine-tuning."""
    
    processor: Any
    decoder_start_token_id: int

    def __call__(self, features: List[Dict[str, Union[List[int], torch.Tensor]]]) -> Dict[str, torch.Tensor]:
        # Split inputs and labels
        input_features = [{"input_features": feature["input_features"]} for feature in features]
        label_features = [{"input_ids": feature["labels"]} for feature in features]

        # Pad input features
        batch = self.processor.feature_extractor.pad(input_features, return_tensors="pt")

        # Pad labels
        labels_batch = self.processor.tokenizer.pad(label_features, return_tensors="pt")

        # Replace padding with -100 to ignore in loss
        labels = labels_batch["input_ids"].masked_fill(
            labels_batch.attention_mask.ne(1), -100
        )

        # Remove decoder_start_token_id if present
        if (labels[:, 0] == self.decoder_start_token_id).all().cpu().item():
            labels = labels[:, 1:]

        batch["labels"] = labels

        return batch


def prepare_dataset(batch, processor):
    """Preprocess a batch of data."""
    audio = batch["audio"]
    
    # Compute input features from audio array
    batch["input_features"] = processor.feature_extractor(
        audio["array"], 
        sampling_rate=audio["sampling_rate"]
    ).input_features[0]
    
    # Encode target text to label ids
    batch["labels"] = processor.tokenizer(batch["sentence"]).input_ids
    
    return batch


def finetune_whisper(
    dataset_dir: str,
    model_name: str = "openai/whisper-base",
    output_dir: str = "./whisper-urdu-finetuned",
    language: str = "ur",
    max_steps: int = 5000,
    batch_size: int = 16,
    learning_rate: float = 1e-5,
    warmup_steps: int = 500,
    eval_steps: int = 500,
    save_steps: int = 500,
    gradient_accumulation_steps: int = 2,
):
    """
    Fine-tune Whisper model on custom dataset.
    
    Args:
        dataset_dir: Path to processed dataset (from prepare_dataset.py)
        model_name: Base model to fine-tune (tiny, base, small, medium)
        output_dir: Where to save checkpoints and final model
        language: Target language code (ur for Urdu)
        max_steps: Maximum training steps
        batch_size: Per-device batch size
        learning_rate: Learning rate
        warmup_steps: Warmup steps
        eval_steps: Evaluation frequency
        save_steps: Checkpoint save frequency
        gradient_accumulation_steps: Gradient accumulation
    """
    
    # Check GPU availability
    if not torch.cuda.is_available():
        logger.warning("⚠️  No GPU detected! Training will be very slow on CPU.")
        logger.warning("Consider using Google Colab, RunPod, or Lambda Labs.")
        response = input("Continue anyway? (y/n): ")
        if response.lower() != 'y':
            return
    else:
        gpu_name = torch.cuda.get_device_name(0)
        gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1e9
        logger.info(f"✓ Using GPU: {gpu_name} ({gpu_memory:.1f}GB)")
    
    # Load model and processor
    logger.info(f"Loading model: {model_name}")
    processor = WhisperProcessor.from_pretrained(
        model_name, 
        language=language, 
        task="transcribe"
    )
    model = WhisperForConditionalGeneration.from_pretrained(model_name)
    
    # Set language and task
    model.config.forced_decoder_ids = processor.get_decoder_prompt_ids(
        language=language, 
        task="transcribe"
    )
    model.config.suppress_tokens = []
    
    # Load dataset
    logger.info(f"Loading dataset from {dataset_dir}")
    dataset = load_from_disk(dataset_dir)
    
    if not isinstance(dataset, DatasetDict):
        raise ValueError("Dataset must have train/validation/test splits")
    
    logger.info("Dataset loaded:")
    for split, data in dataset.items():
        logger.info(f"  {split}: {len(data)} samples")
    
    # Preprocess dataset
    logger.info("Preprocessing dataset...")
    dataset = dataset.map(
        lambda batch: prepare_dataset(batch, processor),
        remove_columns=dataset["train"].column_names,
        num_proc=4,
        desc="Preprocessing"
    )
    
    # Data collator
    data_collator = DataCollatorSpeechSeq2SeqWithPadding(
        processor=processor,
        decoder_start_token_id=model.config.decoder_start_token_id,
    )
    
    # Metrics
    wer_metric = evaluate.load("wer")
    
    def compute_metrics(pred):
        pred_ids = pred.predictions
        label_ids = pred.label_ids
        
        # Replace -100 with pad token id
        label_ids[label_ids == -100] = processor.tokenizer.pad_token_id
        
        # Decode predictions and labels
        pred_str = processor.tokenizer.batch_decode(pred_ids, skip_special_tokens=True)
        label_str = processor.tokenizer.batch_decode(label_ids, skip_special_tokens=True)
        
        # Compute WER
        wer = wer_metric.compute(predictions=pred_str, references=label_str)
        
        return {"wer": wer}
    
    # Training arguments
    training_args = Seq2SeqTrainingArguments(
        output_dir=output_dir,
        per_device_train_batch_size=batch_size,
        gradient_accumulation_steps=gradient_accumulation_steps,
        learning_rate=learning_rate,
        warmup_steps=warmup_steps,
        max_steps=max_steps,
        gradient_checkpointing=True,
        fp16=torch.cuda.is_available(),
        evaluation_strategy="steps",
        per_device_eval_batch_size=batch_size,
        predict_with_generate=True,
        generation_max_length=225,
        save_steps=save_steps,
        eval_steps=eval_steps,
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
        eval_dataset=dataset["validation"],
        data_collator=data_collator,
        compute_metrics=compute_metrics,
        tokenizer=processor.feature_extractor,
    )
    
    # Train
    logger.info("Starting training...")
    logger.info(f"Total steps: {max_steps}")
    logger.info(f"Effective batch size: {batch_size * gradient_accumulation_steps}")
    
    trainer.train()
    
    # Save final model
    final_model_dir = Path(output_dir) / "final"
    final_model_dir.mkdir(parents=True, exist_ok=True)
    
    logger.info(f"Saving final model to {final_model_dir}")
    model.save_pretrained(final_model_dir)
    processor.save_pretrained(final_model_dir)
    
    # Evaluate on test set
    logger.info("Evaluating on test set...")
    test_results = trainer.evaluate(dataset["test"])
    logger.info(f"Test WER: {test_results['eval_wer']:.2%}")
    
    logger.info("✓ Fine-tuning complete!")
    logger.info(f"Model saved to: {final_model_dir}")
    logger.info("\nNext steps:")
    logger.info("1. Convert to faster-whisper format:")
    logger.info(f"   ct2-transformers-converter --model {final_model_dir} \\")
    logger.info(f"       --output_dir {output_dir}/ct2 --quantization int8")
    logger.info("2. Copy to EchoSync models directory")
    logger.info("3. Update stt/engine.py to use the fine-tuned model")


def main():
    parser = argparse.ArgumentParser(
        description="Fine-tune Whisper model on Urdu dataset"
    )
    parser.add_argument(
        "--dataset-dir",
        required=True,
        help="Path to processed dataset (output from prepare_dataset.py)"
    )
    parser.add_argument(
        "--model",
        default="openai/whisper-base",
        choices=[
            "openai/whisper-tiny",
            "openai/whisper-base",
            "openai/whisper-small",
            "openai/whisper-medium",
        ],
        help="Base model to fine-tune (default: base)"
    )
    parser.add_argument(
        "--output-dir",
        default="./whisper-urdu-finetuned",
        help="Output directory for checkpoints and final model"
    )
    parser.add_argument(
        "--language",
        default="ur",
        help="Target language code (default: ur for Urdu)"
    )
    parser.add_argument(
        "--max-steps",
        type=int,
        default=5000,
        help="Maximum training steps (default: 5000)"
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=16,
        help="Per-device batch size (default: 16)"
    )
    parser.add_argument(
        "--learning-rate",
        type=float,
        default=1e-5,
        help="Learning rate (default: 1e-5)"
    )
    
    args = parser.parse_args()
    
    try:
        finetune_whisper(
            dataset_dir=args.dataset_dir,
            model_name=args.model,
            output_dir=args.output_dir,
            language=args.language,
            max_steps=args.max_steps,
            batch_size=args.batch_size,
            learning_rate=args.learning_rate,
        )
    except Exception as e:
        logger.error("Fine-tuning failed: %s", e, exc_info=True)
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
