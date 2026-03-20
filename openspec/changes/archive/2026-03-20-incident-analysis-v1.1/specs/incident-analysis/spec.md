# Incident Analysis v1.1 — Delta

## MODIFIED Requirements

### Requirement: Autonomous Trace Correlation
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

#### Scenario: Service B logs return no useful signal
Given the one-hop query returns logs that add no useful signal
When the agent completes the Service B query
Then it MUST note the gap in synthesis and proceed to Step 5

## ADDED Requirements

### Requirement: Exemplar Trace Selection
The skill MUST select one exemplar trace from the dominant error group when multiple failing requests (>1) are present before entering Step 4.

#### Scenario: Multiple failing requests
Given Stage 2 logs contain more than one failing request with trace fields
When the agent enters Step 4
Then it MUST select one exemplar trace and analyze only that trace
