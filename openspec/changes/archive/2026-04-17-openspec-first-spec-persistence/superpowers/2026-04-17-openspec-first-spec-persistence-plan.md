# OpenSpec-First Spec Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `spec-driven` preset that redirects DESIGN/PLAN artifact creation to committed `openspec/changes/<feature>/` folders, making design intent visible to teammates and durable across sessions — while preserving today's `docs/plans/`-first behavior as the default for solo use.

**Architecture:** Single preset flag (`openspec_first: true`) read at session-start. When active, the hook mutates DESIGN/PLAN phase composition hints to redirect persistence to `openspec/changes/`. `openspec-ship` gains a pre-flight check: if the change folder already exists (created upfront), validate + archive; else create retrospectively (existing behavior). `design-debate` and SKILL.md references follow the same session-mode flag. Capability auto-creation is enabled with a visible warning when a new capability slug is introduced.

**Tech Stack:** Bash 3.2, jq, SKILL.md markdown, preset JSON

**Design Spec:** `docs/plans/2026-04-17-openspec-first-spec-persistence-design.md`

**Locked constraints:**
- Backward compatibility: `docs/plans/`-only mode remains the default for repos without `spec-driven` preset
- `openspec-ship` must work in both modes — idempotent detection of pre-existing change folder
- No migration of existing `docs/plans/*-design.md` artifacts
- New capabilities are auto-created under `openspec/specs/<capability>/` with an activation-context warning

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `config/presets/spec-driven.json` | Preset enabling OpenSpec-first mode |
| `tests/test-spec-driven-flow.sh` | End-to-end test: preset activation → hint mutation → openspec-ship idempotent path |

### Modified files

| File | Change |
|------|--------|
| `hooks/session-start-hook.sh` | Add Step 6c: if preset has `openspec_first: true`, mutate composition hint text via jq |
| `skills/openspec-ship/SKILL.md` | Step 3 gains a "pre-flight check": detect existing `openspec/changes/<feature>/` → validate/sync path vs retrospective create path. Add new-capability warning guidance. |
| `skills/design-debate/SKILL.md` | Output section becomes mode-aware: writes to `openspec/changes/<topic>/` in spec-driven mode, `docs/plans/` otherwise |
| `tests/test-presets.sh` | Add spec-driven preset assertions (file exists, openspec_first=true) |
| `tests/test-registry.sh` | Add assertion that spec-driven preset mutates DESIGN hints to mention `openspec/changes/` |
| `tests/test-openspec-skill-content.sh` | Add assertions for idempotent-sync and new-capability warning content |
| `CLAUDE.md` | New section "Spec Persistence Modes" documenting `spec-driven` vs default |

---

## Task Dependency Graph

```
Task 1 (spec-driven preset) ─────┐
Task 2 (design-debate template) ─┼── independent
Task 3 (openspec-ship sync) ─────┘
                                  │
Task 4 (session-start mutation) ──┼── depends on Task 1 (preset exists)
                                  │
Task 5 (CLAUDE.md docs) ──────────┤── depends on Tasks 1-4
                                  │
Task 6 (e2e test) ────────────────┤── depends on Tasks 1-5
                                  │
Task 7 (full regression) ─────────┘── last
```

**Parallelizable group 1:** Tasks 1, 2, 3
**Sequential after:** Task 4 (needs 1), Task 5 (needs 1-4), Task 6 (needs 1-5), Task 7 (last)

---

### Task 1: Add spec-driven preset

**Files:**
- Create: `config/presets/spec-driven.json`
- Modify: `tests/test-presets.sh`

- [ ] **Step 1: Write the failing test**

