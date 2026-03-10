# SDLC Enforcement Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the skill activation hook enforce the SDLC path (brainstorming -> writing-plans -> executing-plans) by changing instruction language from advisory to mandatory.

**Architecture:** Three changes in `_build_skill_lines()`, `_walk_composition_chain()`, and `_format_output()` — all in the same file. Build "MUST INVOKE" eval strings for process skills, remove the composition chain display gate, and strengthen format path language.

**Tech Stack:** Bash 3.2, jq, existing test harness (`tests/run-tests.sh`)

---

## Chunk 1: Phase-gated evaluation language

### Task 1: Add MUST INVOKE for process skills in `_build_skill_lines()`

**Files:**
- Modify: `hooks/skill-activation-hook.sh:460-499`
- Test: `tests/test-routing.sh` (new test + update existing)

- [ ] **Step 1: Write the failing test**

Add to `tests/test-routing.sh` before the composition chain test section (around line 1482):

```bash
# ---------------------------------------------------------------------------
# SDLC enforcement: MUST INVOKE for process skills
# ---------------------------------------------------------------------------
test_must_invoke_for_build_intent() {
    echo "-- test: build intent gets MUST INVOKE for brainstorming --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a new user dashboard")"
    context="$(extract_context "${output}")"

    assert_contains "brainstorming must invoke" "MUST INVOKE" "${context}"
    assert_not_contains "brainstorming not YES/NO" "brainstorming YES/NO" "${context}"

    teardown_test_env
}

test_must_invoke_for_debug_intent() {
    echo "-- test: debug intent gets MUST INVOKE for debugging --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "debug the authentication crash")"
    context="$(extract_context "${output}")"

    assert_contains "debugging must invoke" "MUST INVOKE" "${context}"
    assert_not_contains "debugging not YES/NO" "systematic-debugging YES/NO" "${context}"

    teardown_test_env
}

test_domain_skills_keep_yes_no() {
    echo "-- test: domain skills still have YES/NO --"
    setup_test_env
    install_registry

    local output context
    output="$(run_hook "build a secure authentication system with encryption")"
    context="$(extract_context "${output}")"

    # Process skill gets MUST INVOKE, domain gets YES/NO
    assert_contains "brainstorming must invoke" "MUST INVOKE" "${context}"
    assert_contains "domain has YES/NO" "YES/NO" "${context}"

    teardown_test_env
}

test_must_invoke_for_build_intent
test_must_invoke_for_debug_intent
test_domain_skills_keep_yes_no
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | tail -20`
Expected: FAIL — "MUST INVOKE" not found in output, "brainstorming YES/NO" still present

- [ ] **Step 3: Implement the change in `_build_skill_lines()`**

In `hooks/skill-activation-hook.sh`, modify `_build_skill_lines()` (lines 470-476). Change the EVAL_SKILLS construction to use `MUST INVOKE` for process skills and `YES/NO` for others:

```bash
      # Replace lines 470-476 (the EVAL_SKILLS construction inside the while loop)
      # Old:
      #   if [[ -n "$EVAL_SKILLS" ]]; then
      #     EVAL_SKILLS="${EVAL_SKILLS}, ${name} YES/NO"
      #   else
      #     EVAL_SKILLS="${name} YES/NO"
      #   fi

      # New:
      if [[ "$role" == "process" ]]; then
        _eval_tag="MUST INVOKE"
      else
        _eval_tag="YES/NO"
      fi
      if [[ -n "$EVAL_SKILLS" ]]; then
        EVAL_SKILLS="${EVAL_SKILLS}, ${name} ${_eval_tag}"
      else
        EVAL_SKILLS="${name} ${_eval_tag}"
      fi
```

- [ ] **Step 4: Update existing test assertions that expect old format**

In `tests/test-context.sh:280`, the test `test_single_skill_compact_format` asserts `Evaluate:` is present. This still holds — the `Evaluate:` keyword doesn't change, only the per-skill tag.

Check `tests/test-routing.sh` for any assertions on `YES/NO` for process skills. The tests at lines 1994 and 2015 assert `Evaluate:` exists — those still pass.

No existing tests assert `brainstorming YES/NO` specifically, so no updates needed.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: use MUST INVOKE for process skills instead of YES/NO"
```

---

### Task 2: Update full-format evaluation instructions

**Files:**
- Modify: `hooks/skill-activation-hook.sh:757-768`
- Test: `tests/test-context.sh` (existing test covers format)

- [ ] **Step 1: Write the failing test**

Add to `tests/test-context.sh`, after the existing format tests:

```bash
test_full_format_must_invoke_instruction() {
    echo "-- test: full format has MUST INVOKE instruction --"
    setup_test_env
    install_context_registry

    # Need 3+ skills on prompt 1 — use a prompt that triggers process + domain + workflow
    # Force prompt count to 1
    printf '1' > "${HOME}/.claude/.skill-prompt-count-${_SESSION_TOKEN:-ctx-test}"

    local output context
    output="$(run_hook "build a secure dashboard and ship it")"
    context="$(extract_context "${output}")"

    assert_contains "full format has MUST INVOKE in eval example" "MUST INVOKE" "${context}"
    assert_contains "full format Step 3 says INVOKE" "INVOKE the process skill" "${context}"
    assert_not_contains "full format Step 3 no longer says State your plan" "State your plan" "${context}"

    teardown_test_env
}

