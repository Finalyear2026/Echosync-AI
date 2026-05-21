"""
STT Engine — wraps faster-whisper for speech transcription.

Supports:
  - Batch transcription: transcribe(audio_bytes) -> TranscriptResult
  - Streaming partial transcripts: transcribe_streaming() for live preview

Model selection:
  - INT8 small  (default, RAM < 8GB)
  - INT8 medium (RAM >= 8GB)

Language hint: "ur" for Urdu/Punjabi mixed audio.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from typing import AsyncIterator, Awaitable, Callable

import numpy as np
import psutil

logger = logging.getLogger(__name__)

SAMPLE_RATE = 16000
RAM_THRESHOLD_BYTES = 8 * 1024 ** 3
PARTIAL_THROTTLE_SECONDS = 1.0  # max one partial update per second


@dataclass
class TranscriptResult:
    text: str
    confidence: float  # mean segment probability (0.0–1.0)
    language_detected: str


@dataclass
class PartialTranscript:
    text: str
    is_final: bool  # False = partial preview, True = finalized


class STTEngine:
    """Wraps faster-whisper for batch and streaming transcription."""

    def __init__(self) -> None:
        self._model = None
        self._model_size = self._select_model_size()
        self._load_model()

    @staticmethod
    def _select_model_size() -> str:
        available = psutil.virtual_memory().available
        return "medium" if available >= RAM_THRESHOLD_BYTES else "small"

    def _load_model(self) -> None:
        try:
            from faster_whisper import WhisperModel  # type: ignore[import]
            import os
            import platform
            from pathlib import Path
            
            # Check for fine-tuned model first
            model_path = self._model_size  # Default to generic model
            
            if platform.system() == "Windows":
                appdata = os.environ.get("APPDATA", "")
                custom_model_path = Path(appdata) / "EchoSync" / "models" / "whisper-base-urdu-ct2"
            else:
                custom_model_path = Path.home() / ".echosync" / "models" / "whisper-base-urdu-ct2"
            
            if custom_model_path.exists() and (custom_model_path / "model.bin").exists():
                logger.info("✓ Found fine-tuned Urdu model at %s", custom_model_path)
                model_path = str(custom_model_path)
            else:
                logger.info("Using generic %s model (fine-tuned model not found)", self._model_size)
            
            # Try to detect CUDA availability for GPU acceleration
            device = "cpu"
            compute_type = "int8"
            
            try:
                import torch
                if torch.cuda.is_available():
                    device = "cuda"
                    compute_type = "float16"  # GPU uses float16 for speed
                    logger.info("CUDA detected - using GPU acceleration")
            except ImportError:
                logger.info("PyTorch not available - using CPU")
            
            logger.info("Loading faster-whisper model: %s (%s, %s)", 
                       model_path, device, compute_type)
            
            self._model = WhisperModel(
                model_path,
                device=device,
                compute_type=compute_type,
                num_workers=4 if device == "cpu" else 1,  # Multi-threading for CPU
                cpu_threads=4 if device == "cpu" else 0,
            )
            logger.info("faster-whisper model loaded successfully.")
        except Exception as exc:
            logger.error("Failed to load faster-whisper model: %s", exc)

    def transcribe(self, audio_bytes: bytes, is_partial: bool = False) -> TranscriptResult:
        """
        Transcribe a WAV audio segment.

        Args:
            audio_bytes: Raw WAV bytes (16kHz mono PCM).
            is_partial: If True, use faster settings for real-time partial transcripts.

        Returns:
            TranscriptResult with text, confidence, and detected language.
            Returns empty TranscriptResult if no speech detected.
        """
        if self._model is None:
            logger.warning("STT model not loaded — returning empty transcript.")
            return TranscriptResult(text="", confidence=0.0, language_detected="")

        try:
            import io
            audio_array = _bytes_to_float32(audio_bytes)

            # Optimize parameters based on whether this is partial or final
            beam_size = 1 if is_partial else 3  # Faster for partials, more accurate for final
            best_of = 1 if is_partial else 3    # Single pass for partials
            
            # Initial prompt helps with Urdu/Roman Urdu accuracy
            initial_prompt = "یہ اردو، پنجابی اور انگریزی میں بات چیت ہے۔ Roman Urdu bhi use ho sakti hai."

            segments, info = self._model.transcribe(
                audio_array,
                language=None,  # Auto-detect language (supports English, Urdu, Punjabi)
                beam_size=beam_size,
                best_of=best_of,
                temperature=0.0,  # Deterministic output
                compression_ratio_threshold=2.4,
                log_prob_threshold=-1.0,
                no_speech_threshold=0.6,
                condition_on_previous_text=True,  # Better context for continuous speech
                initial_prompt=initial_prompt,
                word_timestamps=False,  # Faster without word-level timing
                vad_filter=False,  # we handle VAD ourselves
                without_timestamps=True,  # Faster text-only mode
            )

            segment_list = list(segments)
            if not segment_list:
                return TranscriptResult(text="", confidence=0.0,
                                        language_detected=info.language)

            text = " ".join(s.text.strip() for s in segment_list).strip()
            # Mean of per-segment avg_logprob converted to probability
            probs = [min(1.0, max(0.0, 2 ** s.avg_logprob)) for s in segment_list]
            confidence = float(sum(probs) / len(probs)) if probs else 0.0

            return TranscriptResult(
                text=text,
                confidence=confidence,
                language_detected=info.language,
            )
        except Exception as exc:
            logger.error("Transcription error: %s", exc)
            return TranscriptResult(text="", confidence=0.0, language_detected="")

    async def transcribe_streaming(
        self,
        audio_stream: AsyncIterator[bytes],
        on_partial: Callable[[PartialTranscript], Awaitable[None]],
    ) -> TranscriptResult:
        """
        Stream partial transcripts while audio is being captured.

        Processes rolling 2-second windows and emits PartialTranscript events
        throttled to at most one per second. Emits a final PartialTranscript
        with is_final=True when the stream ends.

        Args:
            audio_stream: Async iterator yielding raw PCM bytes chunks.
            on_partial:   Async callback receiving each PartialTranscript.

        Returns:
            The final authoritative TranscriptResult.
        """
        buffer = bytearray()
        last_emit_time = 0.0
        window_bytes = SAMPLE_RATE * 2 * 2  # 2 seconds of int16 @ 16kHz

        async for chunk in audio_stream:
            buffer.extend(chunk)

            now = time.monotonic()
            if (now - last_emit_time) >= PARTIAL_THROTTLE_SECONDS and len(buffer) >= window_bytes:
                window = bytes(buffer[-window_bytes:])
                partial_result = self.transcribe(window, is_partial=True)  # Use fast mode for partials
                if partial_result.text:
                    await on_partial(PartialTranscript(
                        text=partial_result.text,
                        is_final=False,
                    ))
                    last_emit_time = now

        # Final transcription of the complete buffer with full accuracy
        final_result = self.transcribe(bytes(buffer), is_partial=False)
        await on_partial(PartialTranscript(
            text=final_result.text,
            is_final=True,
        ))
        return final_result


def _bytes_to_float32(audio_bytes: bytes) -> np.ndarray:
    """Convert raw PCM int16 bytes to float32 numpy array in [-1, 1]."""
    import struct
    import wave
    import io

    try:
        # Try parsing as WAV first
        with wave.open(io.BytesIO(audio_bytes)) as wf:
            raw = wf.readframes(wf.getnframes())
            samples = np.frombuffer(raw, dtype=np.int16)
    except Exception:
        # Fall back to treating as raw int16 PCM
        samples = np.frombuffer(audio_bytes, dtype=np.int16)

    return samples.astype(np.float32) / 32768.0
