# Proposal: Push-gate review crediting + precise git-write detection (REVIEW/SHIP)

## Why

The fail-closed push gate in `hooks/openspec-guard.sh` is the plugin's single
hard SDLC enforcement point, but two defects surfaced in a real driven session
(building a feature in a downstream repo) made it both **over-block** and
**under-credit**:

1. **Review done via a review-embedding skill is not credited.** The gate credits
   REVIEW only when the literal `requesting-code-review` skill completes
   (`skill-completion-hook.sh:74-84` records the branch-ledger milestone only for
   that name). A branch reviewed via `subagent-driven-development` (mandated
   per-task reviews **and** a whole-branch review), `agent-team-execution`
   (reviewer-gated), or `agent-team-review` records nothing the gate accepts. The
   gate then denies the push — and the human bypasses it from their terminal
   (the documented escape hatch), shipping the change **with the review evidence
   never recorded**. Net: real review happened, the gate fired anyway, and the
   ledger was left wrong. This is the recurring "blocked-then-bypassed" failure.

2. **The `git push` / `git commit` trigger matches as a raw substring.** The gate
   uses `case "${_COMMAND}" in *"git push"*)` (openspec-guard.sh:26, :59), so any
   command whose text merely *contains* the phrase — `grep "git push" …`, an
   `echo`, a comment — is treated as a push and can be denied. Observed: a
   read-only `grep` was hard-denied during investigation. This trains users to
   distrust and route around the gate.

Both erode the exact guardrail the plugin exists to provide, so both are fixed at
the plugin source (not a downstream repo).

## What Changes

- **Fix #2 — credit review-embedding skills (writer-side normalization).** Extend
  the milestone-recording `case` in `skill-completion-hook.sh` so that
  `subagent-driven-development`, `agent-team-execution`, and `agent-team-review`
  each record the durable branch-ledger REVIEW milestone under the **canonical
  key `requesting-code-review`**. Every existing reader (4 sites in
  `openspec-guard.sh`, the SHIP advisory in `skill-activation-hook.sh`) is
  satisfied unchanged.
- **Fix #3 — first-token git-write detection.** Add a helper that decides whether
  a command actually *invokes* `git push` / `git commit` by inspecting the first
  token of each shell segment (after stripping `VAR=val`/`env` prefixes and git's
  global flags), and replace both raw-substring `case` matches with it. A phrase
  appearing as an argument/string to another command no longer trips the gate.

## Capabilities

- **Modified: pdlc-safety** — push-gate REVIEW crediting now recognizes
  review-embedding skills; the git-write trigger fires only on real invocations.

No change to: the fail-closed posture, the REVIEW→VERIFY→SHIP order, the
routing-governance gate, verdict-at-HEAD hardening, or the human/env bypass
semantics.

## Impact

- **Affected code:** `hooks/skill-completion-hook.sh` (one `case` arm added),
  `hooks/openspec-guard.sh` (two trigger checks routed through one new helper;
  optional shared helper in `hooks/lib/`).
- **Affected tests:** `tests/test-completion-ledger.sh`,
  `tests/test-branch-ledger.sh`, plus a new/extended gate-detection test.
- **Risk:** this is a guardrail change (adversarial-review category). Fix #2
  marginally widens what counts as REVIEW (trusts the review-embedding skills'
  mandated review, same "skill-ran" proxy already used for
  `requesting-code-review`). Fix #3 trades the current false-positive-heavy /
  false-negative-free substring match for first-token detection, accepting rare
  false-negatives for wrapper forms (`bash -c "git push"`, aliases) — judged
  acceptable because the gate is a strong default, not airtight (human-terminal
  and `ACSM_SKIP_PUSH_GATE` bypasses exist by design). Both accepted by the gate
  owner. See design.md Trade-offs.
- **First increment** of a larger phase-gate enforcement program (Increments 2-5:
  canonical phase→required-skill map, an IMPLEMENT edit-gate, REVIEW hardening
  for security-scanner/agent-team-review, DISCOVER/LEARN bookends) to be scoped
  in a separate discovery.
