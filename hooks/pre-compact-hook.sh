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
