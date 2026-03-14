# openspec-ship Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-03-14-openspec-ship-design.md`

**Goal:** Insert an OpenSpec-native documentation skill into the SHIP phase that generates as-built change folders, validates, updates changelog, and archives — with graceful degradation when the CLI is absent.

**Architecture:** New workflow skill (`openspec-ship`) inserted between `verification-before-completion` and `finishing-a-development-branch` via chain walker rewire. Routing engine changes are atomic (four-field rewire + composition + phase guide + methodology hint in one commit). SKILL.md provides the full execution prompt with two-tier degradation (OPSX commands / Claude-native fallback).

**Tech Stack:** Bash 3.2 (hooks), JSON (registry config), Markdown (SKILL.md, phase doc)

---

## Chunk 1: Registry and Routing Changes

### Task 1: Add openspec-ship skill entry and rewire chain in default-triggers.json

**Files:**
- Modify: `config/default-triggers.json:130-158` (skill entries)
- Modify: `config/default-triggers.json:346-352` (phase_guide)
- Modify: `config/default-triggers.json:354` (methodology_hints array)
- Modify: `config/default-triggers.json:785-810` (phase_compositions.SHIP)

All changes in this task MUST be applied atomically in a single commit — partial application breaks the chain walker.

- [ ] **Step 1: Add openspec-ship skill entry after finishing-a-development-branch (line ~159)**

Insert this new skill entry immediately after the `finishing-a-development-branch` entry (after line 159):

```json
    {
      "name": "openspec-ship",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [
        "(document.*built|as.?built|openspec|archive.*feature|shipping.*protocol)"
      ],
      "keywords": [],
      "trigger_mode": "regex",
      "priority": 18,
      "precedes": [
        "finishing-a-development-branch"
      ],
      "requires": [
        "verification-before-completion"
      ],
      "description": "Create retrospective OpenSpec change, validate, archive, update changelog"
    },
```

- [ ] **Step 2: Rewire verification-before-completion.precedes (line 140-142)**

Change:
```json
      "precedes": [
        "finishing-a-development-branch"
      ],
```
To:
```json
      "precedes": [
        "openspec-ship"
      ],
```

- [ ] **Step 3: Rewire finishing-a-development-branch.requires (line 155-157)**

Change:
```json
      "requires": [
        "verification-before-completion"
      ],
```
To:
```json
      "requires": [
        "openspec-ship"
      ],
```

- [ ] **Step 4: Update phase_guide.SHIP (line 351)**

Change:
```json
    "SHIP": "verification-before-completion + finishing-a-development-branch",
```
To:
```json
    "SHIP": "verification-before-completion + openspec-ship + finishing-a-development-branch",
```

- [ ] **Step 5: Add openspec-ship-reminder to methodology_hints array**

Insert this entry into the `methodology_hints` array (after the last existing entry, before the closing `]`):

```json
    {
      "name": "openspec-ship-reminder",
      "triggers": [
        "(ship|merge|deploy|push|release|finish|complete|wrap.?up|finalize)"
      ],
      "trigger_mode": "regex",
      "hint": "OPENSPEC: After verification-before-completion passes, invoke openspec-ship to generate as-built documentation before committing. This is mandatory for feature shipping.",
      "phases": ["SHIP"]
    }
```

- [ ] **Step 6: Update phase_compositions.SHIP.sequence (lines 787-809)**

Replace the current `sequence` array content (lines 787-809) with:

```json
      "sequence": [
        {
          "step": "openspec-ship",
          "purpose": "Create retrospective OpenSpec change, validate, archive, update changelog"
        },
        {
          "plugin": "unified-context-stack",
          "use": "memory consolidation (annotate + memory-save)",
          "when": "installed AND any context_capability is true",
          "purpose": "Consolidate learnings via chub annotate and/or memory-save before session close"
        },
        {
          "plugin": "commit-commands",
          "use": "commands:/commit",
          "when": "installed",
          "purpose": "Execute structured commit after verification passes"
        },
        {
          "step": "finishing-a-development-branch",
          "purpose": "Branch cleanup, merge, or PR creation"
        },
        {
          "plugin": "commit-commands",
          "use": "commands:/commit-push-pr",
          "when": "installed AND user chooses PR option",
          "purpose": "Automated branch-to-PR flow"
        }
      ],
```

The `hints` array (lines 811-822) is preserved unchanged.

- [ ] **Step 7: Validate JSON**

