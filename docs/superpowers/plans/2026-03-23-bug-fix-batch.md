# Bug-Fix Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 9 confirmed bugs found during codebase audit — field count mismatch, test infrastructure issues, broad triggers, missing guards, non-atomic writes, dead code, and parser escaping.

**Architecture:** All fixes are surgical edits to existing files. No new files created (except tests). TDD: failing test first, minimal fix, verify green.

**Tech Stack:** Bash 3.2, jq, awk

**Spec:** `docs/superpowers/specs/2026-03-23-bug-fix-batch-design.md`

---

### Task 1: Complete Fix 2 — Clean fallback-registry.json ✅ (guard already applied)

The `_SKILL_TEST_MODE` guard and canary test are already in place. Remaining work: strip runtime-discovered skills from the committed fallback.

**Files:**
- Modify: `config/fallback-registry.json` — remove `test-driven-development` and `using-superpowers` entries

- [ ] **Step 1: Strip the 2 extra skills from fallback-registry.json**

```bash
jq 'del(.skills[] | select(.name == "test-driven-development" or .name == "using-superpowers"))' \
  config/fallback-registry.json > /tmp/clean-fb.json && mv /tmp/clean-fb.json config/fallback-registry.json
```

- [ ] **Step 2: Verify fallback skill names match default-triggers**

```bash
diff <(jq -r '.skills[].name' config/default-triggers.json | sort) \
     <(jq -r '.skills[].name' config/fallback-registry.json | sort)
```

Expected: no diff (exit 0).

- [ ] **Step 3: Run registry tests to confirm all pass**

```bash
bash tests/test-registry.sh 2>&1 | tail -5
```

Expected: all tests pass including "fallback skills all exist in default-triggers" and "_SKILL_TEST_MODE prevents fallback mutation".

- [ ] **Step 4: Commit Fix 1 + Fix 2 together**

```bash
git add hooks/skill-activation-hook.sh hooks/session-start-hook.sh \
       tests/test-routing.sh tests/test-registry.sh config/fallback-registry.json
git commit -m "fix: field count mismatch and fallback-registry mutation"
```

---

### Task 2: Fix 3 — Sync test registry with production

**Files:**
- Modify: `tests/test-routing.sh` — `install_registry` function (lines ~37-250)

- [ ] **Step 1: Update systematic-debugging priority from 10 to 50**

In `install_registry`, find `"name": "systematic-debugging"` and change `"priority": 10` to `"priority": 50`.

- [ ] **Step 2: Update executing-plans priority from 15 to 35**

Find `"name": "executing-plans"` and change `"priority": 15` to `"priority": 35`.

- [ ] **Step 3: Update brainstorming triggers to match production**

Replace the single monolithic trigger:
```json
"triggers": [
  "(build|create|implement|develop|scaffold|init|bootstrap|brainstorm|design|architect|strateg|scope|outline|approach|generate|set.?up|wire.up|connect|integrate|extend|new|start|introduce|enable|support|how.(should|would|could))"
]
```

With the production two-pattern form:
```json
"triggers": [
  "(brainstorm|design|architect|strateg|scope|outline|approach|set.?up|wire.up|how.(should|would|could))",
  "(^|[^a-z])(build|create|implement|develop|scaffold|init|bootstrap|introduce|enable|add|make|new|start)($|[^a-z])"
]
```

- [ ] **Step 4: Update executing-plans triggers to match production**

Replace:
```json
"triggers": [
  "(execute.*plan|run.the.plan|implement.the.plan|continue|follow.the.plan|resume|next.task|next.step)"
]
```

With:
```json
"triggers": [
  "(execute.*plan|run.the.plan|implement.the.plan|implement.*(rest|remaining)|continue|follow.the.plan|pick.up|resume|next.task|next.step|carry.on|keep.going|where.were.we|what.s.next)"
]
```

- [ ] **Step 5: Run full routing tests**

```bash
bash tests/test-routing.sh 2>&1 | tail -5
```

Expected: all 270+ tests pass. Some tests may need score adjustments due to priority changes — fix any failures by updating expected values.

