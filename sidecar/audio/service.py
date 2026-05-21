"""
Audio_Service — microphone capture with energy-based VAD and STT pipeline.

Uses a simple energy threshold for reliable speech detection,
with Silero VAD as an optional enhancement.
"""

from __future__ import annotations

import asyncio
import io
import logging
import queue
import threading
import time
import wave
from typing import Callable, Optional

import numpy as np

from stt.engine import PartialTranscript

logger = logging.getLogger(__name__)

SAMPLE_RATE = 16000
CHANNELS = 1
DTYPE = "int16"
FRAME_MS = 30
FRAME_SAMPLES = int(SAMPLE_RATE * FRAME_MS / 1000)  # 480 samples

# Energy-based VAD parameters
ENERGY_THRESHOLD = 150      # Increased to reduce background noise capture
SPEECH_FRAMES_MIN = 5       # minimum frames to start a segment (~150ms)
SILENCE_FRAMES_END = 25     # frames of silence to end segment (~750ms)
MAX_SEGMENT_FRAMES = 333    # max segment length (~10s)


class AudioService:
    """Manages microphone capture and the VAD → STT pipeline."""

    def __init__(self, stt_engine=None) -> None:
        from stt.engine import STTEngine
        self._stt = stt_engine or STTEngine()
        self._running = False
        self._stream = None
        self._frame_queue: queue.Queue = queue.Queue()
        self._processing_thread: Optional[threading.Thread] = None

        self._on_segment: Optional[Callable[[bytes], None]] = None
        self._on_partial: Optional[Callable[[PartialTranscript], None]] = None

    def on_speech_segment(self, callback: Callable[[bytes], None]) -> None:
        self._on_segment = callback

    def on_partial_transcript(self, callback: Callable[[PartialTranscript], None]) -> None:
        self._on_partial = callback

    def start_capture(self) -> None:
        if self._running:
            logger.warning("AudioService already running.")
            return

        try:
            import sounddevice as sd
        except ImportError:
            logger.error("sounddevice not installed.")
            return

        self._running = True

        self._processing_thread = threading.Thread(
            target=self._process_frames, daemon=True
        )
        self._processing_thread.start()

        self._stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype=DTYPE,
            blocksize=FRAME_SAMPLES,
            callback=self._audio_callback,
        )
        self._stream.start()

        try:
            mic_name = sd.query_devices(kind='input')['name']
        except Exception:
            mic_name = "unknown"
        logger.info("AudioService started. Microphone: %s", mic_name)

    def stop_capture(self) -> None:
        self._running = False
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        if self._processing_thread is not None:
            self._frame_queue.put(None)
            self._processing_thread.join(timeout=3.0)
            self._processing_thread = None
        logger.info("AudioService stopped.")

    def _audio_callback(self, indata: np.ndarray, frames: int, time_info, status) -> None:
        if status:
            logger.debug("sounddevice status: %s", status)
        frame = indata[:, 0].copy()
        self._frame_queue.put(frame)

    def _process_frames(self) -> None:
        """Energy-based VAD: collect speech frames, transcribe on silence."""
        speech_buffer: list[np.ndarray] = []
        silence_count = 0
        speech_count = 0
        in_speech = False
        last_partial_time = 0.0

        while self._running:
            try:
                frame = self._frame_queue.get(timeout=0.1)
            except queue.Empty:
                continue

            if frame is None:
                break

            rms = float(np.sqrt(np.mean(frame.astype(np.float32) ** 2)))
            is_speech = rms > ENERGY_THRESHOLD

            if is_speech:
                speech_count += 1
                silence_count = 0
                speech_buffer.append(frame)

                if not in_speech and speech_count >= SPEECH_FRAMES_MIN:
                    in_speech = True
                    logger.info("Speech started (RMS=%.1f)", rms)
                    self._emit_partial(PartialTranscript(text="", is_final=False))

                # Emit rolling partial every 2 seconds while speaking
                if in_speech:
                    now = time.monotonic()
                    if now - last_partial_time >= 2.0 and len(speech_buffer) >= 100:
                        # Use larger window (6s) for better Urdu accuracy in partials
                        window = speech_buffer[-200:] if len(speech_buffer) >= 200 else speech_buffer
                        wav = self._frames_to_wav(window)
                        result = self._stt.transcribe(wav)
                        if result.text:
                            logger.info("Partial: %s", result.text[:60])
                            self._emit_partial(PartialTranscript(text=result.text, is_final=False))
                        last_partial_time = now

                # Force end if segment too long
                if len(speech_buffer) >= MAX_SEGMENT_FRAMES:
                    logger.info("Max segment length reached, processing...")
                    self._finalize_segment(speech_buffer)
                    speech_buffer = []
                    in_speech = False
                    speech_count = 0
                    silence_count = 0
                    last_partial_time = 0.0

            else:
                if in_speech:
                    silence_count += 1
                    speech_buffer.append(frame)  # include trailing silence

                    if silence_count >= SILENCE_FRAMES_END:
                        logger.info("Speech ended (%d frames)", len(speech_buffer))
                        self._finalize_segment(speech_buffer)
                        speech_buffer = []
                        in_speech = False
                        speech_count = 0
                        silence_count = 0
                        last_partial_time = 0.0
                else:
                    speech_count = max(0, speech_count - 1)

    def _finalize_segment(self, frames: list[np.ndarray]) -> None:
        """Transcribe a completed speech segment."""
        if not frames:
            return
        wav_bytes = self._frames_to_wav(frames)
        logger.info("Transcribing segment (%d bytes)...", len(wav_bytes))
        result = self._stt.transcribe(wav_bytes)
        logger.info("Transcript: '%s' (confidence=%.2f)", result.text, result.confidence)

        if result.text:
            if self._on_segment:
                self._on_segment(wav_bytes)
            self._emit_partial(PartialTranscript(text=result.text, is_final=True))
        else:
            logger.info("No speech detected in segment.")

    def _emit_partial(self, partial: PartialTranscript) -> None:
        if self._on_partial:
            try:
                result = self._on_partial(partial)
                # Handle both sync and async callbacks
                if asyncio.iscoroutine(result):
                    # Schedule on the event loop if available
                    try:
                        loop = asyncio.get_event_loop()
                        if loop.is_running():
                            asyncio.run_coroutine_threadsafe(result, loop)
                        else:
                            loop.run_until_complete(result)
                    except Exception:
                        pass
            except Exception as exc:
                logger.debug("Partial callback error: %s", exc)

    @staticmethod
    def _frames_to_wav(frames: list[np.ndarray]) -> bytes:
        pcm = np.concatenate(frames).astype(np.int16)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(2)
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(pcm.tobytes())
        return buf.getvalue()