Run: `jq empty config/default-triggers.json`
Expected: No output (valid JSON).

- [ ] **Step 8: Commit all changes atomically**

```bash
git add config/default-triggers.json
git commit -m "feat: add openspec-ship skill entry with chain rewire and methodology hint"
```

### Task 2: Add openspec-ship to label phase in skill-activation-hook.sh

**Files:**
- Modify: `hooks/skill-activation-hook.sh:412`

- [ ] **Step 1: Update the case statement**

Change line 412 from:
```bash
            verification-before-completion|finishing-a-development-branch) PLABEL="Ship / Complete" ;;
```
To:
```bash
            verification-before-completion|finishing-a-development-branch|openspec-ship) PLABEL="Ship / Complete" ;;
```

- [ ] **Step 2: Syntax check**

Run: `bash -n hooks/skill-activation-hook.sh`
Expected: No output (valid syntax).

- [ ] **Step 3: Commit**

```bash
git add hooks/skill-activation-hook.sh
git commit -m "feat: add openspec-ship to Ship / Complete label in activation hook"
```

### Task 3: Update ship-and-learn.md phase document

**Files:**
- Modify: `skills/unified-context-stack/phases/ship-and-learn.md`

- [ ] **Step 1: Insert OpenSpec documentation tier above memory consolidation**

Insert the following section AFTER the existing line 3 (`Before completing the session, consolidate what was learned.`) and BEFORE `**REQUIRED before completing session:**` (line 5):

```markdown

## REQUIRED Before Memory Consolidation: As-Built Documentation

If the session produced working code from a Superpowers plan, generate permanent "as-built" documentation before consolidating learnings:

**Tier 1: OpenSpec CLI** (`command -v openspec` succeeds)
- Execute the `openspec-ship` skill to create a retrospective change folder under `openspec/changes/<feature>/`
- Use `/opsx:propose` (default profile) to scaffold and populate with schema-native templates
- Run `openspec validate <feature>` to verify the change folder
- Update `CHANGELOG.md` under `[Unreleased]`
- Use `/opsx:archive` with delta-spec sync prompt: sync deltas to canonical `openspec/specs/<capability>/spec.md`, then move to archive

**Tier 2: Claude-Native Fallback** (OpenSpec CLI not available)
- Generate the same artifact contract using the templates in the `openspec-ship` skill
- Same change-folder structure, same filenames, same required section headings, compatible content
- Manually move change folder to `openspec/changes/archive/`. Create canonical spec only if none exists; skip canonical update with warning if one already exists

**Skip Condition:** If the session was debugging, reviewing, or performing non-feature work (no Superpowers plan was executed), skip this step entirely.

```

- [ ] **Step 2: Commit**

```bash
git add skills/unified-context-stack/phases/ship-and-learn.md
git commit -m "feat: add OpenSpec documentation tier to ship-and-learn phase document"
```

## Chunk 2: SKILL.md

### Task 4: Create skills/openspec-ship/SKILL.md

**Files:**
- Create: `skills/openspec-ship/SKILL.md`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p skills/openspec-ship
```

- [ ] **Step 2: Write the SKILL.md file**

Create `skills/openspec-ship/SKILL.md` with the full skill prompt. The file must contain:

```markdown
---
name: openspec-ship
description: Use when shipping a completed feature and generating as-built OpenSpec docs before branch finalization
---

# OpenSpec Ship — Retrospective Change Documentation

Generate permanent "as-built" OpenSpec documentation from completed code, then archive it alongside Superpowers execution artifacts.

## When to Use

Invoke this skill during the SHIP phase after `verification-before-completion` passes and before `finishing-a-development-branch`. It runs automatically as part of the SHIP composition chain.

## Hard Precondition

Before proceeding, verify that `verification-before-completion` has already run in this conversation. Look for fresh verification evidence appropriate to the project (e.g., test runner output, lint results, build confirmation — not all projects have all three). If no fresh verification evidence exists, STOP and inform the user:

> "openspec-ship requires passing verification. Invoking verification-before-completion first."

Then invoke `Skill(superpowers:verification-before-completion)` before continuing. Defer to `verification-before-completion` for the exact command set appropriate to the project.

## Input

The user should provide:
- **Required for SP artifact archival:** `plan_path` — the path to the Superpowers execution plan (e.g., `docs/superpowers/plans/2026-03-14-feature.md`). If not provided, skip SP artifact archival with warning.
- **Optional:** `feature-name` — kebab-case change name. If not provided, derive from `plan_path` by stripping the date prefix (e.g., `2026-03-14-feature.md` → `feature`). If neither is available, ask the user.

