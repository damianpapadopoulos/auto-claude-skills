# Incident Analysis Critique Fixes — Delta

## ADDED Requirements

### Requirement: Scope Restriction Infrastructure Exception
Constraint 2 (Scope Restriction) SHALL qualify its restriction to application-level queries and MUST include an explicit infrastructure escalation exception.

#### Scenario: Application-level queries remain scoped
Given the agent is investigating at the application level
When it queries logs, reads files, or searches code
Then all queries MUST be constrained to the specific service or trace ID from Stage 1

#### Scenario: Infrastructure escalation expands scope
Given Step 3 identifies multi-pod or multi-service failures indicating a node-level root cause
When the agent escalates to infrastructure investigation
Then the scope expands to the affected node(s) and their infrastructure signals (kubelet logs, serial console, audit logs, node-level metrics), bounded to implicated nodes only

#### Scenario: Completeness gate permits peer-node checks
Given the agent reaches completeness gate Q6 (systemic risk)
When it checks whether peer nodes are at similar risk
Then the scope exception permits queries against peer nodes

### Requirement: High-Confidence Decision Record Safety Fields
The high-confidence decision record template MUST include all spec-required safety fields.

#### Scenario: Evidence age present
Given a high-confidence decision record is presented
When the user reviews the record
Then the record includes an Evidence Age field showing seconds since oldest signal query and the freshness window

#### Scenario: Veto signals section present
Given a high-confidence decision record is presented
When the user reviews the record
Then the record includes a VETO SIGNALS section showing evaluated veto signals and their states

#### Scenario: State fingerprint present
Given a high-confidence decision record is presented
When the user reviews the record
Then the record includes a State Fingerprint field for EXECUTE recheck comparison

#### Scenario: Explanation present
Given a high-confidence decision record is presented
When the user reviews the record
Then the record includes an Explanation field summarizing why this playbook was selected over alternatives

### Requirement: Step 7 Synthesis Completeness
Step 7 synthesis MUST preserve all material needed by the Investigation Path appendix.

#### Scenario: Ruled-out hypotheses preserved
Given the agent transitions from INVESTIGATE to POSTMORTEM
When it writes the Step 7 synthesis
Then the synthesis MUST include each ruled-out hypothesis with disconfirming evidence and elimination rationale

#### Scenario: Hypothesis revisions preserved
Given the investigation involved direction changes
When the Step 7 synthesis is written
Then it MUST include where the investigation changed direction, what triggered each revision, and what the previous hypothesis was

### Requirement: Postmortem Schema Section Count
The built-in postmortem schema SHALL have 8 section headers (not 7).

#### Scenario: Spec reflects canonical section count
Given the OpenSpec contract references the built-in schema
When it describes the section count
Then it MUST say "8 section headers"

### Requirement: Evidence Persistence Operationalized
The EXECUTE and VALIDATE stages MUST include explicit evidence-writing steps.

#### Scenario: Pre-execution evidence written
Given the agent passes the fingerprint recheck in EXECUTE
When it prepares to execute the command
Then it MUST write sanitized pre.json to the evidence bundle before executing

#### Scenario: Validation evidence written on success
Given validation succeeds
When the agent records verification_status: verified
Then it MUST write sanitized validate.json to the evidence bundle

#### Scenario: Validation evidence written on failure
Given validation fails
When the agent records verification_status: failed
Then it MUST write sanitized validate.json to the evidence bundle

#### Scenario: Validation evidence written when inconclusive
Given validation is inconclusive
When the user is presented with options
Then validate.json MUST be written regardless of which option is chosen
