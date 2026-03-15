# Proposal: Phase-Aware RED FLAGS

## Problem Statement
The skill routing engine had RED FLAGS enforcement only for the SHIP phase (verification-before-completion). All other SDLC phases (DESIGN, PLAN, IMPLEMENT, REVIEW) relied solely on "MUST INVOKE" text and composition chain display, which the model repeatedly ignored when changes felt "small." This led to the model skipping brainstorming, plan-writing, TDD, and code review steps.

## Proposed Solution
Extend the proven RED FLAGS mechanism to all SDLC phases. Each phase gets targeted HALT directives that list specific violations to catch. Add a phase-enforcement methodology hint for DESIGN/PLAN. Clarify the REVIEW phase 3-step sequencing (requesting → agent-team → receiving).

## Out of Scope
- PreToolUse hooks for programmatic phase enforcement (design debate rejected this)
- State-machine tracking of phase completion (tracked for future escalation)
- Changes to superpowers skill content
