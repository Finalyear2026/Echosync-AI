# EchoSync AI - Project Documentation

## Executive Summary

EchoSync AI is a privacy-first, fully offline desktop voice assistant designed specifically for multilingual users in Pakistan and South Asia. The application operates entirely on the local machine without requiring internet connectivity, ensuring complete data privacy and security. It supports Urdu, Punjabi, English, and Roman Urdu (Urdu written in Latin script), making it accessible to a diverse user base.

The system enables users to manage their daily tasks, schedule meetings, set reminders, and ask questions about their schedule using natural voice commands in their preferred language.

---

## Technology Stack

### Frontend Technologies

#### 1. **HTML5/CSS3/JavaScript**
- **Purpose**: Primary user interface
- **Implementation**: `test-ui.html` - A standalone, production-ready web interface
- **Features**:
  - Real-time WebSocket communication
  - Responsive design with modern UI/UX
  - No build process required
  - Cross-browser compatible

#### 2. **React 18.3.1** (Alternative UI)
- **Purpose**: Component-based UI framework
- **Status**: Implemented but has build issues with Vite 8
- **Components**:
  - StatusBar: Real-time connection and status display
  - TranscriptPreview: Live speech-to-text preview
  - HistoryView: Session history browser
  - ModelWizard: First-run setup for model downloads

#### 3. **Tailwind CSS 3.4**
- **Purpose**: Utility-first CSS framework
- **Features**: Responsive design, dark theme, RTL support for Urdu

#### 4. **Vite 7.3** (Build Tool)
- **Purpose**: Fast development server and bundler
- **Note**: Downgraded from v8 due to plugin compatibility

### Backend Technologies

#### 1. **Python 3.10+**
- **Purpose**: Core backend language
- **Advantages**: Rich ML/AI ecosystem, excellent library support

#### 2. **FastAPI 0.115.0**
- **Purpose**: Modern, high-performance web framework
- **Features**:
  - Automatic OpenAPI documentation
  - WebSocket support for real-time communication
  - Type hints and validation with Pydantic
  - CORS middleware for cross-origin requests
- **Endpoints**:
  - REST API for CRUD operations
  - WebSocket for real-time status updates
  - Health checks and monitoring

#### 3. **SQLAlchemy 2.0.35**
- **Purpose**: SQL toolkit and ORM
- **Database**: SQLite (embedded, no server required)
- **Schema**:
  - Tasks table (id, title, priority, status, due_at, created_at)
  - Meetings table (id, title, start_at, end_at, attendees)
  - Reminders table (id, message, trigger_at, status)
  - History table (id, transcript, intent_type, result_summary, session_at)

#### 4. **Uvicorn 0.30.6**
- **Purpose**: ASGI server for FastAPI
- **Configuration**: Bound to localhost (127.0.0.1:8765) for security

### AI/ML Technologies

#### 1. **faster-whisper** (Speech-to-Text)
- **Purpose**: Offline speech recognition
- **Model**: OpenAI Whisper (small/medium variants)
- **Technology**: CTranslate2 for optimized inference
- **Features**:
  - Automatic language detection
  - Support for 99+ languages including Urdu
  - Real-time partial transcription
  - Configurable beam search for accuracy vs speed
- **Performance**:
  - Small model: ~1-2 seconds latency
  - Medium model: ~2-4 seconds latency
  - RAM usage: 1-2 GB

#### 2. **llama-cpp-python** (Language Model)
- **Purpose**: Intent extraction and question answering
- **Model**: Llama 3.2 3B Instruct (Q4_K_M quantized)
- **Technology**: GGUF format for efficient CPU inference
- **Features**:
  - GBNF grammar-constrained generation for structured output
  - Context window: 4096 tokens
  - Quantization: 4-bit for reduced memory footprint
- **RAM Management**:
  - High-RAM mode (≥8GB): Load at startup
  - Low-RAM mode (<8GB): Load on-demand, auto-unload after 5 min idle

