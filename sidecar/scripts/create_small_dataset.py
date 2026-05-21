#!/usr/bin/env python3
"""Create a smaller dataset (10% of original) for quick testing."""
import sys
from pathlib import Path
from datasets import load_from_disk

def create_small_dataset(input_dir: str, output_dir: str, fraction: float = 0.1):
    """Create a smaller version of the dataset."""
    print(f"Loading dataset from {input_dir}...")
    dataset = load_from_disk(input_dir)
    
    print(f"Original sizes:")
    for split, data in dataset.items():
        print(f"  {split}: {len(data)} samples")
    
    # Take a fraction of each split
    small_dataset = {}
    for split, data in dataset.items():
        n_samples = int(len(data) * fraction)
        small_dataset[split] = data.select(range(n_samples))
        print(f"  {split} reduced to: {n_samples} samples")
    
    # Save
    from datasets import DatasetDict
    small_ds = DatasetDict(small_dataset)
    
    print(f"\nSaving to {output_dir}...")
    small_ds.save_to_disk(output_dir)
    print("✓ Done!")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python create_small_dataset.py <input_dir> <output_dir> [fraction]")
        print("Example: python create_small_dataset.py ../dataset/processed_urdu ../dataset/processed_urdu_small 0.1")
        sys.exit(1)
    
    input_dir = sys.argv[1]
    output_dir = sys.argv[2]
    fraction = float(sys.argv[3]) if len(sys.argv) > 3 else 0.1
    
    create_small_dataset(input_dir, output_dir, fraction)
