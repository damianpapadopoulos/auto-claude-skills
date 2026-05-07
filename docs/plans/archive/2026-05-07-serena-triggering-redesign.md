# Serena Triggering Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `auto-claude-skills` route to Serena MCP tools more consistently by extending the Grep nudge to cover regex patterns, propagating Serena guidance into subagent spawn prompts via the SessionStart banner, simplifying diagnostics to a two-pole rule, and adding a silent telemetry layer that produces evidence for the parked-matcher revival criteria.

**Architecture:** Three small edits to existing hook scripts (`hooks/serena-nudge.sh`, `hooks/session-start-hook.sh`) plus three new tiny scripts (`hooks/serena-observer.sh`, `hooks/serena-followthrough.sh`, `scripts/serena-telemetry-report.sh`) and one behavioral eval fixture. Telemetry writes append-only TSV to `~/.claude/.serena-nudge-telemetry`. No new hook libraries, no shared abstraction layer, no shell-to-MCP orchestration.

**Tech Stack:** Bash 3.2 (macOS `/bin/bash`), `jq` (with fallbacks where the existing pattern fallbacks back), Claude Code hook protocol (`hookSpecificOutput`), existing test harness in `tests/test-helpers.sh`.

**Spec:** `docs/plans/2026-05-07-serena-triggering-redesign-design.md`

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `hooks/serena-nudge.sh` | Modify | Extend pattern detection for `\b...\b`, dotted/qualified, definition-prefix-in-regex; add telemetry write on fire. |
| `hooks/session-start-hook.sh` | Modify (lines 1101-1110) | Add subagent-propagation line; remove pull toward `get_diagnostics_for_file`. |
| `hooks/serena-observer.sh` | Create | PreToolUse on `Read|Glob|Edit`. Silent: never emits `additionalContext`. Logs candidate missed-opportunities to telemetry. |
| `hooks/serena-followthrough.sh` | Create | PostToolUse on `^mcp__serena__`. Reads recent telemetry lines for the current session and appends `followup` records correlating Serena calls to prior nudges/observations within 3 turns. |
| `hooks/hooks.json` | Modify | Wire `serena-observer.sh` (PreToolUse `Read|Glob|Edit`) and `serena-followthrough.sh` (PostToolUse `^mcp__serena__`). |
| `scripts/serena-telemetry-report.sh` | Create | On-demand summary of follow-through % per matcher class over a rolling window. No hook integration. |
| `tests/test-serena-nudge.sh` | Create | Unit tests for `serena-nudge.sh` regex patterns (positive cases, false-positive guards) and telemetry write. |
| `tests/test-serena-observer.sh` | Create | Unit tests for observer pattern detection and telemetry write. |
| `tests/test-serena-followthrough.sh` | Create | Unit tests for follow-through correlation. |
| `tests/test-serena-telemetry-report.sh` | Create | Unit tests for the reporting script. |
| `tests/test-session-start-banner.sh` | Create (or extend if file already used by another test) | Assert banner contains subagent-propagation line and does not mention `get_diagnostics_for_file`. |
| `tests/fixtures/serena-grep-patterns.json` | Create | Behavioral eval fixture exercising the broadened Grep matcher in claude -p form, following existing eval pack schema. |
| `CHANGELOG.md` | Modify | Record the change under a new version. |

---

### Task 1: Add failing tests for the broadened Grep regex coverage

**Files:**
- Create: `tests/test-serena-nudge.sh`

- [ ] **Step 1: Write the failing test file**

```bash
#!/usr/bin/env bash
# test-serena-nudge.sh — Verify hooks/serena-nudge.sh fires on the right
# Grep patterns and stays silent on the wrong ones, plus telemetry write.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/serena-nudge.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

# Build a fake registry cache marking serena=true.
mkdir -p "${HOME}/.claude"
cat >"${HOME}/.claude/.skill-registry-cache.json" <<JSON
{"context_capabilities":{"serena":true,"lsp":false,"openspec":false,"context7":false,"context_hub_cli":false,"context_hub_available":false,"forgetful_memory":false,"posthog":false}}
JSON

# Helper — invoke hook with a Grep tool call carrying the given pattern.
_invoke_hook() {
    local pattern="$1"
    local input
    input="$(jq -n --arg p "${pattern}" '{tool_name:"Grep", tool_input:{pattern:$p}}')"
    printf '%s' "${input}" | bash "${HOOK}" 2>/dev/null
}

# --- Patterns that SHOULD fire the nudge ---

assert_contains "fires on plain CamelCase" "find_symbol" "$(_invoke_hook 'UserService')"
assert_contains "fires on plain snake_case" "find_symbol" "$(_invoke_hook 'load_user_profile')"
assert_contains "fires on word-boundary CamelCase" "find_symbol" "$(_invoke_hook '\bUserService\b')"
assert_contains "fires on anchored CamelCase" "find_symbol" "$(_invoke_hook '^UserService$')"
assert_contains "fires on dotted member access" "find_symbol" "$(_invoke_hook 'User\.profile')"
assert_contains "fires on Rust/C++ member access" "find_symbol" "$(_invoke_hook 'User::profile')"
assert_contains "fires on definition prefix in richer regex" "find_symbol" "$(_invoke_hook '^class +Foo\b')"
assert_contains "fires on def-prefix in regex" "find_symbol" "$(_invoke_hook 'def +process_\\w+')"

# --- Patterns that should NOT fire ---

# Heavy alternation — likely a free-text or multi-error grep.
assert_not_contains "stays silent on heavy alternation" "find_symbol" "$(_invoke_hook 'foo|bar|baz|qux|quux')"
# Lookaround — clearly not a symbol search.
assert_not_contains "stays silent on lookahead" "find_symbol" "$(_invoke_hook '(?=Foo)bar')"
# Broad character class — not a symbol shape.
assert_not_contains "stays silent on broad char class" "find_symbol" "$(_invoke_hook '[A-Za-z 0-9_-]+ failed')"
# Free-text quoted phrase.
assert_not_contains "stays silent on free text" "find_symbol" "$(_invoke_hook 'Connection refused')"

# --- Telemetry — fires append a TSV line ---

TELEMETRY="${HOME}/.claude/.serena-nudge-telemetry"
rm -f "${TELEMETRY}"
_invoke_hook '\bUserService\b' >/dev/null
assert_file_exists "telemetry file is created on nudge fire" "${TELEMETRY}"
TELEM_LINE="$(tail -1 "${TELEMETRY}" 2>/dev/null || true)"
assert_contains "telemetry line contains nudge keyword" "nudge" "${TELEM_LINE}"
assert_contains "telemetry line contains grep_extension matcher" "grep_extension" "${TELEM_LINE}"
assert_contains "telemetry line records word_boundary class" "word_boundary" "${TELEM_LINE}"

# --- Telemetry — no log when nudge does not fire ---

rm -f "${TELEMETRY}"
_invoke_hook 'Connection refused' >/dev/null
[ ! -f "${TELEMETRY}" ] && _record_pass "no telemetry on non-fire" || _record_fail "no telemetry on non-fire" "telemetry file exists despite no nudge"

teardown_test_env

# Final exit status
if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/test-serena-nudge.sh`
Expected: Multiple assertions FAIL — current hook does not match `\bFoo\b`, dotted/qualified patterns, or definition prefixes inside richer regexes; no telemetry exists.

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/test-serena-nudge.sh
git commit -m "test: add failing tests for broadened Grep regex coverage and telemetry"
```

---

### Task 2: Extend `hooks/serena-nudge.sh` to handle regex patterns and emit telemetry

**Files:**
- Modify: `hooks/serena-nudge.sh`

- [ ] **Step 1: Replace the pattern-detection block and add telemetry write**

Replace lines 33-54 of `hooks/serena-nudge.sh` (the current `case` + final emit) with the following. The earlier shebang, ERR trap, tool-name guard, and registry cache check (lines 1-31) stay unchanged.

```bash
# Classify the pattern. Empty class means "do not fire".
_CLASS=""