## Steps

### Step 1: Detect Environment

Run `command -v openspec` to check for CLI availability.

- **If found:** Log `"OpenSpec CLI detected. Using OPSX commands."` Record for later steps.
- **If not found:** Log `"OpenSpec CLI not detected. Proceeding with Claude-native documentation. Run 'npm install -g @fission-ai/openspec@latest' for advanced features."` Record for fallback path.

### Step 2: Derive Slugs

**Change slug (`<feature-name>`):**
- If `plan_path` is provided: strip the leading date prefix from the plan filename stem. E.g., `docs/superpowers/plans/2026-03-14-openspec-ship.md` → `openspec-ship`.
- If `plan_path` is not provided and no explicit feature name given: ask the user for a kebab-case change name. Do not guess.

**Capability slug (`<capability>`):**
- If the linked SP spec references a specific capability: use that name in kebab-case.
- If not identifiable: ask the user. Do not guess.

### Step 3: Create Retrospective Change Folder

**OPSX path (CLI available):**
1. Use `/opsx:propose <feature-name>` to create the change folder and generate all artifacts in one step.
2. IMPORTANT: Populate artifacts with **retrospective** content from the shipped codebase and SP artifacts, not forward-looking proposals. The code is already written — describe what was actually built.

**Optional expanded-profile enhancement:** If the project uses the expanded OPSX profile (via `openspec config profile` + `openspec update`), you may use `/opsx:new` + `/opsx:ff` instead. Do NOT depend on expanded-profile commands unless the project has opted in.

**Fallback path (no CLI):**

Create `openspec/changes/<feature-name>/` with:

**proposal.md:**
```
# Proposal: <Feature Name>

## Problem Statement
Why we built this. (Synthesized from SP brainstorming spec if available.)

## Proposed Solution
High-level summary of what was actually built.

## Out of Scope
What we explicitly avoided.
```

**design.md:**
```
# Design: <Feature Name>

## Architecture
Data flow, component breakdown, system diagrams reflecting the as-built state.

## Dependencies
New packages, APIs, or database changes introduced.

## Decisions & Trade-offs
Why Path A over Path B. Rejected alternatives and rationale.
(Synthesized from Superpowers brainstorming spec if available.)
```

**specs/<capability>/spec.md** (delta spec, one per capability):
```
# <Capability Name> — Delta

## ADDED Requirements

### Requirement: <Name>
<Description of the new requirement>

#### Scenario: <Name>
Given <precondition>
When <action>
Then <expected result>
```

**tasks.md** (when `plan_path` is provided):
```
# Tasks: <Feature Name>

## Completed

- [x] 1.1 <task description> (from SP execution plan)
- [x] 1.2 <task description>
```

**tasks.md** (when `plan_path` is NOT provided):
```
# Tasks: <Feature Name>

## Completed

- [x] 1.1 Retrospective tasks unavailable — no Superpowers execution plan was provided. See git log for implementation history.
```

### Step 4: Validate (CLI only)

If OpenSpec CLI was detected in Step 1:
- Run `openspec validate <feature-name>`.
- On validation failure: STOP. Report the issues for the user to resolve. Do not proceed.
- On validation success: proceed to Step 5.

If CLI is not available: skip this step.

Note: The CLI command is `openspec validate <change>`, not `openspec verify`. The `/opsx:verify` slash command exists as an expanded workflow profile but is not the base CLI command.

### Step 5: Update Changelog

1. Check for `CHANGELOG.md` in the project root.
2. If it exists with a recognizable format, append notes matching that format.
3. If it exists with Keep a Changelog format, append under `## [Unreleased]`.
4. If none exists, create a new `CHANGELOG.md` using Keep a Changelog format:
   ```
   # Changelog

   All notable changes to this project will be documented in this file.

   The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
   and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

   ## [Unreleased]
   ```
5. Categorize entries strictly into `### Added`, `### Changed`, `### Fixed`, or `### Removed`.

### Step 6: Archive & Cleanup

**Archive the change folder:**

**OPSX path (CLI available):**
Use `/opsx:archive <feature-name>`. This:
1. Checks artifact completion.
2. If delta specs exist, prompts for sync to canonical specs.
3. Moves the change folder to `openspec/changes/archive/YYYY-MM-DD-<feature-name>`.

