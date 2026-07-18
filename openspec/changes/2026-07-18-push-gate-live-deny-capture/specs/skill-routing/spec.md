# Delta: skill-routing — push-gate live-invocation capture

## ADDED Requirements

### Requirement: Push-gate live-invocation diagnostic capture

The push gate (`hooks/openspec-guard.sh`) MUST emit a diagnostic capture record
for every push/merge-classified invocation, WITHOUT altering any allow/deny
decision. The capture MUST run off the decision path: the guard MUST NOT
`source` any capture code (a source-time failure could trip the fail-open ERR
trap and skip enforcement); capture MUST be performed by a subprocess invoked
only from a hardened EXIT trap that disables the ERR/EXIT traps and fully
redirects stdio so no byte reaches the hook's stdout (preserving the
one-JSON-object contract). The record MUST identify the running file
(`$0`/`BASH_SOURCE`/`cksum`) and the live decision (`allow` or `deny:<gate>`).
On a deny, the record MUST additionally carry a recursion-guarded true replay of
the on-disk guard against the identical original stdin. Logged commands MUST be
redacted of credentials by default (env-prefix and URL-userinfo), with the raw
command opt-in; the log file MUST be created mode `0600`. The capture MUST be
fail-open (jq absent, unwritable log, or missing helper never blocks or errors
the guard) and MUST be excluded from the gate-enforcement canary manifest
(`_GATE_ENFORCE_LIBS`), being diagnostic-only.

#### Scenario: allow path records the live decision without replay

- **GIVEN** a `git push` the guard would ALLOW
- **WHEN** the guard runs to completion
- **THEN** exactly one JSONL record is appended with `decision: "allow"`, the
  running file's `cksum`, and no replay fields
- **AND** the hook's stdout is unchanged (no capture bytes leak)

#### Scenario: deny path records live decision plus a true on-disk replay

- **GIVEN** a `git push` the guard would DENY at the global fail-closed gate
- **WHEN** the guard emits its deny decision and exits
- **THEN** the appended record carries `decision: "deny:global-failclosed"` and
  an `ondisk_replay` field produced by re-running the on-disk guard against the
  identical original stdin with `PUSH_GATE_CAPTURE_DISABLE=1`
- **AND** the replay subprocess writes no record of its own and installs no trap

#### Scenario: capture is fail-open and secret-safe

- **GIVEN** a push command of the form `GH_TOKEN=secret gh pr merge …` or
  `git push https://token@host/repo`
- **WHEN** the capture runs (or when jq is absent / the log dir is unwritable)
- **THEN** the guard's decision and stdout are unaffected
- **AND** no credential substring appears verbatim in the log; `command_sha`
  and `command_len` are present instead