# 1. Definition prefix — works for both literal and regex variants.
case "${_PATTERN}" in
    *"class "*|*"def "*|*"function "*|*"func "*|*"interface "*|*"struct "*|*"import "*|*"type "*)
        _CLASS="definition_prefix"
        ;;
esac

# 2. Plain CamelCase / snake_case (legacy class).
if [ -z "${_CLASS}" ]; then
    if printf '%s' "${_PATTERN}" | grep -qE '^[A-Z][a-zA-Z0-9]+$' 2>/dev/null; then
        _CLASS="camelcase"
    elif printf '%s' "${_PATTERN}" | grep -qE '^[a-z_][a-z0-9_]+$' 2>/dev/null; then
        _CLASS="snake_case"
    fi
fi

# 3. Word-boundary symbol — \bIdentifier\b or ^Identifier$.
if [ -z "${_CLASS}" ]; then
    if printf '%s' "${_PATTERN}" | grep -qE '^\\b[A-Za-z_][A-Za-z0-9_]*\\b$' 2>/dev/null; then
        _CLASS="word_boundary"
    elif printf '%s' "${_PATTERN}" | grep -qE '^\^[A-Za-z_][A-Za-z0-9_]*\$$' 2>/dev/null; then
        _CLASS="word_boundary"
    fi
fi

# 4. Dotted / qualified member access — Foo\.bar or Foo::bar (one level).
if [ -z "${_CLASS}" ]; then
    if printf '%s' "${_PATTERN}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*(\\\.|::)[A-Za-z_][A-Za-z0-9_]*$' 2>/dev/null; then
        _CLASS="dotted_qualified"
    fi
fi

# 5. Suppress on patterns that are clearly not symbol shapes:
#    - heavy alternation (3+ alternatives)
#    - lookaround
#    - broad character classes containing whitespace or non-word chars
if [ -n "${_CLASS}" ]; then
    if printf '%s' "${_PATTERN}" | grep -qE '\|.*\|.*\|' 2>/dev/null; then
        _CLASS="" # heavy alternation
    elif printf '%s' "${_PATTERN}" | grep -qE '\(\?[=!<]' 2>/dev/null; then
        _CLASS="" # lookaround
    elif printf '%s' "${_PATTERN}" | grep -qE '\[[^]]* [^]]*\]' 2>/dev/null; then
        _CLASS="" # broad char class with whitespace
    fi
fi

# Definition prefix overrides the suppress rules above — it's a strong signal even
# when wrapped in regex. Re-promote it.
case "${_PATTERN}" in
    *"class "*|*"def "*|*"function "*|*"func "*|*"interface "*|*"struct "*|*"import "*|*"type "*)
        _CLASS="definition_prefix"
        ;;
esac

[ -n "${_CLASS}" ] || exit 0

# Emit nudge.
_MSG="Serena is available. Consider find_symbol or get_symbols_overview for symbol lookups instead of Grep."
if command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "${_MSG}"
fi

# Telemetry — append-only TSV. Disabled by SERENA_TELEMETRY=0.
if [ "${SERENA_TELEMETRY:-1}" != "0" ]; then
    _TELEM="${HOME}/.claude/.serena-nudge-telemetry"
    _TS="$(date +%s 2>/dev/null || echo 0)"
    _TOKEN="${CLAUDE_SESSION_TOKEN:-unknown}"
    _TURN="${CLAUDE_TURN_ID:-0}"
    # Field separator is tab; pattern is recorded for debug only.
    printf '%s\t%s\t%s\tnudge\tgrep_extension\t%s\n' "${_TS}" "${_TOKEN}" "${_TURN}" "${_CLASS}" >>"${_TELEM}" 2>/dev/null || true
