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

### Requirement: PLAN-phase DESIGN COMPLETENESS emission
The skill-activation hook MUST emit an accurate, file-grounded `DESIGN COMPLETENESS` block in the PLAN-phase activation context when the session has a token, an OpenSpec state file with an active change, and a non-null `design_path` for that change. The block MUST name three canonical sections of the design artifact: `## Capabilities Affected`, `## Out-of-Scope`, and `## Acceptance Scenarios`.

#### Scenario: All three sections present
- **WHEN** the design file at `design_path` contains all three canonical section headers as prefix matches (`^## <Header>`)
- **THEN** the activation output MUST contain the string `DESIGN COMPLETENESS: all sections present` on a single line
- **AND** the activation output MUST NOT contain the word "missing"

#### Scenario: Missing section names the gap
- **WHEN** the design file is missing one or more of the canonical section headers
- **THEN** the activation output MUST include a `DESIGN COMPLETENESS` header
- **AND** the activation output MUST explicitly name each missing section by header with a `(missing — ...)` annotation
- **AND** the activation output MUST instruct the LLM to complete the missing section(s) before invoking `Skill(superpowers:writing-plans)`
- **AND** the activation output MUST NOT annotate any present section with `(missing`

#### Scenario: Design file unreadable
- **WHEN** the state file's `design_path` refers to a file that does not exist on disk
- **THEN** the activation output MUST include a `DESIGN COMPLETENESS` header
- **AND** the output MUST include the word `unreadable` and echo the path
- **AND** the hook MUST still emit a valid JSON context block (no crash)

#### Scenario: No active change with design_path
- **WHEN** the state file is absent, or is present with an empty `changes` object, or has no active change with a non-null `design_path`
- **THEN** the activation output MUST NOT contain the string `DESIGN COMPLETENESS`

### Requirement: DESIGN COMPLETENESS fail-open contract
The PLAN-phase DESIGN COMPLETENESS block MUST fail-open on every sub-check: missing session token, missing state file, malformed state JSON, missing `design_path` key, missing file on disk, and grep errors MUST all degrade silently. The block MUST NOT cause the hook to exit non-zero or emit malformed JSON.

#### Scenario: Malformed state JSON
- **WHEN** the state file exists but is not valid JSON
- **THEN** the activation hook MUST still emit its normal output
- **AND** the activation output MUST NOT contain the string `DESIGN COMPLETENESS`

#### Scenario: Non-PLAN phase
- **WHEN** `PRIMARY_PHASE` is not `PLAN`
- **THEN** the DESIGN COMPLETENESS block MUST NOT fire regardless of state file contents

### Requirement: DESIGN COMPLETENESS SKILL_EXPLAIN breadcrumb
When `SKILL_EXPLAIN=1` is set, the PLAN-phase DESIGN COMPLETENESS block MUST emit an observability breadcrumb to stderr naming the three presence flags and the design path. When multiple open changes have `design_path` set, the block MUST additionally emit a `WARN N open changes` breadcrumb to make the arbitrary first-wins selection visible.

#### Scenario: Presence-flag breadcrumb
- **WHEN** `SKILL_EXPLAIN=1` and the block runs against a readable design file
- **THEN** stderr MUST contain a line of the form `[skill-hook]   [design-guard] caps=<0|1> oos=<0|1> acc=<0|1> path=<design_path>`

#### Scenario: Unreadable-file breadcrumb
- **WHEN** `SKILL_EXPLAIN=1` and the `design_path` points at a missing file
- **THEN** stderr MUST contain `[skill-hook]   [design-guard] unreadable: <design_path>`

#### Scenario: Multi-change ambiguity breadcrumb
- **WHEN** `SKILL_EXPLAIN=1` and two or more non-archived changes have `design_path` set
- **THEN** stderr MUST contain a `WARN <N> open changes with design_path; picked first` line before the presence-flag breadcrumb

### Requirement: Skill-tool completion advances composition state
A `PostToolUse` hook matching `^Skill$` MUST advance `~/.claude/.skill-composition-state-<token>`'s `.completed` array when a chain-member `Skill` tool call returns successfully. The hook MUST extract the skill name from `tool_input.name` (falling back to `tool_input.skill`), strip the plugin prefix by removing the longest leading `<anything>:` segment, and append the bare name to `.completed` only if it appears in `.chain` and not yet in `.completed`. On advancement, the hook MUST also bump `.current` to the next chain member that follows the just-completed skill, or leave `.current` unchanged if the completed skill is the last chain member.

#### Scenario: Chain-member Skill returns successfully
- **WHEN** the `Skill` tool returns with `tool_response.is_error == false` for a plugin-prefixed name whose bare form is in `.chain` and not in `.completed`
- **THEN** the hook MUST append the bare name to `.completed` preserving existing array order
- **AND** `.current` MUST advance to the next chain member not yet completed

#### Scenario: Last chain member preserves current
- **WHEN** the just-completed skill is the final entry in `.chain`
- **THEN** `.current` MUST remain unchanged (the existing value is preserved because no next chain member exists)

#### Scenario: tool_input.skill fallback
- **WHEN** the tool-use payload has `tool_input.skill` set instead of `tool_input.name`
- **THEN** the hook MUST read the skill name from `tool_input.skill` and advance state identically

### Requirement: Skill-completion hook fail-open contract
The `PostToolUse` `^Skill$` hook MUST exit 0 on every error path and MUST NOT mutate the state file on any failure. Specifically: missing stdin, missing `jq`, missing session token, missing state file, malformed state JSON, errored `tool_response`, empty skill name, unknown skill name, non-chain-member, already-completed skill, and `mv` failure MUST all degrade to silent exit 0 with no state change.

#### Scenario: Non-chain skill is a no-op
- **WHEN** the bare skill name is not present in `.chain`
- **THEN** the state file MUST remain byte-identical to its pre-call contents

#### Scenario: Errored tool response is a no-op
- **WHEN** `tool_response.is_error == true`
- **THEN** the state file MUST remain byte-identical to its pre-call contents

#### Scenario: Malformed state JSON is a no-op
- **WHEN** the state file exists but fails `jq empty` validation
- **THEN** the hook MUST exit 0 without overwriting or deleting the state file

#### Scenario: Idempotent re-invocation
- **WHEN** the hook is invoked twice in a row with the same skill name whose bare form is already in `.completed`
- **THEN** `.completed` MUST NOT grow; its length MUST equal its `unique` length

### Requirement: Skill-completion hook emits SKILL_EXPLAIN breadcrumb
When `SKILL_EXPLAIN=1` is set in the environment and the hook advances state, it MUST emit a single-line breadcrumb to stderr naming the skill that was marked completed. The breadcrumb MUST NOT fire on any no-op path.

#### Scenario: Breadcrumb on successful advance
- **WHEN** `SKILL_EXPLAIN=1` and the hook appends a chain-member skill to `.completed`
- **THEN** stderr MUST contain a line of the form `[skill-hook]   [completion] <skill-name> → completed`

#### Scenario: Breadcrumb suppressed on no-op
- **WHEN** `SKILL_EXPLAIN=1` but the skill name is not in `.chain` (or already in `.completed`, or the tool returned with an error)
- **THEN** the hook MUST NOT emit a `[completion]` breadcrumb

