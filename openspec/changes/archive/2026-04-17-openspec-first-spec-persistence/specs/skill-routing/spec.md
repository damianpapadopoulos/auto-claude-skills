## ADDED Requirements

### Requirement: Preset-Gated OpenSpec-First Mode
The plugin MUST support a `spec-driven` preset that redirects DESIGN and PLAN artifact creation from `docs/plans/` to `openspec/changes/<feature>/` when the preset's `openspec_first` flag is `true`.

#### Scenario: spec-driven preset active redirects DESIGN hints
- **GIVEN** `~/.claude/skill-config.json` contains `{"preset": "spec-driven"}`
- **WHEN** session-start hook runs
- **THEN** the cached registry's `phase_compositions.DESIGN.hints[].text` MUST contain `openspec/changes/`
- **AND** MUST NOT contain `docs/plans/YYYY-MM-DD-<slug>-design.md`

#### Scenario: default mode preserves docs/plans/ hints
- **GIVEN** no `~/.claude/skill-config.json` exists (or its `preset` field is empty)
- **WHEN** session-start hook runs
- **THEN** the cached registry's `phase_compositions.DESIGN.hints[].text` MUST contain `docs/plans/YYYY-MM-DD-<slug>-design.md`

#### Scenario: PLAN CARRY hint redirected in spec-driven mode
- **GIVEN** `spec-driven` preset active
- **WHEN** session-start hook runs
- **THEN** the cached registry's `phase_compositions.PLAN.hints[].text` MUST reference `openspec/changes/<feature-slug>/specs/<capability-slug>/spec.md` as the scenario source

### Requirement: openspec-ship Idempotent Pre-flight
`openspec-ship` MUST detect whether `openspec/changes/<feature-name>/` already exists before creating it. If the folder exists (spec-driven upfront mode), the skill SHALL validate and sync rather than overwrite. If the folder does not exist (retrospective mode), the skill SHALL create it from as-built code.

#### Scenario: upfront change folder triggers sync path
- **GIVEN** `openspec/changes/<feature>/` exists with `proposal.md` and `design.md` from DESIGN phase
- **WHEN** `openspec-ship` runs at SHIP
- **THEN** it MUST NOT overwrite `proposal.md` or `design.md`
- **AND** SHOULD update `specs/<capability>/spec.md` if implementation diverged
- **AND** SHOULD append an "Implementation Notes (synced at ship time)" section to `design.md` when deviations exist

#### Scenario: no upfront folder triggers retrospective creation
- **GIVEN** `openspec/changes/<feature>/` does NOT exist
- **WHEN** `openspec-ship` runs at SHIP
- **THEN** it MUST create the folder with retrospective content (existing behavior preserved)

### Requirement: New-Capability Warning
When `openspec-ship` or `design-debate` creates `openspec/specs/<new-capability>/` for the first time (no existing folder for that capability), the skill MUST emit a visible warning in its response prefixed with `⚠️ NEW CAPABILITY:` so the user can course-correct the taxonomy before archive.

#### Scenario: new capability introduced
- **GIVEN** `openspec/specs/<new-capability>/` does not exist
- **WHEN** the skill creates it as part of spec-driven change creation
- **THEN** the skill response MUST contain the string `NEW CAPABILITY` and the new capability name

### Requirement: Dual-Mode design-debate Output
`design-debate` MUST check the session preset before emitting its synthesis artifact. In spec-driven mode, output goes to `openspec/changes/<topic>/`. In solo mode (default), output goes to `docs/plans/YYYY-MM-DD-<topic>-design.md`.

#### Scenario: mode selection on skill invocation
- **GIVEN** the design-debate skill is invoked
- **WHEN** the session preset has `openspec_first: true`
- **THEN** the skill's synthesis MUST be written to `openspec/changes/<topic>/proposal.md`, `openspec/changes/<topic>/design.md`, and `openspec/changes/<topic>/specs/<capability>/spec.md`

- **GIVEN** the design-debate skill is invoked
- **WHEN** the session preset does not have `openspec_first: true` (or no preset)
- **THEN** the skill's synthesis MUST be written to `docs/plans/YYYY-MM-DD-<topic>-design.md`
