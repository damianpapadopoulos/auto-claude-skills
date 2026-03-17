# Skill Routing

## Purpose

Route Claude Code sessions through SDLC phases by scoring prompt intent against skill triggers, selecting skills within role caps, and displaying composition chain guidance with phase-specific enforcement directives.

## Requirements

### Requirement: SDLC composition chain
The hook MUST display an end-to-end composition chain spanning DESIGN → PLAN → IMPLEMENT → REVIEW → SHIP with step markers ([DONE], [CURRENT], [NEXT], [LATER]).

#### Scenario: Full chain visible at IMPLEMENT
Given last-invoked skill is at IMPLEMENT phase
When the hook output is generated
Then the composition shows 7 steps from brainstorming through finishing-a-development-branch

#### Scenario: Skipped steps marked
Given a user enters SHIP without going through REVIEW
When the hook output is generated
Then the skipped REVIEW step shows [DONE?] marker

### Requirement: Role-cap selection
The hook MUST select skills using role caps: max 1 process, 2 domain, 1 workflow, total up to MAX_SUGGESTIONS.

#### Scenario: Process skill reserved
Given multiple process skills score on a prompt
When selection runs
Then the highest-scoring process skill is reserved in pass 1

### Requirement: Required role bypass
Skills with role "required" MUST bypass the process/domain/workflow caps when their phase matches the tentative phase and their triggers match.

#### Scenario: Required bypasses workflow cap
Given a required skill and a workflow skill both score at IMPLEMENT
When selection runs
Then both appear in the output (required does not consume the workflow slot)

#### Scenario: Condition-gated required
Given agent-team-review has required_when condition
When the skill scores at REVIEW phase
Then the eval line shows INVOKE WHEN with the condition text

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

#### Scenario: SHIP RED FLAGS visible
Given verification-before-completion is selected
When the hook output is generated
Then HALT directives mention "tests pass" and "verification commands"

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

### Requirement: IMPLEMENT stickiness
The hook MUST boost executing-plans above the top process skill when the last persisted phase is IMPLEMENT and the prompt contains explicit continuation language.

#### Scenario: Stickiness on continuation
Given last phase is IMPLEMENT and prompt is "continue with the next task"
When scoring runs
Then executing-plans wins over brainstorming

#### Scenario: Stickiness respects HARD-GATE
Given last phase is IMPLEMENT and prompt is "build a new authentication system"
When scoring runs
Then brainstorming wins (generic build verbs do not trigger stickiness)

### Requirement: Composition parallels
Always-on skills MUST appear as PARALLEL entries in their phase's composition output without consuming role cap slots.

#### Scenario: TDD parallel at IMPLEMENT
Given phase is IMPLEMENT
When the hook output is generated
Then a PARALLEL entry for test-driven-development appears

#### Scenario: Security-scanner parallel at REVIEW
Given phase is REVIEW
When the hook output is generated
Then a PARALLEL entry for security-scanner with Skill(auto-claude-skills:security-scanner) invoke appears

### Requirement: REVIEW 3-step sequence
The REVIEW phase composition MUST display 3 sequential steps in the hook output.

#### Scenario: REVIEW sequence visible
Given a prompt that routes to REVIEW phase
When the hook output is generated
Then SEQUENCE entries show requesting-code-review, agent-team-review, and receiving-code-review

### Requirement: IMPLEMENT sequence
The IMPLEMENT phase composition MUST display sequence entries for worktree setup (before) and branch finishing (after).

#### Scenario: IMPLEMENT sequence visible
Given a prompt that routes to IMPLEMENT phase
When the hook output is generated
Then SEQUENCE entries show using-git-worktrees and finishing-a-development-branch
