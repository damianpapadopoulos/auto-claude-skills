# Required Role + SDLC Chain Bridging Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate skill competition where skills should cooperate by adding composition parallels for always-on skills, a `required` role for conditional skills, and SDLC chain bridging for end-to-end phase visibility.

**Architecture:** Three independent mechanisms: (1) security-scanner moves to a plugin-less composition parallel in REVIEW (proven pattern from TDD promotion), (2) git-worktrees and agent-team-review get a new `required` role that bypasses caps when triggered, (3) `precedes`/`requires` links bridge IMPLEMENT→REVIEW→SHIP. Each mechanism is independently testable and deployable.

**Tech Stack:** Bash 3.2, jq, test harness in `tests/test-routing.sh` and `tests/test-context.sh`

**Spec:** `docs/superpowers/specs/2026-03-15-required-role-chain-bridging-design.md`

---

## Chunk 1: Security-Scanner Composition Parallel

### Task 1: Remove security-scanner from skills array and add as REVIEW composition parallel

**Files:**
- Modify: `config/default-triggers.json:217-244` (remove security-scanner skill entry)
- Modify: `config/default-triggers.json:775-794` (add parallel entry to REVIEW phase_compositions)

- [ ] **Step 1: Write the failing test in test-context.sh**

Add to `tests/test-context.sh`:

```bash
# ---------------------------------------------------------------------------
# Security-scanner should appear as REVIEW composition parallel, not scored domain
# ---------------------------------------------------------------------------
test_security_scanner_review_parallel() {
    echo "-- test: security-scanner appears as REVIEW composition parallel --"
    setup_test_env
    install_registry

    # Trigger REVIEW phase
    local output
    output="$(run_hook "review the pull request for the auth module")"
    local context
    context="$(extract_context "${output}")"

    # Security-scanner should appear in PARALLEL composition line
    local parallel_scanner
    parallel_scanner="$(printf '%s' "${context}" | grep -c 'PARALLEL:.*security-scanner' 2>/dev/null)" || parallel_scanner=0
    assert_not_equals "security-scanner in REVIEW parallel" "0" "${parallel_scanner}"

    # Security-scanner should NOT appear as a scored Domain skill
    local domain_scanner
    domain_scanner="$(printf '%s' "${context}" | grep -c 'Domain:.*security-scanner' 2>/dev/null)" || domain_scanner=0
    assert_equals "security-scanner not scored as domain" "0" "${domain_scanner}"

    teardown_test_env
}
test_security_scanner_review_parallel
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh 2>&1 | tail -20`
Expected: FAIL — security-scanner still appears as domain, not in PARALLEL

- [ ] **Step 3: Remove security-scanner from skills array in default-triggers.json**

Remove the entire skill entry at lines 217-244 (the block starting with `"name": "security-scanner"`).

- [ ] **Step 4: Add security-scanner as plugin-less parallel in REVIEW composition**

In `config/default-triggers.json`, add to `phase_compositions.REVIEW.parallel[]` (after the existing unified-context-stack entry, before the closing `]`):

