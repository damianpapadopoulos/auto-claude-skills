# behavioral-evaluation Specification

## Purpose

Opt-in behavioral evaluation harness for installed skills. Wraps a SKILL.md verbatim in `<skill_guidance>` tags around a fixture-prompt `<user_request>`, invokes `claude -p --output-format json`, and asserts case-insensitive ERE regexes from `assertions[].text` against the captured raw output. Provides regression signal for skill behavior that schema validation and content-grep tests cannot reach (e.g. "does the skill actually emit Step 7 synthesis with the expected sections when invoked"). Per-run JSON artifact under `tests/artifacts/`. Opt-in via `BEHAVIORAL_EVALS=1` so the default test suite stays free of LLM cost; CI gating waits until the runner catches a real regression.

## Requirements
### Requirement: Opt-In Execution Gate

The behavioral eval runner MUST refuse to execute unless `BEHAVIORAL_EVALS=1` is set in the environment, and MUST NOT be registered in the default `tests/run-tests.sh` suite.

#### Scenario: Missing opt-in env var
- **WHEN** `tests/run-behavioral-evals.sh` is invoked without `BEHAVIORAL_EVALS=1`
- **THEN** the runner prints an opt-in notice that names `BEHAVIORAL_EVALS`, exits with code 2, and does not invoke `claude`, read any pack, or emit any artifact

#### Scenario: Default suite unaffected
- **WHEN** `tests/run-tests.sh` runs
- **THEN** it MUST NOT invoke `tests/run-behavioral-evals.sh`; the hermetic self-test `tests/test-run-behavioral-evals.sh` MAY run because it stubs `claude` via `CLAUDE_BIN`

### Requirement: Explicit Pre-Flight Failure Modes

The runner MUST fail with exit code 2 and a specific error that names the missing precondition for every recoverable failure before invoking `claude`.

#### Scenario: claude binary missing
- **WHEN** `CLAUDE_BIN` points to a nonexistent path (or `claude` is not on `PATH`)
- **THEN** the runner emits an error naming the missing binary and exits 2 without attempting any invocation

#### Scenario: required argument missing
- **WHEN** the runner is invoked without `--scenario <id>`
- **THEN** the runner emits an error naming `--scenario`, prints usage, and exits 2

#### Scenario: scenario id not in pack
- **WHEN** the runner is invoked with a `--scenario <id>` that does not appear in the pack
- **THEN** the runner emits an error naming the unknown id and exits 2

#### Scenario: scenario missing required field
- **WHEN** the selected scenario is missing `id`, `prompt`, `expected_behavior`, or `assertions` (or has an empty `assertions` array)
- **THEN** the runner emits a schema error that names the missing field and the scenario id, and exits 2

### Requirement: Explicit Skill Loading

The runner MUST load the target skill's `SKILL.md` verbatim from disk and prepend it as `<skill_guidance>` tags wrapping the scenario prompt in `<user_request>` tags. It MUST NOT rely on the skill-activation hook, composition state, or trigger regex matching to select which skill is under test.

#### Scenario: Shipped SKILL.md is evaluated
- **WHEN** the runner constructs the prompt for `claude -p`
- **THEN** the `<skill_guidance>` block MUST contain the current content of `${SKILL_PATH:-skills/incident-analysis/SKILL.md}` verbatim, and the `<user_request>` block MUST contain the scenario's `prompt` field unmodified

#### Scenario: Skill file missing
- **WHEN** `SKILL_PATH` points to a nonexistent file
- **THEN** the runner emits an error naming the missing file and exits 2 without invoking `claude`

### Requirement: Mechanism-Derived Verdict

The runner MUST derive its verdict from the actual captured `claude -p` output, not from the scenario's declared `expected_behavior`. Each `assertions[].text` MUST be applied as a case-insensitive extended regex via `grep -E -i -q`. The overall scenario verdict MUST be PASS iff every assertion regex matches at least once.

#### Scenario: Response satisfies all assertions
- **WHEN** the captured output matches every `assertions[].text` regex at least once
- **THEN** the runner emits `PASS [i]: <description>` for each assertion, prints `OVERALL PASS`, writes an artifact with `overall_passed: true`, and exits 0

#### Scenario: Response fails any assertion
- **WHEN** the captured output fails to match at least one `assertions[].text` regex
- **THEN** the runner emits `FAIL [i]: <description>` for each failing assertion, prints `OVERALL FAIL`, writes an artifact with `overall_passed: false`, and exits 1

### Requirement: Artifact Emission

