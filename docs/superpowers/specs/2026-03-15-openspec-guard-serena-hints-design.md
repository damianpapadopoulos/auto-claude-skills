# Design: OpenSpec PreToolUse Guard & Serena Usage Hints

**Date:** 2026-03-15
**Status:** Approved
**Scope:** Add a PreToolUse guard that warns when `git commit`/`git push` runs during SHIP phase without openspec-ship having run. Also documents the already-shipped Serena session hint.

## Problem

1. **OpenSpec-ship can be skipped.** The SHIP composition chain displays openspec-ship as `[NEXT]` after verification, but nothing prevents the model from committing without running it. As-built documentation is lost permanently.

2. **Serena tools were ignored.** The model saw `serena=true` but defaulted to Grep/Read. *(Already fixed: session-start hint and testing-and-debug phase doc updated in prior commit.)*

## Approach

- **OpenSpec:** Lightweight PreToolUse guard on Bash commands. Checks for actual artifacts when CLI is available, falls back to routing signal when not. Warning only — doesn't block.
- **Serena:** Hint-based nudge in session context. No guard needed — the downside of skipping Serena is suboptimal navigation, not lost data.

### Decision Log

- **Warning over blocking** — a hard block on `git commit` would frustrate users making non-feature commits. A warning lets the model self-correct. We use `additionalContext` rather than `permissionDecision: "ask"` because this is a model-level nudge, not a user-facing permission prompt — the user may not have context about openspec-ship.
- **Artifact check over signal check** when CLI available — the routing signal only proves openspec-ship was *suggested*, not *completed*. Checking `openspec/changes/` proves artifacts exist.
- **Signal fallback** when CLI unavailable — without the CLI, there's no standard artifact location. The routing signal is the best available proxy. Note: the signal file (`~/.claude/.skill-last-invoked-*`) only records the *most recent* routed skill, so if another skill was routed after openspec-ship, the check will miss it. This is an accepted limitation — the artifact check (CLI path) is the authoritative detection.

## Design

### 1. hooks/openspec-guard.sh — New PreToolUse hook

Runs on every `Bash` tool call. Fast path: checks if the command contains `git commit` or `git push`. If not, exits immediately (0 overhead for non-git commands).

```bash
#!/bin/bash
# OpenSpec guard — warns on git commit/push if openspec-ship hasn't run
# PreToolUse hook. Bash 3.2 compatible. Exits 0 always (warning only).
set -uo pipefail

# Read tool input from stdin (PreToolUse provides JSON with tool_input)
_INPUT="$(cat)"

# Extract command — use jq if available, fall back to grep
_COMMAND=""
if command -v jq >/dev/null 2>&1; then
    _COMMAND="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
else
    # Fallback: grep for command field (may miss commands with embedded quotes)
    _COMMAND="$(printf '%s' "${_INPUT}" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')"
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
    _PHASE="$(jq -r '.phase // empty' "${_SIGNAL_FILE}" 2>/dev/null)"
else
    _PHASE="$(grep -o '"phase":"[^"]*"' "${_SIGNAL_FILE}" | sed 's/"phase":"//;s/"$//')"
fi
[ "${_PHASE}" = "SHIP" ] || exit 0

# Detection: has openspec-ship run?
if command -v openspec >/dev/null 2>&1; then
    # CLI available — check for actual artifacts
    _proj_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    if [ -d "${_proj_root}/openspec/changes" ]; then
        # Check for any non-empty subdirectory (a change set)
        _has_changes=$(find "${_proj_root}/openspec/changes" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
        [ -n "${_has_changes}" ] && exit 0
    fi
else
    # No CLI — check routing signal for openspec-ship (best-effort: only detects if it was the LAST routed skill)
    if grep -q "openspec-ship" "${_SIGNAL_FILE}" 2>/dev/null; then
        exit 0
    fi
fi

# Neither check passed — emit warning
_MSG="OPENSPEC GUARD: openspec-ship has not run this session. As-built documentation will be lost if you commit now. Invoke Skill(auto-claude-skills:openspec-ship) first, or proceed if documentation is not needed for this change."
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "${_MSG}"
exit 0
```

**Performance:** Three fast checks (string match, file read, find) — well under 50ms budget.

### 2. hooks/hooks.json — Add PreToolUse section

Add a new `PreToolUse` key inside the existing `"hooks": { ... }` object, after the `UserPromptSubmit` section and before the `PostToolUse` section:

```json
"PreToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/openspec-guard.sh"
      }
    ]
  }
]
```

This is the first `PreToolUse` hook in the project. The `"Bash"` matcher ensures it only runs for Bash tool calls, not for Read/Edit/Grep etc.

### 3. Already shipped (prior commits)

- `hooks/session-start-hook.sh` — Serena usage hint when `serena=true`
- `skills/unified-context-stack/phases/testing-and-debug.md` — Internal Truth section with Serena conditional instructions

## Files Changed

| File | Change |
|------|--------|
| `hooks/openspec-guard.sh` | New — PreToolUse guard for git commit/push during SHIP |
| `hooks/hooks.json` | Add PreToolUse section with Bash matcher |

## What Does NOT Change

- `hooks/session-start-hook.sh` — already has signal cleanup and Serena hint
- `hooks/skill-activation-hook.sh` — routing logic unchanged
- `config/default-triggers.json` — trigger/composition metadata unchanged

## Testing

- `bash -n hooks/openspec-guard.sh` — syntax check
- `bash tests/run-tests.sh` — all existing tests pass
- `bash tests/test-install.sh` — verify hooks.json references openspec-guard.sh
- Manual: simulate git commit in SHIP phase without openspec artifacts → verify warning emits
- Manual: create openspec/changes/test-feature/ directory → verify no warning
- Manual: run git commit outside SHIP phase → verify no warning
