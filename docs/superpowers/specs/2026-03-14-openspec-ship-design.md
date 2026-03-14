# Design: openspec-ship — Post-Execution Documentation via OpenSpec

## Overview

A new `openspec-ship` workflow skill inserted into the SHIP phase between `verification-before-completion` and `finishing-a-development-branch`. Creates a retrospective OpenSpec change folder from the finished codebase, validates it, updates the changelog, and archives it alongside temporary Superpowers execution artifacts. Includes graceful degradation when the OpenSpec CLI is absent.

## Motivation

The current Superpowers SDLC pipeline produces design specs *before* coding (brainstorming) and consolidates learnings at session end (ship-and-learn), but never generates permanent architectural documentation from the *finished* code. Plans diverge during execution — bugs, API surprises, pivots. Post-execution "as-built" documentation captures what was actually shipped, not what was originally guessed.

OpenSpec provides a standardized, change-folder-based framework for this documentation. By inserting it as a SHIP-phase step, the docs ship atomically with the code in the same commit/PR.

## OpenSpec Artifact Model

OpenSpec separates **canonical truth** from **active changes**:

- **`openspec/specs/<capability>/spec.md`** — Canonical truth. The current state of each capability's specification. Updated by syncing delta specs during the archive flow.
- **`openspec/changes/<change>/`** — Active change folder. Contains `proposal.md`, `design.md`, `specs/` (delta specs), `tasks.md`, and `.openspec.yaml` for work in progress.
- **`openspec/changes/archive/YYYY-MM-DD-<change>/`** — Archived change. A completed change folder moved here by the archive operation. The archive flow optionally syncs delta specs to canonical before moving.

Change specs are **delta documents** — they describe what this change adds/modifies/removes, not the full canonical spec. During archive, OpenSpec offers to sync these deltas into canonical `openspec/specs/<capability>/spec.md`.

This skill creates a **retrospective change folder** (populated from the shipped code and Superpowers artifacts), validates it, then archives it — with optional delta-to-canonical sync.

## SHIP Phase Sequence (Updated)

```
verification-before-completion          (driver)
        ↓
   openspec-ship                        ← NEW
        ↓
   unified-context-stack consolidation
        ↓
   /commit
        ↓
   finishing-a-development-branch
        ↓
   /commit-push-pr
```

OpenSpec runs before `/commit` so the generated docs are included in the shipped commit.

## Chain Walker Rewire

The chain walker (`skill-activation-hook.sh` lines 540-580) builds composition chains by following `precedes[0]` forward and `requires[0]` backward from the anchor skill (process or workflow). All four changes below MUST be applied atomically in a single commit alongside the new skill entry — partial application will break the chain (the forward walker terminates at missing skills, and the backward walker silently produces one-node chains for unresolvable `requires` references).

```
verification-before-completion.precedes = ["openspec-ship"]     (was: ["finishing-a-development-branch"])
openspec-ship.requires                  = ["verification-before-completion"]
openspec-ship.precedes                  = ["finishing-a-development-branch"]
finishing-a-development-branch.requires = ["openspec-ship"]     (was: ["verification-before-completion"])
```

**Fallback safety note:** If the `openspec-ship` skill entry is missing from the registry but `verification-before-completion.precedes` references it, the fallback at line 564-571 will build a dead-end two-node chain, dropping `finishing-a-development-branch`. A routing test must verify the full three-node chain renders correctly (see Tests section).

## Phase Guide Update

```json
"SHIP": "verification-before-completion + openspec-ship + finishing-a-development-branch"
```

## Phase Composition Update

Only the `sequence` key is replaced. The existing `hints` array is preserved unchanged:

