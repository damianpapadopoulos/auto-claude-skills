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

# --- Reset depth counter (fresh context after compaction) ---
_SESSION_TOKEN=""
[ -f "${HOME}/.claude/.skill-session-token" ] && _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
if [ -n "$_SESSION_TOKEN" ]; then
    printf '0' > "${HOME}/.claude/.skill-prompt-count-${_SESSION_TOKEN}" 2>/dev/null || true
fi

# --- Re-inject team checkpoint if it exists ---
CHECKPOINT="${HOME}/.claude/team-checkpoint.md"
if [ -f "$CHECKPOINT" ]; then
    echo "=== Team State Recovery (from pre-compaction checkpoint) ==="
    cat "$CHECKPOINT"
    echo ""
    echo "=== End Team State Recovery ==="
fi

# --- Log post-compaction event ---
INPUT="$(cat)"
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
LOG_FILE="$HOME/.claude/.compact-events.log"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    FILE_SIZE=$(stat -f%z "$TRANSCRIPT_PATH" 2>/dev/null || stat -c%s "$TRANSCRIPT_PATH" 2>/dev/null || echo "unknown")
    printf '%s event=post_compact size_bytes=%s path=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$FILE_SIZE" "$TRANSCRIPT_PATH" >> "$LOG_FILE" 2>/dev/null
fi

exit 0
