"""
EchoSync AI Desktop — SQLAlchemy engine, session factory, and schema init.

The SQLite database is stored at %APPDATA%/EchoSync/echosync.db on Windows.
On non-Windows platforms (CI, development) it falls back to
~/.echosync/echosync.db so tests can run without a Windows environment.
"""

from __future__ import annotations

import os
import platform
from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from db.models import Base

# ---------------------------------------------------------------------------
# Database path resolution
# ---------------------------------------------------------------------------


def _resolve_db_path() -> Path:
    """Return the platform-appropriate path for the EchoSync SQLite database."""
    if platform.system() == "Windows":
        appdata = os.environ.get("APPDATA")
        if appdata:
            base = Path(appdata)
        else:
            # Fallback: use user home if APPDATA is unset (unusual on Windows)
            base = Path.home() / "AppData" / "Roaming"
    else:
        # Non-Windows: use ~/.echosync/ for development / CI
        base = Path.home() / ".echosync"

    db_dir = base / "EchoSync"
    db_dir.mkdir(parents=True, exist_ok=True)
    return db_dir / "echosync.db"


DB_PATH: Path = _resolve_db_path()

# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------

engine = create_engine(
    f"sqlite:///{DB_PATH}",
    connect_args={"check_same_thread": False},
    echo=False,
)


@event.listens_for(Engine, "connect")
def _set_sqlite_pragma(dbapi_connection, connection_record) -> None:  # type: ignore[type-arg]
    """Enable WAL mode and foreign-key enforcement on every new connection."""
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


# ---------------------------------------------------------------------------
# Session factory
# ---------------------------------------------------------------------------

SessionLocal = sessionmaker(
    bind=engine,
    autocommit=False,
    autoflush=False,
    expire_on_commit=False,
)


def get_session() -> Session:
    """
    FastAPI dependency that yields a database session and closes it afterwards.

    Usage::

        @app.get("/tasks")
        def list_tasks(session: Session = Depends(get_session)):
            ...
    """
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


# ---------------------------------------------------------------------------
# Schema initialisation
# ---------------------------------------------------------------------------


def init_db() -> None:
    """Create all tables (CREATE TABLE IF NOT EXISTS) using the ORM metadata."""
    Base.metadata.create_all(bind=engine)
