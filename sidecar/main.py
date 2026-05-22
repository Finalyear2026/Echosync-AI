"""
EchoSync AI Desktop — FastAPI sidecar entry point.
Binds exclusively to 127.0.0.1.
"""

from __future__ import annotations

import asyncio
import logging
import os
import signal
from contextlib import asynccontextmanager

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.websocket import manager
from db.database import SessionLocal, init_db, get_session
from db import crud
from models_dl.downloader import ModelDownloader
from notifications.service import NotificationService

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

notification_service = NotificationService()
model_downloader = ModelDownloader()
_audio_service = None
_router = None
_intent_engine = None
_stt_engine = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("EchoSync sidecar starting up...")
    init_db()
    logger.info("Database initialised.")
    notification_service.set_broadcaster(manager)
    await manager.start_broadcaster()
    await notification_service.start_polling()
    try:
        from llm.runtime import get_llm_runtime
        get_llm_runtime().startup_load()
    except Exception as exc:
        logger.warning("LLM startup skipped: %s", exc)
    logger.info("EchoSync sidecar ready.")
    yield
    logger.info("EchoSync sidecar shutting down...")
    await notification_service.stop_polling()
    await manager.stop_broadcaster()
    if _audio_service is not None:
        _audio_service.stop_capture()
    logger.info("EchoSync sidecar shutdown complete.")


app = FastAPI(title="EchoSync AI Sidecar", version="0.1.0", lifespan=lifespan)

# CORS configuration: Restrict to Tauri and localhost origins only
# This prevents unauthorized web pages from accessing the sidecar API
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        # Tauri app origins
        "tauri://localhost",
        "https://tauri.localhost",
        # Localhost origins for development/testing
        "http://localhost:1420",      # Tauri dev server
        "http://127.0.0.1:1420",      # Tauri dev server (IP)
        "http://localhost:5173",      # Vite dev server
        "http://127.0.0.1:5173",      # Vite dev server (IP)
        "http://localhost:8080",      # Alternative dev port
        "http://127.0.0.1:8080",      # Alternative dev port (IP)
        "null",                        # file:// URLs send "null" as origin
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=[
        "Content-Type",
        "Authorization",
        "Accept",
        "Origin",
        "X-Requested-With",
    ],
    max_age=600,  # Cache preflight requests for 10 minutes
)


# --- Response models ---

class HealthResponse(BaseModel):
    status: str

class SessionStarted(BaseModel):
    status: str

class SessionStopped(BaseModel):
    status: str

class ModelStatus(BaseModel):
    models_present: bool
    missing: list[str]

class DownloadRequest(BaseModel):
    source_url: str
    filename: str

class DownloadStarted(BaseModel):
    status: str
    filename: str


# --- Health ---

@app.get("/health", response_model=HealthResponse)
async def health():
    return {"status": "ok"}


@app.post("/shutdown")
async def shutdown():
    logger.info("Shutdown requested.")
    os.kill(os.getpid(), signal.SIGTERM)
    return {"status": "shutting_down"}


# --- Session ---

@app.post("/session/start", response_model=SessionStarted)
async def session_start():
    global _audio_service, _router, _intent_engine, _stt_engine
    try:
        if _audio_service and _audio_service.is_running:
            logger.warning("Session already active.")
            return {"status": "already_started"}

        logger.info("Session start: initializing pipeline...")
        loop = asyncio.get_event_loop()

        # Initialize heavy components in thread pool
        import concurrent.futures
        def _init_components():
            from audio.service import AudioService
            from router.semantic_router import SemanticRouter
            from intent.engine import IntentEngine
            from stt.engine import STTEngine

            stt = STTEngine()
            router = SemanticRouter()
            intent = IntentEngine()
            audio = AudioService(stt_engine=stt)
            return audio, router, intent, stt

        with concurrent.futures.ThreadPoolExecutor() as pool:
            audio, router, intent, stt = await loop.run_in_executor(pool, _init_components)

        _audio_service = audio
        _router = router
        _intent_engine = intent
        _stt_engine = stt

        from stt.engine import PartialTranscript

        async def handle_partial(partial: PartialTranscript):
            logger.info(">> Partial [final=%s]: %s", partial.is_final, partial.text[:80])
            await manager.emit_partial_transcript(partial.text, partial.is_final)
            if partial.is_final and partial.text:
                await manager.emit_status("transcribing", {"transcript": partial.text})

        def handle_partial_sync(partial: PartialTranscript):
            asyncio.run_coroutine_threadsafe(handle_partial(partial), loop)

        def handle_segment(wav_bytes: bytes):
            logger.info("Segment received (%d bytes)", len(wav_bytes))
            asyncio.run_coroutine_threadsafe(
                _process_segment(wav_bytes), loop
            )

        _audio_service.on_speech_segment(handle_segment)
        _audio_service.on_partial_transcript(handle_partial_sync)
        _audio_service.start_capture()

        await manager.emit_status("hearing")
        logger.info("Session started successfully.")
        return {"status": "started"}

    except Exception as exc:
        logger.error("Session start error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/stop", response_model=SessionStopped)
async def session_stop():
    global _audio_service
    if _audio_service:
        _audio_service.stop_capture()
        _audio_service = None
    await manager.emit_status("idle")
    return {"status": "stopped"}


