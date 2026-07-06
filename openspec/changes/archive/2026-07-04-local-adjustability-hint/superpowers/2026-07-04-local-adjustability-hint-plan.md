# Local-Adjustability Hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An evidence-gated session-start banner line that surfaces the existing `~/.claude/skill-config.json` override mechanism when the previous session's zero-match rate shows real routing friction.

**Architecture:** One guarded block in `hooks/session-start-hook.sh` at the banner-assembly point (next to the existing `_ZM_STAT` computation, ~L1206), consuming the already-computed `_PREV_ZM`/`_PREV_TOTAL`. Emits one `CONTEXT` line and touches a 7-day cooldown marker. Everything fail-open.

**Tech Stack:** Bash 3.2, jq (optional at the check site), existing `tests/test-registry.sh` harness (`setup_test_env` fake-HOME pattern).

## Global Constraints

- Bash 3.2: NO quoted operands in `$(( ))`; validate numerics with `[[ "$V" =~ ^[0-9]+$ ]] || V=0` before arithmetic; no associative arrays.
- Fail-open: every check `2>/dev/null` + `|| true`/default; any failure suppresses the hint, never breaks the banner. No `set -e` (file already avoids it).
- Session-start budget ~200ms: at most one jq fork and one `find` fork on the eligibility path, and only after the cheap numeric checks pass.
- Thresholds (exact, from the spec): `_PREV_ZM >= 5`, `_PREV_TOTAL >= 8`, rate `>= 30%` (integer: `_PREV_ZM * 100 / _PREV_TOTAL >= 30`). Cooldown: 7 days.
- Cooldown marker: `~/.claude/.skill-adjustability-hint-last` (bare touch-file, mtime is the datum, not token-scoped).
- Suppression on existing overrides: `jq -e '.skills | type == "object" and length > 0' "$HOME/.claude/skill-config.json"` succeeds → suppress. jq missing, file missing, or jq error → NOT suppressed (still eligible).
- Targeted edits only. Commit format `<type>: <description>`.

## Acceptance scenarios (from `openspec/changes/local-adjustability-hint/specs/skill-routing/spec.md`)

1. 5/10 zero-matches, no cooldown, no overrides → banner contains one routing-hint line naming 5, 10, and the rate; cooldown marker exists afterwards.
2. 5/50 (10%) → no hint line.
3. Qualifying evidence + per-skill overrides present → no hint line.
4. Qualifying evidence + cooldown marker <7 days old → no hint line, marker mtime unchanged.

---

### Task 1: Hint block + tests (single task — one deliverable, one test cycle)

