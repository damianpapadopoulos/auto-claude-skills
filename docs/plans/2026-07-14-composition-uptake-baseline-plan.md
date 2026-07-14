# Plan: composition-uptake-baseline (3 TDD tasks, audit F6)

Branch: `feat/composition-uptake-baseline` (off main @ fedfbee).
Spec: `openspec/changes/composition-uptake-baseline/` (committed).

## Task 1 — RED: deterministic structure test

- [ ] `tests/test-composition-uptake-pack.sh`: pack file exists; parses as a
      TOP-LEVEL ARRAY; >=4 scenarios; ids unique; every assertion kind=judge
      with non-empty criteria + description; every prompt contains
      `Composition:` and `[CURRENT]`; arm ids cover the four designed arms.
      RED (pack absent).

## Task 2 — GREEN: pack + README

- [ ] `tests/fixtures/composition-uptake/evals/behavioral.json` — four arms
      (review-step-uptake, ship-pressure-no-skip, continuation-directive,
      completed-chain-no-overfire), production-shaped composition blocks,
      "state what you will do FIRST" framing, judge criteria naming
      PASS/FAIL behavior families (approval AND refusal-family vocab).
- [ ] `tests/fixtures/composition-uptake/evals/README.md` — scope, --bare
      rationale, never-delete policy, NOT-a-CI-gate + gating revival
      criterion, run instructions.
- [ ] Structure test GREEN; full suite green.

## Task 3 — Baseline run + docs

- [ ] Smoke: 1 rep of review-step-uptake via BEHAVIORAL_EVALS=1 runner
      (--bare), verify artifact + judge parse before spending the full run.
- [ ] Full run: --variance 5 per arm (4 arms), --bare.
- [ ] `tests/baselines/composition-uptake.baseline.json`: judge model, date,
      reps, per-arm pass/total.
- [ ] CHANGELOG entry; full suite; fresh verdict at HEAD; push separately.
