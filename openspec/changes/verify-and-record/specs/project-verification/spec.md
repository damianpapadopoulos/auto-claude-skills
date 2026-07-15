# Delta: project-verification — deterministic verdict writer

## ADDED Requirements

### Requirement: Verdict content is measured, not model-authored, when the gate is declared

The verification verdict SHALL be written by `scripts/verify-and-record.sh`
whenever the target repository declares its gate in `.verify.yml` with
`substrate: local`: the script runs the declared commands itself and records
`passed`/`failed`/`could_not_verify` and `gate_gaming_status` from its own
measured exit codes and check output. The model SHALL invoke the script
rather than authoring the verdict JSON. When `.verify.yml` is absent, the
skill MUST first offer to create one; the model-authored flow remains the
documented fallback and MAY require per-instance user approval.

#### Scenario: failing gate recorded honestly

- GIVEN a repository whose `.verify.yml` declares a command that exits
  non-zero
- WHEN `verify-and-record.sh` runs
- THEN the written verdict lists that command name in `failed[]` and the
  artifact does not satisfy `verdict_is_clean`

#### Scenario: passing gate produces a clean, sha-bound verdict

- GIVEN a repository whose declared gate exits 0 and whose review diff passes
  the gate-gaming check
- WHEN the script runs
- THEN the verdict records the command in `passed[]`, `failed` and
  `could_not_verify` empty, `gate_gaming_status: clean`, and `sha` equal to
  the repository HEAD

#### Scenario: unrunnable command is never a pass

- GIVEN a declared command whose runner is missing (exit 127)
- WHEN the script runs
- THEN the command name is recorded in `could_not_verify[]`

#### Scenario: no declared gate, no silent verdict

- WHEN the script runs in a repository without `.verify.yml`, or with a
  substrate other than `local`
- THEN it exits non-zero and writes no verdict artifact
