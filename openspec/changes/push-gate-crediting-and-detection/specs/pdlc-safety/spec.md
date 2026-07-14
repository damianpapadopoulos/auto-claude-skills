# pdlc-safety (delta)

## ADDED Requirements

### Requirement: Push-gate REVIEW milestone credited to review-embedding skills

The durable branch-ledger REVIEW milestone that the push gate reads MUST be
recorded not only when `requesting-code-review` completes, but also when any
review-embedding skill completes: `subagent-driven-development`,
`agent-team-execution`, or `agent-team-review`. These MUST be recorded under the
canonical milestone key `requesting-code-review` so that existing gate readers are
satisfied without modification. `executing-plans` MUST NOT be credited as REVIEW
(it has no mandated review step). `verification-before-completion` MUST continue
to record under its own key, unchanged. Recording MUST remain fail-open: a missing
ledger library or absent `jq` MUST NOT raise or block.

#### Scenario: Subagent-driven review satisfies the push gate

- **GIVEN** a branch whose review was performed via `subagent-driven-development`
  (which completed), and `verification-before-completion` has also completed, but
  the literal `requesting-code-review` skill was never invoked
- **WHEN** the agent runs `git push` through the Bash tool and the push gate evaluates
- **THEN** the gate MUST find a `requesting-code-review` branch-ledger milestone
  (recorded on `subagent-driven-development` completion) and MUST NOT deny the push
  for a missing REVIEW record

#### Scenario: executing-plans does not count as review

- **GIVEN** a branch where only `executing-plans` completed (no review-embedding
  skill, no `requesting-code-review`)
- **WHEN** the push gate evaluates a `git push`
- **THEN** the gate MUST NOT treat REVIEW as satisfied on the basis of
  `executing-plans`, and MUST deny with the REVIEW remediation message

#### Scenario: Recording is fail-open without jq

- **GIVEN** a review-embedding skill completes in an environment where `jq` or the
  branch-ledger library is unavailable
- **WHEN** `skill-completion-hook.sh` runs
- **THEN** it MUST exit without error and MUST NOT block the session (no milestone
  is recorded; the gate's own fail-open path governs)

### Requirement: git-write gate fires only on real git push/commit invocations

The push/commit gate MUST determine whether a Bash command actually invokes
`git push` or `git commit` by inspecting the first token of each shell-separated
segment (after stripping `VAR=val`/`env` prefixes and git global flags such as
`-C`, `-c`, `--no-pager`, `--git-dir`, `--work-tree`). A command in which
`git push` or `git commit` appears only as an argument or string to another
command MUST NOT trigger the gate. Detection MUST be fail-open: on any parse
failure the gate MUST NOT raise.

#### Scenario: A read-only command containing the phrase is not gated

- **GIVEN** the command `grep -nE "git push|deny" hooks/openspec-guard.sh`
- **WHEN** the PreToolUse push-gate hook evaluates it
- **THEN** the hook MUST NOT treat it as a git write and MUST NOT deny it

#### Scenario: A real push is still gated

- **GIVEN** the command `git -C /repo push -u origin feature/x` on a branch with no
  REVIEW milestone
- **WHEN** the PreToolUse push-gate hook evaluates it
- **THEN** the hook MUST recognize it as a git push and MUST apply the fail-closed
  REVIEW/VERIFY gate (deny with remediation when evidence is absent)

#### Scenario: A commit chained after an env prefix is detected

- **GIVEN** the command `GIT_AUTHOR_NAME=x git commit -m "msg"`
- **WHEN** the PreToolUse hook evaluates it
- **THEN** the hook MUST recognize it as a git commit (first non-assignment token is
  `git`, subcommand `commit`) and apply the gate
