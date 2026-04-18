## Purpose

Skill routing correctness contract. Regression tests for collision resolution, canonical/legacy session-state field aliasing for backward compatibility, and tiered Intent Truth retrieval — ensuring the right artifact wins at the right time across overlapping trigger patterns.

## Requirements

### Requirement: Routing Collision Regression Tests
The routing test suite MUST include interaction tests that verify correct skill selection when overlapping trigger patterns match the same prompt.

#### Scenario: Code review collision resolution
- **WHEN** a prompt contains "review" without team/multi-perspective qualifiers
- **THEN** `requesting-code-review` (priority 25) MUST be selected over `agent-team-review` (priority 20)

#### Scenario: Worktree routing with phase gating
- **WHEN** a prompt triggers brainstorming (DESIGN phase) and also matches `worktree`
- **THEN** `using-git-worktrees` (required role, IMPLEMENT phase) MUST NOT appear in activation context

#### Scenario: Debug vs incident disambiguation
- **WHEN** a prompt mentions infrastructure symptoms (crashloop, OOM, latency spike, SLO burn rate)
- **THEN** `incident-analysis` MUST be selected regardless of `systematic-debugging` also matching

#### Scenario: Negative routing
- **WHEN** a prompt is a greeting or generic question
- **THEN** no domain or process skills SHOULD activate

### Requirement: Session State Canonical Fields
The `openspec_state_upsert_change` function MUST write both canonical field names (`design_path`, `plan_path`, `spec_path`) and legacy aliases (`sp_plan_path`, `sp_spec_path`).

#### Scenario: Backward-compatible reads
- **WHEN** a provenance writer reads a state file written by the new code
- **THEN** both `plan_path` and `sp_plan_path` MUST return the same value

#### Scenario: Legacy state file reads
- **WHEN** a provenance writer reads a state file written by old code (only `sp_plan_path`)
- **THEN** the canonical `plan_path` field MUST fall back to `sp_plan_path` via jq `//` operator

### Requirement: Intent Truth 5-Tier Retrieval
Intent Truth retrieval MUST check sources in this order: OpenSpec active changes, `docs/plans/` live artifacts, `openspec/specs/` canonical, `docs/plans/archive/` archived, `docs/superpowers/specs/` legacy.

#### Scenario: Live intent takes precedence
- **WHEN** both `docs/plans/*-design.md` and `openspec/specs/<cap>/spec.md` exist
- **THEN** `docs/plans/` MUST be read first (Source 2 before Source 3)

### Requirement: Preset-Gated OpenSpec-First Mode
The plugin MUST support a `spec-driven` preset that redirects DESIGN and PLAN artifact creation from `docs/plans/` to `openspec/changes/<feature>/` when the preset's `openspec_first` flag is `true`.

#### Scenario: spec-driven preset active redirects DESIGN hints
- **GIVEN** `~/.claude/skill-config.json` contains `{"preset": "spec-driven"}`
- **WHEN** session-start hook runs
- **THEN** the cached registry's `phase_compositions.DESIGN.hints[].text` MUST contain `openspec/changes/`

### Requirement: openspec-ship Idempotent Pre-flight
`openspec-ship` MUST detect whether `openspec/changes/<feature-name>/` already exists before creating it. If present, validate and sync; if absent, create retrospectively.

#### Scenario: Existing change folder synced not overwritten
- **GIVEN** `openspec/changes/feature-x/` already exists from an upfront DESIGN-phase write
- **WHEN** `openspec-ship` runs in SHIP phase for `feature-x`
- **THEN** the existing proposal.md and design.md MUST NOT be overwritten; only the specs/ folder is updated to reflect as-built

#### Scenario: Missing change folder created retrospectively
- **GIVEN** no `openspec/changes/feature-x/` exists
- **WHEN** `openspec-ship` runs in SHIP phase for `feature-x`
- **THEN** the change folder MUST be created with retrospective proposal.md, design.md, and specs/

### Requirement: New-Capability Warning
When introducing a previously-unknown capability, skills MUST emit a visible `⚠️ NEW CAPABILITY:` warning for user taxonomy review.

#### Scenario: First use of a capability name
- **GIVEN** `openspec/specs/<cap>/` does not exist
- **WHEN** openspec-ship or design-debate introduces that capability
- **THEN** the skill output MUST contain a `⚠️ NEW CAPABILITY` warning line referencing the capability name

### Requirement: Dual-Mode design-debate Output
`design-debate` MUST check the session preset and write its synthesis to `openspec/changes/<topic>/` in spec-driven mode or `docs/plans/YYYY-MM-DD-<topic>-design.md` in solo mode.

#### Scenario: spec-driven mode write location
- **GIVEN** `~/.claude/skill-config.json` has `{"preset": "spec-driven"}`
- **WHEN** design-debate synthesizes its output
- **THEN** the synthesis MUST be written under `openspec/changes/<topic>/` (committed path)

#### Scenario: solo mode write location
- **GIVEN** no `spec-driven` preset is set
- **WHEN** design-debate synthesizes its output
- **THEN** the synthesis MUST be written to `docs/plans/YYYY-MM-DD-<topic>-design.md` (gitignored path)
