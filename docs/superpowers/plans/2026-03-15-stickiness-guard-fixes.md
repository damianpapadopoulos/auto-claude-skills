# Stickiness Gate Guard + Remaining Review Fixes

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the IMPLEMENT stickiness HARD-GATE violation and resolve 5 remaining code review issues.

**Architecture:** Stickiness regex replacement (continuation-only), composition flag optimization, trigger cleanup, log size cap. All changes in existing files.

**Tech Stack:** Bash 3.2, jq, test harness in `tests/test-routing.sh` and `tests/test-context.sh`

**Spec:** `docs/superpowers/specs/2026-03-15-stickiness-guard-fixes-design.md`

---

## Chunk 1: Stickiness Gate Guard (Critical)

### Task 1: Restrict stickiness to continuation language only

**Files:**
- Modify: `hooks/skill-activation-hook.sh:294-353`
- Modify: `tests/test-routing.sh` (update existing stickiness test + add new-design test)

- [ ] **Step 1: Update existing stickiness test prompt to use continuation language**

In `tests/test-routing.sh`, find `test_implement_stickiness` and change the prompt from a generic build verb to explicit continuation:

Change:
```bash
    output="$(run_hook "build the authentication middleware for the API")"
```
To:
```bash
    output="$(run_hook "continue with the next task in the plan")"
```

- [ ] **Step 2: Add test proving new-design-during-IMPLEMENT respects HARD-GATE**

Add before `print_summary` in `tests/test-routing.sh`:

```bash
# ---------------------------------------------------------------------------
# New design intent during IMPLEMENT must route to brainstorming (HARD-GATE)
# ---------------------------------------------------------------------------
test_new_design_during_implement() {
    echo "-- test: new design during IMPLEMENT respects HARD-GATE --"
    setup_test_env
    install_registry_v4

    local token="test-hardgate-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    # "build a new authentication system" is a new design intent, not continuation
    local output
    output="$(run_hook "build a new authentication system for the app")"
    local context
    context="$(extract_context "${output}")"

    # brainstorming should win — HARD-GATE says design before implementation
    assert_contains "brainstorming wins on new design" "brainstorming" "${context}"

    # executing-plans should NOT be injected by stickiness
    if printf '%s' "${context}" | grep -q 'Process:.*executing-plans'; then
        _record_fail "stickiness did not fire on new design" "executing-plans was selected"
    else
        _record_pass "stickiness did not fire on new design"
    fi

    teardown_test_env
}
test_new_design_during_implement
```

- [ ] **Step 3: Add test for resume/pick-up language**

```bash
test_stickiness_on_resume() {
    echo "-- test: stickiness fires on resume language --"
    setup_test_env
    install_registry_v4

    local token="test-resume-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "pick up where we left off")"
    local context
    context="$(extract_context "${output}")"

    if printf '%s' "${context}" | grep -q 'executing-plans'; then
        _record_pass "stickiness fires on resume language"
    else
        _record_fail "stickiness fires on resume language" "executing-plans not selected"
    fi

    teardown_test_env
}
test_stickiness_on_resume
```

- [ ] **Step 4: Run tests to verify — existing stickiness FAILS (prompt changed), new-design FAILS (stickiness still broad), resume FAILS (no continuation pattern yet)**

Run: `bash tests/test-routing.sh 2>&1 | grep -E "(stickiness|HARD-GATE|resume)" -A2 | head -20`

- [ ] **Step 5: Replace stickiness regex — continuation language only**

In `hooks/skill-activation-hook.sh`, replace lines 311-315 (the three conditions: top_process check, verb regex, design-cue blocker) with a single continuation-only check:

Replace:
```bash
    if [[ "$_top_process_phase" == "DESIGN" ]] || [[ -z "$_top_process_phase" ]]; then
      # Check if prompt has continuation/edit verbs
      if [[ "$P" =~ (^|[^a-z])(add|build|create|implement|modify|change|refactor|wire.?up|connect|integrate|extend|update|rename|extract|move|replace)($|[^a-z]) ]]; then
        # Check prompt does NOT have design/discovery cues
        if ! [[ "$P" =~ (how.should|what.approach|best.way.to|ideas.for|options.for|trade.?off|compare|brainstorm|design|architect) ]]; then
```

With:
```bash
    if [[ "$_top_process_phase" == "DESIGN" ]] || [[ -z "$_top_process_phase" ]]; then
      # Only fire on EXPLICIT continuation language — never generic build verbs.
      # Generic verbs like "add/build/create" may indicate new design intents
      # that must go through brainstorming (superpowers HARD-GATE).
      if [[ "$P" =~ (continue|resume|next.task|next.step|pick.up|carry.on|keep.going|where.were.we|what.s.next|move.on|proceed|finish.up|wrap.up.this|remaining|back.to.it) ]]; then
```

Also remove the closing `fi` for the old design-cue blocker (line 351). The new pattern has one fewer nesting level. Replace:
```bash
        fi
      fi
    fi
```
With:
```bash
      fi
    fi
```

- [ ] **Step 6: Update the comment block**