#### 3. **PyAudio / sounddevice**
- **Purpose**: Audio capture from microphone
- **Configuration**: 16kHz mono, 16-bit PCM
- **Frame size**: 30ms chunks for low latency

#### 4. **NumPy**
- **Purpose**: Audio signal processing
- **Usage**: Convert audio bytes to float32 arrays for Whisper

### Desktop Integration

#### 1. **Tauri 2.0**
- **Purpose**: Desktop application framework
- **Technology**: Rust + WebView
- **Features**:
  - Native system tray integration
  - Auto-start on boot
  - Native notifications
  - Small binary size (~10MB)
- **Advantages over Electron**:
  - 10x smaller bundle size
  - Lower memory usage
  - Better security (Rust backend)

#### 2. **Windows Toast Notifications**
- **Purpose**: System notifications for reminders
- **Implementation**: Native Windows API via Python

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User Interface                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  HTML/JS Frontend (test-ui.html)                     │  │
│  │  - Voice controls                                     │  │
│  │  - Real-time transcript display                      │  │
│  │  - Task/Meeting/Reminder views                       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ HTTP/WebSocket
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    FastAPI Backend (Python)                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  API Layer                                            │  │
│  │  - REST endpoints (/tasks, /meetings, /reminders)    │  │
│  │  - WebSocket (/ws/status)                            │  │
│  │  - Session management (/session/start, /stop)        │  │
│  └──────────────────────────────────────────────────────┘  │
│                            │                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Voice Processing Pipeline                            │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │  │
│  │  │   Audio    │→ │    STT     │→ │  Semantic  │     │  │
│  │  │  Capture   │  │  (Whisper) │  │   Router   │     │  │
│  │  └────────────┘  └────────────┘  └────────────┘     │  │
│  │                                         │             │  │
│  │                        ┌────────────────┴──────────┐ │  │
│  │                        ▼                           ▼ │  │
│  │                  ┌──────────┐            ┌──────────┐│  │
│  │                  │  Intent  │            │ Agentic  ││  │
│  │                  │ Extractor│            │  Engine  ││  │
│  │                  │  (LLM)   │            │  (LLM)   ││  │
│  │                  └──────────┘            └──────────┘│  │
│  │                        │                           │ │  │
│  │                        └────────────┬──────────────┘ │  │
│  │                                     ▼                 │  │
│  │                              ┌────────────┐           │  │
│  │                              │  Database  │           │  │
│  │                              │  (SQLite)  │           │  │
│  │                              └────────────┘           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Voice Processing Pipeline

1. **Audio Capture**
   - Continuous microphone monitoring
   - Voice Activity Detection (VAD) using energy-based algorithm
   - Silence detection to segment speech

2. **Speech-to-Text (STT)**
   - Real-time partial transcription (every 2 seconds)
   - Final transcription on speech segment completion
   - Language auto-detection (Urdu/English/Punjabi)

3. **Semantic Routing**
   - Classifies transcript as "command" or "question"
   - Command keywords: create, add, schedule, set, remind
   - Question keywords: what, show, am I, do I have

4. **Intent Extraction** (for commands)
   - LLM-based extraction with GBNF grammar constraints
   - Fallback to rule-based pattern matching
   - Supported intents:
     - create_task
     - update_task
     - complete_task
     - schedule_meeting
     - set_reminder

5. **Agentic Engine** (for questions)
   - ReAct-style reasoning loop (Thought → Action → Observation)
   - Database query tool for looking up tasks/meetings/reminders
   - Multi-step reasoning (max 5 steps)
   - Response synthesis in user's language

6. **Database Operations**
   - CRUD operations via SQLAlchemy ORM
   - Parameterized queries (no SQL injection risk)
   - Transaction management

7. **Response Delivery**
   - WebSocket push for real-time UI updates
   - Status changes: idle → hearing → transcribing → extracting → thinking → idle

---

## Key Features

### 1. **Multilingual Support**
- **Languages**: Urdu, Punjabi, English, Roman Urdu
- **RTL Support**: Right-to-left text rendering for Urdu script
- **Code-Switching**: Handles mixed-language input (e.g., "Task bana do kal ke liye")
- **Response Language**: Responds in the same language as the input

