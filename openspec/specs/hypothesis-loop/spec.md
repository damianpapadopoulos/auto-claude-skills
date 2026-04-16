## ADDED Requirements

### Requirement: Discovery Brief Hypothesis Section
The product-discovery brief template MUST include a Hypotheses section with structured fields: Metric, Baseline, Target, Window. Each hypothesis MUST be numbered (H1, H2, etc.). All structured fields MAY be nullable at discovery time.

#### Scenario: Discovery creates hypothesis artifact
- **WHEN** product-discovery completes and the user approves the brief
- **THEN** the brief is saved to `docs/plans/YYYY-MM-DD-<slug>-discovery.md` with the Hypotheses section, and `discovery_path` is set in session state

### Requirement: Hypothesis Extraction at Ship Time
openspec-ship Step 7a-bis MUST extract hypotheses from the discovery artifact into session state before Step 7b archives the file. The extraction MUST produce a JSON array with id, description, metric, baseline, target, and window fields per hypothesis.

#### Scenario: Hypotheses extracted before archival
- **WHEN** openspec-ship runs and `discovery_path` exists in session state
- **THEN** `changes.<slug>.hypotheses` is populated in session state as a JSON array before the discovery artifact is moved to `docs/plans/archive/`

#### Scenario: No discovery — graceful skip
- **WHEN** openspec-ship runs and `discovery_path` is absent in session state
- **THEN** `hypotheses` stays null in session state; no error is raised

### Requirement: Learn Baseline Written on Ship Event
The `write-learn-baseline` SHIP composition step MUST write a baseline file to `~/.claude/.skill-learn-baselines/<slug>.json` only when a ship event (merge or PR) is detected. The baseline MUST include denormalized hypothesis entries from session state.

#### Scenario: Merge triggers baseline write
- **WHEN** finishing-a-development-branch completes with Option 1 (merge local)
- **THEN** a baseline file exists with `ship_method: "merge_local"`, non-null `shipped_at`, and the hypotheses array from session state

#### Scenario: Keep/discard does not write baseline
- **WHEN** finishing-a-development-branch completes with Option 3 (keep) or Option 4 (discard)
- **THEN** no baseline file is written

### Requirement: Outcome Review Consumes Hypotheses
outcome-review MUST use the baseline's `hypotheses` array (when non-null) to guide metric queries and MUST present a Hypothesis Validation table with per-hypothesis status. When `hypotheses` is null, outcome-review MUST fall back to the existing generic metrics flow.

#### Scenario: Hypothesis-guided outcome review
- **WHEN** outcome-review is invoked and a baseline with non-null hypotheses is found
- **THEN** the outcome report includes a Hypothesis Validation table with one row per hypothesis, each with an Actual value and a Status (Confirmed, Not confirmed, Inconclusive, or Partially confirmed)