The runner MUST write a JSON artifact per run to `${ARTIFACTS_DIR:-tests/artifacts}/${scenario_id}-${UTC-timestamp}.json`. The artifacts directory MUST be gitignored. The artifact MUST contain `scenario_id`, `timestamp_utc`, `model`, `prompt`, `raw_output`, `assertions` (array of `{index, description, regex, passed}`), `overall_passed`, and `elapsed_seconds`.

#### Scenario: Artifact contains captured output and verdict
- **WHEN** the runner finishes evaluation
- **THEN** the artifact file exists, is valid JSON, and every field is populated with values derived from the actual run (not the fixture's expected_behavior string)

#### Scenario: Model identifier survives both mock and real response shapes
- **WHEN** the response is from `mock-claude.sh` (top-level `.model` field)
- **THEN** the artifact's `model` equals the mock's model id (not `"unknown"`)
- **AND WHEN** the response is from real `claude -p --output-format json` (nested `.modelUsage` keyed by model id)
- **THEN** the artifact's `model` equals the first key of `.modelUsage` (not `"unknown"`)

### Requirement: Hermetic Self-Test

The runner MUST ship with a self-test at `tests/test-run-behavioral-evals.sh` that exercises every failure mode and the pass/fail verdicts, using a stub binary for `claude`. The self-test MUST NOT make any real API call and MUST run as part of the default `tests/run-tests.sh` suite.

#### Scenario: Self-test runs green without claude
- **WHEN** `tests/run-tests.sh` runs on a machine where `claude` is absent
- **THEN** `test-run-behavioral-evals.sh` still passes because every test case overrides `CLAUDE_BIN` to point at the in-repo mock

### Requirement: CAST Behavioral Eval Fixture

The behavioral-eval corpus at `tests/fixtures/incident-analysis/evals/behavioral.json` MUST include a scenario with id `cast-systemic-factors-coverage` covering the CAST surface added in PR #18 (Step 7 items 9–10 and Step 8 Q12). The fixture's prompt SHALL be derived from a postmortem (`docs/postmortems/2026-04-08-hcs-gb-billing-tab-500-calendar-api-removed.md`) that was not used during CAST design, so the eval is an independent regression signal rather than a circular test against the evidence that shaped the surface.

#### Scenario: Fixture exists and parses
- **WHEN** the schema validation test runs (`bash tests/test-incident-analysis-evals.sh`)
- **THEN** the fixture file parses
- **AND** the array contains an entry with `id: cast-systemic-factors-coverage`
- **AND** the entry has the required fields `id`, `prompt`, `expected_behavior`, `assertions[]`

#### Scenario: Strict assertion set
- **WHEN** the fixture is inspected
- **THEN** it contains regex assertions covering at minimum: the `Mental model gaps` section header; a controller-belief shape regex (`believed.*actual`); the `Systemic factors` section header; each of the five CAST category names verbatim (`Safety Culture`, `Communication/Coordination`, `Management of Change`, `Safety Information System`, `Environmental Change`); a pointer to `references/cast-framing.md`

#### Scenario: Independent prompt source
- **WHEN** the fixture's `expected_behavior` and `prompt` are reviewed
- **THEN** the prompt is sourced from the 2026-04-08 billing-tab postmortem
- **AND** the prompt does NOT use language from the OCS-logouts postmortem that anchored CAST design

### Requirement: Default Test Suite Stays Free of `claude -p`

The default test runner (`bash tests/run-tests.sh`) MUST NOT invoke `claude -p` against any behavioral-eval scenario, including the new CAST fixture. The behavioral-eval runner SHALL remain opt-in via the `BEHAVIORAL_EVALS=1` environment variable only.

#### Scenario: Default run elapsed time
- **WHEN** `bash tests/run-tests.sh` runs in a clean environment
- **THEN** it completes in under 120 seconds (a `claude -p` invocation alone takes 60–240 seconds; the default suite finishing under 120s is evidence the runner was not invoked)
- **AND** all test files pass

#### Scenario: Default run produces no eval artifact
- **WHEN** `bash tests/run-tests.sh` runs
- **THEN** no new file is written to `tests/artifacts/`

### Requirement: README Lists Notable Scenarios

The fixture-set README at `tests/fixtures/incident-analysis/evals/README.md` MUST list `cast-systemic-factors-coverage` under a "Notable scenarios" subsection or equivalent, with provenance noted (the prompt comes from a postmortem the CAST design did not see).

#### Scenario: README lookup
- **WHEN** a contributor reads the README to understand what the corpus covers
- **THEN** the CAST fixture is named
- **AND** the provenance note explaining why the prompt is independent of CAST design is present

