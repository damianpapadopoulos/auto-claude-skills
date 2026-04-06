## Why
Real OCS investigation (2026-03-09) misattributed calendar failures to SpiceDB without querying calendar's own logs. Calendar had an independent deployment regression (FluxCD v1.194.0-rc.0). The word "likely" laundered the evidence gap into a conclusion. This upgrade makes investigation rigor symmetrical across all affected services.

## What Changes
Five targeted insertions to the incident-analysis skill enforce evidence-only attribution in multi-service incidents. A new behavioral constraint bans speculative language in synthesis output. Step 3 now checks application-logic layers. Step 5 requires per-service attribution proof using a 4-state model. Step 8 adds a completeness gate (Q10) for multi-service attribution verification.

## Capabilities

### Modified Capabilities
- `incident-analysis`: Added evidence-only attribution constraint, application-logic analysis, per-service attribution proof with 4-state model, service_attribution YAML schema, Q10 completeness gate

## Impact
- `skills/incident-analysis/SKILL.md` — 5 insertion points, ~65 lines added
- `tests/test-incident-analysis-content.sh` — 8 new content assertions
- `tests/test-incident-analysis-evals.sh` — extended behavior coverage and field validation
- `tests/fixtures/incident-analysis/evals/behavioral.json` — 2 new scenarios, 1 extended
- `tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json` — service_attribution fields
- `tests/test-incident-analysis-output.sh` — service_attribution validation with co-occurrence check