**Fallback path (no CLI):**
1. Create `openspec/changes/archive/` if it doesn't exist.
2. Move `openspec/changes/<feature-name>/` to `openspec/changes/archive/YYYY-MM-DD-<feature-name>/`.
3. If no canonical spec exists at `openspec/specs/<capability>/spec.md`, create it from the change's delta spec.
4. If a canonical spec already exists, do NOT mutate it. Log: `"Canonical spec exists at openspec/specs/<capability>/spec.md. Skipping canonical update — use OpenSpec CLI for safe merging."`

**Enrich archive with Superpowers artifacts (when plan_path is known):**

1. Parse the `**Spec:**` line from the plan to find the linked SP spec file.
2. Create `openspec/changes/archive/YYYY-MM-DD-<feature-name>/superpowers/`.
3. Move the SP plan file and SP spec file into that `superpowers/` subdirectory.
4. Remove only the specific moved files from `docs/superpowers/`. Do not delete directories or unrelated files.

If `plan_path` is not provided: skip SP artifact archival. Log: `"No Superpowers plan path provided. Skipping SP artifact archival."`

## Graceful Degradation Summary

| OpenSpec CLI | Behavior |
|-------------|----------|
| Available | `/opsx:propose` → `openspec validate` → `/opsx:archive` |
| Not available | Claude-native templates → skip validation → manual archive. Same artifact contract (paths, filenames, section headings). |
```

- [ ] **Step 3: Commit**

```bash
git add skills/openspec-ship/SKILL.md
git commit -m "feat: add openspec-ship skill with OPSX integration and graceful degradation"
```

## Chunk 3: Test Updates

### Task 5: Update inline fixture registries in test files

**Files:**
- Modify: `tests/test-context.sh:132-163`
- Modify: `tests/test-routing.sh:149-173`
- Modify: `tests/test-routing.sh:445-467`
- Modify: `tests/test-routing.sh:559`

- [ ] **Step 1: Update test-context.sh fixture — add openspec-ship skill entry and update phase_guide**

In `tests/test-context.sh`, after the `finishing-a-development-branch` entry (line 154), add:

```json
    {
      "name": "openspec-ship",
      "role": "workflow",
      "triggers": [
        "(document.*built|as.?built|openspec|archive.*feature|shipping.*protocol)"
      ],
      "trigger_mode": "regex",
      "priority": 58,
      "precedes": ["finishing-a-development-branch"],
      "requires": ["verification-before-completion"],
      "invoke": "Skill(auto-claude-skills:openspec-ship)",
      "available": true,
      "enabled": true
    },
```

Also update the `verification-before-completion` entry's `precedes` from `[]` to `["openspec-ship"]` (this fixture doesn't currently have `precedes`/`requires` fields — they may need adding).

Update the `finishing-a-development-branch` entry's `requires` to include `"openspec-ship"`.

Update line 163 phase_guide:
```json
    "SHIP":      "verification-before-completion + openspec-ship + finishing-a-development-branch",
```

- [ ] **Step 2: Update test-routing.sh first fixture (lines 149-173) — rewire chain**

Change `verification-before-completion` at line 157:
```json
      "precedes": ["openspec-ship"],
```

Change `finishing-a-development-branch` at line 172:
```json
      "requires": ["openspec-ship"],
```

Add `openspec-ship` entry between the two (after line 162):
```json
    {
      "name": "openspec-ship",
      "role": "workflow",
      "phase": "SHIP",
      "triggers": [
        "(document.*built|as.?built|openspec|archive.*feature|shipping.*protocol)"
      ],
      "trigger_mode": "regex",
      "priority": 58,
      "precedes": ["finishing-a-development-branch"],
      "requires": ["verification-before-completion"],
      "invoke": "Skill(auto-claude-skills:openspec-ship)",
      "available": true,
      "enabled": true
    },
