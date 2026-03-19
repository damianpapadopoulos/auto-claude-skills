# Incident Analysis — Delta

## ADDED Requirements

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
Then it uses the built-in schema (7 section headers) and writes to `docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md`

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
