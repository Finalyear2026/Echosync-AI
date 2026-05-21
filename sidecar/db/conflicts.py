"""
EchoSync AI Desktop — ConflictWarning dataclass.

Returned by conflict-detection functions in crud.py when a proposed insert
would violate a business-logic constraint (meeting overlap or duplicate task).
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class ConflictWarning:
    conflict_type: str  # "meeting_overlap" | "duplicate_task"
    message: str