Replace lines 294-296:
```bash
  # --- IMPLEMENT stickiness ---
  # If last phase was IMPLEMENT and prompt uses continuation/edit verbs
  # (not design-discovery cues), boost executing-plans above the top process skill.
```
With:
```bash
  # --- IMPLEMENT stickiness ---
  # If last phase was IMPLEMENT and prompt uses EXPLICIT continuation language,
  # boost executing-plans above the top process skill. Generic build verbs
  # (add/build/create) are NOT matched — they may indicate new design intents
  # that must go through brainstorming (superpowers HARD-GATE).
```

- [ ] **Step 7: Syntax check**

Run: `bash -n hooks/skill-activation-hook.sh`
Expected: No output (clean)

- [ ] **Step 8: Run tests**

Run: `bash tests/test-routing.sh 2>&1 | grep -E "(stickiness|HARD-GATE|resume)" -A2 | head -20`
Expected: All 4 stickiness tests PASS

- [ ] **Step 9: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 10: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "fix: restrict IMPLEMENT stickiness to continuation language only

Generic build verbs (add/build/create) removed from stickiness trigger.
These may indicate new design intents that must go through brainstorming
(superpowers HARD-GATE). Only explicit continuation language (continue/
resume/next task/pick up/carry on) now triggers stickiness."
```

---

## Chunk 2: Remaining Review Fixes

### Task 2: Remove agent-team-execution duplicate trigger

**Files:**
- Modify: `config/default-triggers.json` (agent-team-execution entry)

- [ ] **Step 1: Write failing test**

Add to `tests/test-routing.sh` before `print_summary`:

```bash
test_agent_team_not_on_continuation() {
    echo "-- test: agent-team-execution does not co-select on plain continuation --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "continue with the next task")"
    local context
    context="$(extract_context "${output}")"

    local ate_count
    ate_count="$(printf '%s' "${context}" | grep -c 'agent-team-execution' 2>/dev/null)" || ate_count=0
    assert_equals "agent-team not on continuation" "0" "${ate_count}"

    teardown_test_env
}
test_agent_team_not_on_continuation
```

- [ ] **Step 2: Run test — verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep "agent-team not on" -A1`
Expected: FAIL

- [ ] **Step 3: Remove duplicate trigger from production config**

Use jq to remove the second trigger from agent-team-execution:

```bash
cat config/default-triggers.json | jq '
  .skills |= [.[] |
    if .name == "agent-team-execution" then
      .triggers = ["(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)"]
    else . end
  ]
' > /tmp/dt-ate.json && cp /tmp/dt-ate.json config/default-triggers.json
```

- [ ] **Step 4: Update test fixture**

In `tests/test-routing.sh`, update the `install_registry_v4` fixture's `agent-team-execution` entry to have only the team-specific trigger (matching the production change). Use python:

```bash
python3 -c "
content = open('tests/test-routing.sh').read()
content = content.replace(
    '\"triggers\": [\"(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)\", \"(execute.*plan|run.the.plan|implement.the.plan|implement.*(rest|remaining)|continue|follow.the.plan|pick.up|resume|next.task|next.step|carry.on|keep.going|where.were.we|what.s.next)\"],',
    '\"triggers\": [\"(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)\"],'
)
open('tests/test-routing.sh', 'w').write(content)
print('DONE')
"
```

- [ ] **Step 5: Run test — verify it passes**

Run: `bash tests/test-routing.sh 2>&1 | grep "agent-team not on" -A1`
Expected: PASS

- [ ] **Step 6: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 7: Commit**

```bash
git add config/default-triggers.json tests/test-routing.sh
git commit -m "fix: remove duplicate trigger from agent-team-execution

The execute.*plan|continue|resume trigger duplicated executing-plans,
causing false co-selection on every continuation prompt. Keep only
the team-specific trigger (agent.team|team.execute|parallel.team)."
```

### Task 3: Replace TDD fallback grep with flag

**Files:**
- Modify: `hooks/skill-activation-hook.sh:1196-1217`

- [ ] **Step 1: Add _TDD_EMITTED flag in composition output loop**

In `hooks/skill-activation-hook.sh`, add before the composition loop (before line 1196):

```bash
_TDD_EMITTED=0
```

Inside the loop body (line 1199), after the `LINE:` case, add a check:

```bash
      LINE:*)
        COMPOSITION_LINES="${COMPOSITION_LINES}
${_cline#LINE:}"
        # Track if TDD was emitted from jq composition
        case "${_cline}" in *test-driven-development*) _TDD_EMITTED=1 ;; esac
        ;;
```

- [ ] **Step 2: Replace grep with flag check in TDD fallback**

Replace lines 1210-1216:
```bash
case "${CURRENT_PHASE:-}" in
  IMPLEMENT|DEBUG)
    if [[ -z "$COMPOSITION_LINES" ]] || ! printf '%s' "$COMPOSITION_LINES" | grep -q 'test-driven-development'; then
      COMPOSITION_LINES="${COMPOSITION_LINES}
  PARALLEL: test-driven-development -> Skill(superpowers:test-driven-development) — INVOKE before writing production code"
    fi
    ;;
esac
```

