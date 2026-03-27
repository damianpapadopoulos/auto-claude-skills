## ADDED Requirements

### Requirement: Do Now Gate
The report MUST apply a six-requirement gate to all findings before classifying them as Do Now. Items failing any requirement MUST drop to Investigate regardless of confidence level. The six requirements are: (1) exact config diff with derivation, (2) named target owner, (3) numeric time-bounded Outcome DoD with primary and guardrail metrics, (4) pre-change evidence (measured or structural), (5) rollback signal with derived threshold, (6) IaC Location status of Confirmed, Likely, or Search Required.

#### Scenario: Heuristic evidence exclusion
- **WHEN** a finding has heuristic-only evidence basis
- **THEN** it MUST NOT appear in Do Now regardless of other gate requirements being met

#### Scenario: Missing IaC location
- **WHEN** a finding has Unknown IaC location
- **THEN** it MUST drop to Investigate even if all other gate requirements are met

### Requirement: Decision Summary Table
The report MUST include a Decision Summary table capped at 8-12 items with anchor links to detailed sections. Every non-empty category MUST get at least 1 row. After minimum representation, remaining rows SHALL be filled in global priority order: Do Now by impact, then Investigate by urgency, then Needs Decision by deadline.

#### Scenario: More than 12 findings
- **WHEN** the report has more than 12 actionable items
- **THEN** the summary table MUST include a note referencing the detailed sections below

### Requirement: Two-Stage Investigation DoD
Every Investigate item MUST use a two-stage DoD. Stage 1 closes on hypothesis confirmed/refuted with explicit next action documented. Stage 2 MUST be a separate follow-up item with its own numeric outcome DoD.

#### Scenario: Structurally proven gate-blocked item
- **WHEN** a finding has structural or measured evidence but fails a Do Now gate requirement
- **THEN** it MUST land in Investigate with High / Stage 1 readiness and a To Upgrade field stating which gate requirement is missing

### Requirement: Needs Decision Closure
Every Needs Decision item MUST include a Named Decision Owner, advisory Deadline, and Default Recommendation. The deadline MUST NOT auto-execute changes.

#### Scenario: No named owner
- **WHEN** a Needs Decision item lacks a specific named owner
- **THEN** it MUST NOT be rendered with a generic "product owner" or "service owner" placeholder

### Requirement: Verification Scorecard
The report MUST include a Verification Scorecard table with columns: Finding, Baseline, Target, Owner, Merge Date, Review Date, Primary Success Criteria, Guardrail, Confidence.

#### Scenario: Scorecard populated for Do Now items
- **WHEN** the report contains Do Now items
- **THEN** each Do Now item MUST have a corresponding row in the Verification Scorecard with numeric baseline and target values

### Requirement: Global Implementation Standard
The Actionable Findings: Do Now section MUST begin with a Global Implementation Standard block that requires verification of every mutated field against production after merge.

#### Scenario: Threshold change verification
- **WHEN** a Do Now item changes a threshold or query
- **THEN** the Global Implementation Standard MUST instruct the engineer to verify the PromQL condition, thresholds, eval window, and auto_close match the proposed config

## CHANGED Requirements

### Requirement: Report Grouping
The report MUST group findings by action class (Do Now / Investigate / Needs Decision) instead of by confidence band (High / Medium / Needs Analyst).

### Requirement: Systemic Issues Consolidation
Label/Scope Inconsistencies and Coverage Gaps MUST be consolidated into a single Systemic Issues section with four subsections: Ownership/Routing Debt, Dead/Orphaned Config, Missing Coverage, Inventory Health.
