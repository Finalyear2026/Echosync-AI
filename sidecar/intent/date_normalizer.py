"""
EchoSync AI Desktop — Date Normalizer.

Converts relative date expressions (including Urdu tokens) to absolute
datetime objects using the ``dateparser`` library.
"""

from __future__ import annotations

import re
from datetime import datetime

import dateparser


class DateNormalizer:
    """Resolve relative date/time expressions to absolute datetimes.

    Urdu relative tokens are translated to their English equivalents before
    being passed to ``dateparser``, which handles the full range of English
    relative expressions.
    """

    URDU_TOKEN_MAP: dict[str, str] = {
        "aaj": "today",
        "kal": "tomorrow",
        "parson": "day after tomorrow",
        "pichle hafte": "last week",
        "agla hafte": "next week",
        "pichle mahine": "last month",
        "agla mahine": "next month",
    }

    def normalize(self, expression: str, reference_dt: datetime) -> datetime | None:
        """Parse *expression* relative to *reference_dt*.

        Returns:
            A timezone-aware :class:`datetime` on success, or ``None`` if the
            expression cannot be resolved.
        """
        translated = self._apply_urdu_token_map(expression)

        settings = {
            "PREFER_DAY_OF_MONTH": "first",
            "RETURN_AS_TIMEZONE_AWARE": True,
            "RELATIVE_BASE": reference_dt,
        }

        result = dateparser.parse(translated, settings=settings)
        return result  # None if dateparser could not resolve

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _apply_urdu_token_map(self, expression: str) -> str:
        """Replace Urdu tokens with English equivalents (case-insensitive).

        Longer tokens are replaced first to avoid partial matches (e.g.
        "pichle hafte" must be replaced before "hafte" if "hafte" were in
        the map).
        """
        result = expression
        # Sort by token length descending so longer phrases match first.
        for urdu_token, english_equiv in sorted(
            self.URDU_TOKEN_MAP.items(), key=lambda kv: len(kv[0]), reverse=True
        ):
            # Case-insensitive whole-token replacement.
            pattern = re.compile(re.escape(urdu_token), re.IGNORECASE)
            result = pattern.sub(english_equiv, result)
        return result
