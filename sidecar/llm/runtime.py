"""
LLM_Runtime — singleton wrapper around llama_cpp.Llama.

Manages model loading/unloading based on available system RAM:
  - RAM < 8GB : load on first session request; auto-unload after 5-minute idle
  - RAM >= 8GB: load at startup; never auto-unload

Raises OfflineViolationError if the resolved model path looks like a network
location (http://, https://, or a UNC path starting with \\).
"""

from __future__ import annotations

import logging
import os
import platform
import threading
from pathlib import Path
from typing import Optional

import psutil

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MODEL_FILENAME = "Llama-3.2-3B-Instruct-Q4_K_M.gguf"
CONTEXT_WINDOW = 4096
RAM_THRESHOLD_BYTES = 8 * 1024 ** 3  # 8 GB
IDLE_TIMEOUT_SECONDS = 5 * 60  # 5 minutes


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------


class OfflineViolationError(Exception):
    """Raised when the model path resolves to a network location."""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _get_models_dir() -> Path:
    """Return the platform-appropriate models directory."""
    if platform.system() == "Windows":
        appdata = os.environ.get("APPDATA", "")
        return Path(appdata) / "EchoSync" / "models"
    return Path.home() / ".echosync" / "models"


def _validate_model_path(path: Path | str) -> None:
    """
    Raise OfflineViolationError if *path* looks like a network location.

    Blocked prefixes:
      - http://
      - https://
      - \\\\ (UNC path)
    """
    # Always validate against the raw string — Path() on Windows can mangle
    # URL-like strings (e.g. "http://..." becomes a relative path).
    path_str = str(path)
    for prefix in ("http://", "https://", "\\\\"):
        if path_str.lower().startswith(prefix.lower()):
            raise OfflineViolationError(
                f"Model path '{path_str}' appears to be a network location "
                f"(starts with '{prefix}'). EchoSync operates fully offline — "
                "models must be loaded from the local file system only."
            )


def _available_ram() -> int:
    """Return available system RAM in bytes."""
    return psutil.virtual_memory().available


# ---------------------------------------------------------------------------
# LLMRuntime
# ---------------------------------------------------------------------------


