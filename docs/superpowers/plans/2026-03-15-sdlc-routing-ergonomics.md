# SDLC Routing Ergonomics Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve routing accuracy by making PLAN/REVIEW reachable, adding IMPLEMENT stickiness, narrowing noisy triggers, and fixing test/registry correctness issues.

**Architecture:** Registry-only changes for trigger/priority adjustments. One engine addition (IMPLEMENT stickiness in `_apply_context_bonus`). One engine guard (`_current_idx=-1`). Test infrastructure cleanup. Fallback registry regeneration.

**Tech Stack:** Bash 3.2, jq, test harness in `tests/test-routing.sh`, `tests/test-context.sh`, `tests/test-registry.sh`

**Spec:** `docs/superpowers/specs/2026-03-15-sdlc-routing-ergonomics-design.md`

---

## Chunk 1: Fallback Registry + Test Infrastructure

### Task 1: Fix phantom test function and max_suggestions assertion

**Files:**
- Modify: `tests/test-routing.sh:2262` (remove phantom call)
- Modify: `tests/test-routing.sh:1718-1742` (fix max_suggestions assertion)

- [ ] **Step 1: Remove phantom test_skill_debug_stderr call**

In `tests/test-routing.sh`, delete line 2262 (`test_skill_debug_stderr`). The function does not exist.

- [ ] **Step 2: Fix max_suggestions assertion to count role-prefixed lines**

In `tests/test-routing.sh`, replace the assertion in `test_config_max_suggestions` (lines 1733-1734):

```bash
    # With max_suggestions=1, should have only 1 skill line (Process:/Domain:/Workflow:/Required:)
    local skill_count
    skill_count="$(printf '%s' "$ctx" | grep -cE '^(Required|Process|  Domain|Workflow):' || true)"
```

- [ ] **Step 3: Run tests to verify fix**

Run: `bash tests/test-routing.sh 2>&1 | grep "max_suggestions" -A1`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add tests/test-routing.sh
git commit -m "fix: remove phantom test function and fix max_suggestions assertion"
```

### Task 2: Regenerate fallback registry

**Files:**
- Modify: `config/fallback-registry.json`

- [ ] **Step 1: Regenerate fallback from current config**

Run: `bash hooks/session-start-hook.sh < /dev/null 2>/dev/null; cp ~/.claude/.skill-registry-cache.json config/fallback-registry.json`

If session-start doesn't run cleanly, use jq to transform default-triggers.json into fallback format with `available: false, enabled: false` defaults.

- [ ] **Step 2: Verify key fields are correct**

Run: `jq '[.skills[] | select(.name == "using-git-worktrees" or .name == "agent-team-review") | {name, role, required_when}]' config/fallback-registry.json`
Expected: git-worktrees has `role: "required"`, agent-team-review has `role: "required"` with `required_when` present.

Run: `jq '[.skills[] | select(.name == "security-scanner")] | length' config/fallback-registry.json`
Expected: `0` (removed from skills array).

Run: `jq '.skills[] | select(.name == "executing-plans") | .precedes' config/fallback-registry.json`
Expected: `["requesting-code-review"]`

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`
Expected: All tests pass (including previously-failing max_suggestions).

- [ ] **Step 4: Commit**

```bash
git add config/fallback-registry.json
git commit -m "fix: regenerate fallback registry to match current config"
```

---

## Chunk 2: Registry Trigger Changes

### Task 3: Add triggers to writing-plans and receiving-code-review

**Files:**
- Modify: `config/default-triggers.json:47-61` (writing-plans)
- Modify: `config/default-triggers.json:111-121` (receiving-code-review)

- [ ] **Step 1: Write failing test for PLAN routing**

Add to `tests/test-routing.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# writing-plans should be reachable via direct plan triggers
# ---------------------------------------------------------------------------
test_writing_plans_direct_trigger() {
    echo "-- test: direct PLAN prompt selects writing-plans --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "let's plan this out and create the task list")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "writing-plans selected" "writing-plans" "${context}"

    teardown_test_env
}
test_writing_plans_direct_trigger
```

Note: also add `"(plan( it)? out|write.*plan|implementation plan|break.?down|outline|task list|spec( it)? out)"` to the writing-plans entry in the `install_registry_v4` fixture.

- [ ] **Step 2: Write failing test for review-feedback routing**

```bash
test_receiving_code_review_trigger() {
    echo "-- test: review-feedback selects receiving-code-review --"
    setup_test_env
    install_registry_v4

    local output
    output="$(run_hook "address the review comments and fix the nits")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "receiving-code-review selected" "receiving-code-review" "${context}"

    teardown_test_env
}
test_receiving_code_review_trigger
```

