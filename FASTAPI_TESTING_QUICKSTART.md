# FastAPI Testing Quick Start

## The Problem You're Facing

You're getting "method not allowed" errors because you need to use the correct HTTP method (GET vs POST) for each endpoint.

## How to Use FastAPI Docs Interface

**URL**: http://127.0.0.1:8765/docs

### Step-by-Step Instructions:

1. **Open the endpoint** - Click on the colored bar (e.g., "POST /session/start")
2. **Click "Try it out"** button (top right corner of the expanded section)
3. **Click "Execute"** button (big blue button)
4. **See the response** below in the "Response body" section

## Quick Test Sequence

### 1. Health Check ✅
- **Endpoint**: GET /health
- **Steps**: Click "GET /health" → "Try it out" → "Execute"
- **Expected Response**:
```json
{
  "status": "ok"
}
```

### 2. Check Tasks (Empty is Normal!) ✅
- **Endpoint**: GET /tasks
- **Steps**: Click "GET /tasks" → "Try it out" → "Execute"
- **Expected Response**:
```json
[]
```
- **Why empty?** You haven't created any tasks yet! This is correct.

### 3. Check Meetings ✅
- **Endpoint**: GET /meetings
- **Steps**: Click "GET /meetings" → "Try it out" → "Execute"
- **Expected Response**:
```json
[]
```

### 4. Check Reminders ✅
- **Endpoint**: GET /reminders
- **Steps**: Click "GET /reminders" → "Try it out" → "Execute"
- **Expected Response**:
```json
[]
```

### 5. Start Session ⚠️ (Takes 10-30 seconds!)
- **Endpoint**: POST /session/start
- **Steps**: Click "POST /session/start" → "Try it out" → "Execute"
- **Expected Response** (after waiting):
```json
{
  "status": "started"
}
```
OR if already started:
```json
{
  "status": "already_started"
}
```

**WARNING**: This loads AI models (Whisper STT, LLM) and will:
- Take 10-30 seconds to respond
- Use significant CPU/RAM
- Make your computer slow temporarily

### 6. Stop Session ✅
- **Endpoint**: POST /session/stop
- **Steps**: Click "POST /session/stop" → "Try it out" → "Execute"
- **Expected Response**:
```json
{
  "status": "stopped"
}
```

## Common Errors Explained

### "Method Not Allowed" (405 Error)
**Cause**: You're using GET when you should use POST (or vice versa)

**Solution**: Make sure you're clicking the correct endpoint:
- `/session/start` = **POST** (not GET)
- `/session/stop` = **POST** (not GET)
- `/tasks` = **GET** (not POST)

### Empty Arrays `[]`
**Cause**: Database is empty (no data created yet)

**Solution**: This is NORMAL! You need to:
1. Start a session
2. Speak voice commands to create tasks/meetings/reminders
3. Then check the endpoints again

OR use the test-ui.html file to manually create test data.

## What's Working vs Not Working

### ✅ Working (Backend)
- FastAPI server running on port 8765
- Health endpoint responding
- Database initialized
- All API endpoints defined correctly
- GET endpoints returning empty arrays (correct behavior)

### ❌ Not Working (Frontend)
- React UI not rendering (white screen)
- Vite dev server issue (JS files stuck in "Pending")
- Cannot test voice pipeline through UI

## Next Steps

### Option 1: Test Backend Only (Recommended for now)
1. Use FastAPI docs to test all GET endpoints
2. Try starting a session (be patient, takes 30 seconds)
3. Document what works and what doesn't
4. Skip frontend testing for now

### Option 2: Use test-ui.html
1. Open `echosync-desktop/test-ui.html` in browser
2. This bypasses Vite and directly calls the backend
3. Test basic functionality

### Option 3: Build Tauri App
1. Run `npm run tauri build` in `echosync-desktop/` directory
2. This creates a standalone .exe file
3. The built app might work even if dev server doesn't
4. Takes 5-10 minutes to build

### Option 4: Fix Frontend (More Complex)
1. Clear Vite cache: `Remove-Item -Recurse -Force node_modules/.vite`
2. Reinstall: `npm install`
3. Try again: `npm run dev`

## My Recommendation

Given your 1-day deadline:

1. **Test backend thoroughly** using FastAPI docs (15 minutes)
2. **Try test-ui.html** for basic UI testing (10 minutes)
3. **Try Tauri build** to get a working .exe (30 minutes)
4. **Document what works** and what needs fixing
5. **Focus on critical bugs** only

The backend is working perfectly - that's where all the AI logic lives. The frontend is just a UI wrapper.