class LLMRuntime:
    """
    Singleton wrapper around llama_cpp.Llama.

    Do not instantiate directly — use :func:`get_llm_runtime`.
    """

    _instance: Optional["LLMRuntime"] = None

    def __init__(self) -> None:
        self._model: Optional[object] = None  # llama_cpp.Llama instance
        self._lock = threading.Lock()
        self._idle_timer: Optional[threading.Timer] = None
        self._high_ram: bool = _available_ram() >= RAM_THRESHOLD_BYTES

        available_mb = _available_ram() // (1024 ** 2)
        logger.info(
            "LLMRuntime initialised. Available RAM: %d MB. "
            "High-RAM mode: %s.",
            available_mb,
            self._high_ram,
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def load(self, model_path_override: str | None = None) -> None:
        """
        Load the GGUF model into memory.

        Args:
            model_path_override: Optional path string to override the default
                                 model location. Validated against network paths.

        Logs the memory state before and after loading.
        Raises:
            OfflineViolationError: if the model path is a network location.
            FileNotFoundError: if the model file does not exist.
        """
        with self._lock:
            if self._model is not None:
                logger.debug("LLMRuntime.load() called but model already loaded.")
                return

            if model_path_override is not None:
                # Validate the raw string BEFORE converting to Path
                _validate_model_path(model_path_override)
                model_path = Path(model_path_override)
            else:
                model_path = _get_models_dir() / MODEL_FILENAME
                _validate_model_path(model_path)

            if not model_path.exists():
                models_dir = _get_models_dir()
                raise FileNotFoundError(
                    f"Model file not found: {model_path}\n"
                    f"Please place '{MODEL_FILENAME}' in the models directory:\n"
                    f"  {models_dir}\n"
                    "You can download the model via the EchoSync first-run wizard."
                )

            available_mb = _available_ram() // (1024 ** 2)
            logger.info(
                "Loading LLM model '%s'. Available RAM before load: %d MB.",
                MODEL_FILENAME,
                available_mb,
            )

            # Import here so the module can be imported even when llama_cpp
            # is not installed (e.g. during unit tests that mock this layer).
            try:
                from llama_cpp import Llama  # type: ignore[import]
            except ImportError as exc:
                raise ImportError(
                    "llama-cpp-python is not installed. "
                    "Install it with: pip install llama-cpp-python"
                ) from exc

            self._model = Llama(
                model_path=str(model_path),
                n_ctx=CONTEXT_WINDOW,
                verbose=False,
            )

            available_mb_after = _available_ram() // (1024 ** 2)
            logger.info(
                "LLM model loaded successfully. Available RAM after load: %d MB.",
                available_mb_after,
            )

    def unload(self) -> None:
        """
        Unload the model from memory and cancel any pending idle timer.

        Logs the memory state after unloading.
        """
        with self._lock:
            self._cancel_idle_timer()
            if self._model is None:
                logger.debug("LLMRuntime.unload() called but model is not loaded.")
                return

            self._model = None

            available_mb = _available_ram() // (1024 ** 2)
            logger.info(
                "LLM model unloaded. Available RAM after unload: %d MB.",
                available_mb,
            )

    def generate(
        self,
        prompt: str,
        grammar=None,
        max_tokens: int = 512,
    ) -> str:
        """
        Generate text from *prompt*.

        On low-RAM systems the model is loaded on demand here (if not already
        loaded) and the idle-unload timer is reset after each call.

        Args:
            prompt:     The input prompt string.
            grammar:    Optional ``llama_cpp.LlamaGrammar`` for GBNF-constrained
                        output.
            max_tokens: Maximum number of tokens to generate (default 512).

        Returns:
            The generated text as a string.

        Raises:
            OfflineViolationError: if the model path is a network location.
            FileNotFoundError: if the model file is missing.
        """
        # On low-RAM systems, load on demand.
        if not self._high_ram and self._model is None:
            self.load()

        with self._lock:
            if self._model is None:
                raise RuntimeError(
                    "LLM model is not loaded. Call LLMRuntime.load() first."
                )

            kwargs: dict = {
                "max_tokens": max_tokens,
                "echo": False,
            }
            if grammar is not None:
                kwargs["grammar"] = grammar

            result = self._model(prompt, **kwargs)  # type: ignore[operator]
            text: str = result["choices"][0]["text"]

        # Reset the idle timer after each generation on low-RAM systems.
        if not self._high_ram:
            self._reset_idle_timer()

        return text

    def is_loaded(self) -> bool:
        """Return ``True`` if the model is currently loaded in memory."""
        return self._model is not None

    # ------------------------------------------------------------------
    # RAM-aware lifecycle helpers
    # ------------------------------------------------------------------

    def _reset_idle_timer(self) -> None:
        """
        (Re)start the 5-minute idle timer that auto-unloads the model on
        low-RAM systems.  Must be called without holding ``self._lock``.
        """
        # Cancel any existing timer first (requires the lock).
        with self._lock:
            self._cancel_idle_timer()
            timer = threading.Timer(IDLE_TIMEOUT_SECONDS, self._on_idle_timeout)
            timer.daemon = True
            timer.start()
            self._idle_timer = timer
            logger.debug(
                "Idle unload timer reset (%d seconds).", IDLE_TIMEOUT_SECONDS
            )

    def _cancel_idle_timer(self) -> None:
        """Cancel the idle timer if one is running.  Caller must hold ``self._lock``."""
        if self._idle_timer is not None:
            self._idle_timer.cancel()
            self._idle_timer = None

    def _on_idle_timeout(self) -> None:
        """Called by the idle timer thread after 5 minutes of inactivity."""
        logger.info(
            "LLM idle timeout reached (%d s). Unloading model to free RAM.",
            IDLE_TIMEOUT_SECONDS,
        )
        self.unload()

    # ------------------------------------------------------------------
    # Startup helper (called by the sidecar on app start)
    # ------------------------------------------------------------------

    def startup_load(self) -> None:
        """
        Load the model at application startup according to the RAM policy:

        - RAM >= 8 GB: load immediately.
        - RAM < 8 GB:  do nothing; the model will be loaded on the first
                       ``generate()`` call.
        """
        available_mb = _available_ram() // (1024 ** 2)
        logger.info(
            "startup_load() called. Available RAM: %d MB. High-RAM mode: %s.",
            available_mb,
            self._high_ram,
        )
        if self._high_ram:
            self.load()
        else:
            logger.info(
                "Low-RAM mode: LLM will be loaded on first session request."
            )


# ---------------------------------------------------------------------------
# Singleton factory
# ---------------------------------------------------------------------------


def get_llm_runtime() -> LLMRuntime:
    """
    Return the process-wide :class:`LLMRuntime` singleton.

    Thread-safe: the singleton is created at most once even under concurrent
    calls.
    """
    if LLMRuntime._instance is None:
        # Double-checked locking is not strictly necessary in CPython due to
        # the GIL, but we use a module-level lock for correctness on all
        # Python implementations.
        with _singleton_lock:
            if LLMRuntime._instance is None:
                LLMRuntime._instance = LLMRuntime()
    return LLMRuntime._instance


# Module-level lock used only during singleton creation.
_singleton_lock = threading.Lock()
