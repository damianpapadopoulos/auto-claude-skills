# Incident Analysis

## Purpose

Structured production-incident investigation. Tiered observability detection (MCP → gcloud CLI → guidance-only), HITL-gated mutations, and canonical postmortem output that survives the session so incident context reaches the next phase and the next responder.

## Requirements

### Requirement: Tiered Tool Detection
The skill SHALL detect available observability tools at runtime and MUST select the best execution tier.

#### Scenario: MCP tools available
Given the session has `list_log_entries` MCP tool available
When the skill detects tools in Stage 1
Then Tier 1 (MCP) is selected for all subsequent queries

#### Scenario: gcloud CLI available, no MCP
Given `gcloud` is installed and authenticated
When the skill detects tools in Stage 1
Then Tier 2 (Bash with temp-file pattern) is selected

#### Scenario: No tools available
Given neither MCP nor gcloud is available
When the skill detects tools in Stage 1
Then Tier 3 (guidance-only) is selected with Cloud Console instructions

### Requirement: HITL Gate for Mutations
The agent MUST halt and present exact commands before executing any mutating action.

#### Scenario: Restart recommended
Given the agent identifies a service restart as the fix
When it reaches the HITL gate in Stage 1
Then it presents the exact restart command and halts until explicit user confirmation

### Requirement: Structured Postmortem Generation
The skill SHALL generate a postmortem document in a consistent format.

#### Scenario: No template file exists
Given the project has no postmortem template
When the skill reaches Stage 3
Then it uses the built-in schema (8 section headers) and writes to `docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md`

#### Scenario: Project template exists
Given `docs/templates/postmortem.md` exists
When the skill reaches Stage 3
Then it uses the project template instead of the built-in schema

### Requirement: Routing Integration
The skill MUST be routable via the plugin's activation hook.

#### Scenario: Incident keyword triggers skill
Given the user prompt contains "incident" or "postmortem"
When the activation hook scores skills
Then `incident-analysis` appears as a domain skill in DEBUG/SHIP phases

#### Scenario: Phase gating
Given the user prompt contains "incident" but the SDLC phase is DESIGN
When the activation hook scores skills
Then `incident-analysis` does NOT appear (phase-gated to DEBUG/SHIP only)

### Requirement: Session-Start Observability Detection
The session-start hook SHALL detect gcloud CLI availability.

#### Scenario: gcloud installed
Given `gcloud` is on PATH
When the session starts
Then `Observability tools: gcloud=true` is emitted in additionalContext

### Requirement: Autonomous Trace Correlation (v1.1)
The skill SHALL perform bounded one-hop trace correlation when Tier 1 MCP tools are available and explicit failure evidence is present in cross-service span data.

#### Scenario: Clear downstream error span
Given Service A logs contain a trace_id and get_trace reveals Service B with status != OK
When the agent inspects spans in Step 4
Then it MUST query Service B logs scoped to trace_id + resource labels + span time ± 1 minute, synthesize the causal path, and proceed to Step 5

#### Scenario: Timeout cascade
Given Service A failed with timeout/deadline-exceeded and Service B span >= 80% of root span duration and no other non-A span >= 40%
When the agent inspects spans in Step 4
Then it MUST query Service B logs and synthesize the causal path

#### Scenario: Fan-out to multiple services
Given the trace contains failure evidence in 2+ non-Service-A services or 3+ services with any failure signals
When the agent inspects spans in Step 4
Then it MUST present the trace timeline to the user and NOT autonomously choose a service

#### Scenario: No trace field in logs
Given the failing log entries do not contain a trace field
When the agent reaches Step 4
Then it MUST skip Step 4 entirely and proceed to Step 5

#### Scenario: Tier 2 active
Given only gcloud CLI is available (no MCP)
When the agent reaches Step 4
Then it MUST skip Step 4 entirely

### Requirement: Exemplar Trace Selection (v1.1)
The skill MUST select one exemplar trace from the dominant error group when multiple failing requests (>1) are present before entering Step 4.

#### Scenario: Multiple failing requests
Given Stage 2 logs contain more than one failing request with trace fields
When the agent enters Step 4
Then it MUST select one exemplar trace and analyze only that trace

### Requirement: Postmortem Permalink Formatting (v1.2)
The skill SHALL format trace IDs and commit hashes as clickable Markdown links in generated postmortem documents.

#### Scenario: Trace ID in postmortem
Given the postmortem references a trace_id and project_id from Stage 2
When the agent generates the postmortem document
Then the trace reference MUST be formatted as `[Trace TRACE_ID](https://console.cloud.google.com/traces/list?project=PROJECT_ID&tid=TRACE_ID)`

#### Scenario: Cross-project trace references
Given Stage 2 Step 4 correlated Service A and Service B in different projects
When the postmortem references traces from both services
Then Service A trace links MUST use Service A's project_id and Service B trace links MUST use Service B's project_id

#### Scenario: Git commit in postmortem (GitHub-hosted)
Given the postmortem references a deployment commit hash and the remote is GitHub-hosted
When the agent formats the commit reference
Then it MUST format as `[Commit SHORT_HASH](https://github.com/ORG/REPO/commit/FULL_HASH)`

#### Scenario: Non-GitHub remote or command failure
Given `git remote get-url origin` returns a non-GitHub URL or fails
When the agent formats a commit reference
Then it MUST use the raw commit hash without a link

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
