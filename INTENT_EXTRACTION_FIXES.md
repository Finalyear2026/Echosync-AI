# Intent Extraction Fixes

## Problems Identified

1. **LLM not loading**: 7GB RAM < 8GB threshold → LLM never loads → falls back to simple extractor
2. **Simple extractor patterns**: Only had English patterns, missing Urdu/Roman Urdu commands

## Fixes Applied

### 1. Lower RAM Threshold ✅
**File**: `sidecar/llm/runtime.py`

**Change**: Lowered RAM threshold from 8GB to 6GB

```python
RAM_THRESHOLD_BYTES = 6 * 1024 ** 3  # 6 GB (was 8 GB)
```

**Impact**: 
- Your 7GB system now qualifies for "high-RAM mode"
- LLM will load at startup for better intent extraction
- More accurate intent parsing with LLM-based extraction

### 2. Enhanced Simple Extractor Patterns ✅
**File**: `sidecar/intent/simple_extractor.py`

**Changes**: Added comprehensive Urdu/Roman Urdu patterns

#### Create Task Patterns (Added):
```python
# Urdu/Roman Urdu
r"task\s+bana(?:o)?\s+(.+)",           # task banao/bana
r"kaam\s+bana(?:o)?\s+(.+)",           # kaam banao/bana
r"task\s+add\s+kar(?:o)?\s+(.+)",      # task add karo
r"kaam\s+add\s+kar(?:o)?\s+(.+)",      # kaam add karo
r"task\s+likho\s+(.+)",                # task likho
r"bana\s+(?:do|dena)\s+task\s+(.+)",   # bana do task
r"add\s+kar(?:o)?\s+task\s+(.+)",      # add karo task
```

#### Schedule Meeting Patterns (Added):
```python
# Urdu/Roman Urdu
r"meeting\s+schedule\s+kar(?:o)?\s+(.+)",      # meeting schedule karo
r"meeting\s+fix\s+kar(?:o)?\s+(.+)",           # meeting fix karo
r"meeting\s+set\s+kar(?:o)?\s+(.+)",           # meeting set karo
r"mulaqat\s+(?:schedule|fix|set)\s+kar(?:o)?\s+(.+)",  # mulaqat schedule karo
r"schedule\s+kar(?:o)?\s+meeting\s+(.+)",      # schedule karo meeting
```

#### Set Reminder Patterns (Added):
```python
# Urdu/Roman Urdu
r"reminder\s+set\s+kar(?:o)?\s+(.+)",          # reminder set karo
r"reminder\s+laga(?:o)?\s+(.+)",               # reminder lagao
r"yaad\s+dila(?:o)?\s+(.+)",                   # yaad dilao
r"yaad\s+dihani\s+set\s+kar(?:o)?\s+(.+)",     # yaad dihani set karo
r"mujhe\s+yaad\s+dila(?:o)?\s+(.+)",           # mujhe yaad dilao
```

#### Date/Time Extraction (Added):
```python
# Urdu/Roman Urdu time expressions
r"kal",           # tomorrow
r"aaj",           # today
r"parson",        # day after tomorrow
r"subah",         # morning
r"sham",          # evening
r"raat",          # night
r"dophar",        # afternoon
r"\d+\s+baje",    # X o'clock
r"aglay\s+\w+",   # next (week/month)
```

## Testing Commands

### English Commands:
- "create a task to buy groceries"
- "schedule a meeting tomorrow at 2 PM"
- "remind me to call John"
- "set a reminder for tomorrow morning"

### Roman Urdu Commands:
- "task bana do report likhna hai"
- "kaam add karo email bhejni hai"
- "meeting schedule karo kal 3 baje"
- "reminder set karo subah 9 baje"
- "yaad dilao mujhe kal parson"

### Mixed Commands:
- "task banao buy groceries tomorrow"
- "meeting schedule karo with team at 2 PM"
- "reminder lagao kal morning"

## Expected Flow

1. **User speaks**: "task bana do report likhna hai"
2. **STT transcribes**: "task bana do report likhna hai"
3. **Semantic Router**: Classifies as "command" (matches keyword patterns)
4. **Intent Engine**: 
   - **Option A** (LLM available): Uses LLM with GBNF grammar for structured extraction
   - **Option B** (LLM unavailable): Falls back to simple extractor
5. **Simple Extractor**: Matches pattern `r"task\s+bana(?:o)?\s+(.+)"` → extracts "report likhna hai"
6. **Creates Intent**: `CreateTaskIntent(title="report likhna hai", priority="medium")`
7. **Executes**: Calls `crud.create_task()` → saves to database
8. **UI Updates**: Shows "Done: create_task"

## Verification

After restarting the sidecar, check the logs:

### Startup Logs (Should show):
```
LLMRuntime initialised. Total RAM: 7 GB. High-RAM mode: True.
startup_load() called. Total RAM: 7 GB. High-RAM mode: True.
Loading LLM model 'Llama-3.2-3B-Instruct-Q4_K_M.gguf'. Total RAM: 7168 MB.
LLM model loaded successfully.
```

### Command Execution Logs (Should show):
```
Route: command
Matched create_task: title='report likhna hai', due_at='None'
Simple extraction successful: create_task
Task created: report likhna hai
```

## Troubleshooting

### If LLM still doesn't load:
- Check if model file exists at: `%APPDATA%\EchoSync\models\Llama-3.2-3B-Instruct-Q4_K_M.gguf`
- If missing, the system will use simple extractor (which now has Urdu patterns)

### If intent extraction fails:
- Check terminal logs for "Route: command" (should appear)
- Check for "Matched create_task" or similar (from simple extractor)
- If neither appears, the pattern didn't match - share the exact transcript

### If task doesn't appear in UI:
- Click "Tasks" button in sidebar to refresh
- Check terminal for "Task created: ..." message
- Verify database is working: `GET http://127.0.0.1:8765/tasks`

## Performance Impact

- **LLM loading**: +30-60 seconds at startup (one-time cost)
- **Intent extraction with LLM**: ~200-500ms per command
- **Intent extraction with simple extractor**: ~1-5ms per command
- **Overall**: Better accuracy with LLM, faster with simple extractor

## Next Steps

1. Restart sidecar: `python sidecar/main.py`
2. Wait for "EchoSync sidecar ready" (may take 1-2 minutes with LLM loading)
3. Test with various commands (English + Urdu)
4. Check terminal logs for debugging
5. Verify tasks appear in UI sidebar
