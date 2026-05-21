# EchoSync AI - Privacy-First Offline Voice Assistant

A multilingual voice assistant for Windows that works completely offline, supporting Urdu, Punjabi, English, and Roman Urdu.

## Features

✅ **Fully Offline** - No internet required, all processing happens locally
✅ **Multilingual** - Supports Urdu, Punjabi, English, and Roman Urdu
✅ **Voice Commands** - Create tasks, schedule meetings, set reminders
✅ **Natural Questions** - Ask about your schedule, tasks, and more
✅ **Privacy-First** - Your data never leaves your computer

## Architecture

- **Frontend**: HTML/JavaScript web interface (test-ui.html)
- **Backend**: Python FastAPI sidecar
- **STT**: faster-whisper (Whisper.cpp)
- **LLM**: llama-cpp-python (Llama 3.2 3B)
- **Database**: SQLite

## Quick Start

### Prerequisites

- Python 3.10+
- Windows 10/11
- Microphone

### Installation

1. **Install Python dependencies**:
```bash
cd sidecar
pip install -r requirements.txt
```

2. **Download LLM model** (if not already present):
   - Place `Llama-3.2-3B-Instruct-Q4_K_M.gguf` in:
   - `C:\Users\<YourUser>\AppData\Roaming\EchoSync\models\`

### Running

1. **Start the backend**:
```bash
cd sidecar
python main.py
```

2. **Open the frontend**:
   - Open `test-ui.html` in your browser
   - Or navigate to `http://localhost:1420` if using the React dev server

3. **Use the assistant**:
   - Click "Start Listening"
   - Speak a command: "Create a task to buy milk"
   - Wait for processing
   - Check results with "View Tasks" button

## Supported Commands

### Task Management
- "Create a task to [description]"
- "Add a task to [description]"
- "Task to [description]"

### Meeting Scheduling
- "Schedule a meeting [details]"
- "Set up a meeting [details]"
- "Book a meeting [details]"

### Reminders
- "Remind me to [description]"
- "Set a reminder to [description]"

### Questions
- "What tasks do I have?"
- "Am I free tomorrow?"
- "Show me my schedule"

## Project Structure

```
echosync-desktop/
├── sidecar/              # Python FastAPI backend
│   ├── main.py          # Entry point
│   ├── audio/           # Audio capture & VAD
│   ├── stt/             # Speech-to-text engine
│   ├── intent/          # Intent extraction
│   ├── agentic/         # Question answering
│   ├── db/              # Database & CRUD
│   └── llm/             # LLM runtime
├── src/                 # React frontend (has build issues)
├── test-ui.html         # Working HTML interface
└── README.md

```

## API Endpoints

- `GET /health` - Health check
- `POST /session/start` - Start voice session
- `POST /session/stop` - Stop voice session
- `GET /tasks` - List all tasks
- `GET /meetings` - List all meetings
- `GET /reminders` - List all reminders
- `GET /history` - List session history
- `GET /models/status` - Check model status
- `WS /ws/status` - WebSocket for real-time updates

## Known Issues

1. **React UI not rendering** - Use test-ui.html instead
2. **Generic Whisper model** - Urdu accuracy ~60-70% (fine-tuned model needed)
3. **Low RAM mode** - First command takes 30-60 seconds to load LLM

## Development Status

### ✅ Completed
- FastAPI backend with all endpoints
- SQLite database with CRUD operations
- Speech-to-text with faster-whisper
- Intent extraction (LLM + rule-based fallback)
- Semantic routing (command vs question)
- Agentic question answering
- WebSocket real-time communication
- Audio capture with VAD
- Date normalization
- Notification service
- Working HTML interface

### ⚠️ Known Limitations
- React UI has Vite build issues (HTML interface works)
- Generic Whisper model (not fine-tuned for Urdu)
- LLM model file required for full functionality

## Testing

See `MANUAL_TESTING_GUIDE.md` for comprehensive testing procedures.

Quick test:
1. Start backend: `python sidecar/main.py`
2. Open `test-ui.html`
3. Click "Start Listening"
4. Say: "Create a task to test the system"
5. Click "View Tasks" to verify

## Troubleshooting

See `TROUBLESHOOTING.md` for detailed troubleshooting guide.

Common issues:
- **No tasks created**: Check Python terminal for routing (should be "Route: command")
- **Low accuracy**: Use more explicit command phrases
- **Slow first command**: Normal - loading 2GB LLM model

## License

MIT License

## Authors

Final Year Project 2026
