# Hypothesis-to-Learning Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the DISCOVER→LEARN loop by threading durable hypothesis artifacts from product-discovery through openspec-ship to outcome-review via session state and learn-baseline files.

**Architecture:** Five targeted edits to existing skills/libraries plus two composition changes. Data flows: discovery.md → session state (discovery_path) → openspec-ship (hypothesis extraction) → session state (hypotheses array) → write-learn-baseline (denormalized JSON) → outcome-review (per-hypothesis validation report). Zero Superpowers-owned files modified.

**Tech Stack:** Bash 3.2, jq, SKILL.md (markdown), JSON config files.

**Spec:** `docs/plans/2026-04-17-hypothesis-to-learning-loop-design.md`

---

### Task 1: Add `openspec_state_set_discovery_path` helper

**Files:**
- Modify: `hooks/lib/openspec-state.sh:88` (append after `openspec_state_upsert_change`)
- Test: `tests/test-openspec-state.sh` (append new test section)

- [ ] **Step 1: Write the failing test**

Append to `tests/test-openspec-state.sh`, before the `# Summary` section:

```bash
# ---------------------------------------------------------------------------
# 5. set_discovery_path creates/merges discovery_path
# ---------------------------------------------------------------------------
test_set_discovery_path_creates_entry() {
    echo "-- test: set_discovery_path creates change entry --"
    setup_test_env

    local token="test-$$"
    # No prior state — should create file and change entry
    openspec_state_set_discovery_path "$token" "my-feature" "docs/plans/2026-04-17-my-feature-discovery.md"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    assert_equals "state file exists" "true" "$([ -f "$state_file" ] && echo true || echo false)"

    local dp
    dp="$(jq -r '.changes["my-feature"].discovery_path' "$state_file" 2>/dev/null)"
    assert_equals "discovery_path set" "docs/plans/2026-04-17-my-feature-discovery.md" "$dp"

    teardown_test_env
}
test_set_discovery_path_creates_entry

test_set_discovery_path_merges_without_overwrite() {
    echo "-- test: set_discovery_path merges without overwriting existing fields --"
    setup_test_env

    local token="test-$$"
    # Pre-populate with upsert_change
    openspec_state_mark_verified "$token" "opsx-core"
    openspec_state_upsert_change "$token" "my-feature" "plans/my.md" "specs/my.md" "billing" "docs/plans/my-design.md"

    # Now set discovery_path — should merge, not overwrite
    openspec_state_set_discovery_path "$token" "my-feature" "docs/plans/my-discovery.md"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    local dp
    dp="$(jq -r '.changes["my-feature"].discovery_path' "$state_file" 2>/dev/null)"
    assert_equals "discovery_path merged" "docs/plans/my-discovery.md" "$dp"

    local design
    design="$(jq -r '.changes["my-feature"].design_path' "$state_file" 2>/dev/null)"
    assert_equals "design_path preserved after merge" "docs/plans/my-design.md" "$design"

    local plan
    plan="$(jq -r '.changes["my-feature"].plan_path' "$state_file" 2>/dev/null)"
    assert_equals "plan_path preserved after merge" "plans/my.md" "$plan"

    local verified
    verified="$(jq -r '.verification_seen' "$state_file" 2>/dev/null)"
    assert_equals "verification still intact after merge" "true" "$verified"

    teardown_test_env
}
test_set_discovery_path_merges_without_overwrite

test_set_discovery_path_noop_on_empty_token() {
    echo "-- test: set_discovery_path no-op on empty token --"
    setup_test_env

    openspec_state_set_discovery_path "" "slug" "path.md"

    local state_files
    state_files="$(ls "${HOME}/.claude/.skill-openspec-state-"* 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "no state file created on empty token" "0" "${state_files}"

    teardown_test_env
}
test_set_discovery_path_noop_on_empty_token
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-openspec-state.sh`
Expected: FAIL — `openspec_state_set_discovery_path: command not found`

- [ ] **Step 3: Write the implementation**

Append to `hooks/lib/openspec-state.sh` after the `openspec_state_upsert_change` function (after line 88), before `openspec_state_read`:

```bash
# --- openspec_state_set_discovery_path <token> <slug> <discovery_path> ---
# Set discovery_path for a change entry.
# Creates the change entry if it doesn't exist (merges with existing fields).
# Same jq-merge pattern as openspec_state_mark_verified.
openspec_state_set_discovery_path() {
    local token="${1:-}"
    local slug="${2:-}"
    local discovery_path="${3:-}"
    [ -z "$token" ] && return 0
    [ -z "$slug" ] && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    if [ -f "$state_file" ]; then
        local tmp
        tmp="$(jq --arg slug "$slug" --arg dp "$discovery_path" '
            .changes[$slug] = ((.changes[$slug] // {}) + {discovery_path: $dp})
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        jq -n --arg slug "$slug" --arg dp "$discovery_path" '{
            openspec_surface: "none",
            verification_seen: false,
            verification_at: null,
            changes: {($slug): {discovery_path: $dp}}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-openspec-state.sh`
Expected: All tests pass including the 3 new tests.

- [ ] **Step 5: Add `discovery_path` to provenance output**

In `hooks/lib/openspec-state.sh`, in the `openspec_write_provenance` function, add `discovery_path` to the jq output object. In the state-file-present branch (line 126), add after the `design_path` line:

```
                discovery_path: (.changes[$slug].discovery_path // null),
```

And in the no-state-file branch (line 148), add:

```
            discovery_path: null,
```

- [ ] **Step 6: Run full test suite to verify no regressions**

Run: `bash tests/test-openspec-state.sh`
Expected: All tests pass. The provenance test (test 4) still passes since `discovery_path` is a new additive field.

- [ ] **Step 7: Commit**

```bash
git add hooks/lib/openspec-state.sh tests/test-openspec-state.sh
git commit -m "feat: add openspec_state_set_discovery_path helper and discovery_path in provenance"
```

---

### Task 2: Add Hypotheses section to product-discovery brief

**Files:**
- Modify: `skills/product-discovery/SKILL.md:44-58` (Step 3 brief template)

- [ ] **Step 1: Write a content assertion test**

Create test assertions in a new file `tests/test-discovery-content.sh`:

```bash
#!/usr/bin/env bash
# test-discovery-content.sh — product-discovery SKILL.md content assertions
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-discovery-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/product-discovery/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# Hypotheses section exists
assert_contains "Hypotheses section header" "## Hypotheses" "${SKILL_CONTENT}"

# Structured fields documented
assert_contains "Metric field in hypothesis template" "**Metric:**" "${SKILL_CONTENT}"
assert_contains "Baseline field in hypothesis template" "**Baseline:**" "${SKILL_CONTENT}"
assert_contains "Target field in hypothesis template" "**Target:**" "${SKILL_CONTENT}"
assert_contains "Window field in hypothesis template" "**Window:**" "${SKILL_CONTENT}"

# Hypothesis ID pattern documented
assert_contains "Hypothesis H1 pattern" "### H1:" "${SKILL_CONTENT}"

# Brief still has original sections
assert_contains "Problem Statement section preserved" "**Problem Statement:**" "${SKILL_CONTENT}"
assert_contains "Acceptance Criteria section preserved" "**Acceptance Criteria:**" "${SKILL_CONTENT}"
assert_contains "Open Questions section preserved" "**Open Questions:**" "${SKILL_CONTENT}"

# Summary
echo ""
echo "=============================="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "=============================="
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '%s' "${FAIL_MESSAGES}"
    exit 1
else
    echo "All tests passed."
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-discovery-content.sh`
Expected: FAIL on "Hypotheses section header" — section doesn't exist yet.

- [ ] **Step 3: Add the Hypotheses section to the brief template**

In `skills/product-discovery/SKILL.md`, replace the Step 3 section (lines 44-58) with:

```markdown
## Step 3: Synthesize Discovery Brief

Present a structured brief covering:

### Discovery Brief

**Problem Statement:** What user pain point or business need are we addressing?

**Prior Art:** What has been tried before? What related work exists? (from Jira history, Confluence docs)

**Acceptance Criteria:** What does success look like? (from Jira tickets or user input)

**Constraints:** Known limitations — timeline, dependencies, technical constraints

**Hypotheses:**

### H1: [description]
We believe [intervention] will [outcome].
- **Metric:** [specific metric name or event, e.g., "checkout_completion_rate"]
- **Baseline:** [current value or "unknown" — can be refined during DESIGN/PLAN]
- **Target:** [directional — "increase", "decrease >20%", or specific threshold]
- **Window:** [validation timeframe — "2 weeks post-ship", "next sprint"]

Add H2, H3, etc. for additional hypotheses. All structured fields are nullable at discovery time.

**Open Questions:** What needs to be answered before design can begin?
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-discovery-content.sh`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/product-discovery/SKILL.md tests/test-discovery-content.sh
git commit -m "feat: add Hypotheses section to product-discovery brief template"
```

---

### Task 3: Add DISCOVER persistence hint to compositions

**Files:**
- Modify: `config/default-triggers.json:1144-1150` (DISCOVER hints array)
- Modify: `config/fallback-registry.json` (mirror the same change)
- Test: `tests/test-registry.sh` or inline grep assertion

- [ ] **Step 1: Write a failing test**

Add a registry content assertion. Append to `tests/test-discovery-content.sh` (before the summary block):

```bash
# --- Registry: DISCOVER persistence hint ---
REGISTRY="${PROJECT_ROOT}/config/default-triggers.json"
REGISTRY_CONTENT="$(cat "${REGISTRY}")"