```

- [ ] **Step 3: Update test-routing.sh second fixture (lines 445-467) — same rewire**

Apply identical changes as Step 2 to the second fixture registry.

- [ ] **Step 4: Update test-routing.sh SHIP composition fixture (line 559)**

Change the `"SHIP"` composition entry to include `openspec-ship` as the first sequence entry:

```json
    "SHIP": {"driver": "verification-before-completion", "sequence": [{"step": "openspec-ship", "purpose": "Create retrospective OpenSpec change, validate, archive, update changelog"}, {"plugin": "commit-commands", "use": "commands:/commit", "when": "installed", "purpose": "Execute structured commit after verification passes"}, {"step": "finishing-a-development-branch", "purpose": "Branch cleanup, merge, or PR"}, {"plugin": "commit-commands", "use": "commands:/commit-push-pr", "when": "installed AND user chooses PR option", "purpose": "Automated branch-to-PR flow"}], "hints": [{"plugin": "commit-commands", "text": "Consider /commit-push-pr for automated branch-to-PR workflow", "when": "installed"}]},
```

- [ ] **Step 5: Commit fixture updates**

```bash
git add tests/test-context.sh tests/test-routing.sh
git commit -m "test: update inline fixture registries with openspec-ship chain rewire"
```

### Task 6: Update hardcoded test assertions

**Files:**
- Modify: `tests/test-routing.sh:717-718`
- Modify: `tests/test-registry.sh:334`

- [ ] **Step 1: Update test-routing.sh ship assertion (line 717-718)**

The test at line 712 uses prompt `"let's ship this and merge the branch to main"`. After the chain rewire, `verification-before-completion` (priority 60) beats `finishing-a-development-branch` (priority 61) because `verification-before-completion` is the chain anchor and gets priority-first selection in the workflow cap. Update the comment and assertion:

Change:
```bash
    # With no process skill, workflow skills listed without orchestration prefix
    # finishing-a-development-branch has higher priority (61 vs 60), so it wins the single workflow slot
    assert_contains "ship matches workflow skill" "finishing-a-development-branch" "${context}"
```
To:
```bash
    # verification-before-completion (60) wins the workflow slot; openspec-ship and finishing follow via chain
    assert_contains "ship matches workflow skill" "verification-before-completion" "${context}"
```

Note: The actual assertion value depends on the fixture priorities. If `finishing-a-development-branch` still has higher priority (61 vs 60) in the fixture, it will still win. Read the fixture carefully and verify which skill actually wins before changing the assertion. If the fixture priorities haven't changed, update ONLY the comment but keep the existing assertion. Run the test to verify.

- [ ] **Step 2: Update test-registry.sh SHIP sequence count (line 334)**

Change:
```bash
    assert_equals "SHIP has 4 sequence entries" "4" "${ship_sequence}"
```
To:
```bash
    assert_equals "SHIP has 5 sequence entries" "5" "${ship_sequence}"
