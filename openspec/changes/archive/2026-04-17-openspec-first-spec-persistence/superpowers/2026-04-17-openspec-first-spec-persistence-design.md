# Design: OpenSpec-First Spec Persistence for Multi-User Repos

**Date:** 2026-04-17
**Slug:** `openspec-first-spec-persistence`
**Status:** Design — awaiting approval before PLAN phase

---

## Problem

In multi-user repos where work happens across parallel sessions by different developers, three structural failures emerge from the current `docs/plans/`-first model:

1. **Invisibility of in-progress design intent.** `docs/plans/` is `.gitignore`'d (line 4). A dev's DESIGN-phase output is never seen by teammates until the PR lands. Two devs starting related features see each other's commits only after the fact.

2. **No durable decision record until SHIP.** `openspec-ship` writes the retrospective proposal/design/spec at archive time — weeks after the decision was made. The rejected alternatives, the design debate, the "why Path A over Path B" — all of it lives in conversation ether unless the dev manually commits their `docs/plans/*-design.md` (which is gitignored).

3. **No CI-enforceable spec contract during development.** Nothing stops a PR from changing behavior without updating any spec. The first canonical spec lands at archive time, unreviewed against the implementation.

Symptom-level fallout: duplicate/conflicting work, tribal knowledge about why decisions were made, spec drift at merge time, and the need to treat `openspec-ship`'s output as the *first* (not *refined*) version of the spec.

## Capabilities Affected

- **`openspec-ship` skill** — Behavior becomes idempotent: if `openspec/changes/<feature>/` exists (created upfront in DESIGN phase), validate + archive; else create retrospectively (current behavior preserved for backward compat).
- **`design-debate` skill** — Output template becomes mode-aware: writes to `openspec/changes/<feature>/design.md` in team mode, `docs/plans/*-design.md` in solo mode.
- **DESIGN phase composition** (config/default-triggers.json, fallback-registry.json) — `PERSIST DESIGN` hint text is rewritten by session-start when team mode is active, redirecting persistence to `openspec/changes/<feature>/`.
- **PLAN phase composition** — `CARRY SCENARIOS` hint redirected to `openspec/changes/<feature>/specs/<cap>/spec.md` in team mode.
- **`session-start-hook.sh`** — New step after preset resolution: read `openspec_first` flag, mutate composition hint text accordingly.
- **Preset schema** — New optional field `openspec_first: true|false`. New preset `team.json` with `openspec_first: true`.
- **`openspec-state.sh`** — Session state gains `openspec_change_slug` (may already be covered by `change_slug`; verify).
- **Intent Truth tiers** — No change required. Source 1 (`openspec/changes/<feature>/`) already has top precedence in the 5-tier hierarchy shipped in SDLC Task 1.
- **`CLAUDE.md`** — Documents the two modes and when to use each.
- **Tests** — `test-presets.sh` (openspec_first field), `test-registry.sh` (session-start swaps hint), new `test-openspec-first-flow.sh` (end-to-end team-mode session).

## Explicit Out-of-Scope (v1)

- **CI validation gates.** Running `openspec validate` in GitHub Actions, spec-change-required PR checks, CODEOWNERS for `openspec/specs/<capability>/`. Document as v2 follow-up.
- **Graduation automation.** Auto-detecting "design is approved" and migrating from `docs/plans/` to `openspec/changes/`. Manual in v1; preset toggle is the graduation mechanism.
- **Capability taxonomy inference.** Auto-suggesting `capability_slug` from prompt keywords or existing `openspec/specs/` folders. Still user-provided in v1.
- **Forced migration of existing artifacts.** `docs/plans/*-design.md` files that pre-date this change stay where they are. Only new work uses the new flow.
- **Mandatory mode.** Default remains `docs/plans/`-only. Team mode is opt-in via preset. No repo is forced into OpenSpec-first.
- **Spec evolution during IMPLEMENT.** v1 creates `openspec/changes/<feature>/` in DESIGN and treats it as mostly-immutable until SHIP. Iterating the spec delta mid-implementation is a v2 concern.
- **Multi-capability changes.** v1 assumes one `capability_slug` per change. Features touching multiple capabilities use the existing one-change-per-capability convention.

## Approach

### Architecture

A single preset flag controls the artifact destination. Composition hints are rewritten at session-start based on the flag, so the LLM sees a coherent instruction set (not conflicting guidance).

