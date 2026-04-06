## ADDED Requirements

### Requirement: Evidence-Only Attribution Constraint
The skill MUST NOT use speculative language ("likely", "probably", "possibly") in synthesis output or YAML blocks when attributing causation. Words expressing uncertainty MAY appear in intermediate investigation notes but MUST NOT appear in final conclusions.

#### Scenario: Multi-service incident with partial evidence
- **WHEN** investigating a multi-service incident where not all services have been independently verified
- **THEN** unverified services MUST be classified as `inconclusive` or `not-investigated`, not speculatively attributed

### Requirement: Application-Logic Analysis
Step 3 (Single-Service Deep Dive) MUST check the application-logic layer for: N+1 call patterns, retry amplification loops, and gRPC connection pinning or caller-skew anomalies.

#### Scenario: Shared dependency under pressure
- **WHEN** a shared dependency (e.g., database, auth service) shows resource saturation
- **THEN** the investigation MUST check dominant callers' application logic for amplification patterns before attributing root cause solely to the shared dependency

### Requirement: Per-Service Attribution Proof
Step 5 MUST require per-service attribution using the 4-state model: `confirmed-dependent`, `independent`, `inconclusive`, `not-investigated`. Each classification MUST be supported by cited evidence.

#### Scenario: Two services failing during same window
- **WHEN** two services fail during the same time window near a shared dependency
- **THEN** each service MUST be independently assessed; temporal correlation alone MUST NOT be treated as causation

### Requirement: Service Attribution YAML Schema
Step 7 investigation_summary YAML MUST include a `service_attribution` block when 2 or more services are affected. Each entry MUST contain `service`, `status` (one of the 4 states), and `evidence` fields.

#### Scenario: Multi-service incident synthesis
- **WHEN** the investigation identifies 2 or more affected services
- **THEN** the YAML output MUST include a `service_attribution` block with one entry per service, each containing a valid 4-state status and supporting evidence

### Requirement: Completeness Gate Q10
Step 8 MUST include Q10: "For multi-service incidents, has each affected service been independently attributed?" Q10 SHALL be in the not-assessed pool (questions 4-10) and MUST be marked N/A for single-service incidents.

#### Scenario: Multi-service attribution completeness
- **WHEN** the completeness gate runs for a multi-service incident
- **THEN** Q10 MUST verify that every affected service has an attribution status other than `not-investigated`
