## ADDED Requirements

### Requirement: DISCOVER-before-DESIGN precondition in composition step text

The composition-chain renderer MUST support an optional per-skill `precondition` string and,
when the skill carrying it is the CURRENT composition step, MUST emit that string as a
distinct indented line directly beneath the step line. The renderer MUST NOT emit the
precondition for a skill that is a DONE, DONE?, NEXT, or LATER step, and MUST leave rendering
unchanged for skills that do not define the field.

The `brainstorming` skill MUST carry a `precondition` that instructs: when the ask is a new
feature or initiative and no discovery brief exists (session-state `discovery_path` or a
`docs/plans/*-discovery.md`), invoke `Skill(auto-claude-skills:product-discovery)` FIRST and
then return to brainstorming; and to skip for bugfixes, small changes, or when a brief exists.
The prior advisory `discovery-audit-companion` hint MUST be removed.

The precondition text is model-evaluated; the renderer MUST NOT itself suppress the line based
on brief existence (that conditional lives in the text).

#### Scenario: Precondition renders on the CURRENT brainstorming step
- **WHEN** a DESIGN/Build prompt makes `brainstorming` the CURRENT composition step
- **THEN** the composition output MUST include an indented PRECONDITION line beneath that step
  naming `product-discovery` and the "no discovery brief exists" condition

#### Scenario: Precondition does not render off the CURRENT step
- **WHEN** `brainstorming` appears in the chain but is a DONE or LATER step (not CURRENT)
- **THEN** the composition output MUST NOT include the PRECONDITION line for it

#### Scenario: Skills without a precondition are unchanged
- **WHEN** the CURRENT step is a skill that defines no `precondition` field
- **THEN** the composition output MUST render exactly as before (no extra line)

#### Scenario: New-feature ask with no brief routes to discovery first (uptake)
- **WHEN** a new-feature DESIGN ask with no existing discovery brief is presented with the
  precondition in the composition context
- **THEN** the model MUST route to `product-discovery` before brainstorming on a majority of
  eval reps (acceptance ≥4/5), while a brief-exists control MUST correctly skip (≥4/5)