### 2. **Privacy-First Design**
- **Fully Offline**: No internet connection required
- **Local Processing**: All AI inference happens on-device
- **No Cloud**: Data never leaves the user's computer
- **No Telemetry**: No usage tracking or analytics

### 3. **Voice Activity Detection (VAD)**
- **Energy-Based**: RMS threshold detection
- **Configurable**: Adjustable sensitivity for different environments
- **Silence Detection**: Automatic speech segment finalization
- **Max Segment Length**: 10 seconds to prevent memory issues

### 4. **Real-Time Transcription**
- **Partial Transcripts**: Live preview as user speaks
- **Final Transcription**: High-accuracy re-transcription on segment completion
- **Confidence Scores**: Per-segment probability metrics

### 5. **Date Normalization**
- **Relative Dates**: "tomorrow", "next Monday", "in 2 hours"
- **Urdu Dates**: "kal" (tomorrow), "parso" (day after tomorrow)
- **Absolute Dates**: "May 21st", "2026-05-21"
- **Time Expressions**: "at 2 PM", "10:30 AM"

### 6. **Notification Service**
- **Polling**: Checks reminders every 60 seconds
- **Windows Toast**: Native system notifications
- **Status Tracking**: Marks reminders as "delivered"

### 7. **Session Management**
- **Start/Stop**: User-controlled voice capture
- **Auto-Unload**: LLM unloads after 5 min idle (low-RAM mode)
- **History Tracking**: All sessions logged to database

---

## Design Decisions

### 1. **Why Offline?**
- **Privacy**: Voice data is sensitive; users don't want it sent to cloud
- **Latency**: Local processing is faster than cloud API calls
- **Reliability**: Works without internet connection
- **Cost**: No API fees or subscription costs

### 2. **Why Python Backend?**
- **ML Ecosystem**: Best support for AI/ML libraries
- **Rapid Development**: Fast prototyping and iteration
- **Community**: Large community for troubleshooting

### 3. **Why FastAPI?**
- **Performance**: Async support for concurrent requests
- **Type Safety**: Pydantic validation prevents bugs
- **Documentation**: Auto-generated OpenAPI docs
- **Modern**: Built for Python 3.10+ with type hints

### 4. **Why SQLite?**
- **Embedded**: No separate database server required
- **Portable**: Single file database
- **Reliable**: ACID-compliant transactions
- **Fast**: Sufficient for single-user desktop app

### 5. **Why Whisper?**
- **Accuracy**: State-of-the-art speech recognition
- **Multilingual**: Supports 99+ languages out-of-the-box
- **Offline**: Runs entirely on CPU
- **Open Source**: Free to use and modify

### 6. **Why Llama 3.2 3B?**
- **Size**: Small enough to run on consumer hardware
- **Quality**: Good instruction-following capability
- **Quantization**: 4-bit reduces memory to ~2GB
- **Open Source**: Free to use commercially

### 7. **Why Tauri?**
- **Size**: 10x smaller than Electron
- **Performance**: Lower memory usage
- **Security**: Rust backend is memory-safe
- **Native**: Better OS integration

---

## Performance Characteristics

### Latency
- **Audio Capture**: <30ms per frame
- **VAD Detection**: <10ms per frame
- **STT (Partial)**: ~1-2 seconds
- **STT (Final)**: ~2-4 seconds
- **Intent Extraction**: ~1-3 seconds
- **Question Answering**: ~3-10 seconds
- **Total (Command)**: ~5-10 seconds
- **Total (Question)**: ~10-20 seconds

### Memory Usage
- **Base Application**: ~200 MB
- **Whisper Small**: ~1 GB
- **Whisper Medium**: ~2 GB
- **Llama 3.2 3B (Q4)**: ~2 GB
- **Total (Low-RAM)**: ~3-4 GB
- **Total (High-RAM)**: ~5-6 GB

