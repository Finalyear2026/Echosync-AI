"""
EchoSync AI Desktop — SQLAlchemy 2.0 ORM models.

All datetime fields are stored as ISO 8601 strings (TEXT columns) to keep the
schema portable and avoid SQLite's limited datetime type support.
"""

from __future__ import annotations

from sqlalchemy import CheckConstraint, Index, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    """Shared declarative base for all ORM models."""


# ---------------------------------------------------------------------------
# Task
# ---------------------------------------------------------------------------


class Task(Base):
    """Represents a user-created task (to-do item)."""

    __tablename__ = "tasks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(
        String(500),
        nullable=False,
    )
    priority: Mapped[str] = mapped_column(
        String(10),
        nullable=False,
        default="medium",
        server_default="medium",
    )
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="pending",
        server_default="pending",
    )
    created_at: Mapped[str] = mapped_column(Text, nullable=False)
    due_at: Mapped[str | None] = mapped_column(Text, nullable=True)
    completed_at: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        CheckConstraint("length(title) <= 500", name="ck_tasks_title_len"),
        CheckConstraint(
            "priority IN ('low', 'medium', 'high')", name="ck_tasks_priority"
        ),
        CheckConstraint(
            "status IN ('pending', 'in_progress', 'completed')",
            name="ck_tasks_status_values",
        ),
        Index("idx_tasks_status", "status"),
        Index("idx_tasks_due_at", "due_at"),
    )

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<Task id={self.id!r} title={self.title!r} "
            f"priority={self.priority!r} status={self.status!r}>"
        )


# ---------------------------------------------------------------------------
# Meeting
# ---------------------------------------------------------------------------


class Meeting(Base):
    """Represents a scheduled meeting."""

    __tablename__ = "meetings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    # JSON-encoded list of attendee strings, e.g. '["Alice", "Bob"]'
    attendees: Mapped[str] = mapped_column(
        Text, nullable=False, default="[]", server_default="[]"
    )
    start_at: Mapped[str] = mapped_column(Text, nullable=False)
    end_at: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (
        CheckConstraint("length(title) <= 500", name="ck_meetings_title_len"),
        Index("idx_meetings_start_at", "start_at"),
    )

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<Meeting id={self.id!r} title={self.title!r} "
            f"start_at={self.start_at!r}>"
        )


# ---------------------------------------------------------------------------
# Reminder
# ---------------------------------------------------------------------------


class Reminder(Base):
    """Represents a time-based reminder that triggers an OS notification."""

    __tablename__ = "reminders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    message: Mapped[str] = mapped_column(String(500), nullable=False)
    trigger_at: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="pending",
        server_default="pending",
    )
    created_at: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (
        CheckConstraint("length(message) <= 500", name="ck_reminders_message_len"),
        CheckConstraint(
            "status IN ('pending', 'delivered', 'delivered_late')",
            name="ck_reminders_status_values",
        ),
        Index("idx_reminders_trigger", "trigger_at", "status"),
    )

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<Reminder id={self.id!r} trigger_at={self.trigger_at!r} "
            f"status={self.status!r}>"
        )


# ---------------------------------------------------------------------------
# SessionHistory
# ---------------------------------------------------------------------------


class SessionHistory(Base):
    """Records each voice session's transcript, intent type, and result."""

    __tablename__ = "session_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    transcript: Mapped[str] = mapped_column(Text, nullable=False)
    # NULL for question/agentic sessions that have no discrete intent type
    intent_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    result_summary: Mapped[str] = mapped_column(Text, nullable=False)
    session_at: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (Index("idx_history_session_at", "session_at"),)

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<SessionHistory id={self.id!r} intent_type={self.intent_type!r} "
            f"session_at={self.session_at!r}>"
        )
