# EchoSync AI - Manual Testing Guide

## Prerequisites

Before testing, ensure both services are running:

1. **Sidecar Backend**: `python sidecar/main.py` (should be at http://127.0.0.1:8765)
2. **Frontend**: `npm run dev` (should be at http://localhost:1420 or 5173)

---

## Test 1: Health Check & Connectivity

### Backend Health
1. Open browser: `http://127.0.0.1:8765/health`
2. **Expected**: `{"status":"ok"}`
3. **Status**: ✅ Pass / ❌ Fail

### Frontend Connection
1. Open browser: `http://localhost:1420/` (or your port)
2. **Expected**: See "EchoSync AI" title, status bar showing "Connected"
3. **Status**: ✅ Pass / ❌ Fail

### WebSocket Connection
1. Check status bar in UI
2. **Expected**: Green dot with "Connected" text
3. **Status**: ✅ Pass / ❌ Fail

---

## Test 2: Database Initialization

### Check Database File
1. Look for `echosync.db` file in `sidecar/` directory
2. **Expected**: File exists after first run
3. **Status**: ✅ Pass / ❌ Fail

### Check Tables via API
1. Open: `http://127.0.0.1:8765/tasks`
2. **Expected**: `[]` (empty array) or list of tasks
3. **Status**: ✅ Pass / ❌ Fail

---

## Test 3: Voice Pipeline (Critical)

### Prerequisites
- Microphone connected and working
- Quiet environment for testing

### Test 3.1: Start Session
1. Click **"Start Listening"** button
2. **Expected**: 
   - Button changes to "Stop Listening" (red)
   - Status bar shows "Hearing..." with green pulse animation
3. **Status**: ✅ Pass / ❌ Fail

### Test 3.2: Partial Transcription (Live Preview)
1. While session is active, **speak clearly**: "Create a task"
2. **Expected**:
   - See partial text appearing in transcript preview area
   - Blue "Listening..." indicator visible
   - Text updates as you speak
3. **Status**: ✅ Pass / ❌ Fail

### Test 3.3: Final Transcription
1. Stop speaking and wait 1-2 seconds
2. **Expected**:
   - Status changes to "Transcribing..."
   - Partial text becomes finalized (white color)
   - Green "✓ Finalized" indicator appears
3. **Status**: ✅ Pass / ❌ Fail

### Test 3.4: Stop Session
1. Click **"Stop Listening"** button
2. **Expected**:
   - Button changes back to "Start Listening" (blue)
   - Status returns to "Ready"
3. **Status**: ✅ Pass / ❌ Fail

---

## Test 4: Command Processing (Intent Engine)

### Test 4.1: Create Task
1. Start session
2. **Say**: "Create a task to buy groceries tomorrow"
3. **Expected**:
   - Status shows "Extracting..."
   - Then shows "Done: create_task"
   - Returns to "Ready"
4. **Verify**: Open `http://127.0.0.1:8765/tasks`
   - Should see new task with title "buy groceries"
5. **Status**: ✅ Pass / ❌ Fail

### Test 4.2: Schedule Meeting
1. Start session
2. **Say**: "Schedule a meeting for tomorrow at 2 PM"
3. **Expected**:
   - Status shows "Extracting..."
   - Then shows "Done: schedule_meeting"
4. **Verify**: Open `http://127.0.0.1:8765/meetings`
   - Should see new meeting
5. **Status**: ✅ Pass / ❌ Fail

### Test 4.3: Set Reminder
1. Start session
2. **Say**: "Remind me to call John tomorrow at 10 AM"
3. **Expected**:
   - Status shows "Extracting..."
   - Then shows "Done: set_reminder"
4. **Verify**: Open `http://127.0.0.1:8765/reminders`
   - Should see new reminder
5. **Status**: ✅ Pass / ❌ Fail

---

## Test 5: Question Processing (Agentic Engine)

### Test 5.1: Simple Question
1. Start session
2. **Say**: "What tasks do I have?"
3. **Expected**:
   - Status shows "Thinking..."
   - Response appears in "Response" section
   - Should list your tasks or say "no tasks"
4. **Status**: ✅ Pass / ❌ Fail

### Test 5.2: Time-Based Question
1. Start session
2. **Say**: "Am I free tomorrow?"
3. **Expected**:
   - Status shows "Thinking..."
   - Response checks meetings and gives answer
4. **Status**: ✅ Pass / ❌ Fail

---

## Test 6: Multilingual Support (Urdu/English)

### Test 6.1: Urdu Script Detection
1. Start session
2. **Say in Urdu**: "ایک ٹاسک بنائیں" (Create a task)
3. **Expected**:
   - Transcript shows Urdu text
   - Text is right-aligned (RTL)
   - Urdu font is applied
4. **Status**: ✅ Pass / ❌ Fail

### Test 6.2: Mixed Language (Code-Switching)
1. Start session
2. **Say**: "Create a task kal ke liye" (tomorrow in Roman Urdu)
3. **Expected**:
   - Transcript shows mixed text
   - System processes the command
4. **Status**: ✅ Pass / ❌ Fail

---

## Test 7: Date Normalization

### Test 7.1: English Relative Dates
1. Create task: "tomorrow"
2. **Verify**: `http://127.0.0.1:8765/tasks`
   - `due_at` should be tomorrow's date in ISO 8601 format
3. **Status**: ✅ Pass / ❌ Fail

### Test 7.2: Urdu Relative Dates
1. Say: "kal" (tomorrow in Urdu)
2. **Verify**: Date is correctly parsed as tomorrow
3. **Status**: ✅ Pass / ❌ Fail

### Test 7.3: Specific Dates
1. Say: "next Monday"
2. **Verify**: Date is correctly calculated
3. **Status**: ✅ Pass / ❌ Fail

---

## Test 8: History View

### Test 8.1: View History
1. Click **"History"** tab
2. **Expected**:
   - See list of previous voice sessions
   - Each entry shows: intent type, transcript, timestamp
3. **Status**: ✅ Pass / ❌ Fail

### Test 8.2: RTL in History
1. Find an Urdu transcript in history
2. **Expected**:
   - Urdu text is right-aligned
   - Proper font rendering
3. **Status**: ✅ Pass / ❌ Fail

---

## Test 9: Error Handling

### Test 9.1: Empty Audio
1. Start session
2. Stay silent for 3-4 seconds
3. **Expected**:
   - No error
   - Returns to "Hearing..." state
4. **Status**: ✅ Pass / ❌ Fail

### Test 9.2: Unclear Command
1. Say something ambiguous: "um... maybe... I don't know"
2. **Expected**:
   - System attempts to process
   - Either routes to question or shows original transcript
   - No crash
3. **Status**: ✅ Pass / ❌ Fail

### Test 9.3: Backend Disconnect
1. Stop the Python sidecar (Ctrl+C)
2. **Expected**:
   - Frontend shows "Disconnected" (red dot)
   - Buttons become disabled
3. Restart sidecar
4. **Expected**:
   - Auto-reconnects within 2 seconds
   - Shows "Connected" again
5. **Status**: ✅ Pass / ❌ Fail

---

## Test 10: Performance & Responsiveness

### Test 10.1: Transcription Speed
1. Speak a 5-second sentence
2. **Measure**: Time from speech end to final transcript
3. **Expected**: < 3 seconds
4. **Status**: ✅ Pass / ❌ Fail

### Test 10.2: Intent Extraction Speed
1. Say a command
2. **Measure**: Time from transcript to "Done" message
3. **Expected**: < 2 seconds
4. **Status**: ✅ Pass / ❌ Fail

### Test 10.3: Question Response Speed
1. Ask a simple question
2. **Measure**: Time from transcript to response
3. **Expected**: < 10 seconds
4. **Status**: ✅ Pass / ❌ Fail

---

## Test 11: Model Downloader (First Run)

### Test 11.1: Missing Models Detection
1. Delete or rename model files (if any exist)
2. Restart sidecar
3. **Expected**:
   - Frontend shows "First-Run Setup" wizard
   - Lists missing model files
4. **Status**: ✅ Pass / ❌ Fail

### Test 11.2: Model Download (Optional)
1. Provide a valid model source path
2. Click "Download Models"
3. **Expected**:
   - Progress bars appear
   - Shows percentage for each file
4. **Status**: ✅ Pass / ❌ Fail / ⏭️ Skip

---

## Test 12: Notification Service (Reminders)

### Test 12.1: Reminder Polling
1. Create a reminder for 1 minute from now
2. Wait 1 minute
3. **Expected**:
   - Windows toast notification appears
   - Reminder status changes to "delivered"
4. **Verify**: `http://127.0.0.1:8765/reminders`
5. **Status**: ✅ Pass / ❌ Fail

---

## Test 13: Data Persistence

### Test 13.1: Restart Persistence
1. Create a task
2. Stop both sidecar and frontend
3. Restart both
4. **Expected**:
   - Task still exists in `http://127.0.0.1:8765/tasks`
5. **Status**: ✅ Pass / ❌ Fail

---

## Test 14: UI/UX Elements

### Test 14.1: Status Bar Animations
1. Start session
2. **Check**: Green pulse animation on microphone indicator
3. **Status**: ✅ Pass / ❌ Fail

### Test 14.2: Button States
1. **Check**: Buttons are disabled when disconnected
2. **Check**: Loading state shows "Please wait..."
3. **Status**: ✅ Pass / ❌ Fail

### Test 14.3: Responsive Layout
1. Resize browser window
2. **Expected**: UI adapts properly (max-width: 2xl)
3. **Status**: ✅ Pass / ❌ Fail

---

## Known Issues to Document

As you test, document any issues here:

### Issue 1: [Title]
- **Description**: 
- **Steps to Reproduce**: 
- **Expected**: 
- **Actual**: 
- **Severity**: Critical / High / Medium / Low

### Issue 2: [Title]
- **Description**: 
- **Steps to Reproduce**: 
- **Expected**: 
- **Actual**: 
- **Severity**: Critical / High / Medium / Low

---

## Critical Path Testing (Minimum Viable)

If time is limited, focus on these tests in order:

1. ✅ Test 1: Health Check & Connectivity
2. ✅ Test 3: Voice Pipeline (all sub-tests)
3. ✅ Test 4.1: Create Task
4. ✅ Test 5.1: Simple Question
5. ✅ Test 8.1: View History
6. ✅ Test 9.3: Backend Disconnect/Reconnect

---

## Testing Checklist Summary

- [ ] Backend health check passes
- [ ] Frontend loads and connects
- [ ] Voice session starts/stops
- [ ] Partial transcription works
- [ ] Final transcription works
- [ ] Task creation works
- [ ] Meeting scheduling works
- [ ] Reminder setting works
- [ ] Questions get answered
- [ ] Urdu text renders correctly (RTL)
- [ ] History view shows sessions
- [ ] Error handling is graceful
- [ ] Performance is acceptable
- [ ] Data persists after restart

---

## Next Steps After Testing

1. **Document all bugs** found during testing
2. **Prioritize fixes**: Critical → High → Medium → Low
3. **Fix critical bugs** first (anything that blocks core functionality)
4. **Re-test** after each fix
5. **Optional**: Write property tests for critical components

---

## Notes

- Test in a **quiet environment** for best voice recognition
- Use a **good quality microphone**
- **Speak clearly** and at normal pace
- Test with **both English and Urdu** if possible
- **Document everything** - screenshots help!

