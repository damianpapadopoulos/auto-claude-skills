# Intent-extraction behavioral eval (PR2a ship gate)

Red-first quality gate for the intent-extraction DESIGN directive. The directive ships
**only** if the discriminating delta assertions go **red → green** between the baseline
(brainstorming alone) and the treatment (brainstorming + the directive prose). This is the
spec bar: *"measurable intent-capture improvement over brainstorming alone."*

This eval is **opt-in and manual** — it spawns `claude -p` and costs API budget. It is NOT
part of CI `tests/run-tests.sh`. Run it before shipping PR2a and record the result below.

## Mechanism — SKILL_PATH-swap A/B

`run-behavioral-evals.sh` injects the skill body from `SKILL_PATH` into the `claude -p`
prompt; it does **not** inject the working-tree activation-hook directive (and a live
`claude -p` would fire the *installed* plugin hook, not the edit). So we A/B the **skill
body**, not a `--bare` toggle:

- **Baseline body** = the real superpowers brainstorming skill (the cheapest honest
  alternative — do not strawman it with a hand-written stub):
  ```bash
  export SKILL_PATH="$(ls -d "$HOME"/.claude/plugins/cache/*/superpowers/*/skills/brainstorming/SKILL.md | head -1)"
  echo "baseline body: $SKILL_PATH"   # record the resolved path + version below
  ```
- **Treatment body** = baseline `SKILL.md` with the directive prose appended:
  ```bash
  TREAT="$(mktemp)"; cat "$SKILL_PATH" > "$TREAT"
  printf '\n\n## Activation directive (injected at DESIGN)\n\n' >> "$TREAT"
  # Append the INTENT EXTRACTION directive text VERBATIM from
  # hooks/skill-activation-hook.sh (keep it character-identical to what the hook emits).
  ```

## Pinned judge

The runner is regex-only (no LLM judge). "Pinned judge" therefore = the pinned inner
`claude -p --model <model>` plus the date of the gating run. Record both below.

## Pre-registered safety-stop

If the adversarial subset (`intent-mechanical-noninterview`) shows the directive induces a
multi-question intent interview on a mechanical ask, **HALT the ship** and revise the
suppression / prose (strengthen the mechanical-skip clause) before re-running. The developer
running the gate may call this stop.

## Never-delete

Scenarios are append-only. Never delete one; deprecate with `deprecated_on: YYYY-MM-DD` plus
a one-line rationale in the scenario's `expected_behavior`.

## Scenarios

| id | role | gate |
|----|------|------|
| `intent-underspecified-ask` | quality A/B | D1–D4 deltas red→green (discriminating deltas must go green) |
| `intent-mechanical-noninterview` | adversarial (hard) | no intent interview on a mechanical ask |
| `intent-respects-existing-brief` | adversarial (hard) | builds on brief, no re-elicitation |

## Run commands

```bash
# Baseline (expect RED on discriminating deltas):
BEHAVIORAL_EVALS=1 SKILL_PATH="$SKILL_PATH" tests/run-behavioral-evals.sh \
  --pack tests/fixtures/intent-extraction/evals/behavioral.json \
  --scenario intent-underspecified-ask --variance 3

# Treatment (expect GREEN on discriminating deltas):
BEHAVIORAL_EVALS=1 SKILL_PATH="$TREAT" tests/run-behavioral-evals.sh \
  --pack tests/fixtures/intent-extraction/evals/behavioral.json \
  --scenario intent-underspecified-ask --variance 5

# Adversarial (run against TREATMENT; inspect artifact for interview behavior):
BEHAVIORAL_EVALS=1 SKILL_PATH="$TREAT" tests/run-behavioral-evals.sh \
  --pack tests/fixtures/intent-extraction/evals/behavioral.json \
  --scenario intent-mechanical-noninterview --variance 3
```

## Results

### Baseline (RED) — _pending_

- Date: _pending_ · Model: _pending_ · Baseline path: _pending_
- Per-assertion (D1/D2/D3/D4): _pending — paste pass/fail + variance rates_

### Treatment (GREEN) — _pending_

- Date: _pending_ · Model: _pending_
- Per-assertion (D1/D2/D3/D4): _pending_
- Load-bearing deltas: _pending — state which of D1–D4 discriminate; D3 may pass on baseline_
- Adversarial subset: _pending — confirm no interview on mechanical ask_
