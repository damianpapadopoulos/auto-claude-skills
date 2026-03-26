## ADDED Requirements

### Requirement: Disambiguation Probes
The CLASSIFY stage MUST emit a bounded SHORTLIST artifact in medium-confidence (60-84) and low-confidence (<60) outputs. The shortlist MUST contain the leader plus up to 2 runner-ups meeting all eligibility criteria: non-vetoed, confidence > 40, evaluable_weight > 0, declared `disambiguation_probe`, max 2.

#### Scenario: Medium-confidence probe execution
- **WHEN** CLASSIFY produces a medium-confidence result with eligible runner-ups
- **THEN** one pre-canned read-only probe per runner-up executes, signal evaluator recomputes states, scorer re-ranks, and `disambiguation_round` is marked `completed`

#### Scenario: Anti-looping enforcement
- **WHEN** one probe round has completed for a `classification_fingerprint`
- **THEN** no second probe round SHALL execute for the same fingerprint regardless of post-rerank confidence level

#### Scenario: Probe timeout
- **WHEN** a disambiguation probe times out or fails
- **THEN** target signals MUST remain `unknown_unavailable` and the probe MUST NOT strengthen the candidate

### Requirement: Step 2b in INVESTIGATE
INVESTIGATE MUST include a Step 2b (Targeted Disambiguation Probes) after Step 2 (Extract Key Signals) and before Step 3 (Single-Service Deep Dive). Step 2b MUST consume the SHORTLIST handoff from low-confidence CLASSIFY output.

#### Scenario: Low-confidence handoff
- **WHEN** CLASSIFY routes to INVESTIGATE with low confidence and a SHORTLIST
- **THEN** Step 2b executes probes before the expensive Single-Service Deep Dive

### Requirement: Playbook Disambiguation Probe Schema
Playbooks MAY declare an optional `disambiguation_probe` field. When present, the field MUST include `query_ref` (referencing a key in the same playbook's `queries` map) and `resolves_signals` (non-empty array of canonical signal IDs). The referenced query MUST be read-only and MUST declare a `max_results` payload cap.

#### Scenario: Schema validation
- **WHEN** a playbook declares `disambiguation_probe`
- **THEN** `query_ref` MUST cross-reference a valid query, `resolves_signals` MUST be non-empty, the probe query MUST declare `max_results`, and the probe query MUST be read-only

### Requirement: Step 4b Source Analysis
INVESTIGATE MUST include a conditional Step 4b between Step 4 (Autonomous Trace Correlation) and Step 5 (Formulate Root Cause Hypothesis). Step 4b analyzes source code at the deployed version.

#### Scenario: Bad-release gate
- **WHEN** `recent_deploy_detected` signal is detected OR deploy timestamp falls within incident window or 4h before
- **AND** an actionable stack frame exists AND deployed ref is resolvable
- **THEN** Step 4b executes source analysis at the deployed ref (not HEAD)

#### Scenario: Post-hop workload resolution
- **WHEN** Step 4 shifted investigation to a different service
- **THEN** Step 4b MUST resolve that service's workload identity from trace/log resource labels before proceeding

#### Scenario: Fail-open behavior
- **WHEN** GitHub API is unavailable
- **THEN** Step 4b MUST skip with an explicit warning visible to the user

### Requirement: /investigate Command
An `/investigate` command MUST exist as an entry point that pre-populates MITIGATE scope inputs. It MUST NOT bypass MITIGATE steps (tool detection, inventory, impact quantification).

#### Scenario: Command invocation
- **WHEN** the user runs `/investigate user-service 500s in hb-prod`
- **THEN** the skill MUST load and begin at MITIGATE Stage 1 with pre-populated scope

### Requirement: SLO Burn Rate Signal
A `slo_burn_rate_alert` signal MUST exist in signals.yaml as a context signal. MITIGATE Step 2c MUST check for SLO burn rate alerts and surface them in the investigation summary. The signal is intentionally not wired to any playbook.

#### Scenario: SLO context surfacing
- **WHEN** an SLO burn rate alert fired for the investigated service within the time window
- **THEN** MITIGATE MUST note the alert name, burn rate value, and error budget remaining

### Requirement: SLO Routing Trigger
Both `config/default-triggers.json` and `config/fallback-registry.json` MUST include an SLO burn rate trigger pattern for the incident-analysis skill.

#### Scenario: Routing on burn rate language
- **WHEN** the user prompt contains "SLO burn rate" or "error budget" language
- **THEN** the routing engine MUST activate the incident-analysis skill