```json
        {
          "use": "security-scanner -> Skill(security-scanner)",
          "when": "always",
          "purpose": "Scan for vulnerabilities, OWASP risks, compliance issues. INVOKE during every review"
        }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-context.sh 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: All tests pass. No other test should reference security-scanner as a domain skill.

- [ ] **Step 7: Commit**

```bash
git add config/default-triggers.json tests/test-context.sh
git commit -m "feat: promote security-scanner to always-on REVIEW composition parallel"
```

---

## Chunk 2: SDLC Chain Bridging

### Task 2: Add precedes/requires links bridging IMPLEMENT→REVIEW→SHIP

**Files:**
- Modify: `config/default-triggers.json:62-76` (executing-plans: add precedes)
- Modify: `config/default-triggers.json:90-102` (requesting-code-review: add precedes + requires)
- Modify: `config/default-triggers.json:116-130` (verification-before-completion: add requires)

- [ ] **Step 1: Write the failing test for end-to-end chain**

Add to `tests/test-routing.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SDLC chain bridging: end-to-end chain from brainstorming through SHIP
# ---------------------------------------------------------------------------
test_end_to_end_chain() {
    echo "-- test: end-to-end SDLC chain from brainstorming --"
    setup_test_env
    install_registry_v4

    # Set last-invoked to brainstorming so chain walks forward
    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${SESSION_TOKEN}"

    local output
    output="$(run_hook "let's design a new authentication module")"
    local context
    context="$(extract_context "${output}")"

    # Chain should include all 7 steps
    local chain_steps
    chain_steps="$(printf '%s' "${context}" | grep -c 'Step [0-9]' 2>/dev/null)" || chain_steps=0
    assert_equals "chain has 7 steps" "7" "${chain_steps}"

    # Verify key chain members are present
    assert_contains "chain includes requesting-code-review" "requesting-code-review" "${context}"
    assert_contains "chain includes verification-before-completion" "verification-before-completion" "${context}"

    teardown_test_env
}
test_end_to_end_chain
```

- [ ] **Step 2: Write failing test for mid-chain entry at REVIEW**

Add to `tests/test-routing.sh`:

```bash
test_mid_chain_entry_review() {
    echo "-- test: mid-chain entry at REVIEW shows DONE for prior steps --"
    setup_test_env
    install_registry_v4

    # Set last-invoked to executing-plans
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${SESSION_TOKEN}"

    local output
    output="$(run_hook "review this pull request")"
    local context
    context="$(extract_context "${output}")"

    # requesting-code-review should be CURRENT
    assert_contains "review is CURRENT" "CURRENT.*requesting-code-review" "${context}"
    # verification should be NEXT
    assert_contains "verification is NEXT" "NEXT.*verification-before-completion" "${context}"

    teardown_test_env
}
test_mid_chain_entry_review
```

- [ ] **Step 3: Write failing test for skipped-step markers**

Add to `tests/test-routing.sh`:

```bash
test_skipped_step_markers() {
    echo "-- test: skipped steps show DONE? marker --"
    setup_test_env
    install_registry_v4

    # Set last-invoked to executing-plans (skip review)
    printf '{"skill":"executing-plans","phase":"IMPLEMENT"}' \
        > "${HOME}/.claude/.skill-last-invoked-${SESSION_TOKEN}"

    local output
    output="$(run_hook "ship this feature, everything is ready")"
    local context
    context="$(extract_context "${output}")"

    # verification-before-completion should be CURRENT
    assert_contains "verification is CURRENT" "CURRENT.*verification-before-completion" "${context}"
    # requesting-code-review should show DONE? (skipped)
    local done_q
    done_q="$(printf '%s' "${context}" | grep -c 'DONE?.*requesting-code-review' 2>/dev/null)" || done_q=0
    assert_not_equals "review shows DONE? marker" "0" "${done_q}"

    teardown_test_env
}
test_skipped_step_markers
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | grep -E '(FAIL|test:.*chain|test:.*mid-chain|test:.*skipped)' | head -10`
Expected: FAIL for all 3 chain tests

- [ ] **Step 5: Add precedes to executing-plans**

In `config/default-triggers.json`, change `executing-plans` (line 72):

```json
      "precedes": ["requesting-code-review"],
```

- [ ] **Step 6: Add precedes and requires to requesting-code-review**

In `config/default-triggers.json`, change `requesting-code-review` (lines 100-101):

```json
      "precedes": ["verification-before-completion"],
      "requires": ["executing-plans"],
