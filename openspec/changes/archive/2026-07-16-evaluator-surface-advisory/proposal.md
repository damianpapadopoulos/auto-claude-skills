# Proposal: Protected-evaluator-surface advisory

## Why

A branch can edit the files that define what "verified" means — `.verify.yml` (the declared gate), `hooks/lib/verdict.sh` (the clean-predicate), `scripts/verify-and-record.sh` (the verdict writer), `skills/project-verification/scripts/gate-gaming-check.sh` (the gaming tripwire) — and still record a clean verdict that satisfies every push-gate deny path. Routing-governance covers `hooks/` and `skills/` paths, but the clean verdict it demands is produced by the very machinery being edited (self-referential evidence); `.verify.yml` and `scripts/verify-and-record.sh` are covered by no check at all: the gate-gaming diff pathspec is `'*test*' '*spec*'`, which matches neither.

Adopted from the selfpatch triage (2026-07-15): selfpatch's "protected surfaces" principle — the most dangerous self-edit is the one that changes what "good" means — applied narrowly and advisory-first, per this repo's own false-block evidence (gate-status backtest: deny variants 56–94% false-block, 0 catches in 108 PRs).

## What Changes

1. `hooks/lib/verdict.sh` gains an `_EVALUATOR_SURFACES` list and a fail-open `diff_touches_evaluator` predicate (branch diff vs `_routing_base`, prints matched files).
2. `hooks/openspec-guard.sh` appends an advisory (never a deny) to a `git push` whose branch diff touches an evaluator surface, naming the files and the self-reference risk; push advisories now also emit outside SHIP phase (previously silently dropped by the SHIP-phase early-exit).
3. `skills/project-verification/scripts/gate-gaming-check.sh` flags deletions of `- name:` / `run:` entries inside `.verify.yml` hunks as `suspect` (file-tracked via `+++ b/` headers).
4. `scripts/verify-and-record.sh` widens the gate-gaming diff pathspec to include `.verify.yml`.
5. New test `tests/test-evaluator-surface.sh`: list-consistency vs session-start's `_GATE_ENFORCE_LIBS` (CI-blocking if the canary list grows without this list), predicate fixtures, advisory-never-deny, checker red-fixture, non-SHIP-phase emission.

## Capabilities

- **Modified: pdlc-safety** — push gate emits an evaluator-surface advisory.
- **Modified: project-verification** — gate-gaming check covers `.verify.yml` weakening.

## Impact

- Advisory-only: no new deny path; zero false-block risk by construction (worst case is warning noise on the rare branches that edit gate machinery — like this one).
- One-line overlap with the in-flight `feat/verify-and-record` branch on `scripts/verify-and-record.sh` (pathspec line); trivial conflict, flagged for coordination.
- Not gate ENFORCEMENT: the advisory does not enter the drift-canary `_GATE_ENFORCE_LIBS` manifest (that list is for fail-closed enforcement libs; this feature only reads it).
