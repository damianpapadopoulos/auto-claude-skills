# Phase-Aware RED FLAGS Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the RED FLAGS enforcement mechanism to all SDLC phases and add a phase-enforcement methodology hint.

**Architecture:** Add phase-specific RED FLAGS in `_format_output()` using `PRIMARY_PHASE` case statement. Add one methodology hint entry. Tighten one test assertion. All changes in existing files, existing mechanisms.

**Tech Stack:** Bash 3.2, jq, test harness

**Spec:** `docs/superpowers/specs/2026-03-15-phase-red-flags-design.md`

---

## Chunk 1: Phase RED FLAGS + Methodology Hint + Test Fix

### Task 1: Add tests for phase RED FLAGS

**Files:**
- Modify: `tests/test-routing.sh`

- [ ] **Step 1: Write failing test for DESIGN RED FLAGS**

Add before `print_summary` in `tests/test-routing.sh`:

```bash
# ---------------------------------------------------------------------------
# Phase-aware RED FLAGS
# ---------------------------------------------------------------------------
test_design_red_flags() {
    echo "-- test: DESIGN phase has RED FLAGS --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "build a new payment integration for our app")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "DESIGN red flags present" "HALT if any Red Flag" "${context}"
    assert_contains "DESIGN red flag mentions brainstorming" "brainstorming" "${context}"

    teardown_test_env
}
test_design_red_flags

test_implement_red_flags() {
    echo "-- test: IMPLEMENT phase has RED FLAGS --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "continue with the next task in the plan")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "IMPLEMENT red flags present" "HALT if any Red Flag" "${context}"
    assert_contains "IMPLEMENT red flag mentions worktree" "worktree" "${context}"

    teardown_test_env
}
test_implement_red_flags

test_review_red_flags() {
    echo "-- test: REVIEW phase has RED FLAGS --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "review this pull request for the auth module")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "REVIEW red flags present" "HALT if any Red Flag" "${context}"
    assert_contains "REVIEW red flag mentions subagent" "code-reviewer subagent" "${context}"

    teardown_test_env
}
test_review_red_flags
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | grep -E "(DESIGN red|IMPLEMENT red|REVIEW red)" -A2 | head -15`
Expected: FAIL for all 3 (no RED FLAGS yet for these phases)

- [ ] **Step 3: Commit test-first**

```bash
git add tests/test-routing.sh
git commit -m "test: add failing tests for phase-aware RED FLAGS"
```

### Task 2: Implement phase RED FLAGS in hook

**Files:**
- Modify: `hooks/skill-activation-hook.sh:1234-1251`

- [ ] **Step 1: Replace the SHIP-only RED FLAGS block with phase-aware RED FLAGS**

Replace the current RED FLAGS section (lines 1234-1251) with:

```bash
# =================================================================
# RED FLAGS: Phase-aware enforcement checklists
# =================================================================
RED_FLAGS=""
case "${PRIMARY_PHASE}" in
  DESIGN)
    RED_FLAGS="
HALT if any Red Flag is true:
- Editing implementation files before invoking Skill(superpowers:brainstorming)
- Skipping design presentation and user approval
- Jumping to writing code without exploring approaches first
- Not writing a design doc before transitioning to PLAN"
    ;;
  PLAN)
    RED_FLAGS="
HALT if any Red Flag is true:
- Editing implementation files before invoking Skill(superpowers:writing-plans)
- Implementing without an approved plan document
- Skipping TDD steps in the plan
- Not saving the plan to docs/superpowers/plans/ before executing"
    ;;
  IMPLEMENT)
    RED_FLAGS="
HALT if any Red Flag is true:
- Implementing on main without setting up a git worktree first
- Skipping TDD: writing implementation before writing the failing test
- Not following the plan step by step
- Jumping to SHIP without going through REVIEW (requesting-code-review) first
- Use subagent-driven-development or agent-team-execution where appropriate"
    ;;
  REVIEW)
    RED_FLAGS="
HALT if any Red Flag is true:
- Summarizing changes instead of dispatching superpowers:code-reviewer subagent
- Not providing BASE_SHA and HEAD_SHA git diff range to the reviewer
- Claiming review is complete without acting on critical/important findings
- Skipping security-scanner during review"
    ;;
esac

# SHIP: verification-specific RED FLAGS (existing, unchanged)
if printf '%s' "${SELECTED}${OVERFLOW_WORKFLOW}" | grep -q 'verification-before-completion'; then
  RED_FLAGS="${RED_FLAGS}
HALT if any Red Flag is true:
- Claiming 'tests pass' without showing test runner output
- Claiming 'everything works' without running verification commands
- Referencing files that were never read with the Read tool
- Claiming to have executed commands without Bash tool calls in this conversation
- Saying 'no changes needed' on code the user flagged as broken
- Skipping verification steps listed in the skill
- Generating placeholder/stub/TODO implementations as final output"
fi

if [[ -n "$RED_FLAGS" ]]; then
  SKILL_LINES="${SKILL_LINES}${RED_FLAGS}"
fi
```

- [ ] **Step 2: Syntax check**

Run: `bash -n hooks/skill-activation-hook.sh`
Expected: No output (clean)

