"""
VAD Engine — wraps Silero VAD ONNX model for speech boundary detection.

Emits VADEvent literals:
  - "speech_start" : onset detected (within 300ms of first voiced frame)
  - "speech_end"   : silence window of 700ms elapsed after last voiced frame
"""

from __future__ import annotations

import logging
import time
from typing import Literal

import numpy as np

from config import config

logger = logging.getLogger(__name__)

VADEvent = Literal["speech_start", "speech_end"]


class VADEngine:
    """
    Stateful VAD engine wrapping Silero VAD ONNX.

    State machine: idle -> active -> idle
    """

    def __init__(self) -> None:
        self._model = None
        self._state: Literal["idle", "active"] = "idle"
        self._last_speech_time: float = 0.0
        self._h = np.zeros((2, 1, 64), dtype=np.float32)
        self._c = np.zeros((2, 1, 64), dtype=np.float32)
        
        # Load configuration
        self._sample_rate = config.audio.sample_rate
        self._frame_ms = config.audio.frame_ms
        self._frame_samples = int(self._sample_rate * self._frame_ms / 1000)
        self._speech_threshold = config.vad.silero_threshold
        self._silence_window_ms = config.vad.silero_silence_window_ms
        
        self._load_model()

    def _load_model(self) -> None:
        """Load Silero VAD ONNX model."""
        try:
            import onnxruntime as ort  # type: ignore[import]
            import os, platform
            from pathlib import Path

            if platform.system() == "Windows":
                appdata = os.environ.get("APPDATA", "")
                model_path = Path(appdata) / "EchoSync" / "models" / "silero_vad.onnx"
            else:
                model_path = Path.home() / ".echosync" / "models" / "silero_vad.onnx"

            if model_path.exists():
                self._model = ort.InferenceSession(
                    str(model_path),
                    providers=["CPUExecutionProvider"],
                )
                logger.info("Silero VAD ONNX model loaded from %s", model_path)
            else:
                logger.warning(
                    "Silero VAD model not found at %s. "
                    "VAD will use energy-based fallback.",
                    model_path,
                )
        except Exception as exc:
            logger.error("Failed to load Silero VAD model: %s", exc)

    def _predict_onnx(self, frame: np.ndarray) -> float:
        """Run ONNX inference and return speech probability."""
        if self._model is None:
            return self._energy_fallback(frame)

        try:
            # Silero VAD expects float32 normalized audio in shape (1, samples)
            audio = frame.astype(np.float32) / 32768.0  # normalize int16 to [-1, 1]
            audio = audio.reshape(1, -1)
            sr = np.array(self._sample_rate, dtype=np.int64)

            # Reset hidden states if needed
            ort_inputs = {
                "input": audio,
                "sr": sr,
                "h": self._h,
                "c": self._c,
            }
            out, self._h, self._c = self._model.run(None, ort_inputs)
            prob = float(out[0][0])
            if prob > 0.3:  # log when near threshold
                logger.debug("VAD prob=%.3f", prob)
            return prob
        except Exception as exc:
            logger.debug("ONNX inference error: %s — using energy fallback", exc)
            return self._energy_fallback(frame)

    @staticmethod
    def _energy_fallback(frame: np.ndarray) -> float:
        """RMS energy threshold fallback when ONNX model unavailable."""
        rms = float(np.sqrt(np.mean(frame.astype(np.float32) ** 2)))
        # RMS of 100+ = likely speech for low-volume mics
        prob = min(rms / 800.0, 1.0)
        return prob

    def process_frame(self, frame: np.ndarray) -> VADEvent | None:
        """
        Process a single 30ms PCM frame and return a VADEvent or None.

        Args:
            frame: numpy array of int16 PCM samples (480 samples @ 16kHz).

        Returns:
            "speech_start" when speech onset is detected (idle -> active).
            "speech_end"   when silence window expires (active -> idle).
            None           when no state transition occurs.
        """
        prob = self._predict_onnx(frame)
        now = time.monotonic()

        if prob >= self._speech_threshold:
            self._last_speech_time = now
            if self._state == "idle":
                self._state = "active"
                logger.debug("VAD: speech_start (prob=%.3f)", prob)
                return "speech_start"
        else:
            if self._state == "active":
                silence_ms = (now - self._last_speech_time) * 1000
                if silence_ms >= self._silence_window_ms:
                    self._state = "idle"
                    logger.debug(
                        "VAD: speech_end (silence=%.0fms)", silence_ms
                    )
                    return "speech_end"

        return None

    def reset(self) -> None:
        """Reset VAD state and LSTM hidden states."""
        self._state = "idle"
        self._last_speech_time = 0.0
        self._h = np.zeros((2, 1, 64), dtype=np.float32)
        self._c = np.zeros((2, 1, 64), dtype=np.float32)
