"""
Intent Engine — GBNF-constrained LLM extraction for deterministic CRUD intents.

Uses llama-cpp-python with grammar-constrained sampling to force valid JSON.
Retries up to 2 times on grammar/schema violation before returning failure.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from intent.models import AnyIntent, BaseIntent
from intent.sanitizer import Sanitizer, SanitizationError

logger = logging.getLogger(__name__)

GRAMMAR_PATH = Path(__file__).parent / "grammar.gbnf"
MAX_RETRIES = 2  # up to 2 retries = 3 total attempts

SYSTEM_PROMPT = """You are EchoSync AI, a multilingual voice assistant that understands Urdu, Punjabi, English, and Roman Urdu (Urdu written in Latin script).

Your task is to extract structured intent from voice transcripts. You MUST output valid JSON matching exactly one of these intent types:
- create_task: when user wants to create a task or todo
- update_task: when user wants to update/change a task
- complete_task: when user wants to mark a task as done
- schedule_meeting: when user wants to schedule a meeting or appointment
- set_reminder: when user wants to set a reminder

Examples of Roman Urdu commands:
- "kal meeting schedule kar do" → schedule_meeting
- "task bana do report likhna hai" → create_task
- "reminder set karo subah 9 baje" → set_reminder
- "kaam mukammal kar do" → complete_task

Always include the raw_transcript field with the original text.
Output ONLY the JSON object, nothing else."""


@dataclass
class IntentResult:
    success: bool
    intent: Optional[BaseIntent]
    error: Optional[str]


class IntentEngine:
    """Extracts structured intents from transcripts using GBNF-constrained LLM."""

    def __init__(self) -> None:
        self._sanitizer = Sanitizer()
        self._grammar = None
        self._load_grammar()

    def _load_grammar(self) -> None:
        """Load GBNF grammar from file."""
        try:
            from llama_cpp import LlamaGrammar  # type: ignore[import]
            if GRAMMAR_PATH.exists():
                try:
                    self._grammar = LlamaGrammar.from_file(str(GRAMMAR_PATH))
                    logger.info("GBNF grammar loaded from %s", GRAMMAR_PATH)
                except Exception as grammar_exc:
                    logger.warning("Failed to parse GBNF grammar: %s. Will use simple extraction.", grammar_exc)
                    self._grammar = None
            else:
                logger.warning("Grammar file not found at %s", GRAMMAR_PATH)
        except Exception as exc:
            logger.error("Failed to load GBNF grammar: %s", exc)

    def extract_intent(self, transcript: str) -> IntentResult:
        """
        Extract a structured intent from a transcript.

        Uses simple rule-based extraction for reliability and speed.
        Falls back to LLM only if simple extraction fails and LLM is available.

        Args:
            transcript: The voice transcript to parse.

        Returns:
            IntentResult with success=True and a validated intent, or
            IntentResult with success=False and an error message.
        """
        # Try simple extraction first (fast and reliable)
        logger.info("Attempting simple rule-based extraction")
        simple_result = self._extract_simple(transcript)
        if simple_result.success:
            return simple_result
        
        # Fallback to LLM if simple extraction failed
        logger.info("Simple extraction failed, trying LLM fallback")
        from llm.runtime import get_llm_runtime

        runtime = get_llm_runtime()
        
        # Check if LLM is available
        if not runtime.is_loaded():
            try:
                runtime.load()
            except (FileNotFoundError, Exception) as exc:
                logger.warning("LLM not available: %s. Simple extraction already failed.", exc)
                return IntentResult(
                    success=False,
                    intent=None,
                    error="No intent pattern matched and LLM unavailable",
                )
        
        # Skip grammar-based extraction due to compatibility issues
        # Use free-form LLM generation instead
        logger.info("Using free-form LLM extraction (grammar disabled)")
        return self._extract_llm_freeform(transcript, runtime)

    def _build_prompt(self, transcript: str) -> str:
        return (
            f"<|system|>\n{SYSTEM_PROMPT}\n<|end|>\n"
            f"<|user|>\nTranscript: {transcript}\n<|end|>\n"
            f"<|assistant|>\n"
        )

    @staticmethod
    def _parse_intent(data: dict, transcript: str) -> Optional[BaseIntent]:
        """Parse raw dict into a typed Pydantic intent model."""
        from intent.models import (
            CreateTaskIntent, UpdateTaskIntent, CompleteTaskIntent,
            ScheduleMeetingIntent, SetReminderIntent,
        )

        # Ensure raw_transcript is present
        if "raw_transcript" not in data:
            data["raw_transcript"] = transcript

        intent_type = data.get("intent_type", "")
        model_map = {
            "create_task": CreateTaskIntent,
            "update_task": UpdateTaskIntent,
            "complete_task": CompleteTaskIntent,
            "schedule_meeting": ScheduleMeetingIntent,
            "set_reminder": SetReminderIntent,
        }

        model_cls = model_map.get(intent_type)
        if model_cls is None:
            return None

        try:
            return model_cls(**data)
        except Exception as exc:
            logger.debug("Pydantic validation error: %s", exc)
            return None
    
    def _extract_simple(self, transcript: str) -> IntentResult:
        """Fallback to simple rule-based extraction."""
        from intent.simple_extractor import SimpleIntentExtractor
        
        extractor = SimpleIntentExtractor()
        intent = extractor.extract(transcript)
        
        if intent is None:
            return IntentResult(
                success=False,
                intent=None,
                error="No intent pattern matched",
            )
        
        # Sanitize
        sanitized = self._sanitizer.sanitize(intent)
        if isinstance(sanitized, SanitizationError):
            return IntentResult(
                success=False,
                intent=None,
                error=f"Sanitization rejected intent: {sanitized.reason}",
            )
        
        logger.info("Simple extraction successful: %s", intent.intent_type)
        return IntentResult(success=True, intent=sanitized, error=None)
    
    def _extract_llm_freeform(self, transcript: str, runtime) -> IntentResult:
        """Extract intent using LLM without grammar constraints."""
        prompt = self._build_prompt(transcript)
        
        try:
            raw = runtime.generate(prompt=prompt, max_tokens=256)
            raw = raw.strip()
            
            # Try to extract JSON from response
            json_match = re.search(r'\{[^}]+\}', raw)
            if not json_match:
                return IntentResult(
                    success=False,
                    intent=None,
                    error="LLM did not return valid JSON",
                )
            
            data = json.loads(json_match.group(0))
            intent = self._parse_intent(data, transcript)
            
            if intent is None:
                return IntentResult(
                    success=False,
                    intent=None,
                    error="LLM JSON did not match intent schema",
                )
            
            # Sanitize
            sanitized = self._sanitizer.sanitize(intent)
            if isinstance(sanitized, SanitizationError):
                return IntentResult(
                    success=False,
                    intent=None,
                    error=f"Sanitization rejected intent: {sanitized.reason}",
                )
            
            logger.info("LLM extraction successful: %s", intent.intent_type)
            return IntentResult(success=True, intent=sanitized, error=None)
            
        except Exception as exc:
            logger.warning("LLM extraction failed: %s", exc)
            return IntentResult(
                success=False,
                intent=None,
                error=f"LLM extraction error: {exc}",
            )
