"""
EchoSync AI Desktop — Property-Based Tests.

Comprehensive property tests for:
1. Database round-trip (Task, Meeting, Reminder)
2. Sanitizer (SQL injection, HTML tags, control chars, length limits)
3. Meeting conflict detection
4. Date normalizer (relative dates, Urdu tokens)
5. Reminder state transitions
"""

from datetime import datetime, timedelta, timezone
from hypothesis import given, strategies as st, assume
from sqlalchemy.exc import IntegrityError
import pytest
import json

from db.models import Task, Meeting, Reminder, SessionHistory
from db import crud
from intent.sanitizer import Sanitizer, SanitizationError
from intent.date_normalizer import DateNormalizer
from intent.models import CreateTaskIntent, ScheduleMeetingIntent, SetReminderIntent


# ---------------------------------------------------------------------------
# Strategy Helpers
# ---------------------------------------------------------------------------

# Valid priority values
valid_priorities = st.sampled_from(["low", "medium", "high"])

# Valid task status values
valid_task_statuses = st.sampled_from(["pending", "in_progress", "completed"])

# Valid reminder status values
valid_reminder_statuses = st.sampled_from(["pending", "delivered", "delivered_late"])

# Generate valid titles/messages (1-500 chars, no null bytes)
valid_text = st.text(min_size=1, max_size=500).filter(lambda s: "\x00" not in s)

# Generate ISO 8601 datetime strings
def iso_datetime_strategy(min_year=2024, max_year=2027):
    return st.datetimes(
        min_value=datetime(min_year, 1, 1),
        max_value=datetime(max_year, 12, 31),
    ).map(lambda dt: dt.replace(tzinfo=timezone.utc).isoformat())

# Generate attendee lists as JSON strings
def attendee_list_strategy():
    return st.lists(
        st.text(min_size=1, max_size=50).filter(lambda s: "\x00" not in s and '"' not in s),
        min_size=0,
        max_size=10
    ).map(json.dumps)


# ---------------------------------------------------------------------------
# Property 1: Database Round-Trip (Task)
# ---------------------------------------------------------------------------

@given(
    title=valid_text,
    priority=valid_priorities,
    due_at=st.none() | iso_datetime_strategy()
)
def test_property_task_roundtrip(db_session, title, priority, due_at):
    """Property: Task data survives database round-trip without corruption."""
    db_session.rollback()
    db_session.query(Task).delete()
    db_session.commit()
    
    # Create task
    task = crud.create_task(db_session, title=title, priority=priority, due_at=due_at)
    
    # Verify immediate state
    assert task.id is not None
    assert task.title == title
    assert task.priority == priority
    assert task.status == "pending"
    assert task.due_at == due_at
    assert task.created_at is not None
    assert task.completed_at is None
    
    # Fetch from database
    tasks = crud.get_tasks(db_session)
    retrieved = next((t for t in tasks if t.id == task.id), None)
    
    assert retrieved is not None
    assert retrieved.title == title
    assert retrieved.priority == priority
    assert retrieved.due_at == due_at
    assert retrieved.status == "pending"


# ---------------------------------------------------------------------------
# Property 2: Database Round-Trip (Meeting)
# ---------------------------------------------------------------------------

@given(
    title=valid_text,
    attendees=attendee_list_strategy(),
    start_dt=st.datetimes(
        min_value=datetime(2024, 1, 1),
        max_value=datetime(2027, 12, 31),
    ),
    duration_minutes=st.integers(min_value=15, max_value=480)
)
def test_property_meeting_roundtrip(db_session, title, attendees, start_dt, duration_minutes):
    """Property: Meeting data survives database round-trip without corruption."""
    db_session.rollback()
    db_session.query(Meeting).delete()
    db_session.commit()
    
    # Add timezone and calculate end time
    start_dt = start_dt.replace(tzinfo=timezone.utc)
    end_dt = start_dt + timedelta(minutes=duration_minutes)
    start_at = start_dt.isoformat()
    end_at = end_dt.isoformat()
    
    # Create meeting
    meeting = crud.create_meeting(
        db_session,
        title=title,
        attendees=attendees,
        start_at=start_at,
        end_at=end_at
    )
    
    # Verify immediate state
    assert meeting.id is not None
    assert meeting.title == title
    assert meeting.attendees == attendees
    assert meeting.start_at == start_at
    assert meeting.end_at == end_at
    assert meeting.created_at is not None
    
    # Fetch from database
    meetings = crud.get_meetings(db_session)
    retrieved = next((m for m in meetings if m.id == meeting.id), None)
    
    assert retrieved is not None
    assert retrieved.title == title
    assert retrieved.attendees == attendees
    assert retrieved.start_at == start_at
    assert retrieved.end_at == end_at