**Files:**
- Modify: `hooks/session-start-hook.sh` (insert one block immediately after the `_ZM_STAT` assignment, currently ~L1206-1209)
- Test: `tests/test-registry.sh` (append a new test function + call, following the file's `run_test_*` / inline-echo conventions — read the file's existing structure around line 549 first and mirror it)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Added`)

**Interfaces:**
- Consumes: `_PREV_ZM`, `_PREV_TOTAL` (validated-numeric ints computed at ~L113-124; variables survive the state-file cleanup), `CONTEXT` accumulation variable, `HOME`.
- Produces: one optional `CONTEXT` line prefixed `Routing hint:`; marker file `~/.claude/.skill-adjustability-hint-last`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test-registry.sh` (mirror the serena auto-register test's structure: `setup_test_env`, then invoke the hook with `< /dev/null`, capture stdout, assert on it; use the file's existing PASS/FAIL echo + `TESTS_PASSED`/`TESTS_FAILED` counters if that's its convention — read first and match exactly). Test helper for the group:

```bash
# --- local-adjustability hint ---------------------------------------------
# The hint consumes the PREVIOUS session's zero-match counters, so each case
# seeds ~/.claude/.skill-zero-match-count and one .skill-prompt-count-* file
# in the fake HOME before invoking session-start.

_run_session_start_for_hint() {
    # $1 = zero-match count, $2 = total prompts; extra env via caller
    printf '%s' "$1" > "${HOME}/.claude/.skill-zero-match-count"
    printf '%s' "$2" > "${HOME}/.claude/.skill-prompt-count-session-hinttest"
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null < /dev/null
}

echo "-- test: adjustability hint fires at 5/10 and touches cooldown --"
setup_test_env
mkdir -p "${HOME}/.claude"
output="$(_run_session_start_for_hint 5 10)"
if printf '%s' "${output}" | grep -q "Routing hint:.*5 of 10.*skill-config.json"; then
    echo "  PASS: hint line present with counts"; TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL: expected hint line with 5 of 10"; TESTS_FAILED=$((TESTS_FAILED + 1))
fi
if [ -f "${HOME}/.claude/.skill-adjustability-hint-last" ]; then
    echo "  PASS: cooldown marker touched"; TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL: cooldown marker missing"; TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

echo "-- test: adjustability hint suppressed at 10% rate (chatty session) --"
setup_test_env
mkdir -p "${HOME}/.claude"
output="$(_run_session_start_for_hint 5 50)"
if printf '%s' "${output}" | grep -q "Routing hint:"; then
    echo "  FAIL: hint fired at 10% rate"; TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "  PASS: no hint at 10% rate"; TESTS_PASSED=$((TESTS_PASSED + 1))
fi
teardown_test_env

echo "-- test: adjustability hint suppressed below count floor (4/8) --"
setup_test_env
mkdir -p "${HOME}/.claude"
output="$(_run_session_start_for_hint 4 8)"
if printf '%s' "${output}" | grep -q "Routing hint:"; then
    echo "  FAIL: hint fired below ZM floor"; TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "  PASS: no hint below ZM floor"; TESTS_PASSED=$((TESTS_PASSED + 1))
fi
teardown_test_env

echo "-- test: adjustability hint suppressed below total floor (5/7) --"
setup_test_env
mkdir -p "${HOME}/.claude"
output="$(_run_session_start_for_hint 5 7)"
if printf '%s' "${output}" | grep -q "Routing hint:"; then
    echo "  FAIL: hint fired below total floor"; TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "  PASS: no hint below total floor"; TESTS_PASSED=$((TESTS_PASSED + 1))
fi
teardown_test_env

echo "-- test: adjustability hint suppressed by fresh cooldown, mtime unchanged --"
setup_test_env
mkdir -p "${HOME}/.claude"
touch "${HOME}/.claude/.skill-adjustability-hint-last"
_marker_before="$(ls -l "${HOME}/.claude/.skill-adjustability-hint-last")"
output="$(_run_session_start_for_hint 5 10)"
_marker_after="$(ls -l "${HOME}/.claude/.skill-adjustability-hint-last")"
if printf '%s' "${output}" | grep -q "Routing hint:"; then
    echo "  FAIL: hint fired under fresh cooldown"; TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "  PASS: cooldown suppresses hint"; TESTS_PASSED=$((TESTS_PASSED + 1))
fi
if [ "${_marker_before}" = "${_marker_after}" ]; then
    echo "  PASS: marker mtime unchanged"; TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL: marker was re-touched under cooldown"; TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env

echo "-- test: adjustability hint suppressed by existing per-skill overrides --"
setup_test_env
mkdir -p "${HOME}/.claude"
printf '{"skills": {"incident-analysis": {"enabled": false}}}' > "${HOME}/.claude/skill-config.json"
output="$(_run_session_start_for_hint 5 10)"
if printf '%s' "${output}" | grep -q "Routing hint:"; then
    echo "  FAIL: hint fired despite existing overrides"; TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "  PASS: existing overrides suppress hint"; TESTS_PASSED=$((TESTS_PASSED + 1))
fi
teardown_test_env

echo "-- test: adjustability hint fail-open on malformed counter --"
setup_test_env
mkdir -p "${HOME}/.claude"
printf 'garbage' > "${HOME}/.claude/.skill-zero-match-count"
printf '10' > "${HOME}/.claude/.skill-prompt-count-session-hinttest"
output="$(CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null < /dev/null)"
exit_code=$?
if [ "${exit_code}" -eq 0 ] && ! printf '%s' "${output}" | grep -q "Routing hint:"; then
    echo "  PASS: malformed counter → no hint, exit 0"; TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL: malformed counter broke the hook or fired the hint"; TESTS_FAILED=$((TESTS_FAILED + 1))
fi
teardown_test_env
```

IMPORTANT adaptation notes for the implementer: (a) READ `tests/test-registry.sh` around lines 30-80 and 549-590 first — if the file wraps cases in `run_test_*()` functions with a `local` convention or uses a `teardown_test_env` that differs (or doesn't exist — check `tests/test-helpers.sh`), adapt these cases to the file's actual structure; the assertions and seeded values above are the contract, the scaffolding style is the file's. (b) If `setup_test_env` does not create `${HOME}/.claude`, keep the `mkdir -p`. (c) The empty fake HOME means the hook takes its jq-available path only if the fake env satisfies it — verify one existing session-start test passes in the same env and mirror whatever setup it needs (e.g. minimal `config/default-triggers.json` under `CLAUDE_PLUGIN_ROOT` — note the serena test passes `CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}"`, overriding setup_test_env's export; do the same so the real registry loads).

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-registry.sh < /dev/null 2>&1 | grep -A1 "adjustability"`
Expected: the fires-at-5/10 case FAILs (no hint line exists yet); suppression cases may vacuously pass — that is fine, the red signal is the firing case + marker case.

- [ ] **Step 3: Implement the hint block**

In `hooks/session-start-hook.sh`, immediately AFTER the existing `_ZM_STAT` block (`if [[ "$_PREV_TOTAL" -gt 10 ]] && [[ "$_PREV_ZM" -gt 0 ]] ... fi`), insert:

```bash
# --- Local-adjustability hint (evidence-gated, fail-open) -------------------
# Surfaces the skill-config.json override mechanism when the PREVIOUS session
# showed real routing friction. Rate-based (not raw count) so long
# conversational sessions do not false-fire. Suppressed by a 7-day cooldown
# marker and by existing per-skill overrides (user already knows the
# mechanism). Every failure suppresses the hint; the banner is never broken.
_ADJ_HINT=""
_ADJ_MARKER="${HOME}/.claude/.skill-adjustability-hint-last"
if [[ "$_PREV_ZM" -ge 5 ]] && [[ "$_PREV_TOTAL" -ge 8 ]] \
   && [[ $(( _PREV_ZM * 100 / _PREV_TOTAL )) -ge 30 ]]; then
    _adj_eligible=1
    # Cooldown: marker younger than 7 days suppresses. find prints the path
    # only when mtime is >= 7 days ago; existing-but-fresh => suppress.
    if [[ -e "$_ADJ_MARKER" ]]; then
        _adj_aged="$(find "$_ADJ_MARKER" -mtime +6 -print 2>/dev/null || true)"
        [[ -n "$_adj_aged" ]] || _adj_eligible=0
    fi
    # Existing per-skill overrides: user already found the mechanism.
    if [[ "$_adj_eligible" -eq 1 ]] && command -v jq >/dev/null 2>&1 \
       && [[ -f "${HOME}/.claude/skill-config.json" ]]; then
        if jq -e '.skills | type == "object" and length > 0' \
             "${HOME}/.claude/skill-config.json" >/dev/null 2>&1; then
            _adj_eligible=0
        fi
    fi
    if [[ "$_adj_eligible" -eq 1 ]]; then
        _adj_rate=$(( _PREV_ZM * 100 / _PREV_TOTAL ))
        _ADJ_HINT="Routing hint: last session ${_PREV_ZM} of ${_PREV_TOTAL} prompts matched no skill (${_adj_rate}%). Tune triggers locally via ~/.claude/skill-config.json (missed prompts: ~/.claude/.skill-zero-match-log; debug a prompt with SKILL_EXPLAIN=1)."
        touch "$_ADJ_MARKER" 2>/dev/null || true
    fi
fi
```

Then, where `CONTEXT` has been assembled (after the `_CAP_LINE` append is a natural spot — keep it adjacent to other optional lines), append:

```bash
if [ -n "${_ADJ_HINT}" ]; then
    CONTEXT="${CONTEXT}
${_ADJ_HINT}"
fi
```

Note: `_PREV_ZM`/`_PREV_TOTAL` are already validated-numeric by the existing block at ~L113-124, so the arithmetic is safe under Bash 3.2; do not re-quote operands inside `$(( ))`.

- [ ] **Step 4: Syntax-check and run tests to green**

Run: `/bin/bash -n hooks/session-start-hook.sh && bash tests/test-registry.sh < /dev/null 2>&1 | tail -6`
Expected: `-n` clean; registry suite fully green including the 7 new hint cases (9 asserts).

- [ ] **Step 5: Full suite**

Run: `bash tests/run-tests.sh < /dev/null 2>&1 | tail -4` (stdin MUST be /dev/null — the suite blocks forever on a live-socket stdin)
Expected: all files pass.

- [ ] **Step 6: CHANGELOG + commit**

Under `## [Unreleased]` → `### Added` in `CHANGELOG.md`:

```markdown
- Local-adjustability hint: evidence-gated session-start banner line surfacing `~/.claude/skill-config.json` overrides when the previous session's zero-match rate shows routing friction (≥5 misses, ≥8 prompts, ≥30%; 7-day cooldown; suppressed for users with existing overrides; fail-open).
```

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh CHANGELOG.md
git commit -m "feat: evidence-gated local-adjustability hint in session-start banner"
```

---

## Verification mapping (spec scenario → test)

| Spec scenario | Test |
|---|---|
| 5/10 fires + marker touched | fires-at-5/10 case (2 asserts) |
| 5/50 chatty → no hint | 10%-rate case |
| Existing overrides suppress | overrides case |
| Fresh cooldown suppresses, mtime unchanged | cooldown case (2 asserts) |
| Fail-open (spec requirement text) | malformed-counter case; floor cases cover threshold edges |