assert_contains "DISCOVER persistence hint in registry" "PERSIST DISCOVERY" "${REGISTRY_CONTENT}"
assert_contains "discovery_path state write in hint" "openspec_state_set_discovery_path" "${REGISTRY_CONTENT}"

FALLBACK="${PROJECT_ROOT}/config/fallback-registry.json"
FALLBACK_CONTENT="$(cat "${FALLBACK}")"

assert_contains "DISCOVER persistence hint in fallback" "PERSIST DISCOVERY" "${FALLBACK_CONTENT}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-discovery-content.sh`
Expected: FAIL on "DISCOVER persistence hint in registry"

- [ ] **Step 3: Add the DISCOVER persistence hint to default-triggers.json**

In `config/default-triggers.json`, in the `DISCOVER.hints` array (currently has one Atlassian entry), add a second hint object after the existing one:

```json
        {
          "text": "PERSIST DISCOVERY: After product-discovery completes and the user approves the brief, save it to `docs/plans/YYYY-MM-DD-<slug>-discovery.md`. Then run: source hooks/lib/openspec-state.sh && openspec_state_set_discovery_path \"$TOKEN\" \"$SLUG\" \"$DISCOVERY_PATH\" to set discovery_path in session state.",
          "when": "always"
        }
```

- [ ] **Step 4: Mirror the same hint in fallback-registry.json**

Add the identical hint object to the `DISCOVER.hints` array in `config/fallback-registry.json`.

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-discovery-content.sh`
Expected: All tests pass.

- [ ] **Step 6: Run existing registry tests to check for regressions**

Run: `bash tests/test-registry.sh`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json tests/test-discovery-content.sh
git commit -m "feat: add PERSIST DISCOVERY hint to DISCOVER phase composition"
```

---

### Task 4: Add hypothesis extraction to openspec-ship (Step 7a-bis)

**Files:**
- Modify: `skills/openspec-ship/SKILL.md:229` (insert new step before Step 7b)
- Modify: `skills/openspec-ship/SKILL.md:231-240` (add discovery_path to Step 7b archival)

- [ ] **Step 1: Write content assertion tests**

Create `tests/test-openspec-ship-hypothesis.sh`:

```bash
#!/usr/bin/env bash
# test-openspec-ship-hypothesis.sh — hypothesis extraction content assertions
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-openspec-ship-hypothesis.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/openspec-ship/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# Step 7a-bis exists
assert_contains "Step 7a-bis header" "Step 7a-bis" "${SKILL_CONTENT}"
assert_contains "hypothesis extraction documented" "discovery_path" "${SKILL_CONTENT}"
assert_contains "hypotheses written to session state" "hypotheses" "${SKILL_CONTENT}"

# Step 7b includes discovery_path in archival
assert_contains "discovery_path in archival list" "discovery_path" "${SKILL_CONTENT}"

# Graceful skip when no discovery
assert_contains "skip when discovery absent" "Skip silently" "${SKILL_CONTENT}"

# Summary
echo ""
echo "=============================="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "=============================="
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '%s' "${FAIL_MESSAGES}"
    exit 1
else
    echo "All tests passed."
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-openspec-ship-hypothesis.sh`
Expected: FAIL on "Step 7a-bis header" — step doesn't exist yet.

- [ ] **Step 3: Insert Step 7a-bis before Step 7b**

In `skills/openspec-ship/SKILL.md`, insert the following immediately before `### Step 7b: Archive Intent Artifacts` (before line 229):

```markdown
### Step 7a-bis: Extract Hypotheses into Session State

If `discovery_path` exists in session state AND the file at that path is readable:

1. Read the `## Hypotheses` section from the discovery artifact
2. Parse each `### H<N>:` entry, extracting:
   - `id` — the hypothesis ID (e.g., "H1")
   - `description` — the prose hypothesis line ("We believe ...")
   - `metric` — from the **Metric:** field
   - `baseline` — from the **Baseline:** field
   - `target` — from the **Target:** field
   - `window` — from the **Window:** field
