# Incident Analysis — Delta

## ADDED Requirements

### Requirement: Playbook Discovery and Loading (v1.3)
The skill SHALL discover and load playbooks from bundled and repo-local directories.

#### Scenario: Bundled playbooks loaded
Given the skill enters the CLASSIFY stage
When it discovers playbooks
Then it loads all YAML files from skills/incident-analysis/playbooks/

#### Scenario: Repo-local override
Given a repo-local playbook at playbooks/incident-analysis/custom.yaml exists with the same id as a bundled playbook
When the skill loads playbooks
Then the repo-local definition replaces the bundled one

### Requirement: Confidence-Gated Classification (v1.3)
The skill SHALL classify incidents against loaded playbooks using a deterministic scoring engine.

#### Scenario: High confidence proposal
Given a single playbook scores >= 85 confidence with all eligibility conditions met
When the CLASSIFY stage completes
Then the agent presents a high-confidence decision record with command, supporting signals, contradictory signals, state fingerprint, and validation plan

#### Scenario: Medium confidence investigation
Given the top playbook scores 60-84
When the CLASSIFY stage completes
Then the agent presents a medium-confidence investigation summary with suggested follow-up queries and no command block

#### Scenario: Low confidence deep investigation
Given no playbook scores above 60
When the CLASSIFY stage completes
Then the agent transitions to INVESTIGATE Steps 1-5 only and feeds findings back to CLASSIFY

### Requirement: Three-Tier Eligibility (v1.3)
The scoring engine SHALL use three tiers for different purposes.

#### Scenario: Proposal eligibility
Given a playbook is commandable with no veto signals, coverage >= 0.70, params resolved, and pre_conditions passed
When the winner selection runs
Then the playbook is proposal_eligible and can reach the HITL gate

#### Scenario: Classification credibility
Given a non-commandable playbook with no veto signals, coverage >= 0.70, and confidence >= 60
When contradiction collapse is evaluated
Then the playbook participates as classification_credible

### Requirement: Contradiction Collapse (v1.3)
The scoring engine SHALL collapse to investigate when incompatible categories both score >= 60.

#### Scenario: Incompatible high scorers
Given two classification_credible candidates with categories in incompatible_pairs both score >= 60
When contradiction collapse is evaluated
Then all candidates collapse to the investigate path

### Requirement: State Fingerprint Recheck (v1.3)
The agent MUST recheck the state fingerprint after approval and before execution.

#### Scenario: No drift
Given the user approves a mitigation proposal and the fingerprint has not changed
When the agent rechecks the fingerprint
Then execution proceeds

#### Scenario: Drift detected
Given the user approves a mitigation proposal but the fingerprint has changed
When the agent rechecks the fingerprint
Then the command is invalidated and the flow returns to CLASSIFY

### Requirement: Post-Execution Validation (v1.3)
The agent SHALL validate the mitigation outcome in two phases.

#### Scenario: Stabilization grace period
Given a mitigation command has been executed
When the VALIDATE stage begins
Then only hard_stop_conditions are evaluated during stabilization_delay_seconds

#### Scenario: Observation window
Given the stabilization grace period has expired without hard stops
When the observation window begins
Then both hard_stop_conditions and stop_conditions are evaluated, and post_conditions are sampled every sample_interval_seconds for validation_window_seconds

#### Scenario: Validation success
Given all post_conditions are met after the observation window
Then the agent transitions to POSTMORTEM with verification_status: verified

#### Scenario: Validation failure
Given post_conditions are not met or a stop_condition triggers
Then the agent escalates to INVESTIGATE

#### Scenario: Validation inconclusive
Given post_conditions are partially met after the observation window
Then the agent presents the user with choices: extend observation, escalate, or accept as mitigated but unverified

### Requirement: Evidence Sanitization and Persistence (v1.3)
All evidence payloads MUST be sanitized before persistence.

#### Scenario: Evidence redaction
Given the agent captures evidence for an evidence bundle
When the evidence is written to disk
Then all payloads have passed through redact-evidence.sh and no unsanitized data is persisted

#### Scenario: Destructive action pre-capture
Given a playbook has requires_pre_execution_evidence: true
When the agent reaches the HITL gate
Then pre.json must include the sanitized final log window before the command is proposed

### Requirement: Decision Record Format (v1.3)
The agent MUST use compact, structured decision records at the HITL gate.

#### Scenario: High confidence record
Given a proposal passes all eligibility checks
When the agent presents the mitigation proposal
Then the output includes: playbook ID, confidence band, coverage ratio, margin, evidence age, supporting signals with weights, contradictory signals, veto signals, unknown/unavailable signals, state fingerprint, command, explanation, and validation plan