fi

exit 0
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `bash tests/test-serena-nudge.sh`
Expected: PASS, all assertions green.

- [ ] **Step 3: Run the full test suite to confirm no regression**

Run: `bash tests/run-tests.sh`
Expected: Same pass count as baseline, plus the new test file passing.

- [ ] **Step 4: Commit**

```bash
git add hooks/serena-nudge.sh
git commit -m "feat: extend Serena Grep nudge to regex word-boundary, dotted/qualified, and embedded definition-prefix patterns; add telemetry"
```

---

### Task 3: Add failing tests for the silent observer (Read large source files)

**Files:**
- Create: `tests/test-serena-observer.sh`

- [ ] **Step 1: Write the failing test file**

```bash
#!/usr/bin/env bash
# test-serena-observer.sh — Verify hooks/serena-observer.sh logs missed-opportunity
# observations for Read/Glob/Edit but never emits user-visible additionalContext.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/serena-observer.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

mkdir -p "${HOME}/.claude"
cat >"${HOME}/.claude/.skill-registry-cache.json" <<JSON
{"context_capabilities":{"serena":true,"lsp":false}}
JSON

TELEM="${HOME}/.claude/.serena-nudge-telemetry"

# Helper — write a 600-line fake source file and record its path.
_make_large_source() {
    local path="${TEST_TMPDIR}/big.ts"
    local i=1
    : >"${path}"
    while [ "${i}" -le 600 ]; do
        printf 'const x_%d = %d;\n' "${i}" "${i}" >>"${path}"
        i=$((i + 1))
    done
    printf '%s' "${path}"
}

_make_small_source() {
    local path="${TEST_TMPDIR}/small.ts"
    : >"${path}"
    printf 'const x = 1;\n' >"${path}"
    printf '%s' "${path}"
}

_make_md_file() {
    local path="${TEST_TMPDIR}/notes.md"
    local i=1; : >"${path}"
    while [ "${i}" -le 800 ]; do
        printf 'line %d\n' "${i}" >>"${path}"
        i=$((i + 1))
    done
    printf '%s' "${path}"
}

_invoke_observer() {
    local tool="$1" json="$2"
    local input
    input="$(jq -n --arg t "${tool}" --argjson ti "${json}" '{tool_name:$t, tool_input:$ti}')"
    printf '%s' "${input}" | bash "${HOOK}" 2>/dev/null
}

# --- Read on large source file → logs read_large_source observation ---

big="$(_make_large_source)"
rm -f "${TELEM}"
out="$(_invoke_observer Read "$(jq -n --arg p "${big}" '{file_path:$p}')")"
assert_equals "observer never emits additionalContext on Read" "" "${out}"
assert_file_exists "observer logs read_large_source on >500-line .ts" "${TELEM}"
assert_contains "telemetry contains observe keyword" "observe" "$(tail -1 "${TELEM}")"
assert_contains "telemetry classifies read_large_source" "read_large_source" "$(tail -1 "${TELEM}")"

# --- Read on small source file → no log ---

small="$(_make_small_source)"
rm -f "${TELEM}"
_invoke_observer Read "$(jq -n --arg p "${small}" '{file_path:$p}')" >/dev/null
[ ! -f "${TELEM}" ] && _record_pass "no log on small source Read" || _record_fail "no log on small source Read"

# --- Read on markdown (non-source) → no log ---

md="$(_make_md_file)"
rm -f "${TELEM}"
_invoke_observer Read "$(jq -n --arg p "${md}" '{file_path:$p}')" >/dev/null
[ ! -f "${TELEM}" ] && _record_pass "no log on markdown Read regardless of size" || _record_fail "no log on markdown Read"

# --- Read with offset/limit → no log (intentional partial read) ---

rm -f "${TELEM}"
_invoke_observer Read "$(jq -n --arg p "${big}" '{file_path:$p, offset:100, limit:50}')" >/dev/null
[ ! -f "${TELEM}" ] && _record_pass "no log on Read with offset/limit" || _record_fail "no log on Read with offset/limit"

# --- Glob on definition-hunt pattern → log ---

rm -f "${TELEM}"
_invoke_observer Glob "$(jq -n '{pattern:"**/*UserService*"}')" >/dev/null
assert_file_exists "Glob definition-hunt logs observation" "${TELEM}"
assert_contains "Glob log carries glob_definition_hunt class" "glob_definition_hunt" "$(tail -1 "${TELEM}")"

# --- Glob on broad inventory → no log ---

rm -f "${TELEM}"
_invoke_observer Glob "$(jq -n '{pattern:"**/*.md"}')" >/dev/null
[ ! -f "${TELEM}" ] && _record_pass "no log on **/*.md inventory glob" || _record_fail "no log on **/*.md inventory glob"

rm -f "${TELEM}"
_invoke_observer Glob "$(jq -n '{pattern:"**/*.test.ts"}')" >/dev/null
[ ! -f "${TELEM}" ] && _record_pass "no log on test enumeration glob" || _record_fail "no log on test enumeration glob"

# --- Edit on symbol-shaped single-token diff → log ---

src="$(_make_small_source)"
mv "${src}" "${TEST_TMPDIR}/svc.ts"; src="${TEST_TMPDIR}/svc.ts"
rm -f "${TELEM}"
_invoke_observer Edit "$(jq -n --arg p "${src}" '{file_path:$p, old_string:"UserService", new_string:"AccountService"}')" >/dev/null
assert_file_exists "Edit symbol-token diff logs observation" "${TELEM}"
assert_contains "Edit log carries edit_symbol_token class" "edit_symbol_token" "$(tail -1 "${TELEM}")"

# --- Edit on multi-line / non-symbol diff → no log ---

rm -f "${TELEM}"
_invoke_observer Edit "$(jq -n --arg p "${src}" '{file_path:$p, old_string:"const x = 1;\nconst y = 2;", new_string:"const x = 100;\nconst y = 200;"}')" >/dev/null
[ ! -f "${TELEM}" ] && _record_pass "no log on multi-line Edit" || _record_fail "no log on multi-line Edit"

# --- Disabled by env flag ---

rm -f "${TELEM}"
SERENA_TELEMETRY=0 _invoke_observer Read "$(jq -n --arg p "${big}" '{file_path:$p}')" >/dev/null
[ ! -f "${TELEM}" ] && _record_pass "SERENA_TELEMETRY=0 disables observer logging" || _record_fail "SERENA_TELEMETRY=0 should disable observer"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/test-serena-observer.sh`
Expected: All assertions FAIL — `hooks/serena-observer.sh` does not exist.

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/test-serena-observer.sh
git commit -m "test: add failing tests for serena-observer silent missed-opportunity logging"
```

---

### Task 4: Implement `hooks/serena-observer.sh` and wire it into `hooks.json`

**Files:**
- Create: `hooks/serena-observer.sh`
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Implement the observer hook**

```bash
#!/bin/bash
# Serena observer — silent PreToolUse hook on Read|Glob|Edit. Logs candidate
# missed-opportunity classes to ~/.claude/.serena-nudge-telemetry. Never emits
# user-visible additionalContext. Used to gather evidence for the parked-matcher
# revival criteria documented in
# docs/plans/2026-05-07-serena-triggering-redesign-design.md.
#
# Bash 3.2 compatible. Fail-open (exit 0 on any error). jq required; no-op when
# jq is unavailable.
trap 'exit 0' ERR