test_full_format_must_invoke_instruction
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh 2>&1 | tail -20`
Expected: FAIL — "INVOKE the process skill" not found, "State your plan" still present

- [ ] **Step 3: Implement the changes in `_format_output()`**

In `hooks/skill-activation-hook.sh`, modify the full format (lines 757-768):

```bash
    # Replace lines 762-768:
    # Old:
    #   Step 2 -- EVALUATE skills against your phase assessment.${SKILL_LINES}${COMPOSITION_CHAIN}${COMPOSITION_LINES}
    #   You MUST print a brief evaluation for each skill above. Format:
    #     **Phase: [PHASE]** | [skill1] YES/NO, [skill2] YES/NO
    #   Example: **Phase: IMPLEMENT** | test-driven-development YES, claude-md-improver NO (not editing CLAUDE.md)
    #   This line is MANDATORY -- do not skip it.
    #
    #   Step 3 -- State your plan and proceed. Keep it to 1-2 sentences.${DOMAIN_HINT}${COMPOSITION_DIRECTIVE}"

    # New:
    OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})

Step 1 -- ASSESS PHASE. Check conversation context:
${_PHASE_GUIDE}

Step 2 -- EVALUATE skills against your phase assessment.${SKILL_LINES}${COMPOSITION_CHAIN}${COMPOSITION_LINES}
You MUST print a brief evaluation for each skill above. Format:
  **Phase: [PHASE]** | [skill1] MUST INVOKE, [skill2] YES/NO
Example: **Phase: DESIGN** | brainstorming MUST INVOKE, design-debate YES (design work)
This line is MANDATORY -- do not skip it.

Step 3 -- INVOKE the process skill. Do not skip to a later phase.${DOMAIN_HINT}${COMPOSITION_DIRECTIVE}"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-context.sh
git commit -m "feat: strengthen full-format instructions to enforce SDLC phase order"
```

---

## Chunk 2: Always-on composition chain

### Task 3: Remove composition chain display gate

**Files:**
- Modify: `hooks/skill-activation-hook.sh:567-568`
- Test: `tests/test-routing.sh` (existing composition tests)

- [ ] **Step 1: Write the failing test**

Add to `tests/test-routing.sh` in the composition chain section:

```bash
test_composition_chain_single_skill_selected() {
    echo "-- test: composition chain shows even with 1 skill selected --"
    setup_test_env
    install_registry

    # Prompt that triggers only brainstorming (1 skill), but brainstorming has precedes
    local output context
    output="$(run_hook "create a simple utility function")"
    context="$(extract_context "${output}")"

    # Even with 1 selected skill, the chain should display because brainstorming has precedes
    assert_contains "single skill has Composition:" "Composition:" "${context}"
    assert_contains "single skill has NEXT marker" "[NEXT]" "${context}"
    assert_contains "single skill has IMPORTANT directive" "IMPORTANT:" "${context}"

    teardown_test_env
}

test_composition_chain_single_skill_selected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "single skill"`
Expected: FAIL — composition chain not shown when only 1 skill selected (if the prompt triggers only brainstorming without a domain co-selection)

Note: This test may actually pass if "create" also triggers design-debate (both share build-intent triggers). If it passes, adjust the prompt to be more narrow (e.g., `"outline the approach for the config change"`), or set up a custom registry with only brainstorming having triggers. The key assertion is: composition chain appears regardless of SELECTED count.

- [ ] **Step 3: Implement the change**

In `hooks/skill-activation-hook.sh`, change line 568:

```bash
    # Old (line 567-568):
    # Only emit composition if chain has 2+ skills
    if [[ "$_full_chain" == *"|"* ]]; then

    # New:
    # Emit composition for any non-empty chain (single-skill chains show the forward path)
    if [[ -n "$_full_chain" ]]; then
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh`
Expected: ALL PASS — existing `test_composition_no_chain_for_debug` should still pass because debug has no `precedes`, so `_full_chain` will be just "systematic-debugging" (still triggers display, but since there are no NEXT/LATER markers, only CURRENT shows). Wait — this changes the behavior for debug: it would now show `Composition:` with just `[CURRENT]`.

Check: `test_composition_no_chain_for_debug` asserts `assert_not_contains "Composition:"`. This test will BREAK because debug now shows a single-skill chain.

Fix: change the gate to `if [[ "$_full_chain" == *"|"* ]]; then` — this means "show chain only if there's more than 1 skill in the chain." A process skill with `precedes` will produce `brainstorming|writing-plans|executing-plans` (has pipe). A process skill without `precedes` (debug) produces just `systematic-debugging` (no pipe). So the existing gate IS correct for preventing debug from showing a chain.

**Revised understanding:** The `*"|"*` gate is actually correct. The problem must be elsewhere — the chain walk is failing in some edge case, not the gate. Let me reconsider.

The forward walk (`_fwd_chain`) for brainstorming should produce `brainstorming|writing-plans|executing-plans`. If it does, `_full_chain` has pipes and the gate passes. If it doesn't (jq error), `_full_chain` is just `brainstorming` and the gate fails silently.

**Revised approach:** Instead of removing the gate, make it fail loudly. Add a fallback: if the process skill has `precedes` in the registry but the forward walk returned no pipes, re-attempt or use a simpler chain construction.

```bash
    # After the forward walk (line 545), add a fallback:
    # If the process skill has precedes but the walk returned only itself, build chain from precedes directly
    if [[ -n "$_CHAIN_ANCHOR" ]] && [[ "$_fwd_chain" != *"|"* ]]; then
      _precedes_list="$(printf '%s' "$REGISTRY" | jq -r --arg n "$_CHAIN_ANCHOR" '
        .skills[] | select(.name == $n) | .precedes // [] | join("|")
      ' 2>/dev/null)"
      if [[ -n "$_precedes_list" ]]; then
        _fwd_chain="${_CHAIN_ANCHOR}|${_precedes_list}"
      fi
    fi
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh`
Expected: ALL PASS — `test_composition_no_chain_for_debug` passes (debug has no precedes, fallback doesn't fire). `test_composition_chain_forward` passes (chain was already working). New test passes.

- [ ] **Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: add fallback chain construction when jq walk returns single skill"
```

