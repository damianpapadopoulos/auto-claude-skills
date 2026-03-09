# Top 3 Next Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship three independently valuable features: (1) silence noise + false-positive defense, (2) zero-match diagnostics, (3) compaction-resilient composition state.

**Architecture:** All changes are in existing files. Feature 1 modifies `_format_output()` and `_build_skill_lines()` in the routing hook + adds negative tests. Feature 2 adds zero-match logging in the routing hook + rate display in session-start + extends `/skill-explain`. Feature 3 adds composition state writes in the routing hook + recovery reads in the compact-recovery hook.

**Tech Stack:** Bash 3.2 (macOS), jq, existing test harness (`test-helpers.sh`)

---

## Feature 1: Silence + False-Positive Defense

### Task 1.1: Silence zero-match output

**Files:**
- Modify: `hooks/skill-activation-hook.sh:705-716`
- Test: `tests/test-routing.sh` (append)

**Step 1: Write the failing test**

Append to `tests/test-routing.sh` before the `print_summary` line (line 2523):

```bash
# ---------------------------------------------------------------------------
# FALSE-POSITIVE DEFENSE: Zero-match silence and negative tests
# ---------------------------------------------------------------------------

test_zero_match_emits_nothing() {
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "rename this variable to snake_case")"
    ctx="$(extract_context "$output")"

    # Zero-match should produce empty additionalContext
    assert_equals "zero-match prompt should produce empty context" "" "$ctx"

    teardown_test_env
}
test_zero_match_emits_nothing
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>/dev/null | tail -20`
Expected: FAIL — currently zero-match emits a 40-token phase checkpoint

**Step 3: Write minimal implementation**

In `hooks/skill-activation-hook.sh`, replace lines 705-716 (the `TOTAL_COUNT -eq 0` branch in `_format_output()`) with:

```bash
  if [[ "$TOTAL_COUNT" -eq 0 ]]; then
    # Instrument zero-match rate
    _ZM_FILE="${HOME}/.claude/.skill-zero-match-count"
    _zm=0
    [[ -f "$_ZM_FILE" ]] && _zm="$(cat "$_ZM_FILE" 2>/dev/null)"
    [[ "$_zm" =~ ^[0-9]+$ ]] || _zm=0
    printf '%s' "$((_zm + 1))" > "$_ZM_FILE" 2>/dev/null || true

    # Silent exit — no additionalContext on zero match
    return
```

Note: the `return` exits `_format_output()` before the `printf` JSON at line 777. The hook continues to `_emit_explain` (line 1036) which still fires if `SKILL_EXPLAIN=1`.

**Step 4: Run test to verify it passes**

Run: `bash tests/test-routing.sh 2>/dev/null | tail -20`
Expected: PASS

**Step 5: Verify existing zero-match tests still work**

The existing `test_output_valid_json_zero_match` in `tests/test-context.sh:359-364` expects JSON output from zero-match. Update it to expect empty output:

In `tests/test-context.sh`, find `test_zero_skills_minimal_output` and update the assertion to check for empty output instead of JSON with "phase checkpoint" text. The function is around line 10-30 — read it first, then adjust the assertion.

**Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh tests/test-context.sh
git commit -m "feat: silence zero-match output (fitness review T1-#1)"
```

---

### Task 1.2: Full format only on prompt 1

**Files:**
- Modify: `hooks/skill-activation-hook.sh:738`
- Test: `tests/test-routing.sh` (append)

**Step 1: Write the failing test**

```bash
test_full_format_only_prompt_1() {
    setup_test_env
    install_registry
    # Simulate prompt 3 (depth counter)
    printf 'test-session-ff' > "${HOME}/.claude/.skill-session-token"
    printf '2' > "${HOME}/.claude/.skill-prompt-count-test-session-ff"

    # This prompt triggers 3+ skills (would normally get full format at depth 2-5)
    local output ctx
    output="$(run_hook "build a new component and review the design for security")"
    ctx="$(extract_context "$output")"

    # Should NOT contain full-format markers at depth 3
    assert_not_contains "prompt 3 should not get full format Step 1" "Step 1 -- ASSESS" "$ctx"

    teardown_test_env
}
test_full_format_only_prompt_1
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*full.format'`
Expected: FAIL — currently full format shows for prompts 1-5