Note: also add triggers and priority 33 to receiving-code-review in the `install_registry_v4` fixture.

- [ ] **Step 3: Run tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | grep -E "(direct PLAN|review-feedback)" -A1`
Expected: FAIL for both

- [ ] **Step 4: Add triggers to writing-plans in default-triggers.json**

Change `config/default-triggers.json` line 50 from `"triggers": []` to:

```json
      "triggers": [
        "(plan( it)? out|write.*plan|implementation plan|break.?down|outline|task list|spec( it)? out)"
      ],
```

- [ ] **Step 5: Add triggers and raise priority on receiving-code-review**

Change `config/default-triggers.json` lines 114 and 117:

```json
      "triggers": [
        "(review comments|pr comments|feedback|nits?|changes requested|address (the )?(review|comments|feedback)|respond to review|follow.?up review|re.?request review)"
      ],
```

And change priority from `24` to `33`.

- [ ] **Step 6: Update install_registry_v4 fixture with matching changes**

In `tests/test-routing.sh`, update the `install_registry_v4` fixture's `writing-plans` entry to add the same triggers. Update `receiving-code-review` entry to add triggers and priority 33.

- [ ] **Step 7: Run tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | grep -E "(direct PLAN|review-feedback)" -A1`
Expected: PASS for both

- [ ] **Step 8: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 9: Commit**

```bash
git add config/default-triggers.json tests/test-routing.sh
git commit -m "feat: make PLAN and review-feedback directly routable"
```

### Task 4: Narrow brainstorming, design-debate, and agent-team-execution triggers

**Files:**
- Modify: `config/default-triggers.json:25-45` (brainstorming)
- Modify: `config/default-triggers.json:319-331` (design-debate)
- Modify: `config/default-triggers.json:285-301` (agent-team-execution)

- [ ] **Step 1: Write failing test for design-debate narrowing**

```bash
test_design_debate_narrow_triggers() {
    echo "-- test: design-debate only fires on tradeoff language --"
    setup_test_env
    install_registry_v4

    # "add a new endpoint" should NOT trigger design-debate
    local output
    output="$(run_hook "add a new endpoint to the auth module")"
    local context
    context="$(extract_context "${output}")"

    local debate_count
    debate_count="$(printf '%s' "${context}" | grep -c 'design-debate' 2>/dev/null)" || debate_count=0
    assert_equals "design-debate not on generic add" "0" "${debate_count}"

    # "compare the two architecture approaches" SHOULD trigger design-debate
    output="$(run_hook "compare the two architecture approaches for the API")"
    context="$(extract_context "${output}")"
    assert_contains "design-debate on tradeoff" "design-debate" "${context}"

    teardown_test_env
}
test_design_debate_narrow_triggers
```

- [ ] **Step 2: Run test to verify first assertion fails**

Run: `bash tests/test-routing.sh 2>&1 | grep "design-debate only" -A3`
Expected: FAIL on "design-debate not on generic add"

- [ ] **Step 3: Narrow brainstorming triggers**

In `config/default-triggers.json`, replace brainstorming's single trigger (line 29) with:

```json
      "triggers": [
        "(brainstorm|design|architect|strateg|scope|outline|approach|set.?up|wire.up|how.(should|would|could))",
        "(^|[^a-z])(build|create|implement|develop|scaffold|init|bootstrap|introduce|enable|add|make|new|start)($|[^a-z])"
      ],
```

- [ ] **Step 4: Narrow design-debate triggers**

In `config/default-triggers.json`, replace design-debate's trigger (line 323) with:

```json
      "triggers": [
        "(trade.?off|debate|compare.*(option|approach|design)|weigh.*(option|approach)|pro.?con|alternative|architecture)"
      ],
```

- [ ] **Step 5: Narrow agent-team-execution triggers**

In `config/default-triggers.json`, remove the third trigger line from agent-team-execution (line 291, the `build|create|implement|develop|scaffold|add|make` one). Keep only the first two:

```json
      "triggers": [
        "(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)",
        "(execute.*plan|run.the.plan|implement.the.plan|implement.*(rest|remaining)|continue|follow.the.plan|pick.up|resume|next.task|next.step|carry.on|keep.going|where.were.we|what.s.next)"
      ],
```

- [ ] **Step 6: Update install_registry_v4 fixture with narrowed triggers**

Match the production changes in the test fixture.

- [ ] **Step 7: Run tests**

Run: `bash tests/test-routing.sh 2>&1 | grep "design-debate only" -A3`
Expected: PASS

- [ ] **Step 8: Run full test suite for regressions**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 9: Commit**

```bash
git add config/default-triggers.json tests/test-routing.sh
git commit -m "feat: narrow brainstorming, design-debate, and agent-team-execution triggers"
```

