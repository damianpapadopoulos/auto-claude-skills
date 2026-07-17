# Phase-Gate Backtest Results (controller-classified, 2026-07-17)

**Instrument:** `scripts/phase-gate-backtest.sh` @ bf1695f (ADVISORY-ONLY, bidirectional error — see script header). Corpus: 127 local session transcripts of this repo; 319 chain-member Skill invocations.

## Raw output

- 218 raw DENY lines → **78 unique (session, skill) invocation events** across 36 sessions (rates computed on unique events per plan).
- By invoked skill: finishing 64 / verify 54 / review 50 / openspec-ship 31 / writing-plans 14 / impl-slot 5 (raw lines).

## Classification method and findings

1. **Chain-scoping check:** all 36 sessions rendered a composition chain at some point → no blanket out-of-scope exclusion. (The replay still cannot see whether the chain was active *at the invocation*, or its actual membership.)
2. **Context extraction:** the dominant preceding-context for denied events is a prior Skill's instruction block or an SDD dispatch preamble — i.e. **mid-SHIP-sequence invocations** (verify→openspec-ship→finishing runs) and **dispatched-agent plan steps**, not cold skips.
3. **Cross-session sweep:** every one of the 28 sessions carrying a DESIGN/PLAN-missing deny (`missing=brainstorming|writing-plans`) has a sibling session within ±3 days that invoked `brainstorming`/`writing-plans` via Skill (28/28). Consistent with cross-session feature continuation — the exact case the shipped system covers via the **all-step branch ledger** (evidence the replay cannot see). Caveat honestly held: the sweep is date-windowed, not branch-resolved, so it cannot prove per-event ledger coverage.
4. **True catches exist by direct observation:** the discovery brief's A1 incident (this project, 2026-07-16: SDD invoked with `writing-plans` never run) is precisely a C1 deny with no ledger/attest evidence anywhere — ≥1 real catch, the class the user directed us to eliminate.

## Decision per pre-registered thresholds (discovery brief 2026-07-16)

- **C2 outbound DESIGN/PLAN deny flip: NOT taken — stays `warn` (telemetry-only).** The replay's FB rate for the outbound predicate is not measurable to the <10% bar with this instrument (dominant confound: ledger-invisible cross-session continuations = most of the corpus). Pre-registered rule for inconclusive: warn-only with a dated revisit. **Revisit: 2026-08-14** (4 weeks), using live `~/.claude/.phase-gate-events.log` `gate=outbound` lines (match `decision=deny` end-anchored / field-split — the log records the raw config value).
- **C1 skill-sequencing deny: stands (dogfood default).** Structurally different false-block surface from the replay (requires an ACTIVE chain, invoked-skill membership incl. impl-slot aliases, and zero evidence across invocation-record ∪ branch ledger ∪ attestation). The live kill criterion governs: **>10% user-judged false-blocks of C1 denies within 4 weeks → demote `skill_sequencing` to `warn`** (H1, discovery brief). External consumers already default to warn via the plugin-manifest identity check.
- **O3 (Edit/Write deny): stays unbuilt.** Revival requires <10% FB AND ≥1 true catch on a backtest that can resolve the above confound (per design.md Out-of-Scope).

## Instrument limitations reconfirmed on real data

Bidirectional error as labeled; additionally measured here: the replay's per-(invocation, missing-step) line fan-out inflates raw counts 2.8× over unique events, and date-window sibling matching cannot substitute for branch-resolved ledger state. Any future re-run should compute rates only on unique events and treat results as an upper bound on live denies.