**Step 3: Write minimal implementation**

In `hooks/skill-activation-hook.sh`, change line 738:

Old: `elif [[ "$_PROMPT_COUNT" -le 5 ]] && [[ "$TOTAL_COUNT" -ge 3 ]]; then`
New: `elif [[ "$_PROMPT_COUNT" -le 1 ]] && [[ "$TOTAL_COUNT" -ge 3 ]]; then`

**Step 4: Run test to verify it passes**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*full.format'`
Expected: PASS

**Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: restrict full format to prompt 1 only (fitness review T1-#4)"
```

---

### Task 1.3: Reduce segment name-boost from +40 to +20

**Files:**
- Modify: `hooks/skill-activation-hook.sh:124`
- Test: `tests/test-routing.sh` (append)

**Step 1: Write the failing test**

```bash
test_name_boost_segment_reduced() {
    setup_test_env
    install_registry
    # "build a component and review it" — should route to brainstorming (build),
    # not requesting-code-review, because "review" 6-char segment boost is only +20 not +40
    local output ctx
    output="$(run_hook "build a component and review it")"
    ctx="$(extract_context "$output")"

    # brainstorming should be the process skill (highest priority process)
    assert_contains "multi-intent should prefer brainstorming over review" "brainstorming" "$ctx"

    teardown_test_env
}
test_name_boost_segment_reduced
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*multi-intent'`
Expected: May pass or fail depending on current scoring — verify before proceeding

**Step 3: Write minimal implementation**

In `hooks/skill-activation-hook.sh`, change line 124:

Old: `name_boost=40`
New: `name_boost=20`

**Step 4: Run full test suite to verify no regressions**

Run: `bash tests/run-tests.sh`
Expected: All existing tests pass

**Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "fix: reduce segment name-boost from 40 to 20 (fitness review T1-#2)"
```

---

### Task 1.4: Drop overflow "Also relevant:" display

**Files:**
- Modify: `hooks/skill-activation-hook.sh:494-505`
- Test: `tests/test-routing.sh` (append)

**Step 1: Write the failing test**

```bash
test_no_overflow_display() {
    setup_test_env
    install_registry

    # Trigger many skills to force overflow
    local output ctx
    output="$(run_hook "build and debug this security issue then review and ship it")"
    ctx="$(extract_context "$output")"

    assert_not_contains "overflow skills should not appear" "Also relevant:" "$ctx"

    teardown_test_env
}
test_no_overflow_display
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*overflow'`
Expected: FAIL — currently overflow skills are shown

**Step 3: Write minimal implementation**

In `hooks/skill-activation-hook.sh`, replace lines 494-505 in `_build_skill_lines()`. Delete the overflow display loop entirely:

Old (lines 494-505):
```bash
    # Overflow skills (relevant but didn't fit in top suggestions)
    for _overflow_var in OVERFLOW_DOMAIN OVERFLOW_WORKFLOW; do
      _overflow_val="${!_overflow_var}"
      while IFS='|' read -r oname oinvoke; do
        [[ -z "$oname" ]] && continue
        SKILL_LINES="${SKILL_LINES}
  Also relevant: ${oname} -> ${oinvoke}"
        EVAL_SKILLS="${EVAL_SKILLS}, ${oname} YES/NO"
      done <<EOF
${_overflow_val}
EOF
    done
```

New:
```bash
    # Overflow skills are intentionally not displayed — role caps are the signal.
```

**Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass. If any existing test asserts "Also relevant:", update it.

**Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "fix: drop overflow 'Also relevant:' display (fitness review T1-#3)"
```

---

### Task 1.5: Add user escape hatch (`[no-skills]`)

**Files:**
- Modify: `hooks/skill-activation-hook.sh:28-31`
- Test: `tests/test-routing.sh` (append)

**Step 1: Write the failing test**

```bash
test_escape_hatch_no_skills() {
    setup_test_env
    install_registry

    # [no-skills] marker should produce no output
    local output
    output="$(run_hook "[no-skills] build a new feature")"
    assert_equals "escape hatch should produce no output" "" "$output"

    # Also test -- prefix
    output="$(run_hook "-- just do it without skills")"
    assert_equals "-- prefix should produce no output" "" "$output"

    teardown_test_env
}
test_escape_hatch_no_skills
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*escape'`
Expected: FAIL

**Step 3: Write minimal implementation**

In `hooks/skill-activation-hook.sh`, after line 31 (`(( ${#PROMPT} < 5 )) && exit 0`), add:

```bash
# Escape hatch: [no-skills] marker or -- prefix suppresses all routing
[[ "$PROMPT" == *"[no-skills]"* ]] && exit 0
[[ "$PROMPT" =~ ^[[:space:]]*--[[:space:]] ]] && exit 0
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*escape'`
Expected: PASS

**Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

**Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: add [no-skills] escape hatch for prompt-level skill suppression"
```

---

### Task 1.6: Add false-positive negative test suite

**Files:**
- Test: `tests/test-routing.sh` (append)

**Step 1: Write the negative tests**

These tests assert that common non-skill prompts produce zero matches (empty context after Task 1.1 silencing):

```bash
# ---------------------------------------------------------------------------
# FALSE-POSITIVE NEGATIVE TESTS — common prompts that should NOT trigger skills
# ---------------------------------------------------------------------------

test_false_positive_defense() {
    setup_test_env
    install_registry

    local output ctx

    # Simple code operations — should NOT trigger brainstorming/TDD
    output="$(run_hook "rename this variable to snake_case")"
    ctx="$(extract_context "$output")"
    assert_equals "rename variable should zero-match" "" "$ctx"

    output="$(run_hook "explain this function to me")"
    ctx="$(extract_context "$output")"
    assert_equals "explain function should zero-match" "" "$ctx"

    output="$(run_hook "where is the database config defined")"
    ctx="$(extract_context "$output")"
    assert_equals "find definition should zero-match" "" "$ctx"

    output="$(run_hook "show me the recent changes to this file")"
    ctx="$(extract_context "$output")"
    assert_equals "show changes should zero-match" "" "$ctx"

    output="$(run_hook "what does this error message mean")"
    ctx="$(extract_context "$output")"
    # Note: "error" may trigger debugging — this test documents the current behavior.
    # If it fails, that's acceptable (debugging is arguably correct for "error").
    # The key point is it should NOT trigger brainstorming.
    assert_not_contains "error question should not trigger brainstorming" "brainstorming" "$ctx"

    output="$(run_hook "format this code block properly")"
    ctx="$(extract_context "$output")"
    assert_equals "format code should zero-match" "" "$ctx"

    output="$(run_hook "delete the old migration files")"
    ctx="$(extract_context "$output")"
    assert_equals "delete files should zero-match" "" "$ctx"

    output="$(run_hook "move this function to a separate module")"
    ctx="$(extract_context "$output")"
    assert_equals "move function should zero-match" "" "$ctx"

    output="$(run_hook "read the package.json and tell me the version")"
    ctx="$(extract_context "$output")"
    assert_equals "read file should zero-match" "" "$ctx"

    output="$(run_hook "update the copyright year in the license")"
    ctx="$(extract_context "$output")"
    assert_equals "trivial update should zero-match" "" "$ctx"

    teardown_test_env
}
test_false_positive_defense
```

**Step 2: Run tests**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*should (zero|not)'`

Expected: Some may fail if broad triggers fire on these prompts. This is **by design** — the test documents which prompts currently over-fire. Do NOT adjust the tests to pass; instead record which tests fail (these are trigger tightening candidates for Tier 3 of the fitness review).

For tests that fail: change `assert_equals` to a comment noting the false positive, e.g.:
```bash
# KNOWN FALSE POSITIVE: "update" triggers TDD. Track for Tier 3 trigger tightening.
```

**Step 3: Commit**

```bash
git add tests/test-routing.sh
git commit -m "test: add false-positive negative test suite (fitness review T2-#7)"
```

---

## Feature 2: Zero-Match Diagnostics

### Task 2.1: Log zero-match prompts

**Files:**
- Modify: `hooks/skill-activation-hook.sh:705-716` (already modified in Task 1.1)
- Test: `tests/test-routing.sh` (append)

**Step 1: Write the failing test**

```bash
test_zero_match_logs_prompt() {
    setup_test_env
    install_registry

    run_hook "rename this variable to camelCase" >/dev/null
    run_hook "explain the auth flow to me" >/dev/null

    local log_file="${HOME}/.claude/.skill-zero-match-log"
    assert_file_exists "zero-match log should exist" "$log_file"

    local log_content
    log_content="$(cat "$log_file" 2>/dev/null)"
    assert_contains "log should contain first prompt" "rename this variable" "$log_content"
    assert_contains "log should contain second prompt" "explain the auth flow" "$log_content"

    # Verify rotation: log should not exceed 100 lines
    local line_count
    line_count="$(wc -l < "$log_file" | tr -d ' ')"
    if [[ "$line_count" -le 100 ]]; then
        _record_pass "log should stay within 100 lines"
    else
        _record_fail "log should stay within 100 lines" "got $line_count lines"
    fi

    teardown_test_env
}
test_zero_match_logs_prompt
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*zero-match log'`
Expected: FAIL

**Step 3: Write minimal implementation**

In `hooks/skill-activation-hook.sh`, in the `TOTAL_COUNT -eq 0` branch (already modified in Task 1.1), add prompt logging after the counter increment:

```bash
  if [[ "$TOTAL_COUNT" -eq 0 ]]; then
    # Instrument zero-match rate
    _ZM_FILE="${HOME}/.claude/.skill-zero-match-count"
    _zm=0
    [[ -f "$_ZM_FILE" ]] && _zm="$(cat "$_ZM_FILE" 2>/dev/null)"
    [[ "$_zm" =~ ^[0-9]+$ ]] || _zm=0
    printf '%s' "$((_zm + 1))" > "$_ZM_FILE" 2>/dev/null || true

    # Log the zero-match prompt for diagnostics (rotate at 100 entries)
    _ZM_LOG="${HOME}/.claude/.skill-zero-match-log"
    printf '%s\n' "$P" >> "$_ZM_LOG" 2>/dev/null || true
    if [[ -f "$_ZM_LOG" ]]; then
      _lc="$(wc -l < "$_ZM_LOG" 2>/dev/null | tr -d ' ')"
      if [[ "$_lc" =~ ^[0-9]+$ ]] && [[ "$_lc" -gt 100 ]]; then
        tail -n 100 "$_ZM_LOG" > "${_ZM_LOG}.tmp" 2>/dev/null && mv "${_ZM_LOG}.tmp" "$_ZM_LOG" 2>/dev/null || true
      fi
    fi

    # Silent exit — no additionalContext on zero match
    return
  fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*zero-match log'`
Expected: PASS

**Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: log zero-match prompts for diagnostics"
```

---

### Task 2.2: Surface zero-match rate at session start

**Files:**
- Modify: `hooks/session-start-hook.sh:46-48` (read counters before deleting) and `:563` (append to MSG)
- Test: `tests/test-routing.sh` (append)

**Step 1: Write the failing test**

```bash
test_session_start_shows_zero_match_rate() {
    setup_test_env

    # Simulate a previous session with 20 total prompts, 3 zero-match
    printf '20' > "${HOME}/.claude/.skill-prompt-count-prev-session"
    printf '3' > "${HOME}/.claude/.skill-zero-match-count"

    # Run session-start hook (uses PROJECT_ROOT for CLAUDE_PLUGIN_ROOT)
    local output
    output="$(CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null)"
    local ctx
    ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

    assert_contains "session start should show zero-match rate" "unmatched" "$ctx"

    teardown_test_env
}
test_session_start_shows_zero_match_rate
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*session.start.*zero'`
Expected: FAIL

**Step 3: Write minimal implementation**

In `hooks/session-start-hook.sh`, **before** the counter cleanup at line 48 (`rm -f "${HOME}/.claude/.skill-prompt-count-"*`), add:

```bash
# Read previous session's zero-match stats before cleanup
_PREV_ZM=0
_PREV_TOTAL=0
[[ -f "${HOME}/.claude/.skill-zero-match-count" ]] && _PREV_ZM="$(cat "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null)"
[[ "$_PREV_ZM" =~ ^[0-9]+$ ]] || _PREV_ZM=0
# Sum all prompt counters from previous session
for _pcf in "${HOME}/.claude/.skill-prompt-count-"*; do
    [[ -f "$_pcf" ]] || continue
    _pc="$(cat "$_pcf" 2>/dev/null)"
    [[ "$_pc" =~ ^[0-9]+$ ]] && _PREV_TOTAL=$((_PREV_TOTAL + _pc))
done
rm -f "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null || true
```

Then at line 563, modify the MSG line to conditionally append the zero-match rate:

```bash
_ZM_STAT=""
if [[ "$_PREV_TOTAL" -gt 10 ]] && [[ "$_PREV_ZM" -gt 0 ]]; then
    _ZM_STAT=" | prev: ${_PREV_ZM}/${_PREV_TOTAL} unmatched"
fi
MSG="SessionStart: ${AVAILABLE_COUNT} skills active (${INSTALLED_COMPANIONS} of ${TOTAL_COMPANIONS} plugins)${_ZM_STAT}${SETUP_CTA}"
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E '(PASS|FAIL):.*session.start.*zero'`
Expected: PASS

**Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

**Step 6: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-routing.sh
git commit -m "feat: surface previous session zero-match rate at session start"
```

---

### Task 2.3: Extend /skill-explain with zero-match diagnostics

**Files:**
- Modify: `commands/skill-explain.md:66-68`

**Step 1: Read the current command file**

Read `commands/skill-explain.md` to confirm exact structure.

**Step 2: Add zero-match diagnostics section**

After the "Session State" section (line 66-68), add:

```markdown
### Zero-Match Diagnostics
- Zero-match count: {read from ~/.claude/.skill-zero-match-count or "0"}
- Zero-match rate: {zero-match / prompt-count if available, else "n/a"}
- Recent unmatched prompts (last 10):
  {read last 10 lines from ~/.claude/.skill-zero-match-log, display in a code block}
  If the file doesn't exist, say "(no zero-match log found — prompts are matching well)"
```

**Step 3: Commit**

```bash
git add commands/skill-explain.md
git commit -m "feat: add zero-match diagnostics to /skill-explain"
```

---

## Feature 3: Compaction-Resilient Composition State

### Task 3.1: Write composition state to file

**Files:**
- Modify: `hooks/skill-activation-hook.sh:780-788`
- Test: `tests/test-context.sh` (append)

**Step 1: Write the failing test**

Append to `tests/test-context.sh` before the `print_summary` line (line 369):

```bash
test_composition_state_written() {
    setup_test_env
    install_registry

    printf 'comp-test-session' > "${HOME}/.claude/.skill-session-token"
    # Simulate brainstorming was invoked last (so composition chain is active)
    printf '{"skill":"brainstorming","phase":"DESIGN"}' > "${HOME}/.claude/.skill-last-invoked-comp-test-session"

    # Trigger writing-plans (next in chain after brainstorming)
    run_hook "let's plan this out" >/dev/null

    local state_file="${HOME}/.claude/.skill-composition-state-comp-test-session"
    assert_file_exists "composition state file should be created" "$state_file"

    # Verify JSON structure
    local chain_len
    chain_len="$(jq '.chain | length' "$state_file" 2>/dev/null)"
    if [[ "$chain_len" -ge 2 ]]; then
        _record_pass "composition state should have chain with 2+ skills"
    else
        _record_fail "composition state should have chain with 2+ skills" "got chain length: $chain_len"
    fi

    teardown_test_env
}
test_composition_state_written
```

Also add `test_composition_state_written` to the "Run all tests" section.

**Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh 2>/dev/null | grep -E '(PASS|FAIL):.*composition.state'`
Expected: FAIL

**Step 3: Write minimal implementation**

In `hooks/skill-activation-hook.sh`, after the last-invoked signal write (line 786-788), add composition state write:

```bash
    # Write composition state for compaction resilience
    if [[ -n "${_full_chain:-}" ]] && [[ "${_full_chain}" == *"|"* ]] && [[ -n "${_SESSION_TOKEN:-}" ]]; then
      # Build completed array: skills at indices <= _last_skill_chain_idx
      _comp_completed="[]"
      if [[ "${_last_skill_chain_idx:-0}" -ge 0 ]] && [[ -n "${_last_skill_chain_idx:-}" ]]; then
        _comp_completed="$(printf '%s' "$_full_chain" | tr '|' '\n' | head -n "$((_last_skill_chain_idx + 1))" | jq -R . | jq -s . 2>/dev/null)" || _comp_completed="[]"
      fi
      _comp_chain="$(printf '%s' "$_full_chain" | tr '|' '\n' | jq -R . | jq -s . 2>/dev/null)" || true
      if [[ -n "$_comp_chain" ]]; then
        jq -n --argjson chain "$_comp_chain" \
              --argjson completed "$_comp_completed" \
              --argjson idx "${_current_idx:-0}" \
              '{chain:$chain, current_index:$idx, completed:$completed, updated_at:now|todate}' \
          > "${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}" 2>/dev/null || true
      fi
    fi
```

Note: `_full_chain`, `_current_idx`, and `_last_skill_chain_idx` are already computed in `_walk_composition_chain()` (lines 573-627). They are global variables (bash functions share scope). We need to ensure they are accessible in `_format_output()`. Check that they are not declared `local` in `_walk_composition_chain` — they are not (confirmed: no `local` on these variables).

**Step 4: Run test to verify it passes**

Run: `bash tests/test-context.sh 2>/dev/null | grep -E '(PASS|FAIL):.*composition.state'`
Expected: PASS

**Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

**Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-context.sh
git commit -m "feat: write composition state to session-scoped file"
```

---

### Task 3.2: Read composition state in compact-recovery-hook

**Files:**
- Modify: `hooks/compact-recovery-hook.sh:27` (after team state recovery)
- Test: `tests/test-context.sh` (append)

**Step 1: Write the failing test**

```bash
test_composition_recovery_after_compaction() {
    setup_test_env

    printf 'recovery-test-session' > "${HOME}/.claude/.skill-session-token"

    # Create a composition state file (as if a chain was active before compaction)
    cat > "${HOME}/.claude/.skill-composition-state-recovery-test-session" <<'COMP'
{"chain":["brainstorming","writing-plans","executing-plans"],"current_index":1,"completed":["brainstorming"],"updated_at":"2026-03-09T14:30:00Z"}
COMP

    # Run the compact-recovery hook
    local output
    output="$(echo '{}' | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/compact-recovery-hook.sh" 2>/dev/null)"

    assert_contains "recovery should show composition chain" "Composition Recovery" "$output"
    assert_contains "recovery should show completed skills" "brainstorming" "$output"
    assert_contains "recovery should show current step" "writing-plans" "$output"

    teardown_test_env
}
test_composition_recovery_after_compaction
```

Also add this test to the "Run all tests" section.

**Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh 2>/dev/null | grep -E '(PASS|FAIL):.*composition.recovery'`
Expected: FAIL

