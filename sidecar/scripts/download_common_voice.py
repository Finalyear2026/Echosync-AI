#!/usr/bin/env python3
"""
Helper script to guide Common Voice Urdu dataset download.
"""

import sys

def main():
    print("=" * 70)
    print("Mozilla Common Voice Urdu Dataset Download Guide")
    print("=" * 70)
    print()
    print("📦 Dataset: Common Voice Urdu (اردو)")
    print("📊 Size: ~100+ hours of validated Urdu speech")
    print("💰 Cost: FREE (requires email signup)")
    print("📝 License: CC0 (Public Domain)")
    print()
    print("=" * 70)
    print("STEP-BY-STEP INSTRUCTIONS")
    print("=" * 70)
    print()
    print("1. Visit the Common Voice datasets page:")
    print("   https://commonvoice.mozilla.org/en/datasets")
    print()
    print("2. Scroll down and find 'Urdu (اردو)' in the language list")
    print()
    print("3. Click 'Download' next to Urdu")
    print()
    print("4. Sign up with your email (if not already signed in)")
    print()
    print("5. Select the dataset version:")
    print("   - Choose the LATEST version (highest number)")
    print("   - Download size: ~2-4 GB compressed")
    print()
    print("6. Download the file (e.g., cv-corpus-17.0-2024-03-15-ur.tar.gz)")
    print()
    print("7. Extract the downloaded file:")
    print()
    
    if sys.platform == "win32":
        print("   # Windows (PowerShell):")
        print("   mkdir dataset\\common_voice_ur")
        print("   tar -xzf cv-corpus-*-ur.tar.gz -C dataset\\common_voice_ur")
    else:
        print("   # Linux/Mac:")
        print("   mkdir -p dataset/common_voice_ur")
        print("   tar -xzf cv-corpus-*-ur.tar.gz -C dataset/common_voice_ur")
    
    print()
    print("8. Verify extraction:")
    print()
    
    if sys.platform == "win32":
        print("   dir dataset\\common_voice_ur\\cv-corpus-*\\ur\\")
    else:
        print("   ls dataset/common_voice_ur/cv-corpus-*/ur/")
    
    print()
    print("   You should see:")
    print("   - clips/          (audio files)")
    print("   - validated.tsv   (metadata)")
    print("   - train.tsv")
    print("   - dev.tsv")
    print("   - test.tsv")
    print()
    print("=" * 70)
    print("NEXT STEP")
    print("=" * 70)
    print()
    print("After downloading and extracting, run:")
    print()
    print("python scripts/prepare_dataset.py \\")
    
    if sys.platform == "win32":
        print("    --audio-dir dataset\\common_voice_ur\\cv-corpus-*\\ur\\clips \\")
        print("    --metadata dataset\\common_voice_ur\\cv-corpus-*\\ur\\validated.tsv \\")
        print("    --output-dir dataset\\processed_urdu")
    else:
        print("    --audio-dir dataset/common_voice_ur/cv-corpus-*/ur/clips \\")
        print("    --metadata dataset/common_voice_ur/cv-corpus-*/ur/validated.tsv \\")
        print("    --output-dir dataset/processed_urdu")
    
    print()
    print("=" * 70)
    print("ALTERNATIVE: Direct Download Link (if available)")
    print("=" * 70)
    print()
    print("If you have trouble with the website, you can try:")
    print("https://mozilla-common-voice-datasets.s3.amazonaws.com/")
    print()
    print("Look for the latest Urdu dataset file.")
    print()
    print("=" * 70)
    print()
    print("Questions? Check MANUAL_FINETUNING_WALKTHROUGH.md for details.")
    print()

if __name__ == "__main__":
    main()