```json
"SHIP": {
  "driver": "verification-before-completion",
  "sequence": [
    { "step": "openspec-ship", "purpose": "Create retrospective OpenSpec change, validate, archive, update changelog" },
    { "plugin": "unified-context-stack", "use": "memory consolidation (annotate + memory-save)", "when": "installed AND any context_capability is true", "purpose": "Consolidate learnings via chub annotate and/or memory-save before session close" },
    { "plugin": "commit-commands", "use": "commands:/commit", "when": "installed", "purpose": "Execute structured commit after verification passes" },
    { "step": "finishing-a-development-branch", "purpose": "Branch cleanup, merge, or PR creation" },
    { "plugin": "commit-commands", "use": "commands:/commit-push-pr", "when": "installed AND user chooses PR option", "purpose": "Automated branch-to-PR flow" }
  ],
  "hints": [
    {
      "plugin": "commit-commands",
      "text": "Consider /commit-push-pr for automated branch-to-PR workflow",
      "when": "installed"
    },
    {
      "plugin": "github",
      "text": "Use GitHub MCP tools (create_pull_request) for programmatic PR creation with labels and reviewers",
      "when": "installed"
    }
  ]
}
```

Note: `unified-context-stack` moves from position 1 to position 2 (after `openspec-ship`). This is intentional — documentation generation should complete before memory consolidation, since consolidation may reference the generated docs.

## Routing Configuration

```json
{
  "name": "openspec-ship",
  "role": "workflow",
  "phase": "SHIP",
  "triggers": ["(document.*built|as.?built|openspec|archive.*feature|shipping.*protocol)"],
  "trigger_mode": "regex",
  "priority": 18,
  "precedes": ["finishing-a-development-branch"],
  "requires": ["verification-before-completion"],
  "description": "Create retrospective OpenSpec change, validate, archive, update changelog"
}
```

**Trigger design note:** The `ship` keyword is deliberately excluded from `openspec-ship` triggers to avoid competing with `verification-before-completion` (which triggers on `ship` with priority 20). Both skills are `role: "workflow"` and the 1-workflow role cap (max 1, see `skill-activation-hook.sh` line 299) means `verification-before-completion` would always win the slot for bare "ship" prompts. Instead, `openspec-ship` is reached via the composition chain: after `verification-before-completion` completes, the context bonus (+20) from `precedes` ensures `openspec-ship` wins the workflow slot on the next prompt.

**Slot competition design:** `openspec-ship` is a **chained SHIP workflow**, not a co-equal workflow that shares the slot with `finishing-a-development-branch`. The 1-workflow cap is unchanged. The sequencing guarantee comes from three mechanisms working together:
1. **Chain walker** — renders the full `verification → openspec-ship → finishing` chain from the selected anchor skill
2. **SHIP composition step** — always emitted in SHIP phase output regardless of routing caps
3. **Methodology hint** — provides a belt-and-suspenders reminder (see Methodology Hint section below)

For direct invocation, users can say "run openspec", "generate as-built docs", or "archive this feature".

## Methodology Hint

Add a SHIP-phase-scoped methodology hint to `config/default-triggers.json` in the `methodology_hints` array. This ensures `openspec-ship` is always mentioned in SHIP phase output, even if the skill doesn't win a routing slot:

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

This hint fires on the same SHIP-intent terms that `verification-before-completion` triggers on, ensuring Claude always sees the OpenSpec reminder alongside verification activation. The hint operates outside the role-cap system — methodology hints are emitted unconditionally when triggers match and the phase is active.

## Direct Invocation Guard

The `requires` field in the routing config is used for chain walking and context bonus, not as a hard execution gate (see `skill-activation-hook.sh` line 247 and line 552). A user saying "run openspec" can trigger `openspec-ship` directly without `verification-before-completion` having run.

The SKILL.md must include a **hard precondition check** at the start of execution:

> Before proceeding, verify that `verification-before-completion` has already run in this conversation. Look for fresh verification evidence appropriate to the project (e.g., test runner output, lint results, build confirmation — not all projects have all three). If no fresh verification evidence exists, STOP and inform the user: "openspec-ship requires passing verification. Invoking verification-before-completion first." Then invoke `Skill(superpowers:verification-before-completion)` before continuing. Defer to `verification-before-completion` for the exact command set appropriate to the project.

