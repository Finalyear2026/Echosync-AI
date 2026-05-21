"""
EchoSync AI Desktop — Intent Sanitizer.

Cleans all string fields in an intent before any database write.  Applies
four sequential rules to every string field and rejects the entire intent if
a prompt-injection pattern is detected.
"""

from __future__ import annotations

import logging
import re
import unicodedata
from dataclasses import dataclass

from intent.models import AnyIntent

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# SQL metacharacter sequences to strip (order matters: longer tokens first).
_SQL_PATTERNS: list[str] = ["--", "/*", "*/", "xp_", "'", '"', ";"]

# Compiled regex for HTML / script tags.
_HTML_TAG_RE = re.compile(r"<[^>]+>")

# Prompt injection signatures (case-insensitive substring match).
_INJECTION_SIGNATURES: list[str] = [
    "ignore previous",
    "system:",
    "<|",
    "[INST]",
    "###",
]

# Maximum allowed length for any free-text field.
_MAX_FIELD_LEN = 500


# ---------------------------------------------------------------------------
# Public types
# ---------------------------------------------------------------------------


@dataclass
class SanitizationError:
    """Returned when an intent is rejected due to a security violation."""

    field: str   # field name only, never the value
    reason: str


# ---------------------------------------------------------------------------
# Sanitizer
# ---------------------------------------------------------------------------


class Sanitizer:
    """Validates and cleans all string fields in an intent before DB write."""

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def sanitize(self, intent: AnyIntent) -> AnyIntent | SanitizationError:
        """Return a new intent with sanitized string fields.

        Returns a :class:`SanitizationError` (not raises) if any field
        contains a prompt-injection pattern.
        """
        updates: dict[str, object] = {}

        for field_name, field_info in intent.model_fields.items():
            raw_value = getattr(intent, field_name)

            # Only process string fields (skip None, int, list, etc.)
            if not isinstance(raw_value, str):
                continue

            # --- Rule 5: Reject on prompt injection (check before cleaning) ---
            injection_result = self._check_injection(field_name, raw_value)
            if isinstance(injection_result, SanitizationError):
                return injection_result

            # --- Rules 1–4: Clean the value ---
            cleaned = self._clean_string(raw_value)

            # Re-check injection on cleaned value (edge case: cleaning may
            # expose a hidden pattern, but we also want to catch it in the
            # original value which we already did above).
            updates[field_name] = cleaned

        return intent.model_copy(update=updates)

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _check_injection(
        self, field_name: str, value: str
    ) -> SanitizationError | None:
        """Return a SanitizationError if *value* matches any injection pattern."""
        lower = value.lower()
        for sig in _INJECTION_SIGNATURES:
            if sig.lower() in lower:
                logger.warning(
                    "Prompt injection pattern detected in field '%s'", field_name
                )
                return SanitizationError(
                    field=field_name,
                    reason=f"prompt injection pattern detected: {sig!r}",
                )
        return None

    @staticmethod
    def _strip_sql_metacharacters(value: str) -> str:
        """Remove SQL metacharacter sequences from *value*."""
        for token in _SQL_PATTERNS:
            value = value.replace(token, "")
        return value

    @staticmethod
    def _strip_html_tags(value: str) -> str:
        """Remove HTML / script tags from *value*."""
        return _HTML_TAG_RE.sub("", value)

    @staticmethod
    def _strip_control_characters(value: str) -> str:
        """Remove Unicode control characters (categories Cc and Cf)."""
        return "".join(
            ch for ch in value if unicodedata.category(ch) not in ("Cc", "Cf")
        )

    @staticmethod
    def _enforce_max_length(value: str) -> str:
        """Truncate *value* to at most 500 characters."""
        return value[:_MAX_FIELD_LEN]

    def _clean_string(self, value: str) -> str:
        """Apply all four cleaning rules in sequence."""
        value = self._strip_sql_metacharacters(value)
        value = self._strip_html_tags(value)
        value = self._strip_control_characters(value)
        value = self._enforce_max_length(value)
        return value
