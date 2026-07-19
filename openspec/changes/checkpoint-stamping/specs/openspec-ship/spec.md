# Spec: openspec-ship checkpoint stamping

## ADDED Requirements

### Requirement: Per-task checkpoint stamps in retrospective tasks.md

When a Superpowers execution plan is provided, `openspec-ship` MUST attempt to attribute each completed task to a branch commit from `git log <merge-base>..HEAD`, MUST append ` [checkpoint: <sha7>]` only when exactly one in-range commit matches the task (by task number or strong keyword), and MUST leave unattributable or ambiguous tasks unstamped. The generated `tasks.md` MUST carry a header note stating that after squash-merge checkpoint SHAs are typically recoverable only via the feature's GitHub PR (`gh pr view <N> --json commits`) and are not fetched by plain clones or forks. The no-plan placeholder variant of `tasks.md` MUST NOT be stamped.

#### Scenario: Confident attribution is stamped

- **WHEN** a completed task maps unambiguously to a branch commit
- **THEN** the task line ends with `[checkpoint: <sha7>]` where `<sha7>` is that commit's abbreviated SHA

#### Scenario: Unattributable task stays bare

- **WHEN** no branch commit can be confidently attributed to a completed task
- **THEN** the task line carries no checkpoint suffix

### Requirement: Deterministic checkpoint validation before openspec validate

`openspec-ship` MUST run `scripts/checkpoint-validate.sh` on the generated `tasks.md` before the validate step, MUST repair or remove failing stamps when the validator exits 1, and MUST include the validator's `checkpoints: N stamped / M completed tasks` summary line in the ship report. The validator MUST validate every stamp on a line (not only the first), MUST case-normalize stamps before comparison, MUST exit 1 when any stamp is malformed (not exactly 7 hex characters) or references a commit outside `merge-base..HEAD`, and MUST exit 2 (reported, non-blocking) when it cannot run at all. The validator is scoped to pre-merge feature-branch use; re-validating archived `tasks.md` after squash-merge is unsupported.

#### Scenario: Foreign SHA rejected

- **WHEN** a `[checkpoint: <sha>]` stamp references a commit not contained in `merge-base..HEAD`
- **THEN** the validator exits 1 and names the offending stamp

#### Scenario: Bare tasks are counted, not penalized

- **WHEN** `tasks.md` contains completed tasks without checkpoint stamps
- **THEN** the validator exits 0 (given all present stamps are valid) and reports them in the `N stamped / M completed tasks` summary