**Step 3: Write minimal implementation**

In `hooks/compact-recovery-hook.sh`, after the team checkpoint block (line 27), add:

```bash
# --- Re-inject composition state if it exists ---
if [ -n "$_SESSION_TOKEN" ]; then
    COMP_FILE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
    if [ -f "$COMP_FILE" ] && command -v jq >/dev/null 2>&1; then
        _chain="$(jq -r '.chain | join(" -> ")' "$COMP_FILE" 2>/dev/null)"
        _completed="$(jq -r '.completed | join(", ")' "$COMP_FILE" 2>/dev/null)"
        _current="$(jq -r '.chain[.current_index] // "unknown"' "$COMP_FILE" 2>/dev/null)"
        if [ -n "$_chain" ]; then
            echo "=== Composition Recovery (from pre-compaction state) ==="
            echo "Chain: ${_chain}"
            echo "Completed: ${_completed}"
            echo "Current step: ${_current}"
            echo "Resume from: ${_current}"
            echo "=== End Composition Recovery ==="
        fi
    fi
fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-context.sh 2>/dev/null | grep -E '(PASS|FAIL):.*composition.recovery'`
Expected: PASS

**Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

**Step 6: Commit**

```bash
git add hooks/compact-recovery-hook.sh tests/test-context.sh
git commit -m "feat: recover composition state after context compaction"
```