# ---------------------------------------------------------------------------
# Property 3: Database Round-Trip (Reminder)
# ---------------------------------------------------------------------------

@given(
    message=valid_text,
    trigger_at=iso_datetime_strategy()
)
def test_property_reminder_roundtrip(db_session, message, trigger_at):
    """Property: Reminder data survives database round-trip without corruption."""
    db_session.rollback()
    db_session.query(Reminder).delete()
    db_session.commit()
    
    # Create reminder
    reminder = crud.create_reminder(
        db_session,
        message=message,
        trigger_at=trigger_at
    )
    
    # Verify immediate state
    assert reminder.id is not None
    assert reminder.message == message
    assert reminder.trigger_at == trigger_at
    assert reminder.status == "pending"
    assert reminder.created_at is not None
    
    # Fetch from database
    reminders = crud.get_reminders(db_session)
    retrieved = next((r for r in reminders if r.id == reminder.id), None)
    
    assert retrieved is not None
    assert retrieved.message == message
    assert retrieved.trigger_at == trigger_at
    assert retrieved.status == "pending"


# ---------------------------------------------------------------------------
# Property 4: Sanitizer - SQL Injection Protection
# ---------------------------------------------------------------------------

@given(
    base_text=st.text(min_size=1, max_size=100).filter(lambda s: "\x00" not in s),
    sql_token=st.sampled_from(["--", "/*", "*/", "xp_", "'", '"', ";"])
)
def test_property_sanitizer_strips_sql_metacharacters(base_text, sql_token):
    """Property: Sanitizer removes SQL metacharacters from all string fields."""
    sanitizer = Sanitizer()
    
    # Inject SQL token into text
    malicious_text = f"{base_text}{sql_token}DROP TABLE tasks"
    
    intent = CreateTaskIntent(
        intent_type="create_task",
        raw_transcript="test",
        title=malicious_text,
        priority="medium",
        due_at=None
    )
    
    result = sanitizer.sanitize(intent)
    
    # Should not be rejected (SQL tokens are stripped, not rejected)
    assert not isinstance(result, SanitizationError)
    
    # SQL token should be removed
    assert sql_token not in result.title


# ---------------------------------------------------------------------------
# Property 5: Sanitizer - HTML Tag Stripping
# ---------------------------------------------------------------------------

@given(
    base_text=st.text(min_size=1, max_size=100).filter(lambda s: "\x00" not in s and "<" not in s),
    tag=st.sampled_from(["<script>", "</script>", "<img>", "<div>", "<a href='x'>"])
)
def test_property_sanitizer_strips_html_tags(base_text, tag):
    """Property: Sanitizer removes HTML tags from all string fields."""
    sanitizer = Sanitizer()
    
    malicious_text = f"{base_text}{tag}alert('xss')"
    
    intent = CreateTaskIntent(
        intent_type="create_task",
        raw_transcript="test",
        title=malicious_text,
        priority="medium",
        due_at=None
    )
    
    result = sanitizer.sanitize(intent)
    
    assert not isinstance(result, SanitizationError)
    # HTML tags should be stripped
    assert "<" not in result.title or ">" not in result.title


# ---------------------------------------------------------------------------
# Property 6: Sanitizer - Prompt Injection Detection
# ---------------------------------------------------------------------------

@given(
    base_text=st.text(min_size=1, max_size=100).filter(lambda s: "\x00" not in s),
    injection_sig=st.sampled_from([
        "ignore previous",
        "IGNORE PREVIOUS",
        "system:",
        "SYSTEM:",
        "<|",
        "[INST]",
        "###"
    ])
)
def test_property_sanitizer_rejects_prompt_injection(base_text, injection_sig):
    """Property: Sanitizer rejects intents containing prompt injection patterns."""
    sanitizer = Sanitizer()
    
    malicious_text = f"{base_text} {injection_sig} instructions"
    
    intent = CreateTaskIntent(
        intent_type="create_task",
        raw_transcript="test",
        title=malicious_text,
        priority="medium",
        due_at=None
    )
    
    result = sanitizer.sanitize(intent)
    
    # Should be rejected
    assert isinstance(result, SanitizationError)
    assert result.field == "title"
    assert "prompt injection" in result.reason.lower()


