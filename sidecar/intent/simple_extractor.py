"""
Simple Rule-Based Intent Extractor (Fallback)
Used when LLM model is not available.
"""

from __future__ import annotations

import logging
import re
from typing import Optional

from intent.models import (
    CreateTaskIntent,
    ScheduleMeetingIntent,
    SetReminderIntent,
    BaseIntent,
)

logger = logging.getLogger(__name__)


class SimpleIntentExtractor:
    """Rule-based intent extraction without LLM."""
    
    def extract(self, transcript: str) -> Optional[BaseIntent]:
        """
        Extract intent using simple pattern matching.
        
        Returns None if no intent matches.
        """
        text = transcript.lower().strip()
        
        # Create Task patterns (English + Urdu/Roman Urdu)
        task_patterns = [
            # English
            r"create\s+(?:a\s+)?task\s+(?:to\s+)?(.+)",
            r"add\s+(?:a\s+)?task\s+(?:to\s+)?(.+)",
            r"make\s+(?:a\s+)?task\s+(?:to\s+)?(.+)",
            r"new\s+task\s+(?:to\s+)?(.+)",
            r"task\s+(?:to\s+)?(.+)",
            r"todo\s+(.+)",
            # Urdu/Roman Urdu
            r"task\s+bana(?:o)?\s+(.+)",
            r"kaam\s+bana(?:o)?\s+(.+)",
            r"task\s+add\s+kar(?:o)?\s+(.+)",
            r"kaam\s+add\s+kar(?:o)?\s+(.+)",
            r"task\s+likho\s+(.+)",
            r"bana\s+(?:do|dena)\s+task\s+(.+)",
            r"add\s+kar(?:o)?\s+task\s+(.+)",
        ]
        
        for pattern in task_patterns:
            match = re.search(pattern, text)
            if match:
                title = match.group(1).strip()
                # Extract due date if present
                due_at = self._extract_date(title)
                logger.info(f"Matched create_task: title='{title}', due_at='{due_at}'")
                return CreateTaskIntent(
                    intent_type="create_task",
                    raw_transcript=transcript,
                    title=title,
                    priority="medium",
                    due_at=due_at,
                )
        
        # Schedule Meeting patterns (English + Urdu/Roman Urdu)
        meeting_patterns = [
            # English
            r"schedule\s+(?:a\s+)?meeting\s+(.+)",
            r"set\s+(?:up\s+)?(?:a\s+)?meeting\s+(.+)",
            r"book\s+(?:a\s+)?meeting\s+(.+)",
            r"meeting\s+(.+)",
            # Urdu/Roman Urdu
            r"meeting\s+schedule\s+kar(?:o)?\s+(.+)",
            r"meeting\s+fix\s+kar(?:o)?\s+(.+)",
            r"meeting\s+set\s+kar(?:o)?\s+(.+)",
            r"mulaqat\s+(?:schedule|fix|set)\s+kar(?:o)?\s+(.+)",
            r"schedule\s+kar(?:o)?\s+meeting\s+(.+)",
        ]
        
        for pattern in meeting_patterns:
            match = re.search(pattern, text)
            if match:
                details = match.group(1).strip()
                title = self._extract_meeting_title(details)
                start_at = self._extract_date(details)
                logger.info(f"Matched schedule_meeting: title='{title}', start_at='{start_at}'")
                return ScheduleMeetingIntent(
                    intent_type="schedule_meeting",
                    raw_transcript=transcript,
                    title=title,
                    start_at=start_at or "tomorrow at 2 PM",
                    end_at=None,
                    attendees=[],
                )
        
        # Set Reminder patterns (English + Urdu/Roman Urdu)
        reminder_patterns = [
            # English
            r"remind\s+me\s+(?:to\s+)?(.+)",
            r"set\s+(?:a\s+)?reminder\s+(?:to\s+)?(.+)",
            r"reminder\s+(?:to\s+)?(.+)",
            # Urdu/Roman Urdu
            r"reminder\s+set\s+kar(?:o)?\s+(.+)",
            r"reminder\s+laga(?:o)?\s+(.+)",
            r"yaad\s+dila(?:o)?\s+(.+)",
            r"yaad\s+dihani\s+set\s+kar(?:o)?\s+(.+)",
            r"mujhe\s+yaad\s+dila(?:o)?\s+(.+)",
        ]
        
        for pattern in reminder_patterns:
            match = re.search(pattern, text)
            if match:
                message = match.group(1).strip()
                trigger_at = self._extract_date(message)
                logger.info(f"Matched set_reminder: message='{message}', trigger_at='{trigger_at}'")
                return SetReminderIntent(
                    intent_type="set_reminder",
                    raw_transcript=transcript,
                    message=message,
                    trigger_at=trigger_at or "tomorrow at 10 AM",
                )
        
        logger.info(f"No intent matched for: '{transcript}'")
        return None
    
    def _extract_date(self, text: str) -> Optional[str]:
        """Extract date/time expressions from text (English + Urdu)."""
        text_lower = text.lower()
        
        # Common date patterns (English + Urdu/Roman Urdu)
        date_patterns = [
            # English
            r"tomorrow",
            r"today",
            r"next\s+\w+",  # next monday, next week
            r"at\s+\d+\s*(?:am|pm)",  # at 2 PM
            r"\d+\s*(?:am|pm)",  # 2 PM
            r"in\s+\d+\s+(?:hour|minute|day)s?",  # in 2 hours
            # Urdu/Roman Urdu
            r"kal",  # tomorrow
            r"aaj",  # today
            r"parson",  # day after tomorrow
            r"subah",  # morning
            r"sham",  # evening
            r"raat",  # night
            r"dophar",  # afternoon
            r"\d+\s+baje",  # X o'clock
            r"aglay\s+\w+",  # next (week/month)
        ]
        
        for pattern in date_patterns:
            match = re.search(pattern, text_lower)
            if match:
                return match.group(0)
        
        return None
    
    def _extract_meeting_title(self, text: str) -> str:
        """Extract meeting title from details."""
        # Remove common date/time phrases
        title = re.sub(r'\b(?:tomorrow|today|at\s+\d+\s*(?:am|pm)|next\s+\w+)\b', '', text, flags=re.IGNORECASE)
        title = title.strip()
        return title if title else "Meeting"