---

### Task 3.3: Replace [DONE?] with definitive [DONE] using persisted state

**Files:**
- Modify: `hooks/skill-activation-hook.sh:639-644`
- Test: `tests/test-context.sh` (append)

**Step 1: Write the failing test**

```bash
test_composition_done_not_done_question() {
    setup_test_env
    install_registry

    printf 'done-test-session' > "${HOME}/.claude/.skill-session-token"

    # Create composition state showing brainstorming is confirmed complete
    cat > "${HOME}/.claude/.skill-composition-state-done-test-session" <<'COMP'
{"chain":["brainstorming","writing-plans","executing-plans"],"current_index":1,"completed":["brainstorming"],"updated_at":"2026-03-09T14:30:00Z"}
COMP

    # Simulate brainstorming was last invoked
    printf '{"skill":"brainstorming","phase":"DESIGN"}' > "${HOME}/.claude/.skill-last-invoked-done-test-session"

    # Trigger writing-plans
    local output ctx
    output="$(run_hook "let's write the implementation plan")"
    ctx="$(extract_context "$output")"

    # Should show [DONE] not [DONE?] for brainstorming
    assert_contains "brainstorming should be marked DONE" "[DONE]" "$ctx"
    assert_not_contains "should not show DONE?" "[DONE?]" "$ctx"

    teardown_test_env
}
test_composition_done_not_done_question
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh 2>/dev/null | grep -E '(PASS|FAIL):.*DONE'`
Expected: FAIL — currently uses `_last_skill_chain_idx` only, which may produce `[DONE?]`

