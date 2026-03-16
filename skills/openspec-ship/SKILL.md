---
name: openspec-ship
description: Use when shipping a completed feature and generating as-built OpenSpec docs before branch finalization
---

# OpenSpec Ship — Retrospective Change Documentation

Generate permanent "as-built" OpenSpec documentation from completed code, then archive it alongside Superpowers execution artifacts.

## When to Use

Invoke this skill during the SHIP phase after `verification-before-completion` passes and before `finishing-a-development-branch`. It runs automatically as part of the SHIP composition chain.

## When to Skip

Skip this skill ONLY when ALL of these are true:
- No Superpowers plan was executed in this session (no `docs/superpowers/plans/` artifact)
- The session was debugging, reviewing, or non-feature work

**Scope and size are NOT skip criteria.** If a Superpowers plan was executed — regardless of how small the change — this skill MUST run. A 3-file config change that went through brainstorming → writing-plans → execution still needs as-built documentation.

If you are uncertain whether to skip, run it. The cost of an unnecessary openspec-ship is minutes; the cost of missing documentation is permanent knowledge loss.

## Hard Precondition

Before proceeding, verify that `verification-before-completion` has already run in this conversation. Look for fresh verification evidence appropriate to the project (e.g., test runner output, lint results, build confirmation — not all projects have all three). If no fresh verification evidence exists, STOP and inform the user:

> "openspec-ship requires passing verification. Invoking verification-before-completion first."

Then invoke `Skill(superpowers:verification-before-completion)` before continuing. Defer to `verification-before-completion` for the exact command set appropriate to the project.

## Session State

When this skill starts, populate the session state file with linkage information:
1. Read `~/.claude/.skill-session-token` for the session token.
2. Source `hooks/lib/openspec-state.sh` from the auto-claude-skills plugin root.
3. Call `openspec_state_upsert_change "<token>" "<change_slug>" "<plan_path>" "<spec_path>" "<capability_slug>"`.
4. If the state file doesn't exist yet (verification-before-completion hasn't run), the helper creates it with `verification_seen: false`.

## Input

The user should provide:
- **Required for SP artifact archival:** `plan_path` — the path to the Superpowers execution plan (e.g., `docs/superpowers/plans/2026-03-14-feature.md`). If not provided, skip SP artifact archival with warning.
- **Optional:** `feature-name` — kebab-case change name. If not provided, derive from `plan_path` by stripping the date prefix (e.g., `2026-03-14-feature.md` → `feature`). If neither is available, ask the user.

## Steps

### Step 1: Detect Environment

**Primary:** Read the session's `OpenSpec:` capability line from the session-start output (already in conversation context). Parse `surface=` to determine the OPSX surface level.

**Fallback (if capability line not found):** Read `~/.claude/.skill-registry-cache.json` and extract `openspec_capabilities.surface`.

**Last resort (backwards compatibility):** Run `command -v openspec` to check for CLI availability.

Based on the detected surface:
- `opsx-core` or `opsx-expanded`: Use OPSX commands in later steps.
- `openspec-core`: Use CLI commands directly (no OPSX slash commands available).
- `none`: Use Claude-native fallback templates.

### Step 2: Derive Slugs

**Session state (primary):** Read `~/.claude/.skill-session-token` to get the session token. Then read `~/.claude/.skill-openspec-state-<token>` for pre-populated linkage:
- `changes.<slug>.sp_plan_path` — use as `plan_path`
- `changes.<slug>.sp_spec_path` — use as `spec_path`
- `changes.<slug>.capability_slug` — use as capability

If the state file exists and has the relevant change entry, use those values. Skip user prompts for fields that are already populated.

**Fallback (no state file):** Use the existing user-input flow (unchanged from current behavior).

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

**Write provenance metadata:**

After the archive path exists and SP artifacts (if any) have been moved:
1. Read `~/.claude/.skill-session-token` for the session token.
2. Run the `openspec_write_provenance` helper (source `hooks/lib/openspec-state.sh` from the auto-claude-skills plugin root, then call `openspec_write_provenance "<archive_path>" "<token>" "<change_slug>"`).
3. This creates `<archive_path>/superpowers/source.json` with schema_version, paths, branch, commit, surface, and timestamp.
4. If the write fails, log a warning but do not fail the archive.

## Graceful Degradation Summary

| OpenSpec CLI | Behavior |
|-------------|----------|
| Available | `/opsx:propose` → `openspec validate` → `/opsx:archive` |
| Not available | Claude-native templates → skip validation → manual archive. Same artifact contract (paths, filenames, section headings). |