---

### Task 4: Ensure composition chain + directive appear in all format paths

**Files:**
- Modify: `hooks/skill-activation-hook.sh:728-778`
- Test: `tests/test-routing.sh`

- [ ] **Step 1: Write the failing test**

Add to `tests/test-routing.sh`:

```bash
test_composition_in_minimal_format() {
    echo "-- test: composition chain appears in minimal format (depth 11+) --"
    setup_test_env
    install_registry

    # Set prompt count to 12 to trigger minimal format
    printf '12' > "${HOME}/.claude/.skill-prompt-count-${_SESSION_TOKEN:-default}"

    local output context
    output="$(run_hook "build a new feature module")"
    context="$(extract_context "${output}")"

    assert_contains "minimal format has IMPORTANT directive" "IMPORTANT:" "${context}"

    teardown_test_env
}

test_composition_in_minimal_format
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "minimal format has IMPORTANT"`
Expected: FAIL — minimal format (lines 728-736) doesn't include `${COMPOSITION_CHAIN}` or `${COMPOSITION_DIRECTIVE}`

- [ ] **Step 3: Implement the change**

In `hooks/skill-activation-hook.sh`, update the minimal format (lines 728-736):

```bash
    # Old (lines 733-736):
    OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})
${SKILL_LINES}

Evaluate: **Phase: [${EVAL_PHASE}]** | ${EVAL_SKILLS}"

    # New:
    OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})
${SKILL_LINES}${COMPOSITION_CHAIN}

Evaluate: **Phase: [${EVAL_PHASE}]** | ${EVAL_SKILLS}${COMPOSITION_DIRECTIVE}"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: add composition chain and directive to minimal format path"
```

---

## Chunk 3: Verification

### Task 5: Manual end-to-end verification

- [ ] **Step 1: Build intent — verify MUST INVOKE + chain**

```bash
echo '{"prompt":"build a login system"}' | SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh 2>&1
```

Expected output contains:
- `brainstorming MUST INVOKE` (not `YES/NO`)
- `Composition: DESIGN -> PLAN -> IMPLEMENT`
- `[CURRENT] Step 1: Skill(superpowers:brainstorming)`
- `[NEXT] Step 2: Skill(superpowers:writing-plans)`
- `IMPORTANT: After completing brainstorming, invoke Skill(superpowers:writing-plans)`

- [ ] **Step 2: Debug intent — verify MUST INVOKE, no chain**

```bash
echo '{"prompt":"debug this crash in the auth module"}' | SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh 2>&1
```

Expected output contains:
- `systematic-debugging MUST INVOKE` (not `YES/NO`)
- NO `Composition:` (debug has no precedes)

- [ ] **Step 3: Zero-match — verify no regression**

```bash
echo '{"prompt":"yes lets do it"}' | bash hooks/skill-activation-hook.sh 2>&1
```

Expected: empty output (zero-match path unchanged)

- [ ] **Step 4: Run full test suite**

```bash
bash tests/run-tests.sh
```

Expected: ALL PASS, 0 failures

- [ ] **Step 5: Commit all changes**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh tests/test-context.sh
git commit -m "feat: enforce SDLC phase order with MUST INVOKE and always-on composition chain"
```

Note: If individual task commits were already made (steps 6 in tasks 1-4), this final commit is only needed if there are remaining unstaged changes.