```

- [ ] **Step 7: Add requires to verification-before-completion**

In `config/default-triggers.json`, change `verification-before-completion` (line 129):

```json
      "requires": ["requesting-code-review"],
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | grep -E '(FAIL|PASS|test:.*chain|test:.*mid-chain|test:.*skipped)' | head -10`
Expected: PASS for all 3 chain tests

- [ ] **Step 9: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 10: Commit**

```bash
git add config/default-triggers.json tests/test-routing.sh
git commit -m "feat: bridge IMPLEMENT→REVIEW→SHIP in SDLC composition chain"
```

---

## Chunk 3: Required Role — Engine Changes

### Task 3: Extend SKILL_DATA extraction with required_when field

**Files:**
- Modify: `hooks/skill-activation-hook.sh:914-919`

- [ ] **Step 1: Add required_when as 9th field in SKILL_DATA jq extraction**

In `hooks/skill-activation-hook.sh`, change lines 916-918 to:

```bash
SKILL_DATA="$(printf '%s' "$REGISTRY" | jq -r '
  [.skills[] | select(.available == true and .enabled == true)] | .[] |
  (.name + "\u001f" + (.name | ascii_downcase) + "\u001f" + .role + "\u001f" +
   (.priority // 0 | tostring) + "\u001f" + (.invoke // "SKIP") + "\u001f" +
   (.phase // "") + "\u001f" + ((.triggers // []) | join("\u0001")) + "\u001f" +
   ((.keywords // []) | join("\u0001")) + "\u001f" + (.required_when // ""))
' 2>/dev/null)"
```

- [ ] **Step 2: Syntax-check the hook**

Run: `bash -n hooks/skill-activation-hook.sh`
Expected: No output (clean syntax)

- [ ] **Step 3: Run full test suite to verify no regressions**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: All tests pass (9th field is empty for all existing skills, no behavior change)

- [ ] **Step 4: Commit**

```bash
git add hooks/skill-activation-hook.sh
git commit -m "refactor: extend SKILL_DATA extraction with required_when 9th field"
```

### Task 4: Add tentative phase computation and pass 0 to _select_by_role_caps

**Files:**
- Modify: `hooks/skill-activation-hook.sh:299-380`

- [ ] **Step 1: Write the failing test for required skill bypassing workflow cap**

Add to `tests/test-routing.sh`. First, create a helper that installs a registry containing required-role skills:

```bash
install_registry_with_required() {
    local registry_file="${HOME}/.claude/.skill-registry-cache.json"
    cat > "${registry_file}" << 'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "executing-plans",
      "role": "process",
      "phase": "IMPLEMENT",
      "triggers": ["(execute.*plan|implement|continue|build|create)"],
      "trigger_mode": "regex",
      "priority": 35,
      "invoke": "Skill(superpowers:executing-plans)",
      "precedes": ["requesting-code-review"],
      "requires": ["writing-plans"],
      "available": true,
      "enabled": true
    },
    {
      "name": "using-git-worktrees",
      "role": "required",
      "phase": "IMPLEMENT",
      "triggers": ["(parallel|concurrent|worktree|isolat|branch.*(work|switch))"],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(superpowers:using-git-worktrees)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "agent-team-execution",
      "role": "workflow",
      "phase": "IMPLEMENT",
      "triggers": ["(agent.team|team.execute|parallel.team|build|create|implement)"],
      "trigger_mode": "regex",
      "priority": 22,
      "invoke": "Skill(auto-claude-skills:agent-team-execution)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "agent-team-review",
      "role": "required",
      "phase": "REVIEW",
      "required_when": "PR touches 3+ files, crosses module boundaries, or includes security-sensitive changes",
      "triggers": ["(review|pull.?request|code.?review|check.*(code|changes|diff)|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 20,
      "invoke": "Skill(auto-claude-skills:agent-team-review)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "requesting-code-review",
      "role": "process",
      "phase": "REVIEW",
      "triggers": ["(review|pull.?request|code.?review|check.*(code|changes|diff)|(^|[^a-z])pr($|[^a-z]))"],
      "trigger_mode": "regex",
      "priority": 25,
      "invoke": "Skill(superpowers:requesting-code-review)",
      "precedes": ["verification-before-completion"],
      "requires": ["executing-plans"],
      "available": true,
      "enabled": true
    },
    {
      "name": "frontend-design",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": ["(ui|frontend|component|layout|style|css)"],
      "trigger_mode": "regex",
      "priority": 15,
      "invoke": "Skill(frontend-design:frontend-design)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    },
    {
      "name": "design-debate",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": ["(design|architect|trade.?off|debate|build|create)"],
      "trigger_mode": "regex",
      "priority": 18,
      "invoke": "Skill(auto-claude-skills:design-debate)",
      "precedes": [],
      "requires": [],
      "available": true,
      "enabled": true
    }
  ],
  "phase_guide": {},
  "methodology_hints": [],
  "plugins": [],
  "phase_compositions": {}
}
REGISTRY
}
```

Then add the test:

```bash
test_required_bypasses_workflow_cap() {
    echo "-- test: required skill bypasses workflow cap --"
    setup_test_env
    install_registry_with_required

    # Trigger both worktrees (required) and agent-team-execution (workflow)
    local output
    output="$(run_hook "implement the feature using parallel worktrees")"
    local context
    context="$(extract_context "${output}")"

    # Both should appear — worktrees as Required, agent-team-execution as Workflow
    assert_contains "worktrees appears as Required" "Required:.*using-git-worktrees" "${context}"
    assert_contains "agent-team-execution appears as Workflow" "Workflow:.*agent-team-execution" "${context}"

    teardown_test_env
}
test_required_bypasses_workflow_cap
```

- [ ] **Step 2: Write failing test for conditional required showing INVOKE WHEN**

```bash
test_conditional_required_invoke_when() {
    echo "-- test: conditional required shows INVOKE WHEN tag --"
    setup_test_env
    install_registry_with_required

    local output
    output="$(run_hook "review this pull request for the auth module")"
    local context
    context="$(extract_context "${output}")"

    # agent-team-review should show INVOKE WHEN, not YES/NO or REQUIRED
    assert_contains "INVOKE WHEN tag present" "INVOKE WHEN:" "${context}"
    assert_contains "condition text present" "3+ files" "${context}"

    teardown_test_env
}
test_conditional_required_invoke_when
```

- [ ] **Step 3: Write failing test for required skill phase check**

```bash
test_required_skill_wrong_phase() {
    echo "-- test: required skill does not activate at wrong phase --"
    setup_test_env
    install_registry_with_required

    # worktrees is required at IMPLEMENT, but this prompt triggers DESIGN (no process match for IMPLEMENT)
    local output
    output="$(run_hook "design a parallel architecture for the frontend ui component")"
    local context
    context="$(extract_context "${output}")"

    # worktrees should NOT appear (IMPLEMENT required at DESIGN phase)
    local wt_count
    wt_count="$(printf '%s' "${context}" | grep -c 'using-git-worktrees' 2>/dev/null)" || wt_count=0
    assert_equals "worktrees not at wrong phase" "0" "${wt_count}"

    teardown_test_env
}
test_required_skill_wrong_phase
```

- [ ] **Step 4: Write failing test for REQUIRED eval tag**

```bash
test_required_eval_tag() {
    echo "-- test: REQUIRED eval tag present for unconditional required --"
    setup_test_env
    install_registry_with_required

    local output
    output="$(run_hook "implement the feature using parallel worktrees")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "REQUIRED tag in eval" "using-git-worktrees REQUIRED" "${context}"

    teardown_test_env
}
test_required_eval_tag
```

- [ ] **Step 5: Write failing test for required bypassing total cap**

```bash
test_required_bypasses_total_cap() {
    echo "-- test: required skill does not count against total cap --"
    setup_test_env
    install_registry_with_required

    # Trigger process + 2 domains + workflow + required = should show all 5
    local output
    output="$(run_hook "implement the feature with parallel worktrees, design the ui frontend component")"
    local context
    context="$(extract_context "${output}")"

    # Count all skill lines (Required: + Process: + Domain: + Workflow:)
    local skill_count
    skill_count="$(printf '%s' "${context}" | grep -cE '^(Required|Process|  Domain|Workflow):' 2>/dev/null)" || skill_count=0
    # Should be >= 4 (required + process + domain + workflow at minimum)
    if [[ "$skill_count" -ge 4 ]]; then
        echo "  PASS: $skill_count skills shown (required bypasses cap)"
    else
        echo "  FAIL: only $skill_count skills shown, expected >= 4"
        FAILURES=$((FAILURES + 1))
    fi
    TESTS=$((TESTS + 1))

    teardown_test_env
}
test_required_bypasses_total_cap
```

- [ ] **Step 6: Write failing test for required skills not setting PLABEL**

```bash
test_required_no_plabel() {
    echo "-- test: required skills alone do not set PLABEL --"
    setup_test_env

    # Install a minimal registry with ONLY required skills
    local registry_file="${HOME}/.claude/.skill-registry-cache.json"
    cat > "${registry_file}" << 'REGISTRY'
{
  "version": "4.0.0",
  "skills": [
    {
      "name": "using-git-worktrees",
      "role": "required",
      "phase": "IMPLEMENT",
      "triggers": ["(parallel|worktree)"],
      "trigger_mode": "regex",
      "priority": 14,
      "invoke": "Skill(superpowers:using-git-worktrees)",
      "available": true,
      "enabled": true
    }
  ],
  "phase_guide": {},
  "methodology_hints": [],
  "plugins": [],
  "phase_compositions": {}
}
REGISTRY

    local output
    output="$(run_hook "use parallel worktrees for this")"
    local context
    context="$(extract_context "${output}")"

    # PLABEL should fall back since no process/domain/workflow
    assert_contains "assess intent fallback" "assess intent" "${context}"

    teardown_test_env
}
test_required_no_plabel
```

- [ ] **Step 7: Run all new tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | grep -E '(FAIL|test:.*required|test:.*conditional|test:.*PLABEL|test:.*wrong.phase|test:.*eval.tag|test:.*total.cap)' | head -20`
Expected: FAIL for all 6 required-role tests

- [ ] **Step 8: Implement tentative phase computation**

In `hooks/skill-activation-hook.sh`, add after line 923 (after `_apply_context_bonus`), before `_select_by_role_caps`:

```bash
# --- Compute tentative phase for required-role pass 0 ---
_TENTATIVE_PHASE=""
while IFS='|' read -r _tp_score _tp_name _tp_role _tp_invoke _tp_phase; do
  [[ -z "$_tp_name" ]] && continue
  if [[ "$_tp_role" == "process" ]]; then
    _TENTATIVE_PHASE="$_tp_phase"
    break
  fi
  [[ -z "$_TENTATIVE_PHASE" ]] && _TENTATIVE_PHASE="$_tp_phase"
done <<EOF
${SORTED}
EOF
```

- [ ] **Step 9: Implement pass 0 in _select_by_role_caps**

Add the following at the start of `_select_by_role_caps()`, after the variable initializations (after line 310):

```bash
  # Pass 0: Collect required-role skills that match tentative phase.
  # These bypass all caps. Since all required skills have triggers,
  # they WILL be in SORTED when they match.
  REQUIRED_SELECTED=""
  REQUIRED_COUNT=0

  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    [[ "$role" != "required" ]] && continue
    [[ "$phase" != "${_TENTATIVE_PHASE}" ]] && continue

    REQUIRED_SELECTED="${REQUIRED_SELECTED}${score}|${name}|${role}|${invoke}|${phase}
"
    REQUIRED_COUNT=$((REQUIRED_COUNT + 1))
    [[ -n "${SKILL_EXPLAIN:-}" ]] && _EXPLAIN_CAPS="${_EXPLAIN_CAPS}[skill-hook]   [required] ${name} (${score}) <- pass 0
"
  done <<EOF
${SORTED}
EOF
```

Then modify pass 1 (the existing process reservation loop starting around line 312) to skip required skills:

In the existing loop, after `[[ -z "$name" ]] && continue`, add:
```bash
    # Skip skills already selected in pass 0
    printf '%s' "$REQUIRED_SELECTED" | grep -q "|${name}|" && continue
```

Apply the same skip in pass 2 (the main selection loop starting around line 330), after `[[ -z "$name" ]] && continue`:
```bash
    # Skip skills already selected in pass 0
    printf '%s' "$REQUIRED_SELECTED" | grep -q "|${name}|" && continue
```

Change the cap check in pass 2 from `TOTAL_COUNT` to a `CAPPED_COUNT`:
- After pass 2 completes, prepend REQUIRED_SELECTED to SELECTED:
```bash
  # Prepend required skills and update total count
  if [[ -n "$REQUIRED_SELECTED" ]]; then
    SELECTED="${REQUIRED_SELECTED}${SELECTED}"
    TOTAL_COUNT=$((TOTAL_COUNT + REQUIRED_COUNT))
  fi
```

- [ ] **Step 10: Update _build_skill_lines for required role**

In `_build_skill_lines()`, add `_SL_REQUIRED=""` alongside the other accumulators (after line 467).

In the case statement (around line 483), read the 9th field (`required_when`) from SKILL_DATA. Actually — `_build_skill_lines` iterates SELECTED which uses the `score|name|role|invoke|phase` format (5 fields). We need `required_when` from the registry. The simplest approach: look it up from SKILL_DATA by name.

Replace the role-check and eval-tag logic. Before the `while` loop, build a lookup of required_when values:

```bash
  # Build required_when lookup from SKILL_DATA (name -> required_when)
  _RW_LOOKUP=""
  while IFS="$FS" read -r _rw_name _rw_rest; do
    [[ -z "$_rw_name" ]] && continue
    # 9th field is required_when (after 8 US-delimited fields)
    _rw_val="$(printf '%s' "$_rw_rest" | awk -F "$FS" '{print $8}')"
    [[ -n "$_rw_val" ]] && _RW_LOOKUP="${_RW_LOOKUP}${_rw_name}=${_rw_val}
"
  done <<EOF
${SKILL_DATA}
EOF
```

Actually, that's too complex. Simpler: do a single jq call on REGISTRY:

```bash
  # Build required_when lookup (one jq call)
  _RW_LOOKUP="$(printf '%s' "$REGISTRY" | jq -r '
    [.skills[] | select(.required_when != null and .required_when != "")] |
    .[] | "\(.name)=\(.required_when)"
  ' 2>/dev/null)"
```

Then in the while loop, update eval tag and display line logic:

```bash
      if [[ "$role" == "process" ]]; then
        _eval_tag="MUST INVOKE"
      elif [[ "$role" == "required" ]]; then
        # Check if condition-gated
        _rw=""
        if [[ -n "$_RW_LOOKUP" ]]; then
          _rw="$(printf '%s' "$_RW_LOOKUP" | grep "^${name}=" | head -1 | cut -d= -f2-)"
        fi
        if [[ -n "$_rw" ]]; then
          _eval_tag="INVOKE WHEN: ${_rw}"
        else
          _eval_tag="REQUIRED"
        fi
      else
        _eval_tag="YES/NO"
      fi
```

And for the display line:

```bash
      if [[ -n "$PROCESS_SKILL" ]] || [[ "$role" == "required" ]]; then
        case "$role" in
          required)
            if [[ -n "$_rw" ]]; then
              _SL_REQUIRED="${_SL_REQUIRED}
Required when ${_rw}: ${name} -> ${invoke}"
            else
              _SL_REQUIRED="${_SL_REQUIRED}
Required: ${name} -> ${invoke}"
            fi
            ;;
          process)  _SL_PROCESS="
Process: ${name} -> ${invoke}" ;;
          domain)   _SL_DOMAIN="${_SL_DOMAIN}
  Domain: ${name} -> ${invoke}" ;;
          workflow) _SL_WORKFLOW="${_SL_WORKFLOW}
Workflow: ${name} -> ${invoke}" ;;
        esac
```

Update the final assembly:
```bash
    SKILL_LINES="${_SL_REQUIRED}${_SL_PROCESS}${_SL_DOMAIN}${_SL_WORKFLOW}${_SL_STANDALONE}"
```

- [ ] **Step 11: Update _determine_label_phase for required role**

In `_determine_label_phase()`, add handling for `required` role:

In the case statement (around line 394-412), add:
```bash
      required)
        HAS_REQUIRED=1
        ;;
```

Initialize `HAS_REQUIRED=0` alongside `HAS_DOMAIN` and `HAS_WORKFLOW`.

After the `+ Workflow` suffix (around line 423), add:
```bash
  [[ "$HAS_REQUIRED" -eq 1 ]] && PLABEL="${PLABEL} + Required"
```

In the phase priority section, add required after domain:
```bash
      required) [[ -z "$_PHASE_REQUIRED" ]] && _PHASE_REQUIRED="$phase" ;;
```

And update the PRIMARY_PHASE fallback chain (process > workflow > domain > required > first):
```bash
  if [[ -n "$_PHASE_PROCESS" ]]; then
    PRIMARY_PHASE="$_PHASE_PROCESS"
  elif [[ -n "$_PHASE_WORKFLOW" ]]; then
    PRIMARY_PHASE="$_PHASE_WORKFLOW"
  elif [[ -n "$_PHASE_DOMAIN" ]]; then
    PRIMARY_PHASE="$_PHASE_DOMAIN"
  elif [[ -n "$_PHASE_REQUIRED" ]]; then
    PRIMARY_PHASE="$_PHASE_REQUIRED"
  else
    PRIMARY_PHASE="$_PHASE_FIRST"
  fi
```

- [ ] **Step 12: Syntax-check the hook**

Run: `bash -n hooks/skill-activation-hook.sh`
Expected: No output (clean syntax)

- [ ] **Step 13: Run all tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: All tests pass including the 6 new required-role tests

- [ ] **Step 14: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: add required role with pass 0 bypass, tentative phase, and eval tags"
```

---

## Chunk 4: Registry Updates for Required Skills

### Task 5: Reclassify using-git-worktrees and agent-team-review in the registry

**Files:**
- Modify: `config/default-triggers.json:178-202` (using-git-worktrees)
- Modify: `config/default-triggers.json:306-333` (agent-team-review)

- [ ] **Step 1: Update using-git-worktrees**

In `config/default-triggers.json`, change the `using-git-worktrees` entry:
- `"role": "workflow"` → `"role": "required"`
- `"triggers": []` → `"triggers": ["(parallel|concurrent|worktree|isolat|branch.*(work|switch))"]`
- Update description to: `"Use git worktrees for parallel branch work. Trigger-gated required: activates when parallel/isolation keywords match."`

- [ ] **Step 2: Update agent-team-review**

In `config/default-triggers.json`, change the `agent-team-review` entry:
- `"role": "workflow"` → `"role": "required"`
- Add field: `"required_when": "PR touches 3+ files, crosses module boundaries, or includes security-sensitive changes"`
- Update description to: `"Multi-perspective parallel code review with specialist reviewers. Trigger-gated + condition-gated required."`

- [ ] **Step 3: Regenerate fallback registry**

Run: `bash hooks/session-start-hook.sh < /dev/null 2>/dev/null; cp ~/.claude/.skill-registry-cache.json config/fallback-registry.json`

If session-start doesn't run cleanly in isolation, manually copy the relevant changes from default-triggers.json to fallback-registry.json matching the same structure.

- [ ] **Step 4: Run full test suite with production registry**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 5: Run SKILL_EXPLAIN to verify routing**

Run: `echo '{"prompt":"implement the feature using parallel worktrees"}' | SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh 2>&1`
Expected: See `[required] using-git-worktrees ... <- pass 0` in explain output

- [ ] **Step 6: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json
git commit -m "feat: reclassify git-worktrees and agent-team-review to required role"
```