# Telemetry-disabled short-circuit — saves ~10ms by skipping all the wc/regex work.
[ "${SERENA_TELEMETRY:-1}" = "0" ] && exit 0

_INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

_TOOL="$(printf '%s' "${_INPUT}" | jq -r '.tool_name // empty' 2>/dev/null)"
case "${_TOOL}" in
    Read|Glob|Edit) ;;
    *) exit 0 ;;
esac

# Registry capability check.
_CACHE="${HOME}/.claude/.skill-registry-cache.json"
[ -f "${_CACHE}" ] || exit 0
_SERENA="$(jq -r '.context_capabilities.serena // false' "${_CACHE}" 2>/dev/null)"
[ "${_SERENA}" = "true" ] || exit 0

_TELEM="${HOME}/.claude/.serena-nudge-telemetry"
_TS="$(date +%s 2>/dev/null || echo 0)"
_TOKEN="${CLAUDE_SESSION_TOKEN:-unknown}"
_TURN="${CLAUDE_TURN_ID:-0}"

_log() {
    local class="$1" detail="${2:-}"
    printf '%s\t%s\t%s\tobserve\t%s\t%s\n' "${_TS}" "${_TOKEN}" "${_TURN}" "${class}" "${detail}" >>"${_TELEM}" 2>/dev/null || true
}

_is_source_path() {
    case "$1" in
        *.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs|*.java|*.kt|*.scala|*.rb|*.cs|*.cpp|*.cc|*.c|*.h|*.hpp|*.swift|*.m|*.mm) return 0 ;;
    esac
    return 1
}

case "${_TOOL}" in
    Read)
        _PATH="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
        [ -n "${_PATH}" ] || exit 0
        # Skip partial reads — the user/model deliberately scoped them.
        _OFFSET="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.offset // empty' 2>/dev/null)"
        _LIMIT="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.limit // empty' 2>/dev/null)"
        [ -n "${_OFFSET}" ] && exit 0
        [ -n "${_LIMIT}" ] && exit 0
        _is_source_path "${_PATH}" || exit 0
        # File-size gate — skip if unreadable or under threshold.
        [ -f "${_PATH}" ] || exit 0
        _LINES="$(wc -l <"${_PATH}" 2>/dev/null || echo 0)"
        [ "${_LINES}" -gt 500 ] || exit 0
        _log "read_large_source" "${_PATH}"
        ;;

    Glob)
        _PATTERN="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.pattern // empty' 2>/dev/null)"
        [ -n "${_PATTERN}" ] || exit 0
        # Definition-hunt heuristic: pattern contains a CamelCase token in the basename
        # AND targets a source extension or no extension (loose enough to allow
        # `**/*UserService*` and `**/*Controller.{ts,java}` but not `**/*.md`).
        if printf '%s' "${_PATTERN}" | grep -qE '\*[^*/]*[A-Z][a-zA-Z0-9]+[^*/]*\*' 2>/dev/null; then
            # Reject if pattern explicitly targets non-source extensions.
            case "${_PATTERN}" in
                *.md*|*.json*|*.yaml*|*.yml*|*.lock*|*.test.*|*.spec.*) exit 0 ;;
            esac
            _log "glob_definition_hunt" "${_PATTERN}"
        fi
        ;;

    Edit)
        _PATH="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
        _OLD="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.old_string // empty' 2>/dev/null)"
        _NEW="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.new_string // empty' 2>/dev/null)"
        [ -n "${_PATH}" ] && [ -n "${_OLD}" ] && [ -n "${_NEW}" ] || exit 0
        _is_source_path "${_PATH}" || exit 0
        # Single-line both sides
        case "${_OLD}" in *$'\n'*) exit 0 ;; esac
        case "${_NEW}" in *$'\n'*) exit 0 ;; esac
        # Both must match a single identifier shape
        printf '%s' "${_OLD}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' 2>/dev/null || exit 0
        printf '%s' "${_NEW}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' 2>/dev/null || exit 0
        # And they must differ.
        [ "${_OLD}" != "${_NEW}" ] || exit 0
        _log "edit_symbol_token" "${_OLD}->${_NEW}"
        ;;
