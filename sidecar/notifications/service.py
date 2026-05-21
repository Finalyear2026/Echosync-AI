"""
Notification Service — polls DB for pending reminders and dispatches OS notifications.

Polls every 60 seconds. On app start, checks for past-due reminders (delivered_late).
Dispatches notifications via WebSocket event to the Tauri frontend.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional, Set

from db.database import SessionLocal
from db import crud

logger = logging.getLogger(__name__)

POLL_INTERVAL_SECONDS = 60


class NotificationService:
    """Polls the database and dispatches reminder notifications."""

    def __init__(self) -> None:
        self._running = False
        self._task: Optional[asyncio.Task] = None
        self._ws_broadcaster = None  # injected after WebSocket setup
        self._dispatched_ids: Set[int] = set()

    def set_broadcaster(self, broadcaster) -> None:
        """Inject the WebSocket broadcaster for notification events."""
        self._ws_broadcaster = broadcaster

    async def start_polling(self) -> None:
        """Start the background polling loop."""
        if self._running:
            return
        self._running = True
        # Check for past-due reminders on startup
        await self._check_late_reminders()
        self._task = asyncio.create_task(self._poll_loop())
        logger.info("NotificationService polling started (interval=%ds).", POLL_INTERVAL_SECONDS)

    async def stop_polling(self) -> None:
        """Stop the polling loop."""
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("NotificationService polling stopped.")

    async def _poll_loop(self) -> None:
        """Main polling loop."""
        while self._running:
            try:
                await self._check_pending_reminders()
            except Exception as exc:
                logger.error("NotificationService poll error: %s", exc)
            await asyncio.sleep(POLL_INTERVAL_SECONDS)

    async def _check_pending_reminders(self) -> None:
        """Query DB for pending reminders and dispatch notifications."""
        with SessionLocal() as session:
            reminders = crud.get_pending_reminders(session)
            for reminder in reminders:
                if reminder.id in self._dispatched_ids:
                    continue
                await self.dispatch(reminder, status="delivered")
                self._dispatched_ids.add(reminder.id)

    async def _check_late_reminders(self) -> None:
        """On app start, dispatch any reminders that fired while app was closed."""
        with SessionLocal() as session:
            reminders = crud.get_pending_reminders(session)
            for reminder in reminders:
                if reminder.id in self._dispatched_ids:
                    continue
                logger.info(
                    "Late reminder detected (id=%d, trigger_at=%s). Dispatching as delivered_late.",
                    reminder.id, reminder.trigger_at,
                )
                await self.dispatch(reminder, status="delivered_late")
                self._dispatched_ids.add(reminder.id)

    async def dispatch(self, reminder, status: str = "delivered") -> None:
        """
        Dispatch a reminder notification and update its status.

        Args:
            reminder: Reminder ORM object.
            status:   "delivered" or "delivered_late".
        """
        logger.info(
            "Dispatching reminder id=%d: '%s' (status=%s)",
            reminder.id, reminder.message[:50], status,
        )

        # Update DB status
        with SessionLocal() as session:
            crud.update_reminder_status(session, reminder.id, status)

        # Emit WebSocket event to frontend (Tauri notification plugin handles the toast)
        if self._ws_broadcaster:
            await self._ws_broadcaster.broadcast({
                "event": "notification_trigger",
                "reminder_id": reminder.id,
                "message": reminder.message,
                "status": status,
            })
        else:
            logger.warning(
                "No WebSocket broadcaster set — notification not sent to frontend."
            )