---

## Chunk 3: IMPLEMENT Stickiness + Composition Guard

### Task 5: Add IMPLEMENT stickiness rule to _apply_context_bonus

**Files:**
- Modify: `hooks/skill-activation-hook.sh:254-293`

- [ ] **Step 1: Write failing test for IMPLEMENT stickiness**

```bash
test_implement_stickiness() {
    echo "-- test: IMPLEMENT stickiness keeps phase during generic verbs --"
    setup_test_env
    install_registry_v4

    local token="test-sticky-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    # Persist last phase as IMPLEMENT
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "add error handling to the auth module")"
    local context
    context="$(extract_context "${output}")"

    # Should stay in IMPLEMENT (executing-plans), not snap to DESIGN (brainstorming)
    if printf '%s' "${context}" | grep -q 'executing-plans'; then
        _record_pass "IMPLEMENT stickiness: executing-plans selected"
    else
        _record_fail "IMPLEMENT stickiness: executing-plans selected" "got brainstorming instead"
    fi

    teardown_test_env
}
test_implement_stickiness
```

- [ ] **Step 2: Write test that stickiness respects design cues**

```bash
test_implement_stickiness_respects_design_cues() {
    echo "-- test: stickiness respects design cues --"
    setup_test_env
    install_registry_v4

    local token="test-sticky-design-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output
    output="$(run_hook "how should we architect the error handling approach?")"
    local context
    context="$(extract_context "${output}")"

    # Design cue should override stickiness — brainstorming should win
    assert_contains "design cue overrides stickiness" "brainstorming" "${context}"

    teardown_test_env
}
test_implement_stickiness_respects_design_cues
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | grep -E "(IMPLEMENT stickiness|stickiness respects)" -A1`
Expected: First FAIL, second may pass (brainstorming already wins on design keywords)

- [ ] **Step 4: Implement IMPLEMENT stickiness in _apply_context_bonus**

In `hooks/skill-activation-hook.sh`, add the following block after the existing context bonus loop (after line 292, before the closing `}`):

```bash
  # --- IMPLEMENT stickiness ---
  # If last phase was IMPLEMENT and prompt uses continuation/edit verbs
  # (not design-discovery cues), boost executing-plans above the top process skill.
  local _last_phase
  _last_phase="$(jq -r '.phase // empty' "$_signal_file" 2>/dev/null)"
  if [[ "$_last_phase" == "IMPLEMENT" ]]; then
    # Check top process phase in current SORTED
    local _top_process_phase=""
    while IFS='|' read -r _sp_score _sp_name _sp_role _sp_invoke _sp_phase; do
      [[ -z "$_sp_name" ]] && continue
      if [[ "$_sp_role" == "process" ]]; then
        _top_process_phase="$_sp_phase"
        break
      fi
    done <<EOF
${SORTED}
EOF
    if [[ "$_top_process_phase" == "DESIGN" ]] || [[ -z "$_top_process_phase" ]]; then
      # Check if prompt has continuation/edit verbs
      if [[ "$P" =~ (^|[^a-z])(add|build|create|implement|modify|change|refactor|wire.?up|connect|integrate|extend|update|rename|extract|move|replace)($|[^a-z]) ]]; then
        # Check prompt does NOT have design/discovery cues
        if ! [[ "$P" =~ (how.should|what.approach|best.way.to|ideas.for|options.for|trade.?off|compare|brainstorm|design|architect) ]]; then
          # Boost executing-plans above current top process
          local _top_score=0
          while IFS='|' read -r _bs_score _bs_name _bs_role _bs_invoke _bs_phase; do
            [[ -z "$_bs_name" ]] && continue
            [[ "$_bs_role" == "process" ]] && _top_score="$_bs_score" && break
          done <<EOF
${SORTED}
EOF
          local _sticky_score=$((_top_score + 5))
          local _sticky_sorted=""
          local _injected=0
          while IFS='|' read -r _ss_score _ss_name _ss_role _ss_invoke _ss_phase; do
            [[ -z "$_ss_name" ]] && continue
            if [[ "$_ss_name" == "executing-plans" ]]; then
              _sticky_sorted="${_sticky_sorted}${_sticky_score}|${_ss_name}|${_ss_role}|${_ss_invoke}|${_ss_phase}
"
              _injected=1
            else
              _sticky_sorted="${_sticky_sorted}${_ss_score}|${_ss_name}|${_ss_role}|${_ss_invoke}|${_ss_phase}
"
            fi
          done <<EOF
${SORTED}
EOF
          # If executing-plans wasn't in SORTED (no trigger match), inject it
          if [[ "$_injected" -eq 0 ]]; then
            local _ep_invoke
            _ep_invoke="$(printf '%s' "$REGISTRY" | jq -r '.skills[] | select(.name == "executing-plans") | .invoke // "SKIP"' 2>/dev/null)"
            _sticky_sorted="${_sticky_score}|executing-plans|process|${_ep_invoke}|IMPLEMENT
${_sticky_sorted}"
          fi
          SORTED="$(printf '%s' "$_sticky_sorted" | grep -v '^$' | sort -s -t'|' -k1 -rn)"
        fi
      fi
    fi
  fi
```