3. Write to session state as `changes.<slug>.hypotheses`:

```bash
# Read session state
TOKEN="$(cat ~/.claude/.skill-session-token 2>/dev/null)"
STATE_FILE="${HOME}/.claude/.skill-openspec-state-${TOKEN}"

# Extract and write hypotheses array
# (LLM constructs the JSON array from parsed markdown, then merges into state)
jq --arg slug "<slug>" --argjson hyps '<hypotheses_json_array>' '
    .changes[$slug].hypotheses = $hyps
' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
```

If `discovery_path` is absent in session state or the file is unreadable: Skip silently. `hypotheses` stays null in state. This covers sessions that entered at DEBUG or skipped discovery.
```

- [ ] **Step 4: Add discovery_path to Step 7b archival**

In the same file, update Step 7b to include `discovery_path`. Change the condition line from:

```
If `design_path`, `plan_path`, or `spec_path` exist in session state:
```

to:

```
If `discovery_path`, `design_path`, `plan_path`, or `spec_path` exist in session state:
```

And change the bash snippet from:

```bash
   for f in "$design_path" "$plan_path" "$spec_path"; do
```

to:

```bash
   for f in "$discovery_path" "$design_path" "$plan_path" "$spec_path"; do
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-openspec-ship-hypothesis.sh`
Expected: All tests pass.

- [ ] **Step 6: Run existing openspec-ship content tests**

Run: `bash tests/test-openspec-skill-content.sh`
Expected: All tests pass — new content is additive.

- [ ] **Step 7: Commit**

```bash
git add skills/openspec-ship/SKILL.md tests/test-openspec-ship-hypothesis.sh
git commit -m "feat: add hypothesis extraction step (7a-bis) and discovery_path archival to openspec-ship"
```

---

### Task 5: Add `write-learn-baseline` SHIP composition step

**Files:**
- Modify: `config/default-triggers.json:1349-1352` (SHIP sequence, after finishing-a-development-branch)
- Modify: `config/fallback-registry.json` (mirror the same change)

- [ ] **Step 1: Write a failing test**

Add registry assertions to `tests/test-discovery-content.sh` (before the summary block):

```bash
# --- Registry: write-learn-baseline SHIP step ---
assert_contains "write-learn-baseline in SHIP sequence" "write-learn-baseline" "${REGISTRY_CONTENT}"
assert_contains "write-learn-baseline in fallback" "write-learn-baseline" "${FALLBACK_CONTENT}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-discovery-content.sh`
Expected: FAIL on "write-learn-baseline in SHIP sequence"

- [ ] **Step 3: Add the composition step to default-triggers.json**

In `config/default-triggers.json`, in the `SHIP.sequence` array, add a new entry after the `finishing-a-development-branch` step (after line 1352) and before the `commit-push-pr` entry:

```json
        {
          "step": "write-learn-baseline",
          "purpose": "Write learn baseline for outcome-review. Detects ship event (merge or PR) from git state. Snapshots hypotheses from session state. Writes to ~/.claude/.skill-learn-baselines/<slug>.json. Skips silently if no ship detected (Option 3 keep / Option 4 discard)."
        },
```

- [ ] **Step 4: Mirror the same step in fallback-registry.json**

Add the identical entry to the `SHIP.sequence` array in `config/fallback-registry.json`, at the same position.

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-discovery-content.sh`
Expected: All tests pass.

- [ ] **Step 6: Run existing registry tests**

Run: `bash tests/test-registry.sh`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json tests/test-discovery-content.sh
git commit -m "feat: add write-learn-baseline step to SHIP composition sequence"
```

---

### Task 6: Update outcome-review to consume hypothesis baselines

**Files:**
- Modify: `skills/outcome-review/SKILL.md:27-29` (Step 2 baseline field names)
- Modify: `skills/outcome-review/SKILL.md:36-46` (Step 3 hypothesis-guided metrics)
- Modify: `skills/outcome-review/SKILL.md:54-74` (Step 4 report with hypothesis table)

- [ ] **Step 1: Write content assertion tests**

Create `tests/test-outcome-review-content.sh`:

