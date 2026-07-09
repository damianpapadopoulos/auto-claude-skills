# Spec: skill-creation-gate (delta)

## ADDED Requirements

### Requirement: Owned skills require a content-assertion test

Each owned skill that has at least one trigger regex in `config/default-triggers.json` MUST be referenced by at least one test under `tests/` that asserts on its `SKILL.md`, and the suite MUST fail when one is not.

Detection is by content — a test file that references the path `skills/<name>/` — NOT by
filename, because content tests follow no naming convention. An owned skill is one whose
`invoke` targets this plugin (`auto-claude-skills`). Skills invoked via other plugins are
exempt, and owned skills with no trigger regex (composition-only, e.g. `security-scanner`)
are exempt — the same population as the routing-fixture requirement.

#### Scenario: Missing content test fails CI
- **GIVEN** an owned trigger-routed skill whose `SKILL.md` is referenced by no file under `tests/`
- **WHEN** `bash tests/run-tests.sh` runs
- **THEN** the content-coverage test MUST report a failure (non-zero), so `.verify.yml` blocks merge

#### Scenario: Naming-agnostic detection counts non-uniform names
- **GIVEN** an owned skill `runtime-validation` covered only by `tests/test-validation-skill-content.sh` (name does not match `test-runtime-validation-content.sh`)
- **WHEN** the content-coverage test runs
- **THEN** it MUST NOT report a failure for that skill, because the file references `skills/runtime-validation/`

#### Scenario: External and composition-only skills exempt
- **GIVEN** a skill invoked via `Skill(superpowers:<name>)`, OR an owned skill with an empty `triggers` array
- **WHEN** the content-coverage test runs
- **THEN** it MUST NOT report a failure for that skill