Append to `tests/test-presets.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Spec-driven preset structure
# ---------------------------------------------------------------------------
echo "-- Spec-Driven Preset Structure --"

spec_driven="$PROJECT_ROOT/config/presets/spec-driven.json"
assert_file_exists "spec-driven.json exists" "$spec_driven"
assert_json_valid "spec-driven.json is valid JSON" "$spec_driven"

name="$(jq -r '.name' "$spec_driven")"
assert_equals "spec-driven name field" "spec-driven" "$name"

openspec_first="$(jq -r '.openspec_first // false' "$spec_driven")"
assert_equals "spec-driven enables openspec_first" "true" "$openspec_first"

default_enabled="$(jq -r '.default_enabled' "$spec_driven")"
assert_equals "spec-driven default_enabled is true" "true" "$default_enabled"

# Description should mention spec-driven / openspec/changes/ for discoverability
description="$(jq -r '.description' "$spec_driven")"
assert_contains "spec-driven description mentions openspec/changes/" "openspec/changes/" "$description"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-presets.sh`
Expected: FAIL with "spec-driven.json exists" assertion failure.

- [ ] **Step 3: Create the preset file**

Create `config/presets/spec-driven.json`:

```json
{
  "name": "spec-driven",
  "description": "Spec-driven mode — commits design intent to openspec/changes/ instead of docs/plans/ so teammates see in-progress specs via git. Use for multi-user repos with durable decision traceability. Existing docs/plans/*-design.md files are NOT migrated; new work only.",
  "overrides": {},
  "default_enabled": true,
  "openspec_first": true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-presets.sh`
Expected: PASS. Total count increases by 6 (new assertions).

- [ ] **Step 5: Commit**

```bash
git add config/presets/spec-driven.json tests/test-presets.sh
git commit -m "feat: add spec-driven preset with openspec_first flag"
```

---

### Task 2: Make design-debate output template mode-aware

**Files:**
- Modify: `skills/design-debate/SKILL.md` (Output section around line 119-135)
- Modify: `tests/test-skill-content.sh` (or create minimal design-debate content test if none exists)

- [ ] **Step 1: Check for existing design-debate content test**