- [ ] **Step 6: Commit**

```bash
git add tests/test-routing.sh
git commit -m "fix: sync test registry priorities and triggers with production"
```

---

### Task 3: Fix 4 — Tighten overly broad triggers

**Files:**
- Modify: `config/default-triggers.json` — outcome-review and product-discovery trigger patterns
- Modify: `config/fallback-registry.json` — same changes
- Modify: `tests/test-routing.sh` — add false-positive guard tests and update install_registry

- [ ] **Step 1: Write failing false-positive tests**

Add to `tests/test-routing.sh` before `print_summary`:

```bash
test_measure_false_positive_guard() {
    echo "-- test: measure does not false-fire outcome-review --"
    setup_test_env
    install_registry
    # "measure the width" is an IMPLEMENT prompt, not LEARN
    local output ctx
    output="$(run_hook "measure the width of the sidebar component")"
    ctx="$(extract_context "${output}")"
    assert_not_contains "measure impl prompt -> not outcome-review" "outcome-review" "${ctx}"
    teardown_test_env
}

test_discover_false_positive_guard() {
    echo "-- test: discover does not false-fire product-discovery --"
    setup_test_env
    install_registry
    # "I discovered a bug" is a DEBUG prompt, not DISCOVER
    local output ctx
    output="$(run_hook "I discovered a bug in the parser module")"
    ctx="$(extract_context "${output}")"
    assert_not_contains "discovered bug -> not product-discovery" "product-discovery" "${ctx}"
    teardown_test_env
}
```

- [ ] **Step 2: Run tests to verify they fail (RED)**

```bash
bash tests/test-routing.sh 2>&1 | grep -E "(measure does not|discover does not)"
```

Expected: FAIL for both.

- [ ] **Step 3: Tighten outcome-review trigger in default-triggers.json**

Replace the outcome-review trigger:
```json
"(how.did.*(perform|do|go|work)|outcome|adoption|funnel|cohort|experiment.result|feature.impact|post.launch|post.ship|measure|did.it.work)"
```
With:
```json
"(how.did.*(perform|do|go|work)|outcome|adoption|funnel|cohort|experiment.result|feature.impact|post.launch|post.ship|measur(e|ing).*(impact|outcome|metric|adoption|success|result)|did.it.work)"
```

- [ ] **Step 4: Tighten product-discovery first trigger in default-triggers.json**

Replace:
```json
"(discover|user.problem|pain.point|what.to.build|what.should.we|which.issue)"
```
With:
```json
"(discovery|discover(y|.session|.brief)|user.problem|pain.point|what.to.build|what.should.we|which.issue)"
```

- [ ] **Step 5: Apply same trigger changes to fallback-registry.json**

Use `jq` to update the triggers in `config/fallback-registry.json` to match.

- [ ] **Step 6: Update install_registry in test-routing.sh**

Update the outcome-review and product-discovery trigger patterns in the test fixture to match the new production patterns.

- [ ] **Step 7: Run tests to verify they pass (GREEN)**

```bash
bash tests/test-routing.sh 2>&1 | grep -E "(measure does not|discover does not|DISCOVER trigger|LEARN trigger)"
```

Expected: all PASS. Also verify DISCOVER and LEARN routing tests still pass.

- [ ] **Step 8: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json tests/test-routing.sh
git commit -m "fix: tighten overly broad triggers for outcome-review and product-discovery"
```

---

### Task 4: Fix 5 — Hints filter asymmetry

**Files:**
- Modify: `hooks/skill-activation-hook.sh:1198-1200`
- Modify: `tests/test-context.sh` — add test for plugin-independent hint

- [ ] **Step 1: Write failing test in test-context.sh**

Add a test that creates a registry with a plugin-independent hint (no `.plugin` field) and verifies it appears in output. Find where context tests add phase_composition tests and add:

```bash
echo "-- test: plugin-independent hint not dropped --"
# Create a registry with a hint that has no .plugin field
# Verify the hint text appears in the output
```

- [ ] **Step 2: Verify test fails (RED)**

- [ ] **Step 3: Fix the jq filter in skill-activation-hook.sh:1198-1200**

Replace:
```jq
(.hints // [] | .[] |
    select(.plugin as $p | $avail | any(. == $p)) |
    "HINT:\(.text)")
