# Proposal: scenario-coverage report precision

## Why

The behavioral-pack coverage report (`scripts/scenario-coverage.sh`, shipped in `spec-eval-loop-decision`) counted probabilistic-verb matches across every line of a capability spec. That counted incidental matches inside `### Requirement:` / `#### Scenario:` headings and `GIVEN`/`WHEN` preconditions, and treated static-artifact assertions (doc/banner/`.md`/config-flag content) as model behavior. A triage of the report's own output found it over-flagged documentation/guidance capabilities: `unified-context-stack` showed 31 "uncovered" probabilistic clauses when its genuine behavioral count is ~0. An advisory report that cries wolf on its largest flagged item erodes trust.

## What Changes

`scripts/scenario-coverage.sh` now counts probabilistic verbs only in OUTCOME lines: it drops markdown headings and `GIVEN`/`WHEN` precondition lines, and subtracts a static-artifact negative filter. Net effect: `unified-context-stack` clears (31→1, below threshold); `alert-hygiene` stays flagged (5 genuine behavioral outcomes, no pack — the one true gap); backfilled packs stay covered; counts are more honest (`incident-analysis` 32→11). TDD with two isolating fixtures (`doc-cap`, `heading-noise-cap`).

## Capabilities

- **Modified:** `behavioral-evaluation` — adds a precision requirement to the coverage report (ADDED form).

## Impact

- `scripts/scenario-coverage.sh` — narrowed `pcount` computation (~6 LOC).
- `tests/test-scenario-coverage.sh` — two new fixtures + assertions (RED-verified).
- Advisory + fail-open posture unchanged; no gate touched.
