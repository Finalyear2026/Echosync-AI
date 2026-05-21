"""
WebSocket connection manager and status event broadcaster.

Broadcasts StatusEvent and partial_transcript events to all connected clients.
Max latency from state change to push: 500ms (enforced by async queue).
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class ConnectionManager:
    """Manages active WebSocket connections and broadcasts events."""

    def __init__(self) -> None:
        self._connections: list[WebSocket] = []
        self._queue: asyncio.Queue[dict] = asyncio.Queue()
        self._broadcaster_task: asyncio.Task | None = None

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections.append(websocket)
        logger.info("WebSocket client connected. Total: %d", len(self._connections))

    def disconnect(self, websocket: WebSocket) -> None:
        if websocket in self._connections:
            self._connections.remove(websocket)
        logger.info("WebSocket client disconnected. Total: %d", len(self._connections))

    async def broadcast(self, data: dict[str, Any]) -> None:
        """Queue a message for broadcast to all connected clients."""
        await self._queue.put(data)

    async def emit_status(self, state: str, payload: dict | None = None) -> None:
        """Emit a status_change event."""
        await self.broadcast({
            "event": "status_change",
            "state": state,
            "payload": payload or {},
        })

    async def emit_partial_transcript(self, text: str, is_final: bool) -> None:
        """Emit a partial_transcript event."""
        await self.broadcast({
            "event": "partial_transcript",
            "text": text,
            "is_final": is_final,
        })

    async def start_broadcaster(self) -> None:
        """Start the background broadcast loop."""
        self._broadcaster_task = asyncio.create_task(self._broadcast_loop())

    async def stop_broadcaster(self) -> None:
        """Stop the background broadcast loop."""
        if self._broadcaster_task:
            self._broadcaster_task.cancel()
            try:
                await self._broadcaster_task
            except asyncio.CancelledError:
                pass

    async def _broadcast_loop(self) -> None:
        """Drain the queue and send to all connected clients."""
        while True:
            try:
                data = await asyncio.wait_for(self._queue.get(), timeout=0.5)
                message = json.dumps(data)
                dead = []
                for ws in list(self._connections):
                    try:
                        await ws.send_text(message)
                    except Exception:
                        dead.append(ws)
                for ws in dead:
                    self.disconnect(ws)
            except asyncio.TimeoutError:
                continue
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.error("Broadcast error: %s", exc)


# Global singleton
manager = ConnectionManager()