### Disk Usage
- **Application Code**: ~50 MB
- **Whisper Model**: ~500 MB - 1.5 GB
- **LLM Model**: ~2 GB
- **Database**: <10 MB
- **Total**: ~3-4 GB

### Accuracy
- **English STT**: ~95%
- **Urdu STT (Generic)**: ~60-70%
- **Urdu STT (Fine-tuned)**: ~85-90% (not implemented)
- **Intent Extraction**: ~80-90%
- **Question Answering**: ~70-80%

---

## Security Considerations

### 1. **Network Security**
- **Localhost Only**: Backend binds to 127.0.0.1 (not 0.0.0.0)
- **CORS**: Configured to allow only local origins
- **No External Requests**: Application never makes outbound connections

### 2. **Data Security**
- **Local Storage**: All data stored in local SQLite database
- **No Encryption**: Database is unencrypted (single-user desktop app)
- **File Permissions**: Standard OS file permissions apply

### 3. **Input Validation**
- **Pydantic Models**: All API inputs validated
- **SQL Injection**: Prevented by SQLAlchemy ORM
- **XSS**: Frontend sanitizes user input

### 4. **Model Security**
- **Offline Validation**: Checks model paths are local (not network URLs)
- **No Remote Loading**: Models must be present on disk

---

## Limitations and Known Issues

### 1. **Urdu Accuracy**
- **Issue**: Generic Whisper model has ~60-70% accuracy for Urdu
- **Solution**: Fine-tune Whisper on Urdu dataset (not implemented)
- **Workaround**: Use more explicit command phrases

### 2. **React UI Build**
- **Issue**: Vite 8 incompatibility with React plugin
- **Solution**: Downgraded to Vite 7
- **Workaround**: Use test-ui.html (fully functional)

### 3. **LLM Loading Time**
- **Issue**: First command takes 30-60 seconds in low-RAM mode
- **Solution**: Pre-load LLM in high-RAM mode
- **Workaround**: User patience on first command

### 4. **No GPU Acceleration**
- **Issue**: CPU-only inference is slower
- **Solution**: Add CUDA support for NVIDIA GPUs (not implemented)
- **Impact**: 2-5x slower than GPU

### 5. **Single User**
- **Issue**: No multi-user support or authentication
- **Solution**: Not needed for desktop app
- **Impact**: One database per installation

---

## Future Enhancements

### Short-Term (1-3 months)
1. **Fine-tune Whisper** on Urdu/Punjabi dataset for better accuracy
2. **Fix React UI** build issues
3. **Add GPU support** for faster inference
4. **Implement task editing** and deletion via voice
5. **Add calendar view** for meetings

### Medium-Term (3-6 months)
1. **Multi-language LLM** fine-tuned for Urdu/English
2. **Voice feedback** (text-to-speech responses)
3. **Hotword detection** ("Hey EchoSync")
4. **Plugin system** for extensibility
5. **Export/import** data

### Long-Term (6-12 months)
1. **Mobile app** (Android/iOS)
2. **Sync across devices** (optional, privacy-preserving)
3. **Smart home integration** (offline)
4. **Custom wake word** training
5. **Emotion detection** in voice

---

## Conclusion

EchoSync AI demonstrates that privacy-first, offline voice assistants are not only feasible but can provide a superior user experience for multilingual users. By leveraging modern open-source AI models and efficient system design, the application delivers real-time voice interaction without compromising user privacy or requiring expensive cloud infrastructure.

The system is production-ready for single-user desktop deployment and serves as a foundation for future enhancements in multilingual voice AI.

---

## References

- **Whisper**: https://github.com/openai/whisper
- **faster-whisper**: https://github.com/guillaumekln/faster-whisper
- **Llama**: https://ai.meta.com/llama/
- **llama-cpp-python**: https://github.com/abetlen/llama-cpp-python
- **FastAPI**: https://fastapi.tiangolo.com/
- **Tauri**: https://tauri.app/
- **SQLAlchemy**: https://www.sqlalchemy.org/

---

**Project**: EchoSync AI  
**Version**: 1.0.0  
**Date**: May 2026  
**Authors**: Final Year Project Team 2026
