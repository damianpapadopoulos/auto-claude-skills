# OpenSpec PreToolUse Guard — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a PreToolUse hook that warns when `git commit`/`git push` runs during SHIP phase without openspec-ship having produced artifacts.

**Architecture:** New `openspec-guard.sh` hook registered in hooks.json for PreToolUse/Bash events. Detects git commit/push, checks SHIP phase via signal file, verifies openspec artifacts (CLI path) or routing signal (fallback). Emits warning in additionalContext.

**Tech Stack:** Bash 3.2, jq (with fallback)

**Spec:** `docs/superpowers/specs/2026-03-15-openspec-guard-serena-hints-design.md`

---

## Chunk 1: All tasks

### Task 1: Create openspec-guard.sh

**Files:**
- Create: `hooks/openspec-guard.sh`

- [ ] **Step 1: Create the guard hook script**

```bash
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
    _PHASE="$(grep -o '"phase":"[^"]*"' "${_SIGNAL_FILE}" | sed 's/"phase":"//;s/"$//')" || true
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x hooks/openspec-guard.sh`

- [ ] **Step 3: Syntax-check**

Run: `bash -n hooks/openspec-guard.sh`
Expected: no output (clean parse)

- [ ] **Step 4: Commit**

```bash
git add hooks/openspec-guard.sh
git commit -m "feat: add openspec PreToolUse guard hook"
```

### Task 2: Register in hooks.json

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Add PreToolUse section to hooks.json**

Insert a new `"PreToolUse"` key after the `"UserPromptSubmit"` section (after line 36, before the `"PostToolUse"` section). The new section:

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
    ],
```

- [ ] **Step 2: Validate JSON**

Run: `jq empty hooks/hooks.json && echo "valid"`
Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: register openspec guard in hooks.json PreToolUse"
```

### Task 3: Update test-install.sh

**Files:**
- Modify: `tests/test-install.sh:117-127`

- [ ] **Step 1: Add openspec-guard.sh existence and reference assertions**

After the teammate-idle-guard.sh block (line 117), add:

```bash
# Test: hooks/openspec-guard.sh exists and is executable
assert_file_exists \
    "hooks/openspec-guard.sh exists" \
    "${PLUGIN_ROOT}/hooks/openspec-guard.sh"

if [ -x "${PLUGIN_ROOT}/hooks/openspec-guard.sh" ]; then
    _record_pass "hooks/openspec-guard.sh is executable"
else
    _record_fail "hooks/openspec-guard.sh is executable" \
        "file is not executable"
fi

# Verify hooks.json references openspec-guard.sh
assert_contains \
    "hooks.json references openspec-guard.sh" \
    "openspec-guard.sh" \
    "${HOOKS_CONTENT}"
```

- [ ] **Step 2: Add PreToolUse to the event loop**

Find the line:
```bash
for event in SessionStart UserPromptSubmit PostToolUse PreCompact Stop TeammateIdle; do
```

Replace with:
```bash
for event in SessionStart UserPromptSubmit PreToolUse PostToolUse PreCompact Stop TeammateIdle; do
```

- [ ] **Step 3: Run tests to verify**

Run: `bash tests/test-install.sh`
Expected: all tests pass, including new openspec-guard assertions

- [ ] **Step 4: Commit**

```bash
git add tests/test-install.sh
git commit -m "test: add openspec-guard installation assertions"
```

### Task 4: Run full test suite and verify

**Files:** (none modified — verification only)

- [ ] **Step 1: Syntax-check the guard**

Run: `bash -n hooks/openspec-guard.sh`
Expected: no output

- [ ] **Step 2: Run all tests**

Run: `bash tests/run-tests.sh`
Expected: all tests pass

- [ ] **Step 3: Test guard behavior (3 cases in one block)**

Run all three tests in a single shell invocation to share state:

```bash
_tok="test-guard-$$"
_ORIG_TOKEN=""
[ -f "${HOME}/.claude/.skill-session-token" ] && _ORIG_TOKEN="$(cat "${HOME}/.claude/.skill-session-token")"
printf '%s' "${_tok}" > "${HOME}/.claude/.skill-session-token"

# Test A: warning emitted in SHIP phase on git commit
printf '{"skill":"verification-before-completion","phase":"SHIP"}' > "${HOME}/.claude/.skill-last-invoked-${_tok}"
_out=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | bash hooks/openspec-guard.sh)
echo "${_out}" | grep -q "OPENSPEC GUARD" && echo "PASS: warning emitted" || echo "FAIL: no warning"

# Test B: silent outside SHIP phase
printf '{"skill":"brainstorming","phase":"DESIGN"}' > "${HOME}/.claude/.skill-last-invoked-${_tok}"
_out=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | bash hooks/openspec-guard.sh)
[ -z "${_out}" ] && echo "PASS: silent outside SHIP" || echo "FAIL: unexpected output"

# Test C: silent for non-git commands
printf '{"skill":"verification-before-completion","phase":"SHIP"}' > "${HOME}/.claude/.skill-last-invoked-${_tok}"
_out=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash hooks/openspec-guard.sh)
[ -z "${_out}" ] && echo "PASS: silent for non-git" || echo "FAIL: unexpected output"

# Cleanup
rm -f "${HOME}/.claude/.skill-last-invoked-${_tok}"
if [ -n "${_ORIG_TOKEN}" ]; then
    printf '%s' "${_ORIG_TOKEN}" > "${HOME}/.claude/.skill-session-token"
else
    rm -f "${HOME}/.claude/.skill-session-token"
fi
```

Expected: all three PASS