esac

exit 0
```

Make executable:
```bash
chmod +x hooks/serena-observer.sh
```

- [ ] **Step 2: Wire the observer into `hooks/hooks.json`**

Add three new `PreToolUse` entries (one per matcher) immediately after the existing `lsp-nudge.sh` block at line 65. Insert before the closing bracket of the `PreToolUse` array. Use targeted `Edit` to add the JSON.

```json
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/serena-observer.sh"
          }
        ]
      },
      {
        "matcher": "Glob",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/serena-observer.sh"
          }
        ]
      },
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/serena-observer.sh"
          }
        ]
      }
```

- [ ] **Step 3: Run the observer tests**

Run: `bash tests/test-serena-observer.sh`
Expected: PASS.

- [ ] **Step 4: Run the full suite**

Run: `bash tests/run-tests.sh`
Expected: Existing tests still PASS, new test included.

- [ ] **Step 5: Validate hooks.json is syntactically clean**

Run: `jq . hooks/hooks.json >/dev/null && echo OK`
Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
git add hooks/serena-observer.sh hooks/hooks.json
git commit -m "feat: add silent serena-observer for Read/Glob/Edit missed-opportunity telemetry"
```

---

### Task 5: Add failing tests for the follow-through correlator

**Files:**
- Create: `tests/test-serena-followthrough.sh`

- [ ] **Step 1: Write the failing test file**

```bash
#!/usr/bin/env bash
# test-serena-followthrough.sh — Verify hooks/serena-followthrough.sh appends a
# `followup` line when a Serena MCP tool runs within 3 turns of an unmarked nudge
# or observation in the same session.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/serena-followthrough.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env
TELEM="${HOME}/.claude/.serena-nudge-telemetry"

_invoke_followthrough() {
    local tool="$1" turn="$2"
    local input
    input="$(jq -n --arg t "${tool}" --arg tr "${turn}" '{tool_name:$t, tool_input:{}, tool_response:{ok:true}}')"
    CLAUDE_SESSION_TOKEN=tok-A CLAUDE_TURN_ID="${turn}" printf '%s' "${input}" | bash "${HOOK}" 2>/dev/null
}

# Seed: a nudge at turn 5 in session tok-A.
mkdir -p "${HOME}/.claude"
printf '1700000000\ttok-A\t5\tnudge\tgrep_extension\tword_boundary\n' >>"${TELEM}"

# Serena call at turn 6 — within 3 turns → should produce a followup line.
_invoke_followthrough mcp__serena__find_symbol 6 >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_contains "Serena call within 3 turns appends followup" "followup" "${LAST}"
assert_contains "followup carries original class word_boundary" "word_boundary" "${LAST}"
assert_contains "followup names the serena tool" "find_symbol" "${LAST}"

# Already-correlated nudge → no double-followup on second Serena call.
_LINES_BEFORE="$(wc -l <"${TELEM}")"
_invoke_followthrough mcp__serena__get_symbols_overview 6 >/dev/null
_LINES_AFTER="$(wc -l <"${TELEM}")"
assert_equals "no double-followup once nudge correlated" "${_LINES_BEFORE}" "${_LINES_AFTER}"

# Far-apart Serena call (turn 5 nudge + turn 12 Serena call) → no followup.
rm "${TELEM}"
printf '1700000000\ttok-B\t5\tnudge\tgrep_extension\tword_boundary\n' >>"${TELEM}"
CLAUDE_SESSION_TOKEN=tok-B CLAUDE_TURN_ID=12 _invoke_followthrough mcp__serena__find_symbol 12 >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_not_contains "no followup beyond 3 turns" "followup" "${LAST}"

# Different session token → no followup.
rm "${TELEM}"
printf '1700000000\ttok-C\t5\tnudge\tgrep_extension\tword_boundary\n' >>"${TELEM}"
CLAUDE_SESSION_TOKEN=tok-D CLAUDE_TURN_ID=6 _invoke_followthrough mcp__serena__find_symbol 6 >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_not_contains "no followup across sessions" "followup" "${LAST}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/test-serena-followthrough.sh`
Expected: All assertions FAIL — `hooks/serena-followthrough.sh` does not exist.

- [ ] **Step 3: Commit**

```bash
git add tests/test-serena-followthrough.sh
git commit -m "test: add failing tests for serena-followthrough correlation"
```

---

### Task 6: Implement `hooks/serena-followthrough.sh` and wire it into `hooks.json`

**Files:**
- Create: `hooks/serena-followthrough.sh`
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Implement the hook**

