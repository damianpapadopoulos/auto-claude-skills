## ADDED Requirements

### Requirement: Lean Default Injection for Prompt-1 Multi-Skill Tier

The activation hook MUST render the prompt-1 / 3-or-more-skill injection tier in a lean form by default, omitting the Step-1/2/3 scaffold and the phase-guide table. The lean render MUST retain every compliance-carrying element: the selected skill lines, their `MUST INVOKE` markers and `Skill(...)` invocations, and the mandatory evaluation directive. Setting `SKILL_VERBOSE=1` MUST restore the verbose render (scaffold + phase-guide table). This change MUST NOT alter routing scores, skill selection, role caps, or composition-chain advancement.

#### Scenario: Lean render is the default on the session-opening multi-skill prompt
- **WHEN** the hook fires on prompt 1 with 3 or more selected skills and `SKILL_VERBOSE` is unset
- **THEN** the injected context MUST NOT contain the "Step 1 -- ASSESS PHASE" scaffold or the phase-guide table
- **AND** it MUST still contain the `MUST INVOKE` markers, `Skill(` invocations, and the "You MUST print a brief evaluation" directive

#### Scenario: SKILL_VERBOSE restores the verbose tier
- **WHEN** the hook fires on a prompt-1 / 3+-skill condition with `SKILL_VERBOSE=1`
- **THEN** the injected context MUST contain the "Step 1 -- ASSESS PHASE" scaffold and the phase-guide table

#### Scenario: Lean default is strictly smaller than the verbose render
- **WHEN** the same prompt-1 / 3+-skill input is rendered lean (default) and verbose (`SKILL_VERBOSE=1`)
- **THEN** the lean `additionalContext` byte length MUST be strictly less than the verbose byte length