```
~/.claude/skill-config.json
  { "preset": "team" }
    │
    ▼
session-start-hook.sh (Step 6b, after preset resolution)
  IF preset.openspec_first == true:
    mutate DESIGN PERSIST hint → "save to openspec/changes/<feature>/"
    mutate PLAN CARRY hint → "read from openspec/changes/<feature>/specs/"
    emit team-mode marker to activation context
    │
    ▼
Activation context for LLM sees:
  - PERSIST DESIGN: Save to openspec/changes/<feature>/
  - CARRY SCENARIOS: Read openspec/changes/<feature>/specs/<cap>/spec.md
  - Session state: openspec_change_slug populated in DESIGN
```

### Component-level changes

**1. Preset schema extension** (`config/presets/*.json`)

New optional top-level field `openspec_first: boolean`. Absent or `false` → current behavior. `true` → openspec-first mode.

- `starter.json`: unchanged (no `openspec_first` field → defaults false)
- `standard.json`: unchanged
- `full.json`: unchanged
- `team.json` (NEW): `openspec_first: true`, all overrides empty (enables everything + team mode)

**2. Session-start hint mutation** (`hooks/session-start-hook.sh`)

After preset resolution (Step 6b, already exists), add Step 6c:

```bash
# Step 6c: Apply openspec_first mode if preset enables it
_openspec_first="$(jq -r '.openspec_first // false' "$_preset_file" 2>/dev/null)"
if [ "$_openspec_first" = "true" ]; then
  # Swap DESIGN PERSIST hint text
  SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq '...')"
  # (implementation: rewrite phase_compositions.DESIGN.hints entries)
fi
```

The mutation rewrites hint text in-place so downstream code (composition rendering) sees only the team-mode hints. No conditional logic in the hints themselves.

**3. `openspec-ship` idempotent sync** (`skills/openspec-ship/SKILL.md`)

Step 3 gains a "pre-flight" check:

```markdown
### Step 3: Create OR Sync Change Folder

**Check first:** Does `openspec/changes/<feature-name>/` already exist?

- **If YES (team mode path):** The change was created upfront in DESIGN. Validate it against as-built code; update `specs/<cap>/spec.md` if implementation diverged from design; leave `proposal.md` and `design.md` as the historical decision record.
- **If NO (retrospective path):** Proceed with existing Step 3 content — scaffold the change and populate retrospectively.
```

This keeps `openspec-ship` useful in both modes without branching the whole skill.

**4. `design-debate` output template**

Add a mode check at the top of the Output section:

```markdown
## Output

**Team mode (`openspec_first: true`):** Write the synthesis to `openspec/changes/<topic>/design.md` with sections below. Also create `openspec/changes/<topic>/proposal.md` with the problem statement and capabilities affected.

**Solo mode (default):** Write to `docs/plans/YYYY-MM-DD-<topic>-design.md` with the same sections.
```

**5. CLAUDE.md documentation**

New section "Spec Persistence Modes" explaining:
- When to use `team` preset (≥2 active developers, long-lived repo, CI requirements on the horizon)
- When to stay with `starter`/`standard` (solo, exploratory, short-lived)
- How `docs/plans/*-plan.md` is unchanged (task breakdowns remain session-scoped in both modes)

### Flow in team mode

```
DESIGN phase:
  ├─ brainstorming (external skill) → user approves direction
  ├─ HINT fires: "Create openspec/changes/<feature>/ with proposal + design"
  ├─ LLM creates openspec/changes/<feature>/proposal.md (why, what, capabilities, impact)
  ├─ LLM creates openspec/changes/<feature>/design.md (architecture, deps, trade-offs)
  ├─ LLM creates openspec/changes/<feature>/specs/<cap>/spec.md (ADDED/MODIFIED requirements)
  └─ openspec_state_upsert_change with change_slug, capability_slug set

PLAN phase:
  ├─ writing-plans (external skill) → task breakdown
  ├─ HINT fires: "Read openspec/changes/<feature>/specs/<cap>/spec.md for acceptance scenarios"
  └─ LLM writes docs/plans/YYYY-MM-DD-<slug>-plan.md (local, gitignored, tasks + scenarios)

IMPLEMENT:
  └─ references openspec/changes/<feature>/specs/ as authoritative contract

REVIEW:
  ├─ agent-team-review reads openspec/changes/<feature>/ (visible to spec-reviewer subagent)
  └─ implementation-drift-check compares code vs openspec/changes/<feature>/specs/ (committed baseline)

SHIP:
  ├─ verification-before-completion (tests pass)
  ├─ deploy-gate (readiness)
  ├─ openspec-ship sees openspec/changes/<feature>/ exists → validates + archives (not creates)
  │   └─ archive to openspec/changes/archive/YYYY-MM-DD-<feature>/
  └─ canonical spec at openspec/specs/<capability>/spec.md updated
```