**Step 3: Write minimal implementation**

In `hooks/skill-activation-hook.sh`, in `_walk_composition_chain()`, before the chain display loop (around line 636), add a read of the composition state file:

```bash
      # Read persisted composition state for definitive DONE markers
      _COMP_COMPLETED=""
      _COMP_FILE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN:-default}"
      if [[ -f "$_COMP_FILE" ]]; then
        _COMP_COMPLETED="$(jq -r '.completed[]' "$_COMP_FILE" 2>/dev/null)" || _COMP_COMPLETED=""
      fi
```

Then modify the marker logic in the loop (lines 639-644). Replace:

```bash
        if [[ "$_idx" -lt "$_current_idx" ]]; then
          if [[ "$_last_skill_chain_idx" -ge 0 ]] && [[ "$_idx" -le "$_last_skill_chain_idx" ]]; then
            _marker="DONE"
          else
            _marker="DONE?"
          fi
```

With:

```bash
        if [[ "$_idx" -lt "$_current_idx" ]]; then
          # Check persisted state first, fall back to last-invoked signal
          if printf '%s\n' "$_COMP_COMPLETED" | grep -qx "$_cname" 2>/dev/null; then
            _marker="DONE"
          elif [[ "$_last_skill_chain_idx" -ge 0 ]] && [[ "$_idx" -le "$_last_skill_chain_idx" ]]; then
            _marker="DONE"
          else
            _marker="DONE?"
          fi
```