```

- [ ] **Step 3: Commit assertion updates**

```bash
git add tests/test-routing.sh tests/test-registry.sh
git commit -m "test: update SHIP assertion values for openspec-ship chain"
```

### Task 7: Add new test cases for openspec-ship

**Files:**
- Modify: `tests/test-routing.sh` (append new tests)
- Modify: `tests/test-registry.sh` (append new tests)

- [ ] **Step 1: Add routing test — openspec-ship triggers correctly**

Append to `tests/test-routing.sh` before the final summary section:

```bash
# ---------------------------------------------------------------------------
# N. openspec-ship triggers on its own terms, not on bare "ship"
# ---------------------------------------------------------------------------
test_openspec_ship_triggers() {
    echo "-- test: openspec-ship triggers on own terms --"
    setup_test_env
    install_registry

    # Should trigger on "generate as-built docs"
    local output
    output="$(run_hook "generate as-built docs for this feature")"
    local context
    context="$(extract_context "${output}")"
    assert_contains "openspec triggers on as-built" "openspec-ship" "${context}"

    # Should NOT trigger on bare "ship"
    output="$(run_hook "ship this")"
    context="$(extract_context "${output}")"
    assert_not_contains "openspec does not trigger on bare ship" "openspec-ship" "${context}"

    teardown_test_env
}
```

- [ ] **Step 2: Add chain walker test — three-node SHIP chain**

Append to `tests/test-routing.sh`:

```bash
# ---------------------------------------------------------------------------
# N+1. SHIP chain renders three nodes: verification -> openspec-ship -> finishing
# ---------------------------------------------------------------------------
test_ship_chain_three_nodes() {
    echo "-- test: SHIP chain has three nodes --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "ship this feature now")"
    local context
    context="$(extract_context "${output}")"

    # Chain should contain all three SHIP workflow skills
    assert_contains "chain has verification" "verification-before-completion" "${context}"
    assert_contains "chain has openspec-ship" "openspec-ship" "${context}"
    assert_contains "chain has finishing" "finishing-a-development-branch" "${context}"

    teardown_test_env
}
```

- [ ] **Step 3: Add methodology hint test**

Append to `tests/test-routing.sh`:

```bash
# ---------------------------------------------------------------------------
# N+2. openspec-ship-reminder methodology hint fires during SHIP
# ---------------------------------------------------------------------------
test_openspec_hint_fires_on_ship() {
    echo "-- test: openspec-ship-reminder hint fires on ship prompt --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "let's ship this feature")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "openspec hint fires" "OPENSPEC" "${context}"

    teardown_test_env
}
```

Note: For the methodology hint to fire, the fixture registry at the top of test-routing.sh must also include the `openspec-ship-reminder` in its `methodology_hints` array. Add it to both fixture registries' `methodology_hints` arrays.

- [ ] **Step 4: Add registry consistency test**

Append to `tests/test-registry.sh`:

```bash
test_openspec_ship_chain_consistency() {
    echo "-- test: openspec-ship chain rewires are consistent across registries --"
    setup_test_env

    # Check default-triggers.json
    local vbc_precedes
    vbc_precedes="$(jq -r '.skills[] | select(.name == "verification-before-completion") | .precedes[0]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "vbc precedes openspec-ship" "openspec-ship" "${vbc_precedes}"

    local os_requires
    os_requires="$(jq -r '.skills[] | select(.name == "openspec-ship") | .requires[0]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "openspec-ship requires vbc" "verification-before-completion" "${os_requires}"

    local os_precedes
    os_precedes="$(jq -r '.skills[] | select(.name == "openspec-ship") | .precedes[0]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "openspec-ship precedes finishing" "finishing-a-development-branch" "${os_precedes}"

    local fab_requires
    fab_requires="$(jq -r '.skills[] | select(.name == "finishing-a-development-branch") | .requires[0]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    assert_equals "finishing requires openspec-ship" "openspec-ship" "${fab_requires}"

    teardown_test_env
}
```

- [ ] **Step 5: Register new test functions in the test runners**

Add the new test function names to the test runner invocation at the bottom of each test file (look for where existing tests are called and add the new ones).

- [ ] **Step 6: Run all new tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | tail -20`
Expected: All new tests PASS.

Run: `bash tests/test-registry.sh 2>&1 | tail -20`
Expected: All new tests PASS.

- [ ] **Step 7: Commit new tests**

```bash
git add tests/test-routing.sh tests/test-registry.sh
git commit -m "test: add openspec-ship routing, chain walker, hint, and consistency tests"
```

## Chunk 4: Fallback Registry and Full Suite

### Task 8: Regenerate fallback registry

**Files:**
- Modify: `config/fallback-registry.json`

- [ ] **Step 1: Regenerate from clean environment**

```bash
HOME_BAK="$HOME"
export HOME="$(mktemp -d)"
mkdir -p "$HOME/.claude"
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh >/dev/null 2>&1
cp "$HOME/.claude/.skill-registry-cache.json" config/fallback-registry.json
export HOME="$HOME_BAK"
```

- [ ] **Step 2: Verify fallback contains openspec-ship**

Run: `jq '.skills[] | select(.name == "openspec-ship") | .name' config/fallback-registry.json`
Expected: `"openspec-ship"`

Run: `jq '.phase_compositions.SHIP.sequence | length' config/fallback-registry.json`
Expected: `5`

- [ ] **Step 3: Verify JSON is valid**

Run: `jq empty config/fallback-registry.json`
Expected: No output.

- [ ] **Step 4: Commit**

```bash
git add config/fallback-registry.json
git commit -m "chore: regenerate fallback registry with openspec-ship"
```

### Task 9: Run full test suite

**Files:** (verification only, no changes)

- [ ] **Step 1: Syntax-check all modified hooks**

Run: `bash -n hooks/skill-activation-hook.sh && bash -n hooks/session-start-hook.sh`
Expected: No output (both valid).

- [ ] **Step 2: Validate all JSON**

Run: `jq empty config/default-triggers.json && jq empty config/fallback-registry.json`
Expected: No output (both valid).

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass. If any test fails, investigate and fix before proceeding.

- [ ] **Step 4: Run routing tests with explain mode**

Run: `SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh <<< "ship this feature" 2>&1 | head -40`
Expected: Output shows `verification-before-completion` selected as workflow, composition chain includes `openspec-ship`, and `OPENSPEC` methodology hint is present.
