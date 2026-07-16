# Spec: pdlc-safety — phase-transition enforcement

The plugin MUST deterministically prevent silent skipping of composition-chain
steps. A chain step is "done" only via invocation evidence (`.completed` from
the completion hook, or a branch-ledger record) or an explicit, logged
skip-attestation. Sequencing MUST be enforced at the Skill-invocation boundary
(PreToolUse `^Skill$`) with hard-deny + remedy text; DESIGN/PLAN evidence MAY
join the outbound push gate only after the replay backtest shows <10%
false-block for that predicate. Attestation MUST NOT satisfy
`requesting-code-review` or `verification-before-completion` anywhere. Gates
MUST fail open on errors (exit 0, no output) and deny only on positive,
readable violation evidence. Human `!`-prefixed commands are out of gate scope
by construction.

## Acceptance Scenarios

### Scenario 1: out-of-order Skill invocation is denied with a remedy

- GIVEN an active composition chain whose step 2 (`writing-plans`) has no
  invocation evidence and no attestation
- WHEN the model invokes a later chain member (e.g.
  `superpowers:subagent-driven-development`) via the Skill tool
- THEN the skill-gate MUST emit `permissionDecision: deny` naming
  `writing-plans` and the exact remedies (invoke it, attest with reason, or
  human `!` bypass)
- AND after `writing-plans` gains invocation evidence, the SAME invocation
  MUST be allowed

### Scenario 2: explicit skip-attestation satisfies the gate and leaves a trail

- GIVEN an active chain where `product-discovery` precedes `brainstorming`
  and has no evidence
- WHEN `phase_attest product-discovery "bugfix — covered by existing brief"`
  is recorded and `brainstorming` is invoked
- THEN the invocation MUST be allowed
- AND the attestation MUST appear in the phase-gate events log and in the
  REVIEW-phase gate-status surface

### Scenario 3: attestation never satisfies gating milestones

- GIVEN attestations written for `requesting-code-review` and
  `verification-before-completion` (via direct file write, bypassing the
  helper's refusal)
- WHEN a `git push` is attempted on a chain-covered branch without real
  REVIEW/VERIFY invocation evidence
- THEN the push gate MUST still deny
- AND the skill-gate MUST NOT treat those two steps as attestable in either
  direction

### Scenario 4: scoping and fail-open — no false obstruction

- GIVEN no active composition chain, or a non-chain skill invocation, or a
  malformed/unreadable composition state file
- WHEN any skill is invoked via the Skill tool
- THEN the skill-gate MUST allow (exit 0; no deny output)
- AND WHEN the gate itself errors mid-evaluation
- THEN it MUST exit 0 without emitting a malformed decision object
