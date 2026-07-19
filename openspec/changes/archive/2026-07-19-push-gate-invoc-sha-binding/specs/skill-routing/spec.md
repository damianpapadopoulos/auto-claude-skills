## ADDED Requirements

### Requirement: Invocation-evidence soft SHA-binding

The skill-completion hook MUST record a `<skill> <sha>` sidecar entry (`~/.claude/.skill-invocation-evidence-sha-<token>`) for every successful Skill return whose cwd resolves a git HEAD, and MUST NOT alter the format of the main invocation-evidence JSON string array. The push gate's invocation-evidence leg MUST prefer sidecar records whose SHA is HEAD or a branch-local ancestor of HEAD (the ledger-bridge binding rule) when composing its acceptance advisory, and MUST NOT require a bound record for acceptance — the sidecar is annotation only, never acceptance authority.

*Expectation provenance: issue #133 body + consolidated implementation-context comment (2026-07-19); soft-binding constraint from the PR #130 false-block repro.*

#### Scenario: Bound record upgrades the advisory
- **WHEN** the main evidence array carries a gating milestone and the sidecar holds a record for it (or a review-embedding proxy) whose SHA is branch-bound to the push HEAD
- **THEN** the push is allowed and the advisory names the bound SHA ("SHA-bound"), replacing the unbound advisory text

#### Scenario: Unbound record still accepted (soft binding)
- **WHEN** the sidecar's recorded SHA is a mainline or unrelated commit (e.g. the recording cwd was a different checkout than the push branch)
- **THEN** the push is still allowed via the main-array evidence and the "not branch-bound" advisory stands — the gate MUST NOT deny on SHA mismatch

#### Scenario: Sidecar alone never satisfies the gate
- **WHEN** the sidecar holds branch-bound records for both gating milestones but the main invocation-evidence array is absent
- **THEN** the fail-closed push gate denies — sidecar records are not acceptance evidence

### Requirement: Invocation-evidence advisory dedup

The push gate MUST emit the invocation-evidence acceptance advisory at most once per milestone per guard run, even when both the composition-chain block and the global fail-closed gate consult the invocation-evidence leg, and the deduplication MUST NOT change the leg's acceptance result.

*Expectation provenance: PR #134 review disposition (verified 2× duplication in the ledger-absent + invocation-evidence-present scenario).*

#### Scenario: Chain block and global gate both consult the leg
- **WHEN** composition state lists both gating milestones with `.completed` empty and the same-token invocation evidence carries both
- **THEN** the push is allowed and each milestone's acceptance advisory appears exactly once in the guard output
