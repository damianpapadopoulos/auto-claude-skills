# Delta Spec: project-verification — .verify.yml weakening detection

## ADDED Requirements

### Requirement: Gate-declaration weakening is suspect

The gate-gaming check MUST report `suspect` when the diff it receives deletes a gate entry (`- name:` or `run:` line) inside `.verify.yml`, and the verdict writer MUST include `.verify.yml` in the diff pathspec it feeds the checker. Detection is removal-only (rewrites/additions are a documented limit) and the checker remains advisory and fail-open (exit 0 on every path).

#### Scenario: Removed gate entry flags suspect

- GIVEN a unified diff whose `.verify.yml` hunk deletes a `- name: tests` line and its `run:` line
- WHEN the diff is piped into `gate-gaming-check.sh`
- THEN the output starts with `suspect` and quotes the offending deletion lines

#### Scenario: Unrelated .verify.yml edits stay clean

- GIVEN a unified diff whose `.verify.yml` hunk only adds a new gate entry or edits a comment
- WHEN the diff is piped into `gate-gaming-check.sh`
- THEN the output is `clean`

#### Scenario: name/run keywords outside .verify.yml do not false-positive

- GIVEN a unified diff deleting a `- name:` line inside a GitHub workflow file (not `.verify.yml`)
- WHEN the diff is piped into `gate-gaming-check.sh`
- THEN the `.verify.yml` weakening pattern produces no hit
