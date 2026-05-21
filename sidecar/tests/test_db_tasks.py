from hypothesis import given, strategies as st
from sqlalchemy.exc import IntegrityError
import pytest

from db.models import Task
from db import crud

# Generate valid priority values
valid_priorities = st.sampled_from(["low", "medium", "high"])

# Generate invalid priority values (e.g. empty string, arbitrary text, wrong casing)
invalid_priorities = st.text(min_size=1).filter(lambda s: s not in ["low", "medium", "high"])

# Generate valid task titles (up to 500 characters, non-empty)
valid_titles = st.text(min_size=1, max_size=500).filter(lambda s: "\x00" not in s)

# Generate invalid task titles (too long, over 500 characters)
invalid_titles = st.text(min_size=501, max_size=1000).filter(lambda s: "\x00" not in s)


@given(title=valid_titles, priority=valid_priorities, due_at=st.none() | st.text(min_size=10, max_size=30).filter(lambda s: "\x00" not in s))
def test_property_task_roundtrip(db_session, title, priority, due_at):
    """Property 6: Validate task database round-trip."""
    db_session.rollback()
    db_session.query(Task).delete()
    db_session.commit()
    
    # Create the task
    task = crud.create_task(db_session, title=title, priority=priority, due_at=due_at)
    assert task.id is not None
    assert task.title == title
    assert task.priority == priority
    assert task.status == "pending"
    assert task.due_at == due_at
    
    # Fetch from database
    tasks = crud.get_tasks(db_session)
    assert len(tasks) >= 1
    retrieved = next(t for t in tasks if t.id == task.id)
    assert retrieved.title == title
    assert retrieved.priority == priority
    assert retrieved.due_at == due_at
    assert retrieved.status == "pending"


@given(title=valid_titles, invalid_prio=invalid_priorities)
def test_property_task_priority_constraint(db_session, title, invalid_prio):
    """Property 7: Validate task priority constraint invariant (low/medium/high)."""
    db_session.rollback()
    db_session.query(Task).delete()
    db_session.commit()
    
    # Direct model insertion bypasses python defaults, forcing SQLite CHECK constraint evaluation
    task = Task(title=title, priority=invalid_prio, status="pending", created_at="2026-05-21T00:00:00")
    db_session.add(task)
    
    with pytest.raises(IntegrityError):
        db_session.commit()


@given(title=valid_titles)
def test_property_task_title_length_constraint(db_session, title):
    """Validate task title length constraint (<= 500 characters)."""
    db_session.rollback()
    db_session.query(Task).delete()
    db_session.commit()
    
    # Attempting to create a title > 500 characters
    long_title = "a" * 501
    task = Task(title=long_title, priority="medium", status="pending", created_at="2026-05-21T00:00:00")
    db_session.add(task)
    
    with pytest.raises(IntegrityError):
        db_session.commit()


@given(title=valid_titles)
def test_property_duplicate_task_checking(db_session, title):
    """Property 15: Validate duplicate task conflict detection (same day prefix match)."""
    db_session.rollback()
    db_session.query(Task).delete()
    db_session.commit()
    
    # Define date
    date_str = "2026-05-21"
    created_at_str = f"{date_str}T10:00:00+00:00"
    
    # Ensure not duplicate initially
    assert not crud.check_duplicate_task(db_session, title, date_str)
    
    # Add the task
    task = Task(title=title, priority="medium", status="pending", created_at=created_at_str)
    db_session.add(task)
    db_session.commit()
    
    # Ensure detected as duplicate
    assert crud.check_duplicate_task(db_session, title, date_str)
    
    # Another day should not be duplicate
    assert not crud.check_duplicate_task(db_session, title, "2026-05-22")
