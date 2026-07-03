# DB phase-gate decision race — measure before we build

## Why

We have zero DB/query-specific coverage in the PDLC today. PlanetScale published a
strong `database-skills` pack (`github.com/planetscale/database-skills`), which prompted
the question: should our PDLC add a DB-review phase gate (migration / index / query-safety
surfaced at REVIEW)? The driver is opportunistic — no named DB pain — which is exactly the
category we have repeatedly *parked* (GitNexus, cross-LLM, Miora, DocLang).

Rather than park on "no felt pain," we replace the stopping rule with measurement: the
purpose of a gate is to *prevent* the pain, so we prove (or disprove) the gate's value on a
held-out defect corpus before committing. The output of this change is a **decision +
evidence**, not the gate. Full eval framing in
`docs/plans/2026-07-01-planetscale-db-skills-eval.md`.

The disciplines this race is built to honor (all our own scar tissue):
- **Cheapest-baseline** — the control is a real run of current REVIEW, not a strawman; if
  the base model already catches DB defects, the gate is redundant and we park with proof.
- **Held-out / anti-overfit** — a 93%-in-sample detector once scored 14% held-out; the
  corpus is authored cross-model, blind to any checklist content.
- **Small-n lies** — n=3 gives false certainty; ~20 defect + ~8 clean fixtures, `--variance ≥5`.
- **Pre-registered decision rule** — frozen before the first run; can return "park."

## What Changes

In scope for this change:

**Phase 1 — corpus (cross-model synthetic, held-out).**
- Codex authors ~20 planted-defect fixtures + ~8 clean negatives from a fixed anti-pattern
  taxonomy (unsafe migration, missing index, N+1, OFFSET-at-scale, lock-risk long txn),
  blind to any B2 checklist content. Each defect fixture carries a ground-truth label.

**Phase 2 — three arms + harness.**
- **A0** current PDLC REVIEW, no gate (cheapest baseline).
- **B1** gate = thin hint → external `planetscale/database-skills`.
- **B2** gate = owned de-vendored REVIEW checklist.
- Driven by the existing `behavioral-evaluation` runner, `--variance ≥5`, asserting
  detection (flagged planted defect) and specificity (did not flag negatives).

**Phase 3 — pre-registered scoring + decision.**
- Frozen rule: ship the variant maximizing `(detection − false_positive)` only if it beats
  A0 by ≥20pp detection at ≤10pp FP; else park, proven redundant; B1≈B2 → point at external.
- Safety-stop: if arms overlap within run-to-run variance, halt and expand n — do not
  declare a winner.

Out of scope (explicitly): building the production DB gate / routing config changes (a
separate change, gated on a ship verdict from this race); vendoring PlanetScale content
verbatim; Vitess/Neki-specific coverage.

## Capabilities

- **Modified: skill-routing** — adds a decision-gated pathway for a future DB-review phase
  gate. This change produces the *evidence and decision rule*; no routing entry ships unless
  the race clears the pre-registered bar.

## Impact

- No runtime routing change in this change — measurement + committed decision artifact only.
- Reusable eval methodology (held-out defect corpus + multi-arm gate race) applicable to
  future phase-gate proposals.
- A "park" outcome is a success: it closes the DB-gate question with proof instead of vibes.