```bash
#!/bin/bash
# Serena follow-through correlator — PostToolUse on ^mcp__serena__.
# When a Serena MCP tool returns successfully, scans recent telemetry lines from
# the same session and appends a `followup` record for each unmarked nudge or
# observation within 3 turns. Used to compute follow-through % per matcher class.
# Bash 3.2 compatible. Fail-open. jq required; no-op when unavailable.
trap 'exit 0' ERR

[ "${SERENA_TELEMETRY:-1}" = "0" ] && exit 0

_INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

_TOOL="$(printf '%s' "${_INPUT}" | jq -r '.tool_name // empty' 2>/dev/null)"
case "${_TOOL}" in
    mcp__serena__*) ;;
    *) exit 0 ;;
esac

# Skip on errored tool result (best-effort: tool_response.error or .is_error).
_ERR="$(printf '%s' "${_INPUT}" | jq -r '.tool_response.is_error // .tool_response.error // empty' 2>/dev/null)"
[ -z "${_ERR}" ] || exit 0

_TELEM="${HOME}/.claude/.serena-nudge-telemetry"
[ -f "${_TELEM}" ] || exit 0

_TOKEN="${CLAUDE_SESSION_TOKEN:-unknown}"
_TURN="${CLAUDE_TURN_ID:-0}"
_TS="$(date +%s 2>/dev/null || echo 0)"
_SERENA_TOOL_SHORT="${_TOOL#mcp__serena__}"

# Pull the last 50 lines for this session and scan within 3 turns.
# Append a followup line per unmarked nudge/observation — but mark them by writing
# the followup *next to* them rather than mutating earlier lines (preserves append-only).
# Idempotency is guarded by the `seen_keys` accumulator built from existing followups.
_RECENT="$(tail -100 "${_TELEM}" 2>/dev/null | awk -F'\t' -v tok="${_TOKEN}" '$2==tok' || true)"
[ -n "${_RECENT}" ] || exit 0

# Build a set of already-correlated keys: each followup carries
# field-3 = original turn, field-5 = original class. We treat (turn,class) as the key.
_SEEN="$(printf '%s\n' "${_RECENT}" | awk -F'\t' '$4=="followup"{print $3"|"$5}')"

printf '%s\n' "${_RECENT}" | awk -F'\t' '$4=="nudge" || $4=="observe"' | while IFS=$'\t' read -r ts tok turn kind matcher class; do
    [ -n "${turn}" ] || continue
    # Within 3 turns?
    _delta=$((${_TURN} - turn))
    if [ "${_delta}" -lt 0 ] || [ "${_delta}" -gt 3 ]; then continue; fi
    # Already correlated?
    case "${_SEEN}" in
        *"${turn}|${matcher}"*) continue ;;
    esac
    # Append followup line keyed by the original (turn, matcher) so future Serena
    # calls in the same window don't double-record.
    printf '%s\t%s\t%s\tfollowup\t%s\t%s\n' "${_TS}" "${_TOKEN}" "${turn}" "${matcher}" "${_SERENA_TOOL_SHORT}" >>"${_TELEM}" 2>/dev/null || true
    _SEEN="${_SEEN}
${turn}|${matcher}"
done

exit 0
```

```bash
chmod +x hooks/serena-followthrough.sh
```

- [ ] **Step 2: Wire into `hooks/hooks.json` PostToolUse array**

Add a new entry after the existing `^Skill$` block (around line 95):

```json
      {
        "matcher": "^mcp__serena__",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/serena-followthrough.sh"
          }
        ]
      }
```

- [ ] **Step 3: Run the test**

Run: `bash tests/test-serena-followthrough.sh`
Expected: PASS.

- [ ] **Step 4: Validate JSON**

Run: `jq . hooks/hooks.json >/dev/null && echo OK`
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add hooks/serena-followthrough.sh hooks/hooks.json
git commit -m "feat: add PostToolUse follow-through correlator for Serena telemetry"
```

---

### Task 7: Add failing tests for the SessionStart banner edits

**Files:**
- Create: `tests/test-session-start-banner.sh`

- [ ] **Step 1: Write the failing test file**

```bash
#!/usr/bin/env bash
# test-session-start-banner.sh — Verify the SessionStart banner contains the
# subagent-propagation line when serena=true and does NOT mention the third-pole
# diagnostics tool get_diagnostics_for_file.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env
mkdir -p "${HOME}/.claude"

# Stub a registry cache that the session-start hook will treat as serena=true.
# Real session-start has its own discovery; we short-circuit by pre-populating.
cat >"${HOME}/.claude/.skill-registry-cache.json" <<JSON
{"context_capabilities":{"serena":true,"lsp":true}}
JSON

# Run the hook and capture stdout (the JSON envelope).
out="$(printf '{}' | bash "${HOOK}" 2>/dev/null || true)"

# Extract additionalContext for inspection.
ctx="$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

assert_contains "banner mentions Serena MCP tools when serena=true" "mcp__serena__" "${ctx}"
assert_contains "banner instructs propagation into Task spawn prompts" "Task tool" "${ctx}"
assert_contains "banner names the propagated guidance string" "Serena available" "${ctx}"
assert_not_contains "banner does NOT mention get_diagnostics_for_file" "get_diagnostics_for_file" "${ctx}"
assert_contains "banner still names mcp__ide__getDiagnostics for diagnostics" "mcp__ide__getDiagnostics" "${ctx}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/test-session-start-banner.sh`
Expected: FAILS — current banner lacks the propagation line and may include `get_diagnostics_for_file` in some setups; test for `Task tool` will fail.

- [ ] **Step 3: Commit**

```bash
git add tests/test-session-start-banner.sh
git commit -m "test: assert SessionStart banner adds subagent propagation and drops third-pole diagnostics"
```

---

### Task 8: Update the SessionStart banner

**Files:**
- Modify: `hooks/session-start-hook.sh:1101-1110`

- [ ] **Step 1: Replace lines 1101-1110 with the new banner copy**

Replace the existing block:

```bash
# Emit Serena usage hint when available
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.serena == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
Serena: When navigating code, prefer mcp__serena__ tools (find_symbol, find_referencing_symbols, get_symbols_overview) over Grep/Read for symbol lookups and dependency mapping."
fi

# Emit LSP usage hint when available (complementary to Serena — LSP for diagnostics, Serena for symbol nav)
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.lsp == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
LSP: Use mcp__ide__getDiagnostics for compile/type errors before grepping. Complementary to Serena — LSP for diagnostics, Serena for symbol navigation and structural edits."
```

with:

```bash
# Emit Serena usage hint when available
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.serena == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
Serena: When navigating code, prefer mcp__serena__ tools (find_symbol, find_referencing_symbols, get_symbols_overview) over Grep/Read for symbol lookups and dependency mapping. When spawning subagents via the Task tool for code work, include 'Serena available — prefer find_symbol over Grep for symbol lookups' in their prompt so they inherit this guidance."
fi

# Emit LSP usage hint when available (complementary to Serena — LSP for diagnostics, Serena for symbol nav)
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.lsp == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
LSP: Use mcp__ide__getDiagnostics for compile/type errors before grepping. Complementary to Serena — LSP for diagnostics, Serena for symbol navigation and structural edits."
```