This ensures the skill never generates documentation for unverified code, regardless of how it was triggered.

## Slug Derivation

The design uses `<feature-name>` and `<capability>` throughout change-folder paths and CLI commands. These must be deterministically derived, not guessed:

**Change slug (`<feature-name>`):**
- **When `plan_path` is provided:** Strip the leading date prefix from the plan filename stem. E.g., `docs/superpowers/plans/2026-03-14-openspec-ship.md` → `openspec-ship`.
- **When `plan_path` is not provided:** Ask the user for a kebab-case change name. Do not infer from codebase or conversation context.

**Capability slug (`<capability>`):**
- **When the linked SP spec references a specific capability:** Use that capability name in kebab-case.
- **When no capability is identifiable:** Ask the user. Do not guess.

**OPSX path:** When OpenSpec CLI is available, `/opsx:propose <name>` handles change creation and slug validation internally.

## Label Phase Update

Add `openspec-ship` to the `_determine_label_phase` case statement in `hooks/skill-activation-hook.sh` (line 412):

```bash
verification-before-completion|finishing-a-development-branch|openspec-ship) PLABEL="Ship / Complete" ;;
```

This ensures the skill displays "Ship / Complete" in the activation header rather than falling through to "(Claude: assess intent)".

## Skill Execution Flow

### Step 1: Detect Environment

Two-surface detection (simplified from original three-surface design because plugin command availability is not queryable from within a SKILL.md execution context — the registry stores discovered commands but provides no runtime query mechanism for skills):

1. **CLI binary** — Run `command -v openspec` to check for standalone installation. Record result for use in later steps.
2. **Neither** — Log: `"OpenSpec CLI not detected. Proceeding with Claude-native documentation. Run 'npm install -g @fission-ai/openspec@latest' for advanced features."`

This step only detects capability. CLI commands are invoked in the steps where they apply (validate in Step 2b, archive in Step 4).

### Step 2: Create Retrospective Change Folder

**OPSX path (primary):** When OpenSpec CLI is available, use the default-profile OPSX commands:
1. Use `/opsx:propose <feature-name>` to create the change folder and generate all artifacts (proposal.md, design.md, tasks.md) in one step. The propose command internally runs `openspec new change`, then loops through `openspec instructions` for each artifact to get schema-defined templates.
2. Populate the artifacts with retrospective content from the shipped codebase and SP artifacts, rather than forward-looking proposals.

**Optional expanded-profile enhancement:** If the project is explicitly configured for the expanded OPSX profile (via `openspec config profile` + `openspec update`), the skill may use `/opsx:new` + `/opsx:ff` or `/opsx:continue` instead. Do NOT depend on expanded-profile commands unless the project has opted in.

**Fallback path (no CLI):** Read the working codebase and (if available) the Superpowers brainstorming spec and execution plan. Create a retrospective change folder at `openspec/changes/<feature-name>/` with the following artifacts:

**`proposal.md`** — strict structure:
```markdown
# Proposal: <Feature Name>

## Problem Statement
Why are we building this? (Synthesized from SP brainstorming spec if available.)

## Proposed Solution
High-level summary of what was actually built.

## Out of Scope
What we explicitly avoided.
```

**`design.md`** — strict structure:
```markdown
# Design: <Feature Name>

## Architecture
Data flow, component breakdown, system diagrams reflecting the as-built state.

## Dependencies
New packages, APIs, or database changes introduced.

## Decisions & Trade-offs
Why Path A over Path B. Rejected alternatives and rationale.
(Synthesized from Superpowers brainstorming spec if available.)
```

**`specs/<capability>/spec.md`** — delta spec (one per capability affected):

