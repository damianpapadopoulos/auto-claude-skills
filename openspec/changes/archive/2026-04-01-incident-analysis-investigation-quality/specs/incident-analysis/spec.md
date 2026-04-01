## ADDED Requirements

### Requirement: Timeline Extraction Step
The INVESTIGATE stage MUST include a Step 6b (Timeline Extraction) between Flight Plan
(Step 6) and Synthesis (Step 7) that extracts candidate timeline events from all evidence
collected during Steps 1-5.

Each candidate event MUST include timestamp_utc, time_precision (exact|minute|approximate),
event_kind (log_entry|metric_alert|deploy_event|probe_event|user_report|recovery_signal),
description, and evidence_source.

Step 7 MUST curate the candidate list from Step 6b rather than reconstructing from scratch.

#### Scenario: Dedupe at different precisions
- **WHEN** two events describe the same occurrence at different precisions
- **THEN** the higher-precision entry MUST be kept and the lower-precision entry removed

#### Scenario: Low-confidence re-entry
- **WHEN** entered from the CLASSIFY low-confidence path
- **THEN** Step 6b MUST be skipped (only Steps 1-5 run)

### Requirement: Cross-Reference Commits with Log Patterns
Source analysis Step 4.5 MUST annotate each regression candidate with explains_patterns[]
and cannot_explain_patterns[] linking the commit to observed production errors.

#### Scenario: No candidate explains dominant error
- **WHEN** no regression candidate's explains_patterns includes the dominant error pattern
- **THEN** a cross_reference_note MUST be emitted weakening the bad-release hypothesis
- **AND** reviewed candidates MUST be preserved (not replaced with empty list)

### Requirement: Bounded Expansion Fallback
Source analysis Step 4.5b MUST fire when no candidate explains the dominant error pattern,
expanding search by same-commit siblings (max 5) then same-package peers (max 3).

#### Scenario: Expansion stops on first candidate
- **WHEN** a same-commit sibling explains the dominant error
- **THEN** same-package expansion MUST NOT proceed

#### Scenario: Expansion tracks provenance
- **WHEN** expansion finds a candidate or exhausts search
- **THEN** analysis_basis MUST be set to primary_frame, bounded_expansion_same_commit, or bounded_expansion_same_package

### Requirement: Config-Change Source Analysis Trigger
Step 4b MUST fire on repo-backed config changes when config_change_correlated_with_errors
signal is detected AND a resolvable deployed ref exists.

#### Scenario: Console-only config change
- **WHEN** a config change has no git ref (ConfigMap console edit)
- **THEN** Step 4b MUST NOT fire via the config-change path

#### Scenario: User override
- **WHEN** the user explicitly requests source analysis
- **THEN** the category gate (condition 3) MUST be bypassed
- **AND** conditions 1-2 (actionable frame, resolvable ref) MUST still be enforced
