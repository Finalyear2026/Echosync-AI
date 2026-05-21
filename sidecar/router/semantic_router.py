"""
Semantic Router — classifies transcripts as "command" or "question".

Two-stage approach:
  1. Fast keyword/regex matching against curated Urdu + English command phrases.
  2. Cosine similarity fallback using sentence-transformers (all-MiniLM-L6-v2).

Defaults to "question" on low confidence (safe fallback to Agentic Engine).
Classification must complete within 100ms.
"""

from __future__ import annotations

import logging
import re
import time
from typing import Literal

logger = logging.getLogger(__name__)

RouteResult = Literal["command", "question"]

# ---------------------------------------------------------------------------
# Command keyword patterns (Urdu + English)
# ---------------------------------------------------------------------------

COMMAND_PATTERNS: list[re.Pattern[str]] = [
    # English task commands
    re.compile(r"\b(create|add|make|new)\s+(a\s+)?(task|todo|to-do|reminder|meeting)\b", re.I),
    re.compile(r"\b(complete|finish|done|mark)\s+(the\s+)?(task|todo)\b", re.I),
    re.compile(r"\b(update|change|edit|modify)\s+(the\s+)?(task|meeting|reminder)\b", re.I),
    re.compile(r"\bschedule\s+(a\s+)?(meeting|call|appointment)\b", re.I),
    re.compile(r"\bset\s+(a\s+)?(reminder|alarm|alert)\b", re.I),
    re.compile(r"\bremind\s+me\b", re.I),
    re.compile(r"\bcancel\s+(the\s+)?(meeting|reminder|task)\b", re.I),
    # Urdu/Roman Urdu task commands
    re.compile(r"\b(task|kaam)\s+(bana|banao|likho|add karo)\b", re.I),
    re.compile(r"\b(meeting|mulaqat)\s+(schedule|fix|set)\s*(kar|karo|kardo|karo)\b", re.I),
    re.compile(r"\b(reminder|yaad\s*dihani)\s+(set|lagao|laga)\b", re.I),
    re.compile(r"\b(kaam|task)\s+(mukammal|complete|khatam)\s*(kar|karo|kiya)\b", re.I),
    re.compile(r"\b(schedule|fix)\s+kar\b", re.I),
    re.compile(r"\b(add|likho|bana)\s+(karo|do|dena)\b", re.I),
    re.compile(r"\bkal\s+(ke\s+liye\s+)?(meeting|task|reminder)\b", re.I),
    re.compile(r"\b(parson|aaj|kal)\s+(meeting|task)\s*(schedule|set|bana)\b", re.I),
]

# Confidence threshold for embedding fallback
EMBEDDING_THRESHOLD = 0.45


class SemanticRouter:
    """
    Two-stage transcript classifier.

    Stage 1: Keyword/regex matching (fast, < 1ms).
    Stage 2: Sentence embedding cosine similarity (fallback, ~50-80ms).
    """

    def __init__(self) -> None:
        self._embedder = None
        self._command_embeddings = None
        self._question_embeddings = None
        self._load_embedder()

    def _load_embedder(self) -> None:
        """Lazily load sentence-transformers model."""
        try:
            from sentence_transformers import SentenceTransformer  # type: ignore[import]
            import numpy as np

            self._embedder = SentenceTransformer("all-MiniLM-L6-v2")

            # Reference sentences for cosine similarity
            command_refs = [
                "create a task", "schedule a meeting", "set a reminder",
                "add todo", "complete task", "task bana do", "meeting schedule karo",
                "reminder set karo", "kaam add karo",
            ]
            question_refs = [
                "what are my tasks", "am I free tomorrow", "summarize my week",
                "what meetings do I have", "show my schedule", "mera schedule kya hai",
                "kal kya hai", "is hafte kya karna hai",
            ]

            self._command_embeddings = self._embedder.encode(
                command_refs, normalize_embeddings=True
            )
            self._question_embeddings = self._embedder.encode(
                question_refs, normalize_embeddings=True
            )
            logger.info("SemanticRouter: sentence-transformers model loaded.")
        except Exception as exc:
            logger.warning(
                "SemanticRouter: could not load sentence-transformers (%s). "
                "Will use keyword-only classification.",
                exc,
            )

    def classify(self, transcript: str) -> RouteResult:
        """
        Classify transcript as "command" or "question".

        Args:
            transcript: Non-empty transcript string.

        Returns:
            "command" or "question". Defaults to "question" on low confidence.
        """
        if not transcript or not transcript.strip():
            return "question"

        t0 = time.monotonic()

        # Stage 1: keyword matching
        for pattern in COMMAND_PATTERNS:
            if pattern.search(transcript):
                elapsed_ms = (time.monotonic() - t0) * 1000
                logger.debug(
                    "SemanticRouter: command (keyword match, %.1fms)", elapsed_ms
                )
                return "command"

        # Stage 2: embedding similarity
        if self._embedder is not None:
            result = self._classify_by_embedding(transcript)
            elapsed_ms = (time.monotonic() - t0) * 1000
            logger.debug(
                "SemanticRouter: %s (embedding, %.1fms)", result, elapsed_ms
            )
            return result

        # Default fallback
        logger.debug("SemanticRouter: defaulting to 'question' (no embedder).")
        return "question"

    def _classify_by_embedding(self, transcript: str) -> RouteResult:
        """Use cosine similarity to classify when keyword matching fails."""
        try:
            import numpy as np

            query_emb = self._embedder.encode(
                [transcript], normalize_embeddings=True
            )

            cmd_scores = (self._command_embeddings @ query_emb.T).flatten()
            q_scores = (self._question_embeddings @ query_emb.T).flatten()

            max_cmd = float(cmd_scores.max())
            max_q = float(q_scores.max())

            if max_cmd < EMBEDDING_THRESHOLD and max_q < EMBEDDING_THRESHOLD:
                return "question"  # low confidence → safe default

            return "command" if max_cmd > max_q else "question"
        except Exception as exc:
            logger.warning("Embedding classification failed: %s", exc)
            return "question"