**OPSX path:** When OpenSpec CLI is available, `/opsx:propose` handles delta spec generation as part of the artifact loop. The propose command internally uses `openspec instructions specs --change "<name>" --json` to get the schema-defined template. Follow the template exactly — it may include sections like `## ADDED Requirements`, `### Requirement:`, `#### Scenario:`, etc., depending on the configured schema. Do NOT hardcode a template; use what the CLI provides.

**Fallback path (no CLI):** Generate a minimal delta spec:
```markdown
# <Capability Name> — Delta

## ADDED Requirements

### Requirement: <Name>
<Description of the new requirement>

#### Scenario: <Name>
Given <precondition>
When <action>
Then <expected result>
```

The fallback template uses `## ADDED Requirements` / `### Requirement:` / `#### Scenario:` sections compatible with the default OpenSpec schema. This is a best-effort approximation — the CLI path produces authoritative structure.

**`tasks.md`** — strict structure:
```markdown
# Tasks: <Feature Name>

## Completed

- [x] 1.1 <task description> (from SP execution plan)
- [x] 1.2 <task description>
- [x] 2.1 <task description>
```

**When `plan_path` is provided:** Tasks are reconstructed from the Superpowers execution plan with all items marked complete, reflecting the retrospective nature of this change folder.

**When `plan_path` is not provided:** Generate `tasks.md` with a single explicit stub:
```markdown
# Tasks: <Feature Name>

## Completed

- [x] 1.1 Retrospective tasks unavailable — no Superpowers execution plan was provided. See git log for implementation history.
```

### Step 2b: Validate (CLI only)

If OpenSpec CLI was detected in Step 1, run `openspec validate <feature-name>` against the change folder. On validation failure, block the SHIP phase and report the issues for the user to resolve. On validation success, proceed.

Note: The CLI command is `openspec validate <change>`, not `openspec verify`. The `/opsx:verify` slash command exists as an expanded workflow profile but is not the base CLI command. This skill uses the base CLI.

If CLI is not available, skip this step (Claude-native generation has no external validator).

### Step 3: Changelog Update

1. Check for `CHANGELOG.md` in the project root.
2. If it exists with a non-standard format, append notes matching the detected format.
3. If it exists with Keep a Changelog format, append under `## [Unreleased]`.
4. If none exists, the skill MAY create a new `CHANGELOG.md` using Keep a Changelog format with the standard preamble (`# Changelog`, `All notable changes...`, links to keepachangelog.com and semver.org).
5. Categorize entries strictly into `### Added`, `### Changed`, `### Fixed`, or `### Removed`.

### Step 4: Archive & Cleanup

**Archive the change folder:**

- **OPSX path (primary):** Use `/opsx:archive <feature-name>` which follows the native archive flow (mirroring `openspec-archive-change` SKILL.md):
  1. Checks artifact completion via `openspec status --change "<feature-name>" --json`.
  2. If delta specs exist, assesses sync state against canonical `openspec/specs/<capability>/spec.md`. Prompts user: "Sync now (recommended)" or "Archive without syncing." If user chooses sync, invokes `openspec-sync-specs`.
  3. Moves the change folder to `openspec/changes/archive/YYYY-MM-DD-<feature-name>`.
  4. If archive fails, fall back to Claude-native archival (move the folder manually).
- **Fallback path:** Manually move `openspec/changes/<feature-name>/` to `openspec/changes/archive/YYYY-MM-DD-<feature-name>/`. If no canonical spec exists yet at `openspec/specs/<capability>/spec.md`, create it from the change's spec. If a canonical spec already exists, do NOT mutate it heuristically — instead log a warning: `"Canonical spec exists at openspec/specs/<capability>/spec.md. Skipping canonical update — use OpenSpec CLI for safe merging."` The archive still completes; only the canonical spec update is skipped.

**Enrich the archive with Superpowers artifacts:**

Artifact-source selection (strict, no guessing):