**Step 4: Run test to verify it passes**

Run: `bash tests/test-context.sh 2>/dev/null | grep -E '(PASS|FAIL):.*DONE'`
Expected: PASS

**Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

**Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-context.sh
git commit -m "feat: use persisted composition state for definitive DONE markers"
```

---

## Final Verification

### Task 4.1: Full test suite + syntax check

**Step 1: Syntax-check all modified hooks**

```bash
bash -n hooks/skill-activation-hook.sh
bash -n hooks/session-start-hook.sh
bash -n hooks/compact-recovery-hook.sh
```

Expected: No errors

**Step 2: Run full test suite**

```bash
bash tests/run-tests.sh
```

Expected: All tests pass

**Step 3: Verify with SKILL_EXPLAIN**

```bash
echo '{"prompt":"build a new authentication system"}' | \
  SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT="$(pwd)" \
  bash hooks/skill-activation-hook.sh 2>&1
```

Verify output shows scoring, selection, and result.

```bash
echo '{"prompt":"rename this variable"}' | \
  SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT="$(pwd)" \
  bash hooks/skill-activation-hook.sh 2>&1
```

Verify zero-match produces no stdout JSON (only SKILL_EXPLAIN stderr output).

**Step 4: Commit any final adjustments**

If any tests needed fixing, commit with:
```bash
git commit -m "fix: adjust tests for feature 1-3 integration"
```