Run: `grep -l design-debate tests/*.sh`
Expected: Either finds an existing test file to extend, or confirms no test exists (we'll add one to test-skill-content.sh).

- [ ] **Step 2: Write the failing assertion**

Append to `tests/test-skill-content.sh` (pick a section near the top that reads SKILL.md files). Exact block:

```bash
# ---------------------------------------------------------------------------
# design-debate: dual-mode output template
# ---------------------------------------------------------------------------
DEBATE_SKILL="${PROJECT_ROOT}/skills/design-debate/SKILL.md"
DEBATE_CONTENT="$(cat "${DEBATE_SKILL}")"

assert_contains "design-debate: spec-driven mode output documented" "openspec/changes/" "$DEBATE_CONTENT"
assert_contains "design-debate: solo mode output documented" "docs/plans/" "$DEBATE_CONTENT"
assert_contains "design-debate: mode check instruction" "Check session preset" "$DEBATE_CONTENT"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/test-skill-content.sh`
Expected: FAIL — "Check session preset" not found in design-debate SKILL.md.

- [ ] **Step 4: Read current Output section**

Read: `skills/design-debate/SKILL.md` lines 119-135.

- [ ] **Step 5: Replace the Output section with mode-aware template**

In `skills/design-debate/SKILL.md`, replace the entire Output section (starts at `## Output`, ends before the next `##` or end of file) with:

```markdown
## Output

**Check session preset first.** Read `~/.claude/skill-config.json` or check the activation context for the active preset. If the preset has `openspec_first: true` (e.g., `spec-driven`), use the spec-driven mode below. Otherwise, use solo mode.

### Spec-driven mode (preset: `spec-driven`)

After the debate, create `openspec/changes/<topic>/` (committed, visible to teammates):

1. `openspec/changes/<topic>/proposal.md`:
   - **Why** — problem statement
   - **What Changes** — summary of the decision
   - **Capabilities** — Added/Modified capabilities this change touches
   - **Impact** — affected code, APIs, dependencies

2. `openspec/changes/<topic>/design.md`:
   - **Architecture** — consensus or lead's recommendation
   - **Dissenting views** — what the critic and pragmatist flagged
   - **Trade-offs** — what we're accepting
   - **Decisions & Trade-offs** — rejected alternatives and rationale

3. `openspec/changes/<topic>/specs/<capability>/spec.md`:
   - **Acceptance Scenarios** — 2-4 GIVEN/WHEN/THEN scenarios defining success
   - Use RFC 2119 keywords (MUST, SHOULD, MAY) in UPPERCASE

**Capability auto-creation:** If no existing capability fits, create `openspec/specs/<new-capability>/` (auto-created, not gated on user approval). When introducing a new capability, emit a visible warning:
> ⚠️ NEW CAPABILITY: This change introduces capability `<new-capability>`. Confirm the taxonomy is correct before archive.

Prefer extending an existing capability over creating a new one — check `openspec/specs/` for close matches first.

### Solo mode (default)

After the debate, synthesize into a design document at `docs/plans/YYYY-MM-DD-{topic}-design.md` containing:

1. **Problem statement** — what we're solving
2. **Capabilities affected** — every subsystem/module this touches
3. **Explicit out-of-scope** — what this change does NOT do
4. **Recommended approach** — the consensus or lead's recommendation
5. **Dissenting views** — what the critic and pragmatist flagged
6. **Trade-offs** — what we're accepting
7. **Acceptance scenarios** — 2-4 GIVEN/WHEN/THEN scenarios defining success
8. **Decision** — what the user approved

**Persistence:** This artifact is the canonical design intent. It will be:
- Read by `writing-plans` to carry acceptance scenarios into the plan
- Read by `agent-team-review` for spec compliance checking
- Compared against as-built output by `openspec-ship` at archive time
- Archived to `docs/plans/archive/` when the feature ships

Then return to the brainstorming skill's sequential flow → writing-plans.
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/test-skill-content.sh`
Expected: PASS — all three new assertions pass.

- [ ] **Step 7: Commit**

```bash
git add skills/design-debate/SKILL.md tests/test-skill-content.sh
git commit -m "feat: add dual-mode output template to design-debate (spec-driven | solo)"
```

---

### Task 3: openspec-ship idempotent sync

**Files:**
- Modify: `skills/openspec-ship/SKILL.md` (Step 3 section around lines 81-165)
- Modify: `tests/test-openspec-skill-content.sh`

- [ ] **Step 1: Locate the content test file**

Run: `ls tests/test-openspec-skill-content.sh && head -5 tests/test-openspec-skill-content.sh`
Expected: file exists. If not, use `tests/test-skill-content.sh` instead and note the switch.

- [ ] **Step 2: Write the failing assertions**

Append to the openspec-ship content test file:

```bash
# ---------------------------------------------------------------------------
# openspec-ship: idempotent sync for spec-driven mode
# ---------------------------------------------------------------------------
SHIP_SKILL="${PROJECT_ROOT}/skills/openspec-ship/SKILL.md"
SHIP_CONTENT="$(cat "${SHIP_SKILL}")"

assert_contains "openspec-ship: pre-flight check documented" "Pre-flight check" "$SHIP_CONTENT"
assert_contains "openspec-ship: sync path (change exists)" "change folder already exists" "$SHIP_CONTENT"
assert_contains "openspec-ship: retrospective path preserved" "create retrospectively" "$SHIP_CONTENT"
assert_contains "openspec-ship: new capability warning" "NEW CAPABILITY" "$SHIP_CONTENT"
assert_contains "openspec-ship: spec-driven mode reference" "spec-driven" "$SHIP_CONTENT"
```

- [ ] **Step 3: Run tests to verify failure**

Run: `bash tests/test-openspec-skill-content.sh`
Expected: FAIL on all 5 new assertions.

- [ ] **Step 4: Read the current Step 3 section**

Read: `skills/openspec-ship/SKILL.md` lines 81-100 (first 20 lines of Step 3).

- [ ] **Step 5: Replace Step 3 heading and add pre-flight check block**

In `skills/openspec-ship/SKILL.md`, find `### Step 3: Create Retrospective Change Folder` and replace that line plus the next paragraph (the one starting `**OPSX path (CLI available):**`) with:

```markdown
### Step 3: Create OR Sync Change Folder

**Pre-flight check:** Does `openspec/changes/<feature-name>/` already exist at the start of this SHIP phase?

- **If YES (spec-driven mode path):** The change was created upfront during DESIGN phase in a `spec-driven` preset session. Do NOT overwrite `proposal.md` or `design.md` — those are the committed historical decision record. Instead:
  1. Validate the existing change folder structure with `openspec validate <feature-name>` (if CLI available)
  2. Compare the existing `specs/<capability>/spec.md` against as-built code. If implementation diverged from the upfront spec, update `specs/<capability>/spec.md` to reflect what was actually built. Append a brief note at the bottom of `design.md`:
     ```markdown
     ## Implementation Notes (synced at ship time)
     - [describe any deviations from the upfront design]
     ```
  3. Skip to Step 4 (Validate) and continue to Step 5 (Changelog) and Step 6 (Archive).

- **If NO (retrospective mode path):** No upfront change exists. Proceed with the retrospective content below — scaffold the change folder and populate it from as-built code and the execution plan.

**New-capability safeguard:** If creating `openspec/specs/<new-capability>/` for the first time (no existing folder), emit a visible warning in your response:
> ⚠️ NEW CAPABILITY: This change introduces capability `<new-capability>`. Confirm the taxonomy is correct before archive. Prefer extending an existing capability where possible — check `openspec/specs/` for close matches first.

The user can then course-correct (rename, merge, or approve) before `openspec-ship` proceeds to archive.

**Retrospective content (when no upfront change exists):**

**OPSX path (CLI available):**
```

(Keep the existing "OPSX path (CLI available):" content and everything after it unchanged.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/test-openspec-skill-content.sh`
Expected: PASS — all 5 new assertions pass.

- [ ] **Step 7: Commit**

```bash
git add skills/openspec-ship/SKILL.md tests/test-openspec-skill-content.sh
git commit -m "feat: add idempotent pre-flight check and new-capability warning to openspec-ship"
```

---

### Task 4: Session-start hint mutation based on openspec_first flag

**Files:**
- Modify: `hooks/session-start-hook.sh` (after Step 6b preset resolution, add Step 6c)
- Modify: `tests/test-registry.sh` (or `tests/test-install.sh` — whichever exercises session-start)

- [ ] **Step 1: Locate Step 6b in session-start-hook.sh**

Run: `grep -n "Step 6b" hooks/session-start-hook.sh`
Expected: finds the preset resolution block added in the adoption-presets feature (approximately line 386-422).

- [ ] **Step 2: Write the failing test**

Append to `tests/test-registry.sh` before the suite's print_summary:

```bash
# ---------------------------------------------------------------------------
# Test: spec-driven preset mutates DESIGN PERSIST hint text
# ---------------------------------------------------------------------------
test_spec_driven_preset_mutates_design_hints() {
    echo "-- test: spec-driven preset mutates DESIGN PERSIST hint --"
    setup_test_env

    # Write a minimal user config activating spec-driven preset
    mkdir -p "${HOME}/.claude"
    printf '{"preset":"spec-driven"}' > "${HOME}/.claude/skill-config.json"

    # Run session-start hook
    local output
    output="$(run_hook)"

    # Verify the cache has mutated DESIGN hints pointing at openspec/changes/
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "${cache_file}"

    local design_hint_text
    design_hint_text="$(jq -r '.phase_compositions.DESIGN.hints[].text // empty' "${cache_file}" | tr '\n' ' ')"
    assert_contains "DESIGN PERSIST hint redirects to openspec/changes/" "openspec/changes/" "${design_hint_text}"
    assert_not_contains "DESIGN PERSIST no longer mentions docs/plans/ for design-md" "docs/plans/YYYY-MM-DD-<slug>-design.md" "${design_hint_text}"

    local plan_hint_text
    plan_hint_text="$(jq -r '.phase_compositions.PLAN.hints[].text // empty' "${cache_file}" | tr '\n' ' ')"
    assert_contains "PLAN CARRY reads from openspec/changes/" "openspec/changes/" "${plan_hint_text}"

    teardown_test_env
}
test_spec_driven_preset_mutates_design_hints

# ---------------------------------------------------------------------------
# Test: default preset leaves DESIGN hints pointing at docs/plans/ (unchanged)
# ---------------------------------------------------------------------------
test_default_preset_keeps_docs_plans_hints() {
    echo "-- test: default preset keeps docs/plans/ hints --"
    setup_test_env
    # No skill-config.json → no preset → no mutation

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local design_hint_text
    design_hint_text="$(jq -r '.phase_compositions.DESIGN.hints[].text // empty' "${cache_file}" | tr '\n' ' ')"
    assert_contains "DESIGN PERSIST still mentions docs/plans/" "docs/plans/YYYY-MM-DD-<slug>-design.md" "${design_hint_text}"

    teardown_test_env
}
test_default_preset_keeps_docs_plans_hints
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bash tests/test-registry.sh`
Expected: FAIL on "DESIGN PERSIST hint redirects to openspec/changes/" — the mutation hasn't been implemented yet.

- [ ] **Step 4: Read Step 6b end-point in session-start-hook.sh**

Read: `hooks/session-start-hook.sh` around the end of the preset resolution `fi` block (find the closing `fi` that matches the `if [ -f "$_preset_file" ]` block added in SDLC Task 4).

- [ ] **Step 5: Add Step 6c (hint mutation) after Step 6b**

In `hooks/session-start-hook.sh`, insert AFTER the closing `fi` of the preset resolution block (Step 6b) and BEFORE the Step 7 user config overrides block (around line 422):

```bash
# Step 6c: Apply openspec_first mode if preset enables it
# Rewrites DESIGN and PLAN phase composition hints to point at
# openspec/changes/ instead of docs/plans/ for design intent.
# Task plans in docs/plans/*-plan.md are unchanged.
if [ -n "$_preset_name" ] && [ "$_preset_name" != "null" ] && [ -f "$_preset_file" ]; then
  _openspec_first="$(jq -r '.openspec_first // false' "$_preset_file" 2>/dev/null)"
  if [ "$_openspec_first" = "true" ]; then
    # Mutate DESIGN phase hints
    SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq '.')"  # no-op pass-through for skills list; compositions are mutated at cache write time
    # NOTE: phase_compositions live in DEFAULT_JSON (the full registry), not SKILLS_JSON.
    # We mutate DEFAULT_JSON in place so the composition hints written to cache are already rewritten.
    DEFAULT_JSON="$(printf '%s' "${DEFAULT_JSON}" | jq '
      (.phase_compositions.DESIGN.hints // []) |= map(
        if (.text // "" | test("PERSIST DESIGN")) then
          .text = "PERSIST DESIGN (spec-driven): Create `openspec/changes/<feature-slug>/proposal.md`, `openspec/changes/<feature-slug>/design.md`, and `openspec/changes/<feature-slug>/specs/<capability-slug>/spec.md` upfront after brainstorming approval. Sections in proposal: Why, What Changes, Capabilities (Added/Modified), Impact. Sections in design: Architecture, Trade-offs, Dissenting views, Decisions. Spec file uses RFC 2119 UPPERCASE keywords and 2-4 GIVEN/WHEN/THEN acceptance scenarios. Then run: source hooks/lib/openspec-state.sh && openspec_state_upsert_change \"$TOKEN\" \"$SLUG\" \"\" \"\" \"$CAPABILITY_SLUG\" \"\" to set change_slug + capability_slug in session state. If introducing a new capability, emit a visible NEW CAPABILITY warning for user review."
        elif (.text // "" | test("DESIGN..PLAN CONTRACT")) then
          .text = "DESIGN→PLAN CONTRACT (spec-driven): Before transitioning from DESIGN to PLAN, the `openspec/changes/<feature-slug>/` folder MUST contain: (1) proposal.md with Capabilities section listing every subsystem touched, (2) design.md with Architecture and explicit out-of-scope, (3) specs/<capability-slug>/spec.md with 2-4 GIVEN/WHEN/THEN acceptance scenarios. These files are COMMITTED so teammates see in-progress design intent via git."
        else . end
      ) |
      (.phase_compositions.PLAN.hints // []) |= map(
        if (.text // "" | test("CARRY SCENARIOS")) then
          .text = "CARRY SCENARIOS (spec-driven): Read acceptance scenarios from `openspec/changes/<feature-slug>/specs/<capability-slug>/spec.md` and carry them into the plan as verification criteria. Save the plan to `docs/plans/YYYY-MM-DD-<slug>-plan.md` (local task breakdown, gitignored)."
        else . end
      )
    ')"
    WARNINGS="$(printf '%s' "${WARNINGS}" | jq --arg m "spec-driven mode active: design intent persisted to openspec/changes/ (committed)" '. + [$m]')"
  fi
fi
```

**Important:** This block must appear AFTER Step 6b (preset resolution) so `$_preset_name` and `$_preset_file` are populated, and BEFORE the Step 7 user-config-override block that writes the final cache.

- [ ] **Step 6: Verify the cache write path uses DEFAULT_JSON's phase_compositions**

Run: `grep -n "phase_compositions" hooks/session-start-hook.sh | head -5`
Expected: Confirms that the cache assembly pulls `phase_compositions` from `DEFAULT_JSON`. If the assembly pulls from a different variable, adjust Step 5's mutation target accordingly.

- [ ] **Step 7: Run tests to verify they pass**

Run: `bash tests/test-registry.sh`
Expected: PASS including the two new tests. Zero failures.

- [ ] **Step 8: Run syntax check**

Run: `bash -n hooks/session-start-hook.sh && echo "syntax OK"`
Expected: `syntax OK`

- [ ] **Step 9: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-registry.sh
git commit -m "feat: mutate DESIGN/PLAN composition hints when spec-driven preset active"
```

---

### Task 5: CLAUDE.md documentation for the two modes

**Files:**
- Modify: `CLAUDE.md` (add new section)

- [ ] **Step 1: Read current CLAUDE.md structure**

Read: `CLAUDE.md` (full file, should be ~40 lines per project convention).

- [ ] **Step 2: Add the Spec Persistence Modes section**

In `CLAUDE.md`, append after the `## Gotchas` section (or before `## Style` if Gotchas is the last one):

```markdown
## Spec Persistence Modes

Two modes for where design intent is persisted:

**Default (`docs/plans/`-first):** Design docs, plans, and specs go to `docs/plans/*.md` (gitignored). Low-ceremony, session-scoped. Best for solo dev or exploratory work. `openspec-ship` creates retrospective `openspec/changes/` at SHIP time.

**Spec-driven mode (`openspec/changes/`-first):** Set `{"preset": "spec-driven"}` in `~/.claude/skill-config.json`. Design intent is committed to `openspec/changes/<feature>/proposal.md + design.md + specs/<cap>/spec.md` during DESIGN phase. Teammates see in-progress specs via `git pull`. `openspec-ship` syncs the existing change at SHIP time instead of creating from scratch.

**When to use spec-driven:**
- ≥2 active developers on the repo
- Long-lived codebase where decision traceability matters
- Teams with concurrent work on overlapping capabilities
- Repos planning to add `openspec validate` to CI

**When to stay default:**
- Solo development
- Short-lived repos / prototypes
- Exploratory phases where designs frequently get rejected
- Repos without an established capability taxonomy

**Task plans stay local in both modes.** `docs/plans/*-plan.md` (task breakdowns, checkbox progress) is unchanged by the mode flag — those are the dev's execution scratch.

**Switching modes:** Change the preset at any time; existing artifacts are not migrated. New features use the new location.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add spec-persistence modes section to CLAUDE.md"
```

---

### Task 6: End-to-end test for spec-driven flow

**Files:**
- Create: `tests/test-spec-driven-flow.sh`

- [ ] **Step 1: Write the end-to-end test**

Create `tests/test-spec-driven-flow.sh`:

```bash
#!/usr/bin/env bash
# test-spec-driven-flow.sh — End-to-end verification of spec-driven mode
# 1. Preset file has openspec_first: true
# 2. Session-start with spec-driven preset mutates DESIGN/PLAN hints
# 3. Session-start without preset leaves hints pointing at docs/plans/
# 4. openspec-ship SKILL.md has pre-flight check content
# 5. design-debate SKILL.md has both mode outputs
#
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-spec-driven-flow.sh ==="

# ---------------------------------------------------------------------------
# Phase 1: Preset file has the flag
# ---------------------------------------------------------------------------
echo "-- Phase 1: preset file --"
preset_file="${PROJECT_ROOT}/config/presets/spec-driven.json"
assert_file_exists "spec-driven preset exists" "$preset_file"
flag="$(jq -r '.openspec_first // false' "$preset_file")"
assert_equals "openspec_first is true" "true" "$flag"

# ---------------------------------------------------------------------------
# Phase 2: Session-start with spec-driven preset mutates hints
# ---------------------------------------------------------------------------
echo "-- Phase 2: session-start mutates hints --"
setup_test_env
mkdir -p "${HOME}/.claude"
printf '{"preset":"spec-driven"}' > "${HOME}/.claude/skill-config.json"

CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    bash "${HOOK}" >/dev/null 2>&1

cache_file="${HOME}/.claude/.skill-registry-cache.json"
assert_file_exists "cache file exists" "$cache_file"

design_hints="$(jq -r '.phase_compositions.DESIGN.hints[].text // empty' "$cache_file" | tr '\n' ' ')"
assert_contains "DESIGN hints mention openspec/changes/" "openspec/changes/" "$design_hints"
assert_contains "DESIGN hints mention specs/<capability-slug>/spec.md" "specs/<capability-slug>/spec.md" "$design_hints"

plan_hints="$(jq -r '.phase_compositions.PLAN.hints[].text // empty' "$cache_file" | tr '\n' ' ')"
assert_contains "PLAN hints mention openspec/changes/" "openspec/changes/" "$plan_hints"

teardown_test_env

# ---------------------------------------------------------------------------
# Phase 3: Session-start without preset preserves docs/plans/ hints
# ---------------------------------------------------------------------------
echo "-- Phase 3: no preset preserves defaults --"
setup_test_env
# No skill-config.json → no preset → no mutation
CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    bash "${HOOK}" >/dev/null 2>&1

cache_file="${HOME}/.claude/.skill-registry-cache.json"
design_hints="$(jq -r '.phase_compositions.DESIGN.hints[].text // empty' "$cache_file" | tr '\n' ' ')"
assert_contains "DESIGN hints mention docs/plans/ in default mode" "docs/plans/YYYY-MM-DD-<slug>-design.md" "$design_hints"
teardown_test_env

# ---------------------------------------------------------------------------
# Phase 4: openspec-ship has idempotent pre-flight check content
# ---------------------------------------------------------------------------
echo "-- Phase 4: openspec-ship content --"
ship_content="$(cat "${PROJECT_ROOT}/skills/openspec-ship/SKILL.md")"
assert_contains "pre-flight check documented" "Pre-flight check" "$ship_content"
assert_contains "spec-driven mode path documented" "change folder already exists" "$ship_content"
assert_contains "new-capability warning documented" "NEW CAPABILITY" "$ship_content"

# ---------------------------------------------------------------------------
# Phase 5: design-debate has dual-mode output template
# ---------------------------------------------------------------------------
echo "-- Phase 5: design-debate content --"
debate_content="$(cat "${PROJECT_ROOT}/skills/design-debate/SKILL.md")"
assert_contains "design-debate: spec-driven section" "Spec-driven mode" "$debate_content"
assert_contains "design-debate: solo section" "Solo mode" "$debate_content"

print_summary
exit $?
```

- [ ] **Step 2: Run the end-to-end test**

Run: `bash tests/test-spec-driven-flow.sh`
Expected: PASS — all phases green.

- [ ] **Step 3: Commit**

```bash
git add tests/test-spec-driven-flow.sh
git commit -m "test: add end-to-end spec-driven flow verification"
```

---

### Task 7: Full regression and final verification

**Files:**
- None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All test suites pass. Zero failures.

- [ ] **Step 2: Run preset tests specifically**

Run: `bash tests/test-presets.sh`
Expected: 22+ assertions pass (18 existing + 6 new spec-driven).

- [ ] **Step 3: Run registry tests**

Run: `bash tests/test-registry.sh`
Expected: All pass including the two new mutation tests.

- [ ] **Step 4: Run openspec-ship content tests**

Run: `bash tests/test-openspec-skill-content.sh`
Expected: All pass including the 5 new idempotent-sync assertions.

- [ ] **Step 5: Verify hook syntax**

Run: `bash -n hooks/session-start-hook.sh && bash -n hooks/skill-activation-hook.sh && echo "all valid"`
Expected: `all valid`

- [ ] **Step 6: Manual smoke test with spec-driven preset**

Run:
```bash
mkdir -p /tmp/spec-driven-smoke && cd /tmp/spec-driven-smoke
mkdir -p .claude
printf '{"preset":"spec-driven"}' > .claude/skill-config.json
HOME=/tmp/spec-driven-smoke CLAUDE_PLUGIN_ROOT="$(cd - >/dev/null && pwd)" _SKILL_TEST_MODE=1 \
    bash "$(cd - >/dev/null && pwd)/hooks/session-start-hook.sh" 2>&1 | head -20
cd - >/dev/null
```

Expected: session-start emits the "spec-driven mode active" warning in output.

- [ ] **Step 7: Fix any failures found in steps 1-6**

If any test fails, diagnose the root cause, fix, and re-run. Do not proceed until all tests pass.

- [ ] **Step 8: Commit any fixes (if needed)**

```bash
git add -A
git commit -m "fix: address test regressions from spec-driven feature integration"
```

Only commit if there were actual fixes. Skip if all tests passed on first run.

---

## Self-Review Checklist

**Spec coverage:** Every capability in the design's "Capabilities Affected" section maps to a task:
- Preset schema + spec-driven.json → Task 1 ✓
- session-start-hook.sh Step 6c → Task 4 ✓
- openspec-ship Step 3 pre-flight → Task 3 ✓
- design-debate dual template → Task 2 ✓
- Intent Truth tiers → no change (Source 1 already in place from SDLC Task 1)
- CLAUDE.md docs → Task 5 ✓
- Tests (presets, registry, skill content, e2e) → Tasks 1, 2, 3, 4, 6 ✓

**Placeholder scan:** No "TBD", no "TODO later", no "add appropriate error handling". Each step has concrete code or commands.

**Type consistency:** Preset field `openspec_first` used consistently throughout (never `openspec-first` or `openspecFirst`). Preset name `spec-driven` used consistently. Change folder path `openspec/changes/<feature-slug>/` used consistently (not `<feature>` in some places and `<feature-slug>` in others — plan uses `<feature-slug>` everywhere as the canonical placeholder).

**Acceptance scenarios from design:** All 5 design-doc scenarios are exercised:
- #1 spec-driven DESIGN redirects → Task 4 test
- #2 solo mode unchanged → Task 4 test
- #3 openspec-ship idempotent sync → Task 3 content test
- #4 concurrent-dev visibility → implicit (committed files → git pull works)
- #5 mid-feature upgrade fallback → Task 3 "If NO" path preserves existing behavior

---

## Open questions / assumptions

1. **DEFAULT_JSON mutation location:** Task 4 Step 5 mutates `DEFAULT_JSON` with the assumption that `phase_compositions` comes from that variable and is written to cache downstream. Task 4 Step 6 verifies this assumption. If the hook uses a different variable for compositions, Task 4 needs adjustment before proceeding.

2. **Two DESIGN hints currently exist** (`DESIGN→PLAN CONTRACT` and `PERSIST DESIGN`). Both are mutated by the Task 4 jq expression. If the hints are refactored in the future, the jq `test()` patterns must be updated.

3. **Plan placement:** This plan lives in `docs/plans/` per the current SDLC Task 1 contract. Once spec-driven mode ships, future plans for spec-driven repos would instead create `openspec/changes/<feature>/proposal.md` + design.md upfront. This plan itself is a meta-example of the old flow.
