"""
EchoSync AI Desktop — CRUD operations for all four database tables.

All queries use SQLAlchemy parameterized expressions.  No raw SQL strings are
constructed from user-supplied or LLM-supplied data.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from db.conflicts import ConflictWarning
from db.models import Meeting, Reminder, SessionHistory, Task

# Re-export ConflictWarning so callers can import it from either location.
__all__ = [
    "ConflictWarning",
    "create_task",
    "update_task",
    "complete_task",
    "get_tasks",
    "create_meeting",
    "get_meetings",
    "create_reminder",
    "update_reminder_status",
    "get_pending_reminders",
    "get_reminders",
    "insert_history",
    "get_history",
    "check_meeting_conflict",
    "check_duplicate_task",
]


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------


def _now_iso() -> str:
    """Return the current UTC time as an ISO 8601 string."""
    return datetime.now(tz=timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# Task CRUD
# ---------------------------------------------------------------------------


def create_task(
    session: Session,
    title: str,
    priority: str = "medium",
    due_at: str | None = None,
) -> Task:
    """
    Insert a new Task record and return it.

    Parameters
    ----------
    session:  Active SQLAlchemy session.
    title:    Task title (max 500 chars, enforced by DB CHECK constraint).
    priority: One of "low", "medium", "high".  Defaults to "medium".
    due_at:   Optional ISO 8601 due-date string.
    """
    task = Task(
        title=title,
        priority=priority,
        status="pending",
        created_at=_now_iso(),
        due_at=due_at,
        completed_at=None,
    )
    session.add(task)
    session.commit()
    session.refresh(task)
    return task


def update_task(
    session: Session,
    task_id: int,
    priority: str | None = None,
    due_at: str | None = None,
) -> Task | None:
    """
    Update a Task's priority and/or due_at.  Returns the updated Task or None
    if no Task with the given id exists.
    """
    stmt = select(Task).where(Task.id == task_id)
    task = session.scalars(stmt).first()
    if task is None:
        return None

    if priority is not None:
        task.priority = priority
    if due_at is not None:
        task.due_at = due_at

    session.commit()
    session.refresh(task)
    return task


def complete_task(session: Session, task_id: int) -> Task | None:
    """
    Mark a Task as completed and record the completion timestamp.
    Returns the updated Task or None if not found.
    """
    stmt = select(Task).where(Task.id == task_id)
    task = session.scalars(stmt).first()
    if task is None:
        return None

    task.status = "completed"
    task.completed_at = _now_iso()
    session.commit()
    session.refresh(task)
    return task


def get_tasks(session: Session) -> list[Task]:
    """Return all Task records ordered by creation time (newest first)."""
    stmt = select(Task).order_by(Task.created_at.desc())
    return list(session.scalars(stmt).all())


# ---------------------------------------------------------------------------
# Meeting CRUD
# ---------------------------------------------------------------------------


def create_meeting(
    session: Session,
    title: str,
    attendees: str,
    start_at: str,
    end_at: str,
) -> Meeting:
    """
    Insert a new Meeting record and return it.

    Parameters
    ----------
    session:   Active SQLAlchemy session.
    title:     Meeting title (max 500 chars).
    attendees: JSON-encoded list of attendee strings, e.g. '["Alice", "Bob"]'.
    start_at:  ISO 8601 start timestamp.
    end_at:    ISO 8601 end timestamp.
    """
    meeting = Meeting(
        title=title,
        attendees=attendees,
        start_at=start_at,
        end_at=end_at,
        created_at=_now_iso(),
    )
    session.add(meeting)
    session.commit()
    session.refresh(meeting)
    return meeting


def get_meetings(session: Session) -> list[Meeting]:
    """Return all Meeting records ordered by start time (soonest first)."""
    stmt = select(Meeting).order_by(Meeting.start_at.asc())
    return list(session.scalars(stmt).all())


# ---------------------------------------------------------------------------
# Reminder CRUD
# ---------------------------------------------------------------------------


def create_reminder(
    session: Session,
    message: str,
    trigger_at: str,
) -> Reminder:
    """
    Insert a new Reminder record with status "pending" and return it.

    Parameters
    ----------
    session:    Active SQLAlchemy session.
    message:    Reminder message text (max 500 chars).
    trigger_at: ISO 8601 timestamp at which the notification should fire.
    """
    reminder = Reminder(
        message=message,
        trigger_at=trigger_at,
        status="pending",
        created_at=_now_iso(),
    )
    session.add(reminder)
    session.commit()
    session.refresh(reminder)
    return reminder


def update_reminder_status(
    session: Session,
    reminder_id: int,
    status: str,
) -> Reminder | None:
    """
    Update a Reminder's status field.  Returns the updated Reminder or None.

    Valid status values: "pending", "delivered", "delivered_late".
    """
    stmt = select(Reminder).where(Reminder.id == reminder_id)
    reminder = session.scalars(stmt).first()
    if reminder is None:
        return None

    reminder.status = status
    session.commit()
    session.refresh(reminder)
    return reminder


def get_pending_reminders(session: Session) -> list[Reminder]:
    """
    Return all Reminder records with status "pending" whose trigger_at is
    less than or equal to the current UTC time.

    ISO 8601 string comparison is correct for UTC timestamps stored in the
    same format (e.g. "2024-01-15T09:00:00+00:00").
    """
    now = _now_iso()
    stmt = (
        select(Reminder)
        .where(Reminder.status == "pending")
        .where(Reminder.trigger_at <= now)
        .order_by(Reminder.trigger_at.asc())
    )
    return list(session.scalars(stmt).all())


def get_reminders(session: Session) -> list[Reminder]:
    """Return all Reminder records ordered by trigger time (soonest first)."""
    stmt = select(Reminder).order_by(Reminder.trigger_at.asc())
    return list(session.scalars(stmt).all())


# ---------------------------------------------------------------------------
# SessionHistory CRUD
# ---------------------------------------------------------------------------


def insert_history(
    session: Session,
    transcript: str,
    intent_type: str | None,
    result_summary: str,
) -> SessionHistory:
    """
    Insert a new SessionHistory record and return it.

    Parameters
    ----------
    session:        Active SQLAlchemy session.
    transcript:     Raw transcript text from the voice session.
    intent_type:    Intent type string (e.g. "create_task") or None for
                    question/agentic sessions.
    result_summary: Human-readable summary of the action or answer produced.
    """
    record = SessionHistory(
        transcript=transcript,
        intent_type=intent_type,
        result_summary=result_summary,
        session_at=_now_iso(),
    )
    session.add(record)
    session.commit()
    session.refresh(record)
    return record


def get_history(session: Session) -> list[SessionHistory]:
    """Return all SessionHistory records ordered by session time (newest first)."""
    stmt = select(SessionHistory).order_by(SessionHistory.session_at.desc())
    return list(session.scalars(stmt).all())


# ---------------------------------------------------------------------------
# Conflict detection (Tasks 2.3)
# ---------------------------------------------------------------------------


def check_meeting_conflict(
    session: Session,
    start_at: str,
    end_at: str,
) -> bool:
    """
    Return True if any existing Meeting overlaps with the proposed time window.

    Two intervals overlap when::

        existing.start_at < new_end_at  AND  new_start_at < existing.end_at

    Both timestamps are ISO 8601 strings.  Lexicographic comparison is correct
    for UTC timestamps stored in the same format (e.g. "2024-01-15T09:00:00+00:00").

    Parameters
    ----------
    session:  Active SQLAlchemy session.
    start_at: Proposed meeting start (ISO 8601).
    end_at:   Proposed meeting end (ISO 8601).
    """
    stmt = select(Meeting).where(
        Meeting.start_at < end_at,
        start_at < Meeting.end_at,
    )
    return session.scalars(stmt).first() is not None


def check_duplicate_task(
    session: Session,
    title: str,
    date: str,
) -> bool:
    """
    Return True if a Task with the same *title* already exists whose
    created_at starts with the given *date* string (YYYY-MM-DD prefix match).

    Parameters
    ----------
    session: Active SQLAlchemy session.
    title:   Exact task title to check.
    date:    Calendar date string in "YYYY-MM-DD" format.
    """
    # SQLAlchemy's like() generates a parameterized LIKE query — no raw SQL.
    date_prefix = f"{date}%"
    stmt = select(Task).where(
        Task.title == title,
        Task.created_at.like(date_prefix),
    )
    return session.scalars(stmt).first() is not None
