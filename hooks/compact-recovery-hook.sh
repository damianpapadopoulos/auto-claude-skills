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