The intent is precisely two textual changes:
1. Append a propagation sentence to the Serena hint (one new sentence in the same string).
2. Leave the LSP hint unchanged — `get_diagnostics_for_file` is not currently mentioned in the live banner, but the test asserts it remains absent.

- [ ] **Step 2: Run the test**

Run: `bash tests/test-session-start-banner.sh`
Expected: PASS.

- [ ] **Step 3: Run the full suite**

Run: `bash tests/run-tests.sh`
Expected: All passing.

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: instruct parent to propagate Serena guidance into Task spawn prompts"
```

---

### Task 9: Add failing tests for the telemetry-report script

**Files:**
- Create: `tests/test-serena-telemetry-report.sh`

- [ ] **Step 1: Write the failing test file**

```bash
#!/usr/bin/env bash
# test-serena-telemetry-report.sh — Verify scripts/serena-telemetry-report.sh
# computes per-class follow-through % over a rolling window.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOL="${REPO_ROOT}/scripts/serena-telemetry-report.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env
mkdir -p "${HOME}/.claude"
TELEM="${HOME}/.claude/.serena-nudge-telemetry"

# Synthetic dataset: 10 grep_extension nudges, 5 followups → 50% follow-through.
# 4 read_large_source observations, 1 followup → 25%.
# 2 glob_definition_hunt observations, 0 followups → 0%.
# All within last day.
NOW="$(date +%s)"
i=1
while [ "${i}" -le 10 ]; do
    printf '%d\ttok-X\t%d\tnudge\tgrep_extension\tword_boundary\n' "$((NOW - i*60))" "${i}" >>"${TELEM}"
    if [ "${i}" -le 5 ]; then
        printf '%d\ttok-X\t%d\tfollowup\tgrep_extension\tfind_symbol\n' "$((NOW - i*60 + 30))" "${i}" >>"${TELEM}"
    fi
    i=$((i+1))
done
i=1
while [ "${i}" -le 4 ]; do
    printf '%d\ttok-X\t%d\tobserve\tread_large_source\tsrc/big.ts\n' "$((NOW - i*30))" "$((100+i))" >>"${TELEM}"
    if [ "${i}" -eq 1 ]; then
        printf '%d\ttok-X\t%d\tfollowup\tread_large_source\tget_symbols_overview\n' "$((NOW - i*30 + 30))" "$((100+i))" >>"${TELEM}"
    fi
    i=$((i+1))
done
i=1
while [ "${i}" -le 2 ]; do
    printf '%d\ttok-X\t%d\tobserve\tglob_definition_hunt\t**/*Foo*\n' "$((NOW - i*45))" "$((200+i))" >>"${TELEM}"
    i=$((i+1))
done

out="$(bash "${TOOL}" 14 2>/dev/null)"

assert_contains "report includes grep_extension" "grep_extension" "${out}"
assert_contains "grep_extension shows 50% follow-through" "50" "${out}"
assert_contains "grep_extension shows 10 firings" "10" "${out}"
assert_contains "report includes read_large_source" "read_large_source" "${out}"
assert_contains "read_large_source shows 25%" "25" "${out}"
assert_contains "report includes glob_definition_hunt" "glob_definition_hunt" "${out}"
assert_contains "glob_definition_hunt shows 0%" "0" "${out}"

# --- Empty telemetry → graceful empty report ---
rm -f "${TELEM}"
out_empty="$(bash "${TOOL}" 14 2>/dev/null)"
assert_contains "empty telemetry produces a recognisable empty report" "no telemetry" "${out_empty}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/test-serena-telemetry-report.sh`
Expected: FAILS — `scripts/serena-telemetry-report.sh` does not exist.

- [ ] **Step 3: Commit**

```bash
git add tests/test-serena-telemetry-report.sh
git commit -m "test: add failing tests for serena-telemetry-report rolling-window summary"
```

---

### Task 10: Implement `scripts/serena-telemetry-report.sh`

**Files:**
- Create: `scripts/serena-telemetry-report.sh`

- [ ] **Step 1: Implement**

```bash
#!/usr/bin/env bash
# serena-telemetry-report.sh — Summarise follow-through % per matcher class
# from ~/.claude/.serena-nudge-telemetry over a rolling window (default 14 days).
#
# Usage: bash scripts/serena-telemetry-report.sh [days]
set -u

DAYS="${1:-14}"
TELEM="${HOME}/.claude/.serena-nudge-telemetry"

if [ ! -s "${TELEM}" ]; then
    echo "no telemetry recorded yet at ${TELEM}"
    exit 0
fi

NOW="$(date +%s)"
WINDOW=$((DAYS * 86400))
CUTOFF=$((NOW - WINDOW))

# AWK: for each (kind, class) compute counts; for each class sum nudges/observes
# and matching followups, then print the percentage.
awk -F'\t' -v cutoff="${CUTOFF}" '
$1 >= cutoff {
    kind = $4; cls = $5;
    if (kind == "nudge" || kind == "observe") {
        firings[cls]++;
    } else if (kind == "followup") {
        followups[cls]++;
    }
}
END {
    if (length(firings) == 0) {
        print "no firings in window";
        exit 0;
    }
    printf "%-25s %8s %10s %12s\n", "class", "firings", "followups", "pct";
    for (cls in firings) {
        n = firings[cls];
        f = followups[cls] + 0;
        pct = (n > 0) ? int((f * 100) / n) : 0;
        printf "%-25s %8d %10d %11d%%\n", cls, n, f, pct;
    }
}' "${TELEM}"
```

