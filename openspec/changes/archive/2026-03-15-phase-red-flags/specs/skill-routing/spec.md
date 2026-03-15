# Skill Routing — Delta

## ADDED Requirements

### Requirement: Phase-aware RED FLAGS
The hook MUST inject a targeted HALT checklist into additionalContext for each SDLC phase (DESIGN, PLAN, IMPLEMENT, REVIEW).

#### Scenario: DESIGN RED FLAGS visible
Given a prompt that routes to DESIGN phase
When the hook output is generated
Then HALT directives mention "brainstorming" and "design presentation"

#### Scenario: PLAN RED FLAGS visible
Given a prompt that routes to PLAN phase
When the hook output is generated
Then HALT directives mention "approved plan document"

#### Scenario: IMPLEMENT RED FLAGS visible
Given a prompt that routes to IMPLEMENT phase
When the hook output is generated
Then HALT directives mention "worktree" and "TDD"

#### Scenario: REVIEW RED FLAGS visible
Given a prompt that routes to REVIEW phase
When the hook output is generated
Then HALT directives mention "code-reviewer subagent"

### Requirement: Phase-enforcement methodology hint
The hook MUST emit a methodology hint during DESIGN/PLAN when implementation-intent language is detected.

#### Scenario: Hint fires at DESIGN with implementation intent
Given PRIMARY_PHASE is DESIGN
When the prompt contains implementation verbs (fix, change, refactor, etc.)
Then the hint "PHASE ENFORCEMENT" appears in the output

#### Scenario: Hint suppressed at IMPLEMENT
Given PRIMARY_PHASE is IMPLEMENT
When the prompt contains implementation verbs
Then the hint "PHASE ENFORCEMENT" does NOT appear

### Requirement: REVIEW 3-step sequence
The REVIEW phase composition MUST display 3 sequential steps in the hook output.

#### Scenario: REVIEW sequence visible
Given a prompt that routes to REVIEW phase
When the hook output is generated
Then SEQUENCE entries show requesting-code-review, agent-team-review, and receiving-code-review
