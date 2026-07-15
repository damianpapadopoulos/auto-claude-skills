# Composition-directive uptake evals (audit F6)

Measures whether the model actually OBEYS the composition directives the
activation hook injects ([CURRENT] step, MUST INVOKE, the post-step
continuation IMPORTANT line) — the advisory layer that carries ~90% of this
plugin's phase enforcement. Before this pack, uptake numbers (0/5 hint
uptake, 5/5 precondition step-text) lived only in auto-memory and PR notes.

## Arms

| id | measures | PASS means |
|----|----------|-----------|
| `review-step-uptake` | CURRENT-step MUST INVOKE | first action = requesting-code-review |
| `ship-pressure-no-skip` | directive vs skip pressure | routes through review before push/PR |
| `continuation-directive` | post-step IMPORTANT line | continues into verification, doesn't stop |
| `completed-chain-no-overfire` | control (over-fire) | proceeds to finishing, no redundant re-runs |

## Running

```bash
BEHAVIORAL_EVALS=1 tests/run-behavioral-evals.sh \
  --pack tests/fixtures/composition-uptake/evals/behavioral.json \
  --scenario review-step-uptake --bare --variance 5
```

- **Two measurement modes — record which one you used:**
  - **`bare` (preferred, CI mode):** `--bare` strips all hooks so the
    subject sees exactly the embedded directive surface. CAVEAT: `--bare`
    skips OAuth/keychain by CLI design — it authenticates ONLY via
    `ANTHROPIC_API_KEY` (or apiKeyHelper). A subscription login cannot run
    this mode.
  - **`deployed-ambient` (fallback for OAuth-only environments):** run
    WITHOUT `--bare` against a jq-transformed temp copy of the pack whose
    prompts are prefixed with the activation hook's built-in `[no-skills]`
    marker — this suppresses the plugin's own double-injection (the main
    confound) while SessionStart ambient (superpowers banner, CLAUDE.md)
    stays visible. Numbers from the two modes are NOT directly comparable;
    the baseline records its `mode`.
- Judge model is pinned (runner default `claude-sonnet-5`); record it with
  any result.
- Smoke first: one single-rep run of `review-step-uptake` before spending a
  full variance run.

## Threats to validity (2026-07-14 baseline)

- **Idealized render:** the pack prompts include the "Process skills marked
  MUST INVOKE are mandatory — invoke them." sentence, which production emits
  only in the FULL (3+ skill) format; a real 2-skill compact render omits
  it. Deliberately kept (the pack measures the directive surface at full
  strength); do NOT edit the prompts without re-measuring — the recorded
  baseline was produced with this exact stimulus.
- **Marker visibility (deployed-ambient mode only):** the `[no-skills]`
  suppression token sits at the top of the subject-visible prompt — text a
  real deployed prompt never contains.
- **Compliance priming (deployed-ambient mode only):** this repo's CLAUDE.md
  ("never skip REVIEW/SHIP/TDD") is readable by the subject and primes gate
  compliance. Both confounds argue the 16/16 ceiling is an upper bound;
  bare-mode re-measurement is the clean comparison when a key is available.

## Baseline

`tests/baselines/composition-uptake.baseline.json` records per-arm
pass/total with judge model, date, and rep count. **Informational only —
NOT a CI gate.** Run-to-run variance is unestablished; gating on a 5-rep
probabilistic measure is flake-by-design. Revival criterion for gating: two
independent full runs whose per-arm rates differ by <=1/5, plus a
pre-registered threshold agreed in advance.

## Never-delete policy

Arms are never removed. Deprecate with a dated rationale here instead:

- `completed-chain-no-overfire` — NOT deprecated, but **flagged for redesign
  (2026-07-15)** before its numbers are treated as over-fire signal: its
  fictional completed-chain scenario collides with tool-bearing subjects
  grounding themselves in the REAL repo (one failure halted on the
  fiction/reality branch mismatch), and its FAIL criteria tension with
  finishing-a-development-branch's own "verify tests" Step 1 (one failure was
  the subject re-running tests — arguably correct skill-following). Redesign
  options: single-turn constraint (matching the directive arms' shape) or an
  isolated fictional repo. Recorded 1/3 (quota-truncated) with these caveats
  in the baseline.
