"""
EchoSync AI Desktop — Pydantic intent models.

Defines the five supported intent types and a helper for parsing raw dicts
into the correct typed model.
"""

from __future__ import annotations

from typing import Literal, Union

from pydantic import BaseModel, Field


class BaseIntent(BaseModel):
    intent_type: str
    raw_transcript: str


class CreateTaskIntent(BaseIntent):
    intent_type: Literal["create_task"]
    title: str = Field(max_length=500)
    priority: Literal["low", "medium", "high"] = "medium"
    due_at: str | None = None


class UpdateTaskIntent(BaseIntent):
    intent_type: Literal["update_task"]
    task_id: int | None = None
    title_hint: str | None = Field(default=None, max_length=500)
    priority: Literal["low", "medium", "high"] | None = None
    due_at: str | None = None


class CompleteTaskIntent(BaseIntent):
    intent_type: Literal["complete_task"]
    task_id: int | None = None
    title_hint: str | None = Field(default=None, max_length=500)


class ScheduleMeetingIntent(BaseIntent):
    intent_type: Literal["schedule_meeting"]
    title: str = Field(max_length=500)
    attendees: list[str] = Field(default_factory=list)
    start_at: str
    end_at: str | None = None


class SetReminderIntent(BaseIntent):
    intent_type: Literal["set_reminder"]
    message: str = Field(max_length=500)
    trigger_at: str


AnyIntent = Union[
    CreateTaskIntent,
    UpdateTaskIntent,
    CompleteTaskIntent,
    ScheduleMeetingIntent,
    SetReminderIntent,
]

# Ordered list of concrete intent types used by parse_intent.
_INTENT_TYPES: list[type[AnyIntent]] = [  # type: ignore[assignment]
    CreateTaskIntent,
    UpdateTaskIntent,
    CompleteTaskIntent,
    ScheduleMeetingIntent,
    SetReminderIntent,
]


def parse_intent(data: dict) -> AnyIntent:
    """Try each intent model in order and return the first successful parse.

    Raises:
        ValueError: if *data* does not match any known intent schema.
    """
    errors: list[str] = []
    for model_cls in _INTENT_TYPES:
        try:
            return model_cls.model_validate(data)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{model_cls.__name__}: {exc}")
    raise ValueError(
        f"data does not match any known intent schema. Errors: {errors}"
    )