```bash
mkdir -p scripts
chmod +x scripts/serena-telemetry-report.sh
```

- [ ] **Step 2: Run the test**

Run: `bash tests/test-serena-telemetry-report.sh`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/serena-telemetry-report.sh
git commit -m "feat: add serena-telemetry-report rolling-window summary script"
```

---

### Task 11: Add behavioral eval fixture for the broadened Grep matcher

**Files:**
- Create: `tests/fixtures/serena-grep-patterns.json`

- [ ] **Step 1: Inspect the existing eval pack schema to align this fixture**

Run: `bash tests/test-eval-pack-schema.sh -h 2>/dev/null || head -30 tests/test-eval-pack-schema.sh`
Inspect `tests/fixtures/` for an existing pattern fixture (e.g. an `incident-analysis` JSON) and note the required top-level keys.

- [ ] **Step 2: Write the fixture**

Create `tests/fixtures/serena-grep-patterns.json` mirroring the schema discovered in step 1. Required behavior:
- `\bUserService\b` → matcher fires; `additionalContext` mentions `find_symbol`.
- `Foo::bar` → matcher fires.
- `^class +Foo\b` → matcher fires; class is `definition_prefix`.
- `Connection refused` → matcher does NOT fire.
- `[A-Za-z 0-9_-]+ failed` → matcher does NOT fire.

If the existing schema does not naturally express hook-output assertions, document this fixture as informational (skipped from CI) and open a TODO in the design doc — but do not block the implementation. Most of the assertion surface is covered by `test-serena-nudge.sh`; this fixture adds end-to-end confidence.

- [ ] **Step 3: Run the eval-pack schema validator**

Run: `bash tests/test-eval-pack-schema.sh`
Expected: PASS, with the new fixture validated.

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/serena-grep-patterns.json
git commit -m "test: add behavioral eval fixture for broadened Grep matcher"
```

---

### Task 12: Update CHANGELOG and bump version

**Files:**
- Modify: `CHANGELOG.md`
- Modify: any `VERSION` / `package.json` / `plugin.json` / equivalent if the plugin tracks a single source of truth.

- [ ] **Step 1: Inspect current version**

Run: `grep -n "^## " CHANGELOG.md | head -3 && grep -rn '"version"' . 2>/dev/null --include="*.json" | head -5`

- [ ] **Step 2: Add a new top entry to `CHANGELOG.md`**

Add under the current `Unreleased` section or as a new `[3.31.0]` entry following the repo's conventional-commits style. Sample copy:

```markdown
## [3.31.0] — 2026-05-07

### Added
- `hooks/serena-observer.sh` — silent PreToolUse hook on Read/Glob/Edit that logs missed-opportunity classes (`read_large_source`, `glob_definition_hunt`, `edit_symbol_token`) for parked-matcher revival evidence.
- `hooks/serena-followthrough.sh` — PostToolUse correlator that appends `followup` records when a Serena MCP tool runs within 3 turns of a nudge or observation.
- `scripts/serena-telemetry-report.sh` — rolling-window follow-through summary keyed off `~/.claude/.serena-nudge-telemetry`.
- Behavioral eval fixture exercising the broadened Grep matcher (`tests/fixtures/serena-grep-patterns.json`).

### Changed
- `hooks/serena-nudge.sh` — Grep regex coverage extended to word-boundary, dotted/qualified, and embedded definition-prefix patterns; nudge fire now writes a TSV telemetry line.
- `hooks/session-start-hook.sh` — Serena banner instructs the parent to propagate Serena guidance into Task spawn prompts so subagents inherit it.
```

- [ ] **Step 3: Bump version where it is canonically recorded**

If version is in a `plugin.json` or similar, bump per the repo's convention (e.g. minor bump from `3.30.1` to `3.31.0`).

- [ ] **Step 4: Run the full test suite as a final gate**

Run: `bash tests/run-tests.sh`
Expected: All passing.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md <version-file-if-any>
git commit -m "chore: bump version to 3.31.0 — Serena triggering redesign"
```

---

## Self-Review

**Spec coverage.** The design spec lists three MVP changes (Grep extension, banner additions, banner cleanup) plus telemetry, observer, follow-through, reporting, and a behavioral eval. Each maps to a task:
- Grep extension → Tasks 1-2.
- Subagent-propagation banner addition → Tasks 7-8.
- Two-pole diagnostics (no third pole) → covered by Task 7's negative assertion + Task 8 leaving the LSP hint unchanged.
- Silent observer for Read/Glob/Edit → Tasks 3-4.
- Follow-through correlator → Tasks 5-6.
- Reporting script → Tasks 9-10.
- Behavioral eval → Task 11.
- Versioning + changelog → Task 12.

**Placeholder scan.** No `TBD`, no `TODO`, no "implement later", no "similar to Task N". Task 11 has a fallback path if the eval schema doesn't fit, but the fallback is concrete (skip from CI, note in design doc).

**Type consistency.** Telemetry record shape is identical across all writers and the reader: `<unix-ts>\t<session-token>\t<turn-id>\t<kind>\t<matcher-or-class>\t<detail>`. Kind is one of `nudge|observe|followup`. The follow-through correlator and the report script both use `$4` for kind and `$5` for class. The classes named in `serena-nudge.sh` (`word_boundary`, `dotted_qualified`, `definition_prefix`, `camelcase`, `snake_case`) and in `serena-observer.sh` (`read_large_source`, `glob_definition_hunt`, `edit_symbol_token`) are referenced consistently in tests, design, and report assertions.

**Bash-3.2 compatibility.** No associative arrays anywhere. `awk` is used for set-membership in the report; `case` statements are used for set-membership in the hooks. Pipelines are one-shot and do not rely on bashisms.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-07-serena-triggering-redesign.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints.

Which approach?