### Flow in solo mode

Unchanged. `docs/plans/*-design.md` → `docs/plans/*-plan.md` → implement → `openspec-ship` creates retrospective change at SHIP. This is exactly today's behavior.

## Acceptance Scenarios

1. **GIVEN** a multi-user repo with `{ "preset": "team" }` in `~/.claude/skill-config.json`
   **WHEN** a dev enters DESIGN phase for a new feature
   **THEN** the activation context includes the mutated `PERSIST DESIGN` hint pointing to `openspec/changes/<feature>/` (not `docs/plans/`), and the LLM's design output is committed to `openspec/changes/<feature>/design.md` where teammates can see it via `git pull`.

2. **GIVEN** a solo repo with no preset or `{ "preset": "starter" }`
   **WHEN** a dev enters DESIGN phase
   **THEN** the activation context emits the existing `PERSIST DESIGN` hint pointing to `docs/plans/*-design.md` — behavior is unchanged from today.

3. **GIVEN** `openspec/changes/<feature>/` was created upfront in DESIGN (team mode) and the session has progressed to SHIP
   **WHEN** `openspec-ship` runs
   **THEN** it detects the existing change folder, validates the spec delta against the as-built code, updates `specs/<cap>/spec.md` if drift is found, preserves `proposal.md` and `design.md` as the historical record, and archives the change — without overwriting the upfront design rationale.

4. **GIVEN** a team-mode repo with a committed `openspec/changes/feature-a/` created by dev Alice
   **WHEN** dev Bob starts work on a related feature that touches the same capability
   **THEN** Bob's DESIGN phase Intent Truth retrieval (Source 1) surfaces Alice's in-progress change, and Bob can either extend Alice's change or coordinate to avoid conflict.

5. **GIVEN** the repo upgrades to this release mid-feature (`openspec/changes/<feature>/` does NOT exist, preset is now `team`)
   **WHEN** `openspec-ship` runs at SHIP
   **THEN** it falls back to retrospective creation (existing behavior) because the pre-flight check finds no upfront folder — the feature still ships, just without the upfront decision record.

## Decision

**Approach C (dual-track preset-gated) with mutation-at-session-start.**

Rationale:
- Progressive adoption: solo repos unaffected until they opt in
- Single toggle per repo (preset flag) — no per-feature decision fatigue
- `openspec-ship` remains useful in both modes
- Backward-compatible: existing artifacts stay, retrospective path preserved
- Foundation for v2 CI validation (once `openspec/changes/` is reliably populated upfront, CI can enforce)

**V1 ships:** preset schema + team preset, session-start hint mutation, `openspec-ship` idempotent sync, `design-debate` dual template, CLAUDE.md docs, 3 test suites.

**V2 follow-ups (not in v1 scope):** CI `openspec validate` gate, CODEOWNERS integration, capability taxonomy inference, mid-flight spec iteration helpers.

---

## Resolved decisions

1. **Preset name**: `spec-driven` (not `team`). More accurately describes what the flag does.

2. **Migration messaging**: **no** session-start warning (adds noise on every session). Migration guidance goes in CLAUDE.md and the preset file's `description` field. Users who check the preset see it; others discover it in seconds via filesystem.

3. **`design-debate` mode-awareness**: **follows session preset**, not invocation path. A skill that does different things depending on how you got there is harder to reason about. Same pattern as `openspec-ship` reading the detected OpenSpec surface — ambient session state drives behavior, not invocation source.

4. **Capability auto-creation**: **auto-create** when a new feature doesn't map to an existing capability (preserves plug-and-play). The LLM infers the capability name from feature context and creates `openspec/specs/<new-capability>/` without asking. Heuristic guidance in the SKILL.md nudges toward coarser capabilities (prefer extending an existing one). **Safeguard:** visible warning in the activation context whenever a NEW capability is introduced, so the user can course-correct before the change is archived.

Global naming throughout this plan uses `spec-driven` as the preset name and the config field.

## Global rename (from earlier draft)

Where the earlier sections of this doc said `team` preset or `openspec_first` field, read `spec-driven` preset and `openspec_first: true` field on that preset. The flag name `openspec_first` is kept because it describes the flag's *behavior*; the preset name `spec-driven` describes the *mode the user opts into*.
