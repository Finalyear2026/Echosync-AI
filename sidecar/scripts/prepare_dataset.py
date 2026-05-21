#!/usr/bin/env python3
"""
Dataset preparation script for Whisper fine-tuning.
Converts audio files and metadata into HuggingFace dataset format.
"""

import argparse
import logging
from pathlib import Path
import pandas as pd
from datasets import Dataset, Audio, DatasetDict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def prepare_whisper_dataset(
    audio_dir: str,
    metadata_csv: str,
    output_dir: str,
    test_split: float = 0.1,
    validation_split: float = 0.05,
) -> DatasetDict:
    """
    Prepare dataset for Whisper fine-tuning.
    
    Args:
        audio_dir: Directory containing audio files
        metadata_csv: CSV/TSV with columns: file_name/path, transcript/sentence, duration, language
        output_dir: Where to save processed dataset
        test_split: Fraction for test set (default 0.1 = 10%)
        validation_split: Fraction for validation set (default 0.05 = 5%)
    
    Returns:
        DatasetDict with train/validation/test splits
    """
    
    logger.info("Loading metadata from %s", metadata_csv)
    
    # Auto-detect separator (CSV or TSV)
    separator = '\t' if metadata_csv.endswith('.tsv') else ','
    df = pd.read_csv(metadata_csv, sep=separator)
    
    logger.info("Detected %d rows in metadata", len(df))
    logger.info("Columns: %s", list(df.columns))
    
    # Handle Common Voice format (path, sentence) or custom format (file_name, transcript)
    if 'path' in df.columns and 'sentence' in df.columns:
        # Common Voice format
        logger.info("Detected Common Voice format (path, sentence)")
        df = df.rename(columns={'path': 'file_name', 'sentence': 'transcript'})
    elif 'file_name' not in df.columns or 'transcript' not in df.columns:
        # Try to find similar columns
        file_col = next((c for c in df.columns if 'file' in c.lower() or 'path' in c.lower()), None)
        text_col = next((c for c in df.columns if 'transcript' in c.lower() or 'sentence' in c.lower() or 'text' in c.lower()), None)
        
        if file_col and text_col:
            logger.info(f"Using columns: {file_col} → file_name, {text_col} → transcript")
            df = df.rename(columns={file_col: 'file_name', text_col: 'transcript'})
        else:
            raise ValueError(
                f"Could not find required columns. Available: {list(df.columns)}\n"
                f"Expected: 'file_name' and 'transcript' OR 'path' and 'sentence'"
            )
    
    # Filter out empty transcripts
    original_len = len(df)
    df = df[df['transcript'].notna() & (df['transcript'].str.strip() != '')]
    if len(df) < original_len:
        logger.info("Filtered out %d rows with empty transcripts", original_len - len(df))
    
    # Build full audio paths
    audio_dir_path = Path(audio_dir)
    audio_paths = []
    valid_indices = []
    
    for idx, filename in enumerate(df["file_name"]):
        audio_path = audio_dir_path / filename
        if audio_path.exists():
            audio_paths.append(str(audio_path))
            valid_indices.append(idx)
        else:
            logger.warning("Audio file not found: %s", audio_path)
    
    # Filter to valid files only
    df = df.iloc[valid_indices].reset_index(drop=True)
    
    logger.info("Found %d valid audio files", len(audio_paths))
    
    # Create dataset
    dataset = Dataset.from_dict({
        "audio": audio_paths,
        "sentence": df["transcript"].tolist(),
    })
    
    # Cast audio column to Audio type (will load and resample to 16kHz)
    logger.info("Processing audio files (resampling to 16kHz)...")
    dataset = dataset.cast_column("audio", Audio(sampling_rate=16000))
    
    # Create splits
    logger.info("Creating train/validation/test splits...")
    
    # First split: separate test set
    train_val_test = dataset.train_test_split(test_size=test_split, seed=42)
    test_dataset = train_val_test["test"]
    train_val_dataset = train_val_test["train"]
    
    # Second split: separate validation from train
    val_size = validation_split / (1 - test_split)  # Adjust for already removed test
    train_val = train_val_dataset.train_test_split(test_size=val_size, seed=42)
    
    dataset_dict = DatasetDict({
        "train": train_val["train"],
        "validation": train_val["test"],
        "test": test_dataset,
    })
    
    logger.info("Dataset splits:")
    logger.info("  Train: %d samples", len(dataset_dict["train"]))
    logger.info("  Validation: %d samples", len(dataset_dict["validation"]))
    logger.info("  Test: %d samples", len(dataset_dict["test"]))
    
    # Save to disk
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    logger.info("Saving dataset to %s", output_path)
    dataset_dict.save_to_disk(str(output_path))
    
    logger.info("✓ Dataset preparation complete!")
    
    return dataset_dict


def main():
    parser = argparse.ArgumentParser(
        description="Prepare audio dataset for Whisper fine-tuning"
    )
    parser.add_argument(
        "--audio-dir",
        required=True,
        help="Directory containing audio files (.wav, .mp3, etc.)"
    )
    parser.add_argument(
        "--metadata",
        required=True,
        help="CSV file with columns: file_name, transcript, [duration], [language]"
    )
    parser.add_argument(
        "--output-dir",
        default="dataset/processed",
        help="Output directory for processed dataset (default: dataset/processed)"
    )
    parser.add_argument(
        "--test-split",
        type=float,
        default=0.1,
        help="Fraction of data for test set (default: 0.1)"
    )
    parser.add_argument(
        "--validation-split",
        type=float,
        default=0.05,
        help="Fraction of data for validation set (default: 0.05)"
    )
    
    args = parser.parse_args()
    
    try:
        prepare_whisper_dataset(
            audio_dir=args.audio_dir,
            metadata_csv=args.metadata,
            output_dir=args.output_dir,
            test_split=args.test_split,
            validation_split=args.validation_split,
        )
    except Exception as e:
        logger.error("Failed to prepare dataset: %s", e, exc_info=True)
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