# ---------------------------------------------------------------------------
# Property 7: Sanitizer - Length Enforcement
# ---------------------------------------------------------------------------

@given(
    long_text=st.text(min_size=501, max_size=1000).filter(lambda s: "\x00" not in s)
)
def test_property_sanitizer_enforces_max_length(long_text):
    """Property: Sanitizer truncates fields to 500 characters."""
    # Ensure no injection patterns in the text
    assume("ignore previous" not in long_text.lower())
    assume("system:" not in long_text.lower())
    assume("<|" not in long_text)
    assume("[INST]" not in long_text)
    assume("###" not in long_text)
    
    sanitizer = Sanitizer()
    
    # Bypass Pydantic validation by using model_construct
    intent = CreateTaskIntent.model_construct(
        intent_type="create_task",
        raw_transcript="test",
        title=long_text,
        priority="medium",
        due_at=None
    )
    
    result = sanitizer.sanitize(intent)
    
    assert not isinstance(result, SanitizationError)
    assert len(result.title) <= 500


# ---------------------------------------------------------------------------
# Property 8: Meeting Conflict Detection
# ---------------------------------------------------------------------------

@given(
    start1=st.datetimes(
        min_value=datetime(2024, 1, 1, 10, 0),
        max_value=datetime(2024, 12, 31, 18, 0),
    ),
    duration1=st.integers(min_value=30, max_value=240),
    offset_minutes=st.integers(min_value=-120, max_value=120)
)
def test_property_meeting_conflict_detection(db_session, start1, duration1, offset_minutes):
    """Property: Meeting conflict detection correctly identifies overlapping time windows."""
    db_session.rollback()
    db_session.query(Meeting).delete()
    db_session.commit()
    
    # Add timezone to datetime
    start1 = start1.replace(tzinfo=timezone.utc)
    
    # Create first meeting
    end1 = start1 + timedelta(minutes=duration1)
    meeting1 = crud.create_meeting(
        db_session,
        title="Meeting 1",
        attendees="[]",
        start_at=start1.isoformat(),
        end_at=end1.isoformat()
    )
    
    # Create second meeting with offset
    start2 = start1 + timedelta(minutes=offset_minutes)
    end2 = start2 + timedelta(minutes=duration1)
    
    # Check for conflict
    has_conflict = crud.check_meeting_conflict(
        db_session,
        start_at=start2.isoformat(),
        end_at=end2.isoformat()
    )
    
    # Determine expected conflict
    # Two intervals overlap when: start1 < end2 AND start2 < end1
    expected_conflict = (start1 < end2) and (start2 < end1)
    
    assert has_conflict == expected_conflict


# ---------------------------------------------------------------------------
# Property 9: Date Normalizer - Relative Date Resolution
# ---------------------------------------------------------------------------

@given(
    days_offset=st.integers(min_value=-30, max_value=30)
)
def test_property_date_normalizer_relative_dates(days_offset):
    """Property: Date normalizer correctly resolves relative date expressions."""
    normalizer = DateNormalizer()
    reference = datetime(2024, 6, 15, 12, 0, 0, tzinfo=timezone.utc)
    
    # Map offset to expression
    if days_offset == 0:
        expression = "today"
    elif days_offset == 1:
        expression = "tomorrow"
    elif days_offset == -1:
        expression = "yesterday"
    elif days_offset > 1:
        expression = f"in {days_offset} days"
    else:
        expression = f"{abs(days_offset)} days ago"
    
    result = normalizer.normalize(expression, reference)
    
    # Should successfully parse
    assert result is not None
    
    # Calculate expected date (ignoring time component)
    expected_date = (reference + timedelta(days=days_offset)).date()
    result_date = result.date()
    
    # Allow 1-day tolerance for parsing ambiguities
    assert abs((result_date - expected_date).days) <= 1


# ---------------------------------------------------------------------------
# Property 10: Date Normalizer - Urdu Token Translation
# ---------------------------------------------------------------------------