```
With:
```jq
(.hints // [] | .[] |
    if .plugin then
      select(.plugin as $p | $avail | any(. == $p)) |
      "HINT:\(.text)"
    else
      "HINT:\(.text)"
    end)
```

- [ ] **Step 4: Verify test passes (GREEN)**

- [ ] **Step 5: Run full test suite**

```bash
bash tests/run-tests.sh 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-context.sh
git commit -m "fix: hints filter asymmetry — allow plugin-independent hints"
```

---

### Task 5: Fix 6 — Non-atomic cache writes + JSON injection

**Files:**
- Modify: `hooks/session-start-hook.sh:772,783,788` — atomic write pattern
- Modify: `hooks/skill-activation-hook.sh:963-964` — jq for signal file

- [ ] **Step 1: Replace cache write at session-start-hook.sh:772**

Replace:
```bash
printf '%s' "${RESULT}" | jq '.registry' > "${CACHE_FILE}"
```
With:
```bash
printf '%s' "${RESULT}" | jq '.registry' > "${CACHE_FILE}.tmp.$$" && mv "${CACHE_FILE}.tmp.$$" "${CACHE_FILE}"
```

- [ ] **Step 2: Replace fallback write at session-start-hook.sh:783**

Replace:
```bash
printf '%s\n' "${_new_fallback}" > "${_FALLBACK}" 2>/dev/null || {
```
With:
```bash
printf '%s\n' "${_new_fallback}" > "${_FALLBACK}.tmp.$$" 2>/dev/null && mv "${_FALLBACK}.tmp.$$" "${_FALLBACK}" 2>/dev/null || {
```

Apply the same pattern to line 788.

- [ ] **Step 3: Replace printf JSON with jq in skill-activation-hook.sh:963-964**

Replace:
```bash
printf '{"skill":"%s","phase":"%s"}' "$_top_skill" "$_top_phase" \
    > "${HOME}/.claude/.skill-last-invoked-${_SESSION_TOKEN}" 2>/dev/null || true
```
With:
```bash
jq -n --arg s "$_top_skill" --arg p "$_top_phase" '{skill:$s,phase:$p}' \
    > "${HOME}/.claude/.skill-last-invoked-${_SESSION_TOKEN}" 2>/dev/null || true
```

- [ ] **Step 4: Run full test suite**

```bash
bash tests/run-tests.sh 2>&1 | tail -10
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start-hook.sh hooks/skill-activation-hook.sh
git commit -m "fix: atomic cache writes and proper JSON escaping in signal file"
```

---

### Task 6: Fix 7 — Dead code + unknown role fallthrough + grep -qF

**Files:**
- Modify: `hooks/skill-activation-hook.sh:646` — remove `COMPOSITION_NEXT`
- Modify: `hooks/skill-activation-hook.sh:419-461` — add default case
- Modify: `hooks/skill-activation-hook.sh` — `grep -q` → `grep -qF` (multiple lines)
- Modify: `hooks/session-start-hook.sh:233-236` — remove `SOURCE_COUNT`

- [ ] **Step 1: Remove COMPOSITION_NEXT dead variable (line 646)**

Delete the line `COMPOSITION_NEXT=""`.

- [ ] **Step 2: Remove SOURCE_COUNT dead code (session-start-hook.sh:233-236)**

Delete the 4 lines computing `SOURCE_COUNT`.

- [ ] **Step 3: Add default case to role-cap selection (skill-activation-hook.sh)**

After the `workflow)` case block (before `esac`), add:
```bash
      *)
        # Unknown role — skip to prevent bypassing caps
        continue
        ;;
