# Proposal: improvement-miner (Self-Improvement Factory, Stage 1)

## Why

The repo accumulates improvement evidence faster than it gets triaged:
weekly behavioral-eval results vs committed baselines, gate-status/backtest
calibration output, 39 feedback entries in auto-memory, and ~20 parked items
carrying explicit revival criteria. Today that evidence is mined only when
the user happens to remember it. Review bandwidth (solo user) is the
bottleneck, so raw dumps don't help — proposals must arrive ranked and
evidence-graded, each carrying an A/B evidence contract, behind a human
approve/reject gate with a durable queue.

Discovery brief (assumption ledger, Codex-sparred, checker-clean):
`docs/plans/2026-07-16-improvement-miner-discovery.md` (gitignored,
session-scoped). Decision provenance: auto-memory `self-improvement-factory`
+ `selfpatch-triage`.

## What Changes

- `skills/improvement-miner/SKILL.md` — LEARN-phase, manually triggered,
  advise-only skill: semantic extraction of proposal candidates from a
  deterministic evidence bundle, A–F evidence grading (assumption-audit
  ceilings), ranking, A/B contract authoring, in-session approve/reject,
  `gh issue create` for approved items, run-ledger issue written last.
- `skills/improvement-miner/scripts/mine-evidence.sh` — deterministic
  collector (Bash 3.2, requires gh+jq, fail-loud): evidence bundle,
  fingerprints, dedup against prior rejections, author-allowlisted GitHub
  reads, kill-criterion arithmetic. Everything with a hard threshold or a
  trust boundary is code, not prose.
- Routing entries in `config/default-triggers.json` AND
  `config/fallback-registry.json` (together), LEARN phase.
- Done-gate artifacts: `tests/fixtures/routing/improvement-miner.txt`
  (>=1 MATCH, >=1 verbatim-borrowed NO_MATCH decoy) and
  `tests/test-improvement-miner.sh` (content assertions + script unit tests
  with a PATH-shimmed fake gh, red-first).
- GitHub labels: `improvement-miner-run` (one owner-authored ledger issue
  per run), `improvement-miner` (approved proposals).

## Kill criterion (pre-registered)

<1 approved of the first 5 PRESENTED proposals → decommission the skill.
Calendar-independent. The arithmetic is computed by the script from the
run-ledger issues and printed in every report; a tripped criterion makes the
skill refuse to mine without explicit user override. This measures PROPOSER
viability, not delivered value (delivered value is each item's A/B contract,
post-implementation).

## Non-goals

- GH Action automation (revival criterion: manual run proves valuable AND
  becomes a chore). No new API-key dependency.
- Stage 2 (spec+implement on labeled issues) and Stage 3 (retro loop).
- Session-start nudge (PR #93 pattern) — kill criterion is
  calendar-independent; add later only if the ritual demonstrably decays.
- Live eval-pack or backtest execution during a mine run (the weekly
  workflow exists to produce results; mining reads them).
- Org-hub or web evidence sources.
