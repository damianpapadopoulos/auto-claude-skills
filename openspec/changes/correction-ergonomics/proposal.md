# Proposal: Correction-Ergonomics Message Rewrite (TrueCall adoption, Phase C)

## Why

TrueCall's correction-ergonomics finding: rewriting agent-facing gate messages from
passive notices into an **expected → actual → imperative-remediation** shape lifted
self-correction from 8% to 64%. Our owned hard-gate / could-not-verify / iterative-fix-loop
messages are currently passive ("report remaining failures as requiring human review",
"PUSH GATE: X has not been completed…"). Adopting the imperative shape on exactly these
messages should raise the rate at which a downstream agent actually performs the remediation
instead of narrating a passive status.

Scope is deliberately narrow. A prior broad imperative sweep was killed for "imperative
theater" — forcing corrective action on hints that legitimately offer an opt-out. This change
rewrites **only** hard-gates and could-not-verify/fix-loop terminals in files **we own**, and
leaves genuinely-advisory opt-out warnings advisory.

## What Changes

- **`hooks/openspec-guard.sh`** — rewrite the two hard-block PUSH GATE deny strings (L82
  code-review gate, L94 verification gate) to expected → actual → imperative. Leave the five
  SHIP-phase `…or proceed if not needed` advisory warnings untouched (opt-out = advisory).
- **`skills/agent-team-review/SKILL.md`** — add an imperative `On blocking_issues` paragraph
  under the §5 verdict-routing table (expected zero blocking → actual N remain → return to
  IMPLEMENT, fix each cited finding, re-review, do not SHIP).
- **`skills/runtime-validation/SKILL.md`** — rewrite the Step 5 fix-loop terminal
  ("after 3 iterations…") to an explicit per-failure hand-off; fold in the Coverage Gaps /
  Manual Checks imperative edits (same could-not-verify family).
- **`hooks/consolidation-stop.sh`** — rewrite the session-end CONSOLIDATION REMINDER to the
  expected → actual → imperative shape, **preserving an explicit honest opt-out** ("if nothing
  durable emerged, say so and stop") so it does not force consolidation theater when there is
  nothing to persist.
- **New red-first behavioral A/B pack** `tests/fixtures/correction-ergonomics/evals/behavioral.json`
  proving the lift: baseline (passive wording) fails a corrective-action assertion, treatment
  (imperative wording) passes. Includes an adversarial opt-out-advisory scenario with a
  pre-registered safety-stop against imperative theater.

## Capabilities

### Modified
- **pdlc-safety** — adds a requirement that owned hard-gate / could-not-verify messages use the
  expected → actual → imperative-remediation shape, validated by a red-first A/B eval, while
  opt-out advisories stay advisory. No new capability is minted; this extends the existing
  safety-gate + eval-strategy surface.

## Impact

- Message prose only in three owned files; no control-flow or gating-logic change. Push-gate
  block/allow decisions, verdict routing, and fix-loop iteration counts are unchanged — only
  the wording of the human/agent-facing text.
- New opt-in eval pack (`BEHAVIORAL_EVALS=1`), not in CI; a JSON-validity/append-only guard is
  added to `tests/run-tests.sh` so the pack cannot rot silently.
- No change to superpowers-owned skills; those are referenced, not edited.
