# incident-analysis eval fixtures

This directory holds two fixture files that serve distinct purposes.

## `routing.json`
Positive/negative trigger cases for the skill-activation routing scorer.
Exercised by `tests/test-incident-analysis-evals.sh` (schema validation only).

## `behavioral.json`
A structured **corpus of expected behaviors** for the incident-analysis skill.
Each scenario contains a prompt, an `expected_behavior` prose description, and
a list of regex assertions intended to match correct skill output.

### What gets tested today

| Script | What it actually does |
|---|---|
| `tests/test-incident-analysis-evals.sh` | Validates that `behavioral.json` parses, has required fields, and that the corpus covers the documented skill behaviors by name. **Does not invoke the skill or grep real output.** |
| `tests/run-behavioral-evals.sh` (v1) | **Does** invoke the skill via `claude -p`, captures output, and enforces `assertions[].text` as regexes against the real output. **Opt-in** via `BEHAVIORAL_EVALS=1`, never in the default `run-tests.sh` suite. |

The corpus existed before the runner did. Scaling this pattern to other skills
is deferred until v1 catches a real regression — see
`docs/plans/2026-04-20-behavioral-eval-runner-v1-design.md`.

### Running the behavioral eval runner locally

```bash
BEHAVIORAL_EVALS=1 tests/run-behavioral-evals.sh \
    --scenario crashloop-exit-code-triage
```

The runner writes a JSON artifact to `tests/artifacts/` (gitignored). Each
artifact records the scenario id, a UTC timestamp, the model identifier
returned by `claude -p`, the full prompt, the raw output, per-assertion
pass/fail, and the overall verdict.

### Optional additive fields

The pack schema accepts three optional fields per entry:
- `tags: string[]` — labels for filtering (e.g. `"critical"`, `"flake-prone"`).
- `source_artifact: string` — pointer to a postmortem or decision doc.
- `skill_version: string` — version of `SKILL.md` when the assertions were authored.

None are required for v1 evaluation.

### Notable scenarios

- `cast-systemic-factors-coverage` — Exercises Step 7 items 9–10 (Mental model gaps, Systemic factors across all 5 CAST categories) and Q12 coverage. Prompt derived from the 2026-04-08 billing-tab postmortem — a multi-team incident **not** seen during CAST design, so the fixture is an independent regression signal rather than a circular test against the incident that shaped the surface.

To list all scenarios: `jq '[.[].id]' tests/fixtures/incident-analysis/evals/behavioral.json`.