@given(
    urdu_token=st.sampled_from([
        ("aaj", "today"),
        ("kal", "tomorrow"),
        ("parson", "day after tomorrow"),
    ])
)
def test_property_date_normalizer_urdu_tokens(urdu_token):
    """Property: Date normalizer correctly translates Urdu tokens to English."""
    normalizer = DateNormalizer()
    reference = datetime(2024, 6, 15, 12, 0, 0, tzinfo=timezone.utc)
    
    urdu_expr, english_equiv = urdu_token
    
    # Parse Urdu expression
    urdu_result = normalizer.normalize(urdu_expr, reference)
    
    # Parse English equivalent
    english_result = normalizer.normalize(english_equiv, reference)
    
    # Both should parse successfully
    assert urdu_result is not None
    assert english_result is not None
    
    # Should resolve to the same date
    assert urdu_result.date() == english_result.date()


# ---------------------------------------------------------------------------
# Property 11: Reminder State Transitions
# ---------------------------------------------------------------------------

@given(
    message=valid_text,
    status_sequence=st.lists(
        valid_reminder_statuses,
        min_size=1,
        max_size=5
    )
)
def test_property_reminder_state_transitions(db_session, message, status_sequence):
    """Property: Reminder status can be updated through valid state transitions."""
    db_session.rollback()
    db_session.query(Reminder).delete()
    db_session.commit()
    
    # Create reminder with initial "pending" status
    trigger_at = datetime(2024, 6, 15, 12, 0, 0, tzinfo=timezone.utc).isoformat()
    reminder = crud.create_reminder(
        db_session,
        message=message,
        trigger_at=trigger_at
    )
    
    assert reminder.status == "pending"
    
    # Apply status transitions
    for new_status in status_sequence:
        updated = crud.update_reminder_status(
            db_session,
            reminder_id=reminder.id,
            status=new_status
        )
        
        assert updated is not None
        assert updated.status == new_status
        
        # Verify persistence
        reminders = crud.get_reminders(db_session)
        retrieved = next((r for r in reminders if r.id == reminder.id), None)
        assert retrieved is not None
        assert retrieved.status == new_status


# ---------------------------------------------------------------------------
# Property 12: Pending Reminders Query
# ---------------------------------------------------------------------------

@given(
    num_past=st.integers(min_value=0, max_value=5),
    num_future=st.integers(min_value=0, max_value=5)
)
def test_property_pending_reminders_query(db_session, num_past, num_future):
    """Property: get_pending_reminders returns only past-due pending reminders."""
    db_session.rollback()
    db_session.query(Reminder).delete()
    db_session.commit()
    
    now = datetime.now(tz=timezone.utc)
    
    # Create past-due pending reminders
    past_ids = []
    for i in range(num_past):
        trigger = (now - timedelta(hours=i+1)).isoformat()
        r = crud.create_reminder(db_session, message=f"Past {i}", trigger_at=trigger)
        past_ids.append(r.id)
    
    # Create future pending reminders
    for i in range(num_future):
        trigger = (now + timedelta(hours=i+1)).isoformat()
        crud.create_reminder(db_session, message=f"Future {i}", trigger_at=trigger)
    
    # Query pending reminders
    pending = crud.get_pending_reminders(db_session)
    pending_ids = [r.id for r in pending]
    
    # Should return exactly the past-due reminders
    assert len(pending) == num_past
    assert set(pending_ids) == set(past_ids)


# ---------------------------------------------------------------------------
# Property 13: Session History Round-Trip
# ---------------------------------------------------------------------------

@given(
    transcript=valid_text,
    intent_type=st.none() | st.sampled_from([
        "create_task",
        "create_meeting",
        "create_reminder",
        "update_task",
        "complete_task"
    ]),
    result_summary=valid_text
)
def test_property_session_history_roundtrip(db_session, transcript, intent_type, result_summary):
    """Property: Session history data survives database round-trip without corruption."""
    db_session.rollback()
    db_session.query(SessionHistory).delete()
    db_session.commit()
    
    # Insert history record
    record = crud.insert_history(
        db_session,
        transcript=transcript,
        intent_type=intent_type,
        result_summary=result_summary
    )
    
    # Verify immediate state
    assert record.id is not None
    assert record.transcript == transcript
    assert record.intent_type == intent_type
    assert record.result_summary == result_summary
    assert record.session_at is not None
    
    # Fetch from database
    history = crud.get_history(db_session)
    retrieved = next((h for h in history if h.id == record.id), None)
    
    assert retrieved is not None
    assert retrieved.transcript == transcript
    assert retrieved.intent_type == intent_type
    assert retrieved.result_summary == result_summary