- [ ] **Step 5: Syntax check**

Run: `bash -n hooks/skill-activation-hook.sh`
Expected: No output (clean)

- [ ] **Step 6: Run stickiness tests**

Run: `bash tests/test-routing.sh 2>&1 | grep -E "(IMPLEMENT stickiness|stickiness respects)" -A1`
Expected: Both PASS

- [ ] **Step 7: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 8: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: add IMPLEMENT stickiness rule to prevent DESIGN snap-back"
```

### Task 6: Guard _current_idx=-1 in composition state

**Files:**
- Modify: `hooks/skill-activation-hook.sh:652-656` and `889-901`

- [ ] **Step 1: Write failing test for composition state guard**

```bash
test_composition_state_no_corrupt() {
    echo "-- test: missing chain anchor does not corrupt composition state --"
    setup_test_env
    install_registry_with_required

    local token="test-corrupt-session"
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"
    # Set last-invoked to a skill NOT in the registry (forces anchor miss)
    printf '{"skill":"nonexistent-skill","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    run_hook "implement the feature using parallel worktrees" >/dev/null

    local state_file="${HOME}/.claude/.skill-composition-state-${token}"
    if [[ -f "$state_file" ]]; then
        local idx
        idx="$(jq '.current_index' "$state_file" 2>/dev/null)"
        if [[ "$idx" == "-1" ]]; then
            _record_fail "composition state not corrupted" "current_index is -1"
        else
            _record_pass "composition state not corrupted"
        fi
    else
        _record_pass "composition state not corrupted (no file written)"
    fi

    teardown_test_env
}
test_composition_state_no_corrupt
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep "composition state not corrupt" -A1`

- [ ] **Step 3: Add guard after _current_idx search**

In `hooks/skill-activation-hook.sh`, after the `_current_idx` search loop (around line 675, after the `while` that finds the anchor index), add:

```bash
      # Guard: if anchor not found in chain, skip composition display and state write
      if [[ "$_current_idx" -lt 0 ]]; then
        _full_chain=""
      fi
```

This must go right before the "Batch-lookup all chain skills" block (around line 678). Setting `_full_chain=""` prevents the display block from executing (it checks `_full_chain == *"|"*`) and prevents the state write (which also checks `_full_chain`).

- [ ] **Step 4: Run test**

Run: `bash tests/test-routing.sh 2>&1 | grep "composition state not corrupt" -A1`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

- [ ] **Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "fix: guard composition state against _current_idx=-1 corruption"
```

---

## Chunk 4: Final Verification

### Task 7: Regenerate fallback registry with all changes and run SKILL_EXPLAIN checks

**Files:**
- Modify: `config/fallback-registry.json`

- [ ] **Step 1: Regenerate fallback registry**

Run: `bash hooks/session-start-hook.sh < /dev/null 2>/dev/null; cp ~/.claude/.skill-registry-cache.json config/fallback-registry.json`

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -15`
Expected: All tests pass.

- [ ] **Step 3: SKILL_EXPLAIN check — PLAN entry**

Run: `echo '{"prompt":"lets plan this out and create a task list"}' | SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT=. bash hooks/skill-activation-hook.sh 2>&1 | grep -E '(writing-plans|Result)'`
Expected: writing-plans scores > 0, appears in result.

- [ ] **Step 4: SKILL_EXPLAIN check — mid-IMPLEMENT continuation**

Run:
```bash
printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' > ~/.claude/.skill-last-invoked-$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)
echo '{"prompt":"add error handling to the auth module"}' | SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT=. bash hooks/skill-activation-hook.sh 2>&1 | grep -E '(executing-plans|brainstorming|Result)'
```
Expected: executing-plans wins over brainstorming.

- [ ] **Step 5: SKILL_EXPLAIN check — review feedback**

Run: `echo '{"prompt":"address the review comments and fix the nits"}' | SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT=. bash hooks/skill-activation-hook.sh 2>&1 | grep -E '(receiving-code-review|requesting-code-review|Result)'`
Expected: receiving-code-review wins over requesting-code-review.

- [ ] **Step 6: Commit fallback**

```bash
git add config/fallback-registry.json
git commit -m "chore: regenerate fallback registry with all routing ergonomics changes"
```
