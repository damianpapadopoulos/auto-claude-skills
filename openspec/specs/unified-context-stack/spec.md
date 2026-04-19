# Unified Context Stack

## Purpose

Tiered context retrieval across External, Internal, Historical, and Intent Truth. Phase-specific guidance chooses the highest available source per tier and degrades gracefully — falling through to Grep, CLAUDE.md, or web search — when a tier's tool is unavailable.

## Requirements

### Requirement: Design phase context retrieval
The unified-context-stack SHALL provide a phase document for the DESIGN phase that guides Intent Truth and Historical Truth retrieval before approaches are proposed during brainstorming.

#### Scenario: Existing spec found during brainstorming
Given a feature with an existing OpenSpec canonical spec at `openspec/specs/<capability>/spec.md`
When the DESIGN phase activates
Then the phase doc instructs the model to read the canonical spec and account for existing requirements in proposed approaches

#### Scenario: Past decisions found during brainstorming
Given Forgetful Memory is available (`forgetful_memory=true`)
When the DESIGN phase activates
Then the phase doc instructs the model to query Forgetful for past architectural decisions and known constraints

#### Scenario: No context tools available
Given neither Forgetful Memory nor OpenSpec artifacts exist
When the DESIGN phase activates
Then the phase doc instructs the model to read CLAUDE.md, docs/architecture.md, and .cursorrules as fallback

### Requirement: Narrowed DESIGN-phase activation hint
The activation hook's DESIGN phase composition MUST emit hint text specific to Intent Truth and Historical Truth, not generic 4-tier text.

#### Scenario: Activation hook emits DESIGN hint
Given the unified-context-stack plugin is available
When a DESIGN-phase prompt is processed
Then the PARALLEL hint references "Intent Truth, Historical Truth" specifically
And the purpose describes checking existing specs and past decisions

