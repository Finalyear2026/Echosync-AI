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

from config import config

logger = logging.getLogger(__name__)


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
        self._sample_rate = config.audio.sample_rate
        self._ram_threshold_bytes = config.stt.ram_threshold_gb * 1024 ** 3
        self._model_size = self._select_model_size()
        self._load_model()

    def _select_model_size(self) -> str:
        available = psutil.virtual_memory().available
        if available >= self._ram_threshold_bytes:
            return config.stt.model_size_medium
        return config.stt.model_size_small

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
                num_workers=config.stt.num_workers if device == "cpu" else 1,
                cpu_threads=config.stt.cpu_threads if device == "cpu" else 0,
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
            beam_size = config.stt.beam_size_partial if is_partial else config.stt.beam_size_final
            best_of = config.stt.best_of_partial if is_partial else config.stt.best_of_final

            segments, info = self._model.transcribe(
                audio_array,
                language=config.stt.language if config.stt.language else None,
                beam_size=beam_size,
                best_of=best_of,
                temperature=config.stt.temperature,
                compression_ratio_threshold=config.stt.compression_ratio_threshold,
                log_prob_threshold=config.stt.log_prob_threshold,
                no_speech_threshold=config.stt.no_speech_threshold,
                condition_on_previous_text=config.stt.condition_on_previous_text,
                initial_prompt=config.stt.initial_prompt,
                word_timestamps=False,
                vad_filter=False,  # we handle VAD ourselves
                without_timestamps=config.stt.without_timestamps,
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
        partial_interval = config.vad.partial_interval_seconds
        window_bytes = self._sample_rate * 2 * 2  # 2 seconds of int16 @ 16kHz

        async for chunk in audio_stream:
            buffer.extend(chunk)

            now = time.monotonic()
            if (now - last_emit_time) >= partial_interval and len(buffer) >= window_bytes:
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