async def _process_segment(wav_bytes: bytes):
    """Process a finalized speech segment through the full pipeline."""
    global _router, _intent_engine, _stt_engine

    if _stt_engine is None or _router is None:
        return

    # Re-transcribe the full segment for accuracy
    result = _stt_engine.transcribe(wav_bytes)
    logger.info("Final transcript: '%s' (lang=%s, conf=%.2f)",
                result.text, result.language_detected, result.confidence)

    if not result.text.strip():
        await manager.emit_status("hearing")
        return

    # Emit final transcript to UI
    await manager.emit_partial_transcript(result.text, True)

    route = _router.classify(result.text)
    logger.info("Route: %s", route)

    # Use context manager for proper session handling
    with SessionLocal() as db:
        try:
            if route == "command":
                await manager.emit_status("extracting", {"transcript": result.text})
                intent_result = _intent_engine.extract_intent(result.text)
                if intent_result.success and intent_result.intent:
                    _execute_intent(intent_result.intent, db)
                    await manager.emit_status("idle", {"result": f"Done: {intent_result.intent.intent_type}"})
                else:
                    await manager.emit_status("idle", {"result": result.text})
            else:
                await manager.emit_status("thinking", {"transcript": result.text})
                from agentic.engine import AgenticEngine
                agentic = AgenticEngine(db)
                response = agentic.run(result.text)
                await manager.emit_status("idle", {"result": response.answer})

            crud.insert_history(
                db,
                transcript=result.text,
                intent_type=route if route == "command" else None,
                result_summary="processed",
            )
        except Exception as exc:
            logger.error("Pipeline processing error: %s", exc, exc_info=True)
            await manager.emit_status("idle", {"result": result.text})


def _execute_intent(intent, session: Session):
    from intent.models import (
        CreateTaskIntent, UpdateTaskIntent, CompleteTaskIntent,
        ScheduleMeetingIntent, SetReminderIntent,
    )
    from intent.date_normalizer import DateNormalizer
    from datetime import datetime, timezone, timedelta
    import json

    dn = DateNormalizer()
    now = datetime.now(tz=timezone.utc)

    try:
        if isinstance(intent, CreateTaskIntent):
            due_at = None
            if intent.due_at:
                dt = dn.normalize(intent.due_at, now)
                due_at = dt.isoformat() if dt else None
            crud.create_task(session, title=intent.title, priority=intent.priority, due_at=due_at)
            logger.info("Task created: %s", intent.title)

        elif isinstance(intent, UpdateTaskIntent):
            if intent.task_id:
                due_at = None
                if intent.due_at:
                    dt = dn.normalize(intent.due_at, now)
                    due_at = dt.isoformat() if dt else None
                crud.update_task(session, intent.task_id, priority=intent.priority, due_at=due_at)

        elif isinstance(intent, CompleteTaskIntent):
            if intent.task_id:
                crud.complete_task(session, intent.task_id)

        elif isinstance(intent, ScheduleMeetingIntent):
            start_dt = dn.normalize(intent.start_at, now)
            if start_dt:
                end_dt = dn.normalize(intent.end_at, now) if intent.end_at else start_dt + timedelta(hours=1)
                crud.create_meeting(
                    session,
                    title=intent.title,
                    attendees=json.dumps(intent.attendees),
                    start_at=start_dt.isoformat(),
                    end_at=(end_dt or start_dt + timedelta(hours=1)).isoformat(),
                )

        elif isinstance(intent, SetReminderIntent):
            trigger_dt = dn.normalize(intent.trigger_at, now)
            if trigger_dt:
                crud.create_reminder(session, message=intent.message, trigger_at=trigger_dt.isoformat())
    except Exception as exc:
        logger.error("Intent execution error: %s", exc)


# --- Data endpoints ---

@app.get("/tasks")
def list_tasks(db: Session = Depends(get_session)):
    tasks = crud.get_tasks(db)
    return [{"id": t.id, "title": t.title, "priority": t.priority,
             "status": t.status, "due_at": t.due_at, "created_at": t.created_at} for t in tasks]


@app.get("/meetings")
def list_meetings(db: Session = Depends(get_session)):
    meetings = crud.get_meetings(db)
    return [{"id": m.id, "title": m.title, "start_at": m.start_at,
             "end_at": m.end_at, "attendees": m.attendees} for m in meetings]


@app.get("/reminders")
def list_reminders(db: Session = Depends(get_session)):
    reminders = crud.get_reminders(db)
    return [{"id": r.id, "message": r.message, "trigger_at": r.trigger_at,
             "status": r.status} for r in reminders]


@app.get("/history")
def list_history(db: Session = Depends(get_session)):
    records = crud.get_history(db)
    return [{"id": h.id, "transcript": h.transcript, "intent_type": h.intent_type,
             "result_summary": h.result_summary, "session_at": h.session_at} for h in records]


# --- Model downloader ---

@app.get("/models/status", response_model=ModelStatus)
def models_status():
    return {
        "models_present": model_downloader.check_models_present(),
        "missing": model_downloader.get_missing_models(),
    }


@app.post("/models/download", response_model=DownloadStarted)
async def models_download(req: DownloadRequest):
    loop = asyncio.get_event_loop()

    async def run_download():
        def sync_progress(pct: float):
            asyncio.run_coroutine_threadsafe(
                manager.broadcast({"event": "download_progress",
                                   "filename": req.filename,
                                   "progress": round(pct * 100, 1)}),
                loop
            )
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor() as pool:
            result = await loop.run_in_executor(
                pool, lambda: model_downloader.download(req.source_url, req.filename, sync_progress)
            )
        await manager.broadcast({
            "event": "download_complete",
            "filename": req.filename,
            "success": result.success,
            "message": result.message,
        })

    asyncio.create_task(run_download())
    return {"status": "started", "filename": req.filename}


# --- WebSocket ---

@app.websocket("/ws/status")
async def websocket_status(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)


def main():
    uvicorn.run("main:app", host="127.0.0.1", port=8765, log_level="info", reload=False)


if __name__ == "__main__":
    main()
