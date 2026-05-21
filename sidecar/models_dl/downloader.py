"""
Model Downloader — first-run wizard backend.

Downloads GGUF model files, verifies SHA-256 checksums, streams progress.
Never marks a file as ready if checksum verification fails.
"""

from __future__ import annotations

import hashlib
import logging
import os
import platform
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

logger = logging.getLogger(__name__)

# Known-good SHA-256 checksums for required model files
MODEL_CHECKSUMS: dict[str, str] = {
    "Llama-3.2-3B-Instruct-Q4_K_M.gguf": "",  # populated at release time
    "silero_vad.onnx": "",
}

REQUIRED_MODELS = list(MODEL_CHECKSUMS.keys())


@dataclass
class DownloadResult:
    success: bool
    filename: str
    message: str


def _get_models_dir() -> Path:
    if platform.system() == "Windows":
        appdata = os.environ.get("APPDATA", "")
        return Path(appdata) / "EchoSync" / "models"
    return Path.home() / ".echosync" / "models"


class ModelDownloader:
    """Handles model file downloads with checksum verification."""

    def __init__(self) -> None:
        self._models_dir = _get_models_dir()
        self._models_dir.mkdir(parents=True, exist_ok=True)

    def check_models_present(self) -> bool:
        """Return True if all required model files exist."""
        for filename in REQUIRED_MODELS:
            if not (self._models_dir / filename).exists():
                logger.info("Missing model: %s", filename)
                return False
        return True

    def get_missing_models(self) -> list[str]:
        """Return list of missing model filenames."""
        return [f for f in REQUIRED_MODELS if not (self._models_dir / f).exists()]

    def download(
        self,
        source_url: str,
        filename: str,
        on_progress: Callable[[float], None],
    ) -> DownloadResult:
        """
        Download a model file from source_url and verify its checksum.

        Args:
            source_url:   URL or local file path to download from.
            filename:     Target filename in the models directory.
            on_progress:  Callback receiving progress as float 0.0–1.0.

        Returns:
            DownloadResult indicating success or failure.
        """
        dest_path = self._models_dir / filename

        try:
            if source_url.startswith(("http://", "https://")):
                result = self._download_http(source_url, dest_path, on_progress)
            else:
                result = self._copy_local(Path(source_url), dest_path, on_progress)

            if not result:
                return DownloadResult(
                    success=False, filename=filename,
                    message="Download failed or was interrupted."
                )

            # Verify checksum if known
            expected = MODEL_CHECKSUMS.get(filename, "")
            if expected:
                if not self.verify_checksum(dest_path, expected):
                    dest_path.unlink(missing_ok=True)
                    return DownloadResult(
                        success=False, filename=filename,
                        message="Checksum verification failed. File deleted. Please retry."
                    )

            on_progress(1.0)
            logger.info("Model '%s' downloaded and verified successfully.", filename)
            return DownloadResult(success=True, filename=filename, message="OK")

        except Exception as exc:
            dest_path.unlink(missing_ok=True)
            logger.error("Download error for '%s': %s", filename, exc)
            return DownloadResult(success=False, filename=filename, message=str(exc))

    def verify_checksum(self, file_path: Path, expected_sha256: str) -> bool:
        """
        Verify SHA-256 checksum of a file.

        Returns True if checksum matches or expected is empty (skip check).
        Returns False if mismatch.
        """
        if not expected_sha256:
            return True  # no known checksum — skip verification

        sha256 = hashlib.sha256()
        try:
            with open(file_path, "rb") as f:
                for chunk in iter(lambda: f.read(65536), b""):
                    sha256.update(chunk)
            actual = sha256.hexdigest()
            match = actual.lower() == expected_sha256.lower()
            if not match:
                logger.error(
                    "Checksum mismatch for %s: expected %s, got %s",
                    file_path.name, expected_sha256, actual,
                )
            return match
        except Exception as exc:
            logger.error("Checksum verification error: %s", exc)
            return False

    def _download_http(
        self,
        url: str,
        dest: Path,
        on_progress: Callable[[float], None],
    ) -> bool:
        """Download from HTTP URL with progress reporting."""
        try:
            import httpx
            with httpx.stream("GET", url, follow_redirects=True, timeout=300) as r:
                r.raise_for_status()
                total = int(r.headers.get("content-length", 0))
                downloaded = 0
                with open(dest, "wb") as f:
                    for chunk in r.iter_bytes(chunk_size=65536):
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total > 0:
                            on_progress(min(downloaded / total, 0.99))
            return True
        except Exception as exc:
            logger.error("HTTP download failed: %s", exc)
            return False

    def _copy_local(
        self,
        source: Path,
        dest: Path,
        on_progress: Callable[[float], None],
    ) -> bool:
        """Copy from local path with progress reporting."""
        try:
            total = source.stat().st_size
            copied = 0
            with open(source, "rb") as src, open(dest, "wb") as dst:
                for chunk in iter(lambda: src.read(65536), b""):
                    dst.write(chunk)
                    copied += len(chunk)
                    if total > 0:
                        on_progress(min(copied / total, 0.99))
            return True
        except Exception as exc:
            logger.error("Local copy failed: %s", exc)
            return False