1. **Primary:** Explicit `plan_path` provided by the user as direct input (e.g., "ship the plan at `docs/superpowers/plans/2026-03-14-openspec-ship.md`"). This repo does not persist `plan_path` in session state — the only persisted state is composition progress (`chain`, `completed`, `current_index`) in `skill-activation-hook.sh` (line 820). The plan path must come from the user.
2. **Linked spec:** Parse the `**Spec:**` line from the identified plan (e.g., `docs/superpowers/plans/2026-03-13-unified-context-stack.md` line 11) to find the corresponding spec file.
3. **If no explicit plan path is provided:** Skip SP artifact archival with warning: `"No Superpowers plan path provided. Skipping SP artifact archival."` The change folder creation, validation, changelog update, and OpenSpec archive steps still execute — only the SP artifact move is skipped. No mtime, date, or topic heuristic fallback.

**When plan_path is known:**

Create `openspec/changes/archive/YYYY-MM-DD-<feature-name>/superpowers/` and move the original SP artifacts there:

```
openspec/changes/archive/YYYY-MM-DD-<feature-name>/
├── proposal.md          # From Step 2
├── design.md            # From Step 2
├── specs/               # From Step 2
│   └── <capability>/
│       └── spec.md
├── tasks.md             # From Step 2
└── superpowers/         # Original SP artifacts (moved here)
    ├── spec.md          # From docs/superpowers/specs/
    └── plan.md          # From docs/superpowers/plans/
```

Remove only the specific moved files from `docs/superpowers/`. Do not delete directories or unrelated files.

**Archive timestamp:** Use `YYYY-MM-DD-<feature-name>` (date only, matching SP plan naming convention). This is the fallback format. When OpenSpec CLI performs the archive, defer to its native naming convention.

**Multiple features in one session:** Each feature gets its own change folder and archive. If the session ships two features, two separate operations execute sequentially, each with its own `plan_path`.

## Graceful Degradation

| Detection | Behavior |
|-----------|----------|
| `openspec` CLI binary in PATH | Use OPSX commands: `/opsx:propose` to create change, `openspec validate` to validate, `/opsx:archive` to archive. Expanded profile commands optional if configured. |
| CLI not available | Claude-native: generate the same artifact contract (same paths, same filenames, same required section headings, compatible content — not byte-identical to CLI output). Manually move change folder to archive. Create canonical spec only if none exists; skip canonical update with warning if one already exists. |

This mirrors the unified-context-stack's tiered degradation model.

## ship-and-learn.md Phase Document Update

Add the following section to `skills/unified-context-stack/phases/ship-and-learn.md` **above** the existing memory consolidation protocol:

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

## SKILL.md Structure

The `skills/openspec-ship/SKILL.md` file follows the conventions of existing skills in this repo:

```markdown
---
name: openspec-ship
description: Use when shipping a completed feature and generating as-built OpenSpec docs before branch finalization
---

# OpenSpec Ship — Retrospective Change Documentation

## When to Use

Invoke this skill during the SHIP phase after `verification-before-completion` passes and before `finishing-a-development-branch`. It runs automatically as part of the SHIP composition chain.

## Hard Precondition

Before proceeding, verify that `verification-before-completion` has already run in this conversation. Look for fresh verification evidence appropriate to the project (e.g., test runner output, lint results, build confirmation — not all projects have all three). If no fresh verification evidence exists, STOP and inform the user: "openspec-ship requires passing verification. Invoking verification-before-completion first." Then invoke `Skill(superpowers:verification-before-completion)` before continuing. Defer to `verification-before-completion` for the exact command set appropriate to the project.

## Prerequisites

- All tests passing (enforced by hard precondition above)
- Feature code complete and working

## Steps

### Step 1: Detect Environment
[CLI detection: `command -v openspec` — record result for later steps]

### Step 2: Create Retrospective Change Folder
[OPSX path: `/opsx:propose <feature>` for schema-native generation. Fallback: create `openspec/changes/<feature>/` manually using embedded templates.]

### Step 2b: Validate (CLI only)
[Run `openspec validate <feature>` — block on failure]

### Step 3: Update Changelog
[Detect existing format or default to Keep a Changelog — append under [Unreleased]]

### Step 4: Archive & Cleanup
[OPSX path: `/opsx:archive <feature>` with delta-spec sync prompt — fallback: manual move, create canonical spec only if none exists, skip canonical update with warning if one already exists. Enrich archive with SP artifacts if plan_path provided.]

## Templates
[Embedded proposal.md, design.md, spec.md, tasks.md templates with strict section headings]

## Graceful Degradation
[Two-tier: CLI binary / Claude-native with same artifact contract]
```

