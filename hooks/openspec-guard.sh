#!/bin/bash
# OpenSpec guard — warns on git commit/push if openspec-ship hasn't run
# PreToolUse hook. Bash 3.2 compatible. Exits 0 always (warning only, fail-open).

# Fail-open: any error → silent exit (never block the user)
trap 'exit 0' ERR

# Read tool input from stdin (PreToolUse provides JSON with tool_input)
_INPUT="$(cat)"

# Extract command — use jq if available, fall back to grep
_COMMAND=""
if command -v jq >/dev/null 2>&1; then
    _COMMAND="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null)" || true
else
    # Fallback: grep for command field (may miss commands with embedded quotes)
    _COMMAND="$(printf '%s' "${_INPUT}" | grep -o '"command" *: *"[^"]*"' | head -1 | sed 's/"command" *: *"//;s/"$//')" || true
fi

# Fast path: only care about git commit/push
case "${_COMMAND}" in
    *"git commit"*|*"git push"*) ;;
    *) exit 0 ;;
esac

# Check session token
_SESSION_TOKEN=""
[ -f "${HOME}/.claude/.skill-session-token" ] && \
    _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
[ -z "${_SESSION_TOKEN}" ] && exit 0

# Check if we're in SHIP phase (signal file is JSON: {"skill":"...","phase":"..."})
_SIGNAL_FILE="${HOME}/.claude/.skill-last-invoked-${_SESSION_TOKEN}"
[ -f "${_SIGNAL_FILE}" ] || exit 0
_PHASE=""
if command -v jq >/dev/null 2>&1; then
    _PHASE="$(jq -r '.phase // empty' "${_SIGNAL_FILE}" 2>/dev/null)" || true
else
    _PHASE="$(grep -o '"phase" *: *"[^"]*"' "${_SIGNAL_FILE}" | sed 's/"phase" *: *"//;s/"$//')" || true
fi
[ "${_PHASE}" = "SHIP" ] || exit 0

# Detection: has openspec-ship run?
if command -v openspec >/dev/null 2>&1; then
    # CLI available — check for actual artifacts
    _proj_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    if [ -d "${_proj_root}/openspec/changes" ]; then
        # Check for any non-empty subdirectory (a change set) — glob avoids fork
        for _d in "${_proj_root}/openspec/changes"/*/; do
            [ -d "${_d}" ] && exit 0
        done
    fi
else
    # No CLI — check routing signal for openspec-ship (best-effort: only detects if it was the LAST routed skill)
    if grep -q "openspec-ship" "${_SIGNAL_FILE}" 2>/dev/null; then
        exit 0
    fi
fi

# Neither check passed — emit warning via jq for safe JSON encoding (or printf fallback)
_MSG="OPENSPEC GUARD: openspec-ship has not run this session. As-built documentation will be lost if you commit now. Invoke Skill(auto-claude-skills:openspec-ship) first, or proceed if documentation is not needed for this change."
if command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "${_MSG}"
fi
exit 0