With:
```bash
case "${CURRENT_PHASE:-}" in
  IMPLEMENT|DEBUG)
    if [[ "$_TDD_EMITTED" -eq 0 ]]; then
      COMPOSITION_LINES="${COMPOSITION_LINES}
  PARALLEL: test-driven-development -> Skill(superpowers:test-driven-development) — INVOKE before writing production code"
    fi
    ;;
esac
```

- [ ] **Step 3: Syntax check + full test suite**

Run: `bash -n hooks/skill-activation-hook.sh && bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 4: Commit**

```bash
git add hooks/skill-activation-hook.sh
git commit -m "perf: replace TDD fallback grep with boolean flag

Track _TDD_EMITTED during composition output loop to avoid forking
a grep subprocess on every IMPLEMENT/DEBUG prompt."
```

### Task 4: Add zero-match log size cap + prompt truncation

**Files:**
- Modify: `hooks/skill-activation-hook.sh:875-883`

- [ ] **Step 1: Add byte-size check and prompt truncation**

Replace lines 875-883:
```bash
    # Log the zero-match prompt for diagnostics (rotate at 100 entries)
    _ZM_LOG="${HOME}/.claude/.skill-zero-match-log"
    printf '%s\n' "$P" >> "$_ZM_LOG" 2>/dev/null || true
    if [[ -f "$_ZM_LOG" ]]; then
      _lc="$(wc -l < "$_ZM_LOG" 2>/dev/null | tr -d ' ')"
      if [[ "$_lc" =~ ^[0-9]+$ ]] && [[ "$_lc" -gt 100 ]]; then
        tail -n 100 "$_ZM_LOG" > "${_ZM_LOG}.tmp" 2>/dev/null && mv "${_ZM_LOG}.tmp" "$_ZM_LOG" 2>/dev/null || true
      fi
    fi
```

With:
```bash
    # Log the zero-match prompt for diagnostics (rotate at 100 entries, cap at 50KB)
    _ZM_LOG="${HOME}/.claude/.skill-zero-match-log"
    # Truncate prompt to 200 chars to prevent unbounded log growth
    printf '%.200s\n' "$P" >> "$_ZM_LOG" 2>/dev/null || true
    if [[ -f "$_ZM_LOG" ]]; then
      # Rotate by line count
      _lc="$(wc -l < "$_ZM_LOG" 2>/dev/null | tr -d ' ')"
      if [[ "$_lc" =~ ^[0-9]+$ ]] && [[ "$_lc" -gt 100 ]]; then
        tail -n 100 "$_ZM_LOG" > "${_ZM_LOG}.tmp" 2>/dev/null && mv "${_ZM_LOG}.tmp" "$_ZM_LOG" 2>/dev/null || true
      fi
      # Rotate by byte size (50KB cap)
      _zm_size="$(wc -c < "$_ZM_LOG" 2>/dev/null | tr -d ' ')"
      if [[ "$_zm_size" =~ ^[0-9]+$ ]] && [[ "$_zm_size" -gt 51200 ]]; then
        tail -n 50 "$_ZM_LOG" > "${_ZM_LOG}.tmp" 2>/dev/null && mv "${_ZM_LOG}.tmp" "$_ZM_LOG" 2>/dev/null || true
      fi
    fi
```

- [ ] **Step 2: Syntax check + full test suite**

Run: `bash -n hooks/skill-activation-hook.sh && bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 3: Commit**

```bash
git add hooks/skill-activation-hook.sh
git commit -m "fix: cap zero-match log with prompt truncation and byte-size rotation

Truncate logged prompts to 200 chars. Add 50KB byte-size rotation
alongside existing 100-line rotation. Prevents unbounded log growth
from long prompts."
```

### Task 5: Regenerate fallback registry + final verification

**Files:**
- Modify: `config/fallback-registry.json`

- [ ] **Step 1: Regenerate fallback**

Run: `bash hooks/session-start-hook.sh < /dev/null 2>/dev/null; cp ~/.claude/.skill-registry-cache.json config/fallback-registry.json`

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -15`
Expected: All tests pass

- [ ] **Step 3: SKILL_EXPLAIN — verify stickiness on continuation**

```bash
printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' > ~/.claude/.skill-last-invoked-$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)
echo '{"prompt":"continue with the next task"}' | SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT=. bash hooks/skill-activation-hook.sh 2>&1 | grep -E '(executing-plans|brainstorming|Result)' | head -3
```
Expected: executing-plans wins

- [ ] **Step 4: SKILL_EXPLAIN — verify HARD-GATE on new design during IMPLEMENT**

```bash
echo '{"prompt":"build a new authentication system"}' | SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT=. bash hooks/skill-activation-hook.sh 2>&1 | grep -E '(executing-plans|brainstorming|Result)' | head -3
```
Expected: brainstorming wins (stickiness does NOT fire on "build")

- [ ] **Step 5: Commit fallback**

```bash
git add config/fallback-registry.json
git commit -m "chore: regenerate fallback registry"
```
