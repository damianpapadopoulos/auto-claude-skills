# Cozempic Compaction Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-fire cozempic treat (prune) whenever Claude Code compaction triggers, and recover critical state after compaction completes.

**Architecture:** Two new shell scripts wired into hooks.json — `pre-compact-hook.sh` runs checkpoint + treat before compaction, `compact-recovery-hook.sh` re-injects team state after compaction via SessionStart/compact matcher. Fail-open: errors exit 0 silently.

**Tech Stack:** Bash scripts, cozempic CLI, Claude Code hooks system

---

### Task 1: Create pre-compact-hook.sh

**Files:**
- Create: `hooks/pre-compact-hook.sh`

**Step 1: Create the script**

```bash
#!/bin/bash
# pre-compact-hook.sh — Checkpoint team state and prune session before compaction
# Runs on both auto and manual compaction. Fail-open: errors exit 0.
#
# Called by Claude Code PreCompact hook. stdin receives JSON with:
#   session_id, transcript_path, trigger ("auto"|"manual"), cwd

set -o pipefail

# --- PATH discovery (same as cozempic-wrapper.sh) ---
if ! command -v cozempic >/dev/null 2>&1; then
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
fi

if ! command -v cozempic >/dev/null 2>&1; then
    exit 0  # cozempic not installed, fail-open
fi

# --- Read hook input ---
INPUT="$(cat)"
TRANSCRIPT_PATH="$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)"
TRIGGER="$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('trigger','unknown'))" 2>/dev/null)"

# --- Log compaction event (for future adaptive calibration) ---
LOG_FILE="$HOME/.claude/.compact-events.log"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    FILE_SIZE=$(stat -f%z "$TRANSCRIPT_PATH" 2>/dev/null || stat -c%s "$TRANSCRIPT_PATH" 2>/dev/null || echo "unknown")
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) trigger=$TRIGGER size_bytes=$FILE_SIZE path=$TRANSCRIPT_PATH" >> "$LOG_FILE" 2>/dev/null
fi

# --- Checkpoint team state ---
cozempic checkpoint 2>/dev/null

# --- Treat (prune) session in-place ---
cozempic treat current -rx standard --execute 2>/dev/null

exit 0
```

**Step 2: Make it executable**

Run: `chmod +x hooks/pre-compact-hook.sh`

**Step 3: Smoke test the script**

Run: `echo '{"session_id":"test","transcript_path":"/tmp/fake.jsonl","trigger":"manual"}' | bash hooks/pre-compact-hook.sh; echo "exit: $?"`
Expected: exit 0 (even with no real session — fail-open)

**Step 4: Commit**

```bash
git add hooks/pre-compact-hook.sh
git commit -m "feat: add pre-compact hook for cozempic treat on compaction"
```

---

### Task 2: Create compact-recovery-hook.sh

**Files:**
- Create: `hooks/compact-recovery-hook.sh`

**Step 1: Create the script**

```bash
#!/bin/bash
# compact-recovery-hook.sh — Re-inject critical state after compaction
# Runs as SessionStart hook with matcher "compact".
# stdout is injected into Claude's fresh context.

# --- PATH discovery ---
if ! command -v cozempic >/dev/null 2>&1; then
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
fi

# --- Re-inject team checkpoint if it exists ---
CHECKPOINT=".claude/team-checkpoint.md"
if [ -f "$CHECKPOINT" ]; then
    echo "=== Team State Recovery (from pre-compaction checkpoint) ==="
    cat "$CHECKPOINT"
    echo ""
    echo "=== End Team State Recovery ==="
fi

# --- Log post-compaction event ---
INPUT="$(cat)"
TRANSCRIPT_PATH="$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)"
LOG_FILE="$HOME/.claude/.compact-events.log"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    FILE_SIZE=$(stat -f%z "$TRANSCRIPT_PATH" 2>/dev/null || stat -c%s "$TRANSCRIPT_PATH" 2>/dev/null || echo "unknown")
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) event=post_compact size_bytes=$FILE_SIZE path=$TRANSCRIPT_PATH" >> "$LOG_FILE" 2>/dev/null
fi

exit 0
```

**Step 2: Make it executable**

Run: `chmod +x hooks/compact-recovery-hook.sh`

**Step 3: Smoke test**

Run: `mkdir -p .claude && echo "# Test checkpoint" > .claude/team-checkpoint.md && echo '{}' | bash hooks/compact-recovery-hook.sh && rm .claude/team-checkpoint.md`
Expected: Outputs "=== Team State Recovery ===" with checkpoint content

**Step 4: Commit**

```bash
git add hooks/compact-recovery-hook.sh
git commit -m "feat: add post-compaction recovery hook for team state re-injection"
```

---

### Task 3: Wire hooks into hooks.json

**Files:**
- Modify: `hooks/hooks.json:49-57` (PreCompact section)
- Modify: `hooks/hooks.json:3-17` (SessionStart section — add compact matcher)

**Step 1: Update PreCompact hook**

Replace the PreCompact section (lines 49-58):

```json
"PreCompact": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-compact-hook.sh"
      }
    ]
  }
],
```

**Step 2: Add SessionStart/compact entry**

Add a new entry to the SessionStart array (after the existing entry):

```json
"SessionStart": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start-hook.sh",
        "timeout": 10
      },
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/cozempic-wrapper.sh guard --daemon"
      }
    ]
  },
  {
    "matcher": "compact",
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/compact-recovery-hook.sh"
      }
    ]
  }
],
```

**Step 3: Validate JSON**

Run: `python3 -m json.tool hooks/hooks.json > /dev/null && echo "valid" || echo "invalid"`
Expected: `valid`

**Step 4: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: wire pre-compact treat and post-compact recovery hooks"
```