- [ ] **Step 3: Run tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | grep -E "(DESIGN red|IMPLEMENT red|REVIEW red)" -A2 | head -15`
Expected: PASS for all 3

- [ ] **Step 4: Run full test suite for regressions**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`
Expected: All routing tests pass

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh
git commit -m "feat: extend RED FLAGS to DESIGN, PLAN, IMPLEMENT, and REVIEW phases"
```

### Task 3: Add phase-enforcement methodology hint

**Files:**
- Modify: `config/default-triggers.json`

- [ ] **Step 1: Write failing test for hint**

Add to `tests/test-routing.sh` before `print_summary`:

```bash
test_phase_enforcement_hint() {
    echo "-- test: phase enforcement hint fires at DESIGN with impl intent --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "fix the authentication bug in the login module")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "phase enforcement hint" "PHASE ENFORCEMENT" "${context}"

    teardown_test_env
}
test_phase_enforcement_hint

test_phase_enforcement_hint_not_at_implement() {
    echo "-- test: phase enforcement hint does NOT fire at IMPLEMENT --"
    setup_test_env
    install_registry_v4

    local token="test-enforce-impl"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "continue with the next task")"
    local context
    context="$(extract_context "${output}")"

    local enforce_count
    enforce_count="$(printf '%s' "${context}" | grep -c 'PHASE ENFORCEMENT' 2>/dev/null)" || enforce_count=0
    assert_equals "no enforcement hint at IMPLEMENT" "0" "${enforce_count}"

    teardown_test_env
}
test_phase_enforcement_hint_not_at_implement
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | grep "phase enforcement" -A2 | head -10`
Expected: FAIL (no hint exists yet)

- [ ] **Step 3: Add hint to default-triggers.json**

Use jq to add the methodology hint:

```bash
cat config/default-triggers.json | jq '
  .methodology_hints += [{
    "name": "phase-enforcement",
    "triggers": ["(fix|change|update|rename|move|add a|modify|edit|refactor|implement|write the|create the)"],
    "trigger_mode": "regex",
    "hint": "PHASE ENFORCEMENT: You are in DESIGN/PLAN phase. Complete the current phase skill before editing implementation files. Small changes still require the full flow — scaled down, not skipped.",
    "phases": ["DESIGN", "PLAN"]
  }]
' > /tmp/dt-hint.json && cp /tmp/dt-hint.json config/default-triggers.json
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | grep "phase enforcement" -A2 | head -10`
Expected: PASS for both

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 6: Update REVIEW phase_compositions.sequence with 3-step flow**

Use jq to replace the current REVIEW sequence (single requesting-code-review entry) with the full 3-step flow:

```bash
cat config/default-triggers.json | jq '
  .phase_compositions.REVIEW.sequence = [
    {
      "step": "requesting-code-review",
      "purpose": "Get BASE_SHA and HEAD_SHA. Dispatch superpowers:code-reviewer subagent with diff and plan reference. Fix critical/important issues."
    },
    {
      "step": "agent-team-review",
      "purpose": "For substantial changes (3+ files, cross-module, security-sensitive): dispatch parallel specialist reviewers alongside code-reviewer."
    },
    {
      "step": "receiving-code-review",
      "purpose": "Process reviewer findings with technical rigor. Verify claims against codebase. Push back if wrong. Fix issues one at a time."
    }
  ]
' > /tmp/dt-seq.json && cp /tmp/dt-seq.json config/default-triggers.json
```

- [ ] **Step 7: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 8: Commit**

```bash
git add config/default-triggers.json tests/test-routing.sh
git commit -m "feat: add phase-enforcement hint and REVIEW 3-step sequence"
```

### Task 4: Tighten security-scanner test assertion

**Files:**
- Modify: `tests/test-context.sh:819-826`

- [ ] **Step 1: Tighten the assertion**

In `tests/test-context.sh`, change the PARALLEL assertion in `test_security_scanner_review_parallel`:

From:
```bash
    parallel_scanner="$(printf '%s' "${context}" | grep -c 'PARALLEL:.*security-scanner' 2>/dev/null)" || parallel_scanner=0
```
To:
```bash
    parallel_scanner="$(printf '%s' "${context}" | grep -c 'PARALLEL:.*security-scanner.*Skill(security-scanner)' 2>/dev/null)" || parallel_scanner=0
```

Also update the pass/fail messages from "security-scanner in REVIEW parallel" to "security-scanner in REVIEW parallel with invoke".

- [ ] **Step 2: Run test to verify it still passes**

Run: `bash tests/test-context.sh 2>&1 | grep "security-scanner" | head -3`
Expected: PASS (the composition renders the full invoke pattern)

- [ ] **Step 3: Commit**

```bash
git add tests/test-context.sh
git commit -m "test: tighten security-scanner parallel assertion to check invoke pattern"
```

### Task 5: Regenerate fallback + final verification

**Files:**
- Modify: `config/fallback-registry.json`

- [ ] **Step 1: Regenerate fallback**

Run: `bash hooks/session-start-hook.sh < /dev/null 2>/dev/null; cp ~/.claude/.skill-registry-cache.json config/fallback-registry.json`

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -15`
Expected: All tests pass

- [ ] **Step 3: SKILL_EXPLAIN — verify DESIGN RED FLAGS appear**

```bash
echo '{"prompt":"build a new payment system for our app"}' | SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT=. bash hooks/skill-activation-hook.sh 2>&1 | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -A5 "HALT"
```
Expected: DESIGN RED FLAGS visible

- [ ] **Step 4: Commit fallback**

```bash
git add config/fallback-registry.json
git commit -m "chore: regenerate fallback registry"
```