```bash
#!/usr/bin/env bash
# test-outcome-review-content.sh — outcome-review hypothesis support assertions
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-outcome-review-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/outcome-review/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# Step 2 references hypotheses field
assert_contains "hypotheses field in baseline lookup" "hypotheses" "${SKILL_CONTENT}"

# Step 3 references hypothesis-guided queries
assert_contains "metric field guides queries" "metric" "${SKILL_CONTENT}"

# Step 4 has hypothesis validation table
assert_contains "Hypothesis Validation section" "Hypothesis Validation" "${SKILL_CONTENT}"
assert_contains "Status: Confirmed" "Confirmed" "${SKILL_CONTENT}"
assert_contains "Status: Not confirmed" "Not confirmed" "${SKILL_CONTENT}"
assert_contains "Status: Inconclusive" "Inconclusive" "${SKILL_CONTENT}"

# Graceful fallback when no hypotheses
assert_contains "fallback for null hypotheses" "null" "${SKILL_CONTENT}"

# Summary
echo ""
echo "=============================="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "=============================="
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '%s' "${FAIL_MESSAGES}"
    exit 1
else
    echo "All tests passed."
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-outcome-review-content.sh`
Expected: FAIL on "Hypothesis Validation section"

- [ ] **Step 3: Update Step 2 field names**

In `skills/outcome-review/SKILL.md`, replace lines 27-29:

```markdown
1. Check for a learn baseline file in `~/.claude/.skill-learn-baselines/`:
   - List files, match by feature name or branch name from the user's prompt
   - If found, use the baseline's `shipped_at`, `suggested_metrics`, and `jira_ticket` fields
```

with:

```markdown
1. Check for a learn baseline file in `~/.claude/.skill-learn-baselines/`:
   - List files, match by feature name or branch name from the user's prompt
   - If found, use the baseline's `shipped_at`, `ship_method`, `hypotheses`, and `jira_ticket` fields
   - If `ship_method` is `"pull_request"`, verify the PR was actually merged before proceeding (check `pr_url` via `gh pr view`)
```

- [ ] **Step 4: Update Step 3 with hypothesis-guided queries**

In `skills/outcome-review/SKILL.md`, add after the existing Tier 1 step 1 (line 38, after "Compare to the period before shipping"):

```markdown
   - If the baseline has non-null `hypotheses`, use each hypothesis's `metric` field to target specific events/properties instead of generic adoption queries
```

And add after the existing Tier 2 step 1 (line 50, after "Ask the user to share metrics"):

```markdown
   - If the baseline has `hypotheses`, present each hypothesis and its metric to the user: "For H1 ([description]), I need the current value of [metric]. What is it?"
```

- [ ] **Step 5: Update Step 4 report with hypothesis validation table**

In `skills/outcome-review/SKILL.md`, insert after the existing `**Assessment:**` block (after line 73) and before `**Recommendations:**`:

```markdown
**Hypothesis Validation** (when baseline has non-null `hypotheses`):

| ID | Hypothesis | Metric | Baseline | Target | Actual | Status |
|----|-----------|--------|----------|--------|--------|--------|
| H1 | [description] | [metric] | [baseline] | [target] | [measured value] | [status] |

Status values:
- `Confirmed` — Actual meets or exceeds target
- `Not confirmed` — Actual does not meet target
- `Inconclusive` — Insufficient data, or validation window has not elapsed
- `Partially confirmed` — Directionally correct but below target threshold

When `hypotheses` is null in the baseline (or no baseline found): skip this section entirely. Fall back to the existing generic metrics flow with no behavioral change.
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/test-outcome-review-content.sh`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add skills/outcome-review/SKILL.md tests/test-outcome-review-content.sh
git commit -m "feat: add hypothesis validation to outcome-review report"
```

---

### Task 7: Run full test suite and verify no regressions

**Files:**
- No new files — verification only

- [ ] **Step 1: Run all tests**

Run: `bash tests/run-tests.sh`
Expected: All test suites pass.

- [ ] **Step 2: Syntax-check modified hooks**

Run: `bash -n hooks/lib/openspec-state.sh`
Expected: Exit 0, no output.

- [ ] **Step 3: Verify registry JSON is valid**

Run: `jq '.' config/default-triggers.json > /dev/null && echo "valid" || echo "invalid"`
Expected: `valid`

Run: `jq '.' config/fallback-registry.json > /dev/null && echo "valid" || echo "invalid"`
Expected: `valid`

- [ ] **Step 4: Run the new test files specifically**

Run: `bash tests/test-discovery-content.sh && bash tests/test-openspec-ship-hypothesis.sh && bash tests/test-outcome-review-content.sh`
Expected: All pass.

- [ ] **Step 5: Commit any fixes if needed, then final commit**

If all green:
```bash
git add -A
git commit -m "test: verify hypothesis-to-learning loop integration"
```