The full SKILL.md content will be written during the implementation phase with complete prompt instructions for Claude. The above is the structural skeleton.

## Context Bonus Mechanics

After `verification-before-completion` is invoked, the `_apply_context_bonus` function grants +20 to skills in its `precedes` array. With `openspec-ship` at priority 18 + context bonus 20 = effective 38, it reliably wins the workflow slot over `finishing-a-development-branch` (priority 19, no bonus at that point). After `openspec-ship` completes, the same bonus shifts to `finishing-a-development-branch` (18+20=39 effective). This cascading boost is the mechanism that drives the three-step SHIP chain.

## Artifact Structure (Complete — OpenSpec-Native)

```
openspec/
├── specs/                                      # Canonical truth (updated by archive)
│   └── <capability>/
│       └── spec.md                             # Current specification for this capability
├── changes/
│   ├── <feature-name>/                         # Active change folder (Step 2)
│   │   ├── proposal.md                         # Why this change exists
│   │   ├── design.md                           # Technical approach (as-built)
│   │   ├── specs/
│   │   │   └── <capability>/
│   │   │       └── spec.md                     # Spec deltas for this change
│   │   └── tasks.md                            # Implementation checklist (retrospective)
│   └── archive/
│       └── YYYY-MM-DD-<feature-name>/          # Archived change (Step 4)
│           ├── proposal.md
│           ├── design.md
│           ├── specs/
│           │   └── <capability>/
│           │       └── spec.md
│           ├── tasks.md
│           └── superpowers/                    # Original SP artifacts (moved here)
│               ├── spec.md                     # From docs/superpowers/specs/
│               └── plan.md                     # From docs/superpowers/plans/
```

## Files to Modify

| File | Change |
|------|--------|
| `config/default-triggers.json` | Add skill entry; update `verification-before-completion.precedes` and `finishing-a-development-branch.requires`; update `phase_guide.SHIP`; replace `phase_compositions.SHIP.sequence` (preserve `hints` unchanged); add `openspec-ship-reminder` to `methodology_hints` — all in a single atomic commit |
| `config/fallback-registry.json` | Regenerate by running the session-start hook in a clean environment to produce a fresh cache, then copy the output: `HOME_BAK="$HOME"; export HOME="$(mktemp -d)"; mkdir -p "$HOME/.claude"; CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh >/dev/null 2>&1; cp "$HOME/.claude/.skill-registry-cache.json" config/fallback-registry.json; export HOME="$HOME_BAK"`. This is the documented maintenance flow (see `docs/superpowers/plans/2026-03-13-unified-context-stack.md` Task 10). |
| `skills/openspec-ship/SKILL.md` | New file: full skill prompt with templates, degradation logic, execution sequence, hard precondition guard |
| `skills/unified-context-stack/phases/ship-and-learn.md` | Add OpenSpec documentation tier above memory consolidation (see ship-and-learn.md section above for exact content) |
| `hooks/skill-activation-hook.sh` | Add `openspec-ship` to `_determine_label_phase` case statement (line 412) for "Ship / Complete" label |
| `tests/` | See Tests section below |

## Tests

### Required test cases:

1. **Routing test** (`tests/test-routing.sh`): Verify `openspec-ship` scores above threshold for its trigger set ("generate as-built docs", "run openspec", "archive this feature") and does NOT trigger for bare "ship" or "ship this".

