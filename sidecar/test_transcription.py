#!/usr/bin/env python3
"""
Quick transcription test script.
Records audio for 5 seconds and transcribes it to test speed and accuracy.
"""

import time
import logging
import sounddevice as sd
import numpy as np
from stt.engine import STTEngine
from audio.service import AudioService

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)


def test_transcription():
    """Record 5 seconds of audio and transcribe it."""
    
    logger.info("=" * 60)
    logger.info("EchoSync Transcription Test")
    logger.info("=" * 60)
    
    # Initialize STT engine
    logger.info("Loading STT engine...")
    stt = STTEngine()
    
    # Record audio
    duration = 5  # seconds
    sample_rate = 16000
    
    logger.info(f"\nRecording for {duration} seconds...")
    logger.info("Speak in Urdu, English, or Roman Urdu now!")
    logger.info("-" * 60)
    
    audio = sd.rec(
        int(duration * sample_rate),
        samplerate=sample_rate,
        channels=1,
        dtype='int16'
    )
    sd.wait()
    
    logger.info("Recording complete. Transcribing...")
    
    # Convert to WAV bytes
    import io
    import wave
    
    buf = io.BytesIO()
    with wave.open(buf, 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(audio.tobytes())
    
    wav_bytes = buf.getvalue()
    
    # Transcribe
    start_time = time.time()
    result = stt.transcribe(wav_bytes, is_partial=False)
    elapsed = time.time() - start_time
    
    # Display results
    logger.info("=" * 60)
    logger.info("RESULTS")
    logger.info("=" * 60)
    logger.info(f"Transcript: {result.text}")
    logger.info(f"Confidence: {result.confidence:.2%}")
    logger.info(f"Language: {result.language_detected}")
    logger.info(f"Processing time: {elapsed:.2f}s")
    logger.info(f"Real-time factor: {elapsed/duration:.2f}x")
    logger.info("=" * 60)
    
    if elapsed > duration:
        logger.warning(
            f"⚠️  Transcription is slower than real-time ({elapsed/duration:.2f}x)"
        )
        logger.warning("Consider:")
        logger.warning("  - Using the 'small' model instead of 'medium'")
        logger.warning("  - Installing GPU support (PyTorch + CUDA)")
        logger.warning("  - Reducing beam_size in stt/engine.py")
    else:
        logger.info(f"✓ Transcription is faster than real-time!")
    
    if result.confidence < 0.5:
        logger.warning(f"⚠️  Low confidence ({result.confidence:.2%})")
        logger.warning("Consider:")
        logger.warning("  - Speaking louder and clearer")
        logger.warning("  - Reducing background noise")
        logger.warning("  - Using the 'medium' model for better accuracy")
    
    if not result.text:
        logger.error("❌ No speech detected!")
        logger.error("Check:")
        logger.error("  - Microphone is working")
        logger.error("  - ENERGY_THRESHOLD in audio/service.py (try lowering it)")
        logger.error("  - Speaking loud enough")


if __name__ == "__main__":
    try:
        test_transcription()
    except KeyboardInterrupt:
        logger.info("\nTest cancelled.")
    except Exception as e:
        logger.error(f"Error: {e}", exc_info=True)
