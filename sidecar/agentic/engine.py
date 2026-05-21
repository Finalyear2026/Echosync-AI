"""
Agentic Engine — ReAct-style reasoning loop for cognitive queries.

Implements: Thought → Action → Observation → Answer (max 5 steps).
Exposes query_database tool using parameterized SQLAlchemy queries only.
Synthesizes response in the same language as the input transcript.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import Any, Optional

from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

MAX_STEPS = 5

SYSTEM_PROMPT = """You are EchoSync AI, a multilingual voice assistant. You understand Urdu, Punjabi, English, and Roman Urdu.

You have access to a tool called query_database to look up the user's tasks, meetings, reminders, and history.

To use the tool, output:
THOUGHT: <your reasoning>
ACTION: query_database
PARAMS: {{"table": "tasks"|"meetings"|"reminders"|"history", "filters": {{"status": "...", "date_from": "...", "date_to": "..."}}}}

When you have enough information, output:
THOUGHT: I have enough information to answer.
ANSWER: <your response in the same language as the user's question>

Always respond in the same language the user used. If they spoke Urdu/Roman Urdu, respond in Roman Urdu or Urdu.
Maximum {{max_steps}} reasoning steps allowed."""


@dataclass
class QuerySpec:
    """Typed query specification — never a raw SQL string."""
    table: str  # "tasks" | "meetings" | "reminders" | "history"
    filters: dict[str, Any] = field(default_factory=dict)


@dataclass
class AgenticResponse:
    answer: str
    steps_taken: int
    fallback: bool  # True if max steps exceeded without answer


class AgenticEngine:
    """ReAct reasoning loop with parameterized database tool."""

    def __init__(self, session: Session) -> None:
        self._session = session

    def run(self, transcript: str) -> AgenticResponse:
        """
        Run the ReAct loop for a question transcript.

        Args:
            transcript: The user's question.

        Returns:
            AgenticResponse with the synthesized answer.
        """
        from llm.runtime import get_llm_runtime

        runtime = get_llm_runtime()
        conversation = self._build_initial_prompt(transcript)
        steps = 0

        while steps < MAX_STEPS:
            steps += 1
            response = runtime.generate(
                prompt=conversation,
                grammar=None,
                max_tokens=512,
            )

            logger.debug("AgenticEngine step %d response: %s", steps, response[:200])

            # Check for ANSWER
            if "ANSWER:" in response:
                answer = self._extract_answer(response)
                return AgenticResponse(
                    answer=answer,
                    steps_taken=steps,
                    fallback=False,
                )

            # Check for ACTION
            if "ACTION: query_database" in response:
                params = self._extract_params(response)
                if params:
                    observation = self._execute_query(params)
                    conversation += f"\n{response}\nOBSERVATION: {observation}"
                    continue

            # No valid action found — append and continue
            conversation += f"\n{response}"

        # Max steps exceeded
        logger.warning("AgenticEngine: max steps (%d) exceeded for: %s", MAX_STEPS, transcript[:100])
        fallback_msg = self._generate_fallback(transcript)
        return AgenticResponse(
            answer=fallback_msg,
            steps_taken=steps,
            fallback=True,
        )

    def _build_initial_prompt(self, transcript: str) -> str:
        system = SYSTEM_PROMPT.format(max_steps=MAX_STEPS)
        return (
            f"<|system|>\n{system}\n<|end|>\n"
            f"<|user|>\n{transcript}\n<|end|>\n"
            f"<|assistant|>\nTHOUGHT:"
        )

    def _execute_query(self, spec: QuerySpec) -> str:
        """Execute a parameterized database query and return JSON string result."""
        try:
            from db import crud

            table = spec.table.lower()
            filters = spec.filters

            if table == "tasks":
                records = crud.get_tasks(self._session)
                data = [
                    {
                        "id": r.id, "title": r.title,
                        "priority": r.priority, "status": r.status,
                        "due_at": r.due_at, "created_at": r.created_at,
                    }
                    for r in records
                ]
            elif table == "meetings":
                records = crud.get_meetings(self._session)
                data = [
                    {
                        "id": r.id, "title": r.title,
                        "start_at": r.start_at, "end_at": r.end_at,
                        "attendees": r.attendees,
                    }
                    for r in records
                ]
            elif table == "reminders":
                records = crud.get_reminders(self._session)
                data = [
                    {
                        "id": r.id, "message": r.message,
                        "trigger_at": r.trigger_at, "status": r.status,
                    }
                    for r in records
                ]
            elif table == "history":
                records = crud.get_history(self._session)
                data = [
                    {
                        "id": r.id, "transcript": r.transcript[:100],
                        "intent_type": r.intent_type,
                        "result_summary": r.result_summary,
                        "session_at": r.session_at,
                    }
                    for r in records
                ]
            else:
                return json.dumps({"error": f"Unknown table: {table}"})

            # Apply simple date filters if provided
            if "date_from" in filters:
                data = [r for r in data
                        if r.get("start_at", r.get("created_at", "")) >= filters["date_from"]]
            if "date_to" in filters:
                data = [r for r in data
                        if r.get("start_at", r.get("created_at", "")) <= filters["date_to"]]
            if "status" in filters:
                data = [r for r in data if r.get("status") == filters["status"]]

            return json.dumps(data[:20])  # cap at 20 records

        except Exception as exc:
            logger.error("AgenticEngine query error: %s", exc)
            return json.dumps({"error": str(exc)})

    @staticmethod
    def _extract_answer(response: str) -> str:
        """Extract text after ANSWER: marker."""
        idx = response.find("ANSWER:")
        if idx >= 0:
            return response[idx + 7:].strip()
        return response.strip()

    @staticmethod
    def _extract_params(response: str) -> Optional[QuerySpec]:
        """Extract PARAMS JSON from response and return a QuerySpec."""
        try:
            idx = response.find("PARAMS:")
            if idx < 0:
                return None
            params_str = response[idx + 7:].strip()
            # Extract JSON object
            brace_start = params_str.find("{")
            brace_end = params_str.rfind("}") + 1
            if brace_start < 0 or brace_end <= 0:
                return None
            params = json.loads(params_str[brace_start:brace_end])
            return QuerySpec(
                table=params.get("table", "tasks"),
                filters=params.get("filters", {}),
            )
        except Exception as exc:
            logger.debug("Failed to extract params: %s", exc)
            return None

    @staticmethod
    def _generate_fallback(transcript: str) -> str:
        """Return a graceful fallback message."""
        # Detect language hint from transcript
        urdu_chars = sum(1 for c in transcript if '\u0600' <= c <= '\u06ff')
        if urdu_chars > 3:
            return "Maafi chahta hoon, aapke sawal ka jawab nahi de saka. Dobara koshish karein."
        return "Sorry, I wasn't able to find an answer to your question. Please try rephrasing."