2. **Chain walker test** (`tests/test-routing.sh`): Verify the full three-node SHIP chain renders correctly: `verification-before-completion | openspec-ship | finishing-a-development-branch`. Feed a SHIP-phase prompt and assert the composition output contains all three nodes with correct [CURRENT]/[NEXT]/[LATER] markers.

3. **Regression test** (`tests/test-routing.sh`): Confirm `verification-before-completion` still routes correctly for "ship this feature" after the `precedes` rewire — it should still win the workflow slot and show the composition chain.

4. **Registry test** (`tests/test-registry.sh`): Verify `openspec-ship` appears in the built registry with correct `role`, `phase`, `precedes`, and `requires` fields.

5. **Label test**: Verify that when `openspec-ship` is the only selected workflow skill, the label shows "Ship / Complete" (not "(Claude: assess intent)").

6. **Registry consistency test** (`tests/test-registry.sh`): Assert that all four chain rewires are present together in both `default-triggers.json` and `fallback-registry.json`: (a) `verification-before-completion.precedes` contains `"openspec-ship"`, (b) `openspec-ship.requires` contains `"verification-before-completion"`, (c) `openspec-ship.precedes` contains `"finishing-a-development-branch"`, (d) `finishing-a-development-branch.requires` contains `"openspec-ship"`. The chain walker (`skill-activation-hook.sh` line 541) is not designed to gracefully handle half-applied graph edits — the four rewires must always be co-present.

7. **Methodology hint test** (`tests/test-routing.sh`): Verify that the `openspec-ship-reminder` hint fires for "ship this feature" prompts when SHIP phase is active. The hint should appear in output alongside the `verification-before-completion` skill activation.

### Existing test assertions that must be updated:

The following hardcoded assertions in the current test suite will break after the chain rewire and composition changes. The implementation plan must update these:

**Assertion lines:**
- `tests/test-context.sh` line 163: Hardcodes `"SHIP": "verification-before-completion + finishing-a-development-branch"` in the phase guide. Must add `openspec-ship` to the expected string.
- `tests/test-routing.sh` line 717: Asserts `finishing-a-development-branch` wins the workflow slot for "ship" prompts. After the chain rewire, `verification-before-completion` wins first (priority 20), and `openspec-ship` follows via context bonus. This assertion's comment and expected behavior may need updating depending on the test's input prompt.
- `tests/test-registry.sh` line 334: Asserts `"SHIP has 4 sequence entries"`. Must change to 5 after inserting `openspec-ship`.

**Inline fixture registries (contain the old SHIP graph and must have `openspec-ship` inserted):**
- `tests/test-context.sh` line 133: Inline fixture JSON with old phase guide.
- `tests/test-routing.sh` line 150: Inline fixture registry with old `verification-before-completion` and `finishing-a-development-branch` skill entries (missing `openspec-ship`, old `precedes`/`requires` values).
- `tests/test-routing.sh` line 446: Second inline fixture registry (fallback-style) with old skill entries.
- `tests/test-routing.sh` line 559: Inline fixture `phase_compositions.SHIP` JSON with old sequence (no `openspec-ship` entry).

## Non-Goals

- This skill does NOT replace Superpowers' brainstorming or planning phases.
- This skill does NOT use OpenSpec's planning commands (`/opsx:propose`, `/opsx:apply`) — Superpowers handles those phases natively.
- This skill does NOT auto-install OpenSpec CLI — it only suggests installation.
- The `/opsx:verify` expanded slash-command profile is not part of the core design — the skill uses the base CLI command `openspec validate <change>`.
- The `/opsx:explore` command (thinking/exploration mode, ships with default profile) is not used in the shipping flow — it's a brainstorming tool, not a documentation tool.
- No engine changes to the role-cap system. The 1-workflow cap is unchanged. Sequencing is guaranteed by chain walking + composition steps + methodology hint.
