## ADDED Requirements

### Requirement: DB phase-gate decision race with pre-registered rule

The project SHALL decide whether to add a DB-review phase gate to the PDLC by running a
three-arm evaluation (A0 bare REVIEW, B1 external-pointer gate, B2 owned-checklist gate)
against a held-out DB-defect corpus, using a decision rule that is FROZEN before any run.
The gate SHALL NOT be added to routing configuration unless a variant clears the frozen bar.
A "park" outcome (no variant clears the bar) is a valid, logged result.

#### Scenario: Corpus is authored blind to the gate content
- **GIVEN** the B2 owned checklist defines the DB-defect taxonomy the gate would flag
- **WHEN** the held-out corpus is authored
- **THEN** it MUST be produced cross-model (Codex) from the taxonomy WITHOUT access to the
  B2 checklist text, to avoid in-sample overfit
- **AND** it MUST contain planted-defect fixtures AND clean negative fixtures so both
  detection and false-positive rates are measurable

#### Scenario: The cheapest baseline is a real arm
- **WHEN** the race runs
- **THEN** arm A0 MUST be an actual run of the current PDLC REVIEW with no DB gate injected
- **AND** if A0 detection is not beaten by any gate variant by the frozen margin, the
  decision MUST be "park — proven redundant", not "ship anyway"

#### Scenario: Decision rule is pre-registered and honored
- **GIVEN** a decision rule frozen in design.md before the first run (ship the best variant
  only if it beats A0 by ≥20pp detection at ≤10pp false-positive; B1≈B2 → adopt B1)
- **WHEN** scoring completes
- **THEN** the shipped decision MUST follow the frozen rule exactly, with per-arm detection
  and false-positive rates recorded as evidence
- **AND** the rule MUST NOT be altered after results are seen

#### Scenario: Small-n / high-variance safety-stop
- **GIVEN** each fixture-arm pair is run with `--variance ≥5`
- **WHEN** per-arm score ranges across the variance runs overlap between the leading arms
- **THEN** the race MUST halt without declaring a winner and expand the corpus size,
  rather than shipping on noise

#### Scenario: No routing change ships from this change
- **WHEN** this change is completed
- **THEN** no entry in `config/default-triggers.json` or `config/fallback-registry.json`
  is added or modified
- **AND** any decision to build the gate opens a SEPARATE change that carries this race's
  evidence as its justification