```

- [ ] **Step 4: Replace grep -q with grep -qF for literal skill-name matching**

In `skill-activation-hook.sh`, change these patterns:
- `grep -q "|${name}|"` → `grep -qF "|${name}|"`
- `grep -q "|${hint_skill}|"` → `grep -qF "|${hint_skill}|"`

In `session-start-hook.sh`, change:
- `grep -q "^${skill_name}|"` → `grep -qF "${skill_name}|"` (note: -F can't anchor to ^, use string match instead or keep as-is since skill names are safe)

Actually, for the session-start grep at line 219, skill names from `basename` are filesystem-safe. The `-qF` is most important in the activation hook where user-configured skills could have unusual names. Change only activation-hook greps.

- [ ] **Step 5: Run full test suite**

```bash
bash tests/run-tests.sh 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh hooks/session-start-hook.sh
git commit -m "fix: remove dead code, add unknown-role guard, use grep -qF"
```

---

### Task 7: Fix 8 — Missing keywords field + compact-recovery fail-open

**Files:**
- Modify: `config/default-triggers.json` — add `keywords: []` to security-scanner
- Modify: `config/fallback-registry.json` — same
- Modify: `hooks/compact-recovery-hook.sh` — add trap

- [ ] **Step 1: Add keywords field to security-scanner in default-triggers.json**

Find the `security-scanner` entry and add `"keywords": []` after the triggers field.

- [ ] **Step 2: Apply same change to fallback-registry.json**

- [ ] **Step 3: Add fail-open trap to compact-recovery-hook.sh**

Add after the shebang/header:
```bash
trap 'exit 0' ERR
```

- [ ] **Step 4: Syntax check**

```bash
bash -n hooks/compact-recovery-hook.sh && echo "OK"
```

- [ ] **Step 5: Run full test suite**

```bash
bash tests/run-tests.sh 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json hooks/compact-recovery-hook.sh
git commit -m "fix: add missing keywords field and fail-open trap"
```

---

### Task 8: Fix 9 — Frontmatter parser backslash escaping

**Files:**
- Modify: `hooks/session-start-hook.sh` — awk parser lines 125, 144

- [ ] **Step 1: Write failing test in test-registry.sh**

Add a test that creates a SKILL.md with a backslash in a frontmatter value and verifies the frontmatter parses without error:

```bash
test_frontmatter_backslash_escaping() {
    echo "-- test: frontmatter backslash in value produces valid JSON --"
    setup_test_env
    # Create a skill with a backslash in the description
    local sp_dir="${HOME}/.claude/plugins/cache/claude-plugins-official/superpowers/1.0.0/skills"
    mkdir -p "${sp_dir}/bs-test"
    printf '---\nname: bs-test\ndescription: test\ntriggers:\n  - "foo\\\\bar"\n---\n' > "${sp_dir}/bs-test/SKILL.md"
    run_hook >/dev/null 2>&1
    local cache="${HOME}/.claude/.skill-registry-cache.json"
    assert_json_valid "cache with backslash trigger is valid JSON" "${cache}"
    teardown_test_env
}
```

- [ ] **Step 2: Verify test fails (RED)**

- [ ] **Step 3: Add backslash escaping to awk parser**

In `hooks/session-start-hook.sh`, in the `_parse_frontmatter` awk function, add `gsub(/\\/, "\\\\", val)` BEFORE the existing `gsub(/"/, "\\\"", val)` at two locations:

Line 125 (array items): Add before existing gsub:
```awk
gsub(/\\/, "\\\\", val)
```

Line 144 (scalar values): Add before existing gsub:
```awk
gsub(/\\/, "\\\\", val)
```

- [ ] **Step 4: Verify test passes (GREEN)**

- [ ] **Step 5: Run full test suite**

```bash
bash tests/run-tests.sh 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "fix: escape backslashes in frontmatter parser"
```

---

### Task 9: Final verification

- [ ] **Step 1: Run full test suite**

```bash
bash tests/run-tests.sh 2>&1
```

Expected: all test files pass, 0 failures.

- [ ] **Step 2: Syntax-check all modified hooks**

```bash
bash -n hooks/skill-activation-hook.sh && bash -n hooks/session-start-hook.sh && \
bash -n hooks/compact-recovery-hook.sh && echo "All hooks syntax OK"
```

- [ ] **Step 3: Verify git status is clean (no unexpected changes)**

```bash
git status
git log --oneline -10
```
