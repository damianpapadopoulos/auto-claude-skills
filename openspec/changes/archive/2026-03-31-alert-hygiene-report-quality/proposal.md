## Why
Cross-report comparison (Mar-26 to Mar-30) revealed four reproducible quality gaps in the alert-hygiene skill's report output: lost config diffs when items were demoted from Do Now, inflated open-incident hours from an incorrect estimation formula, non-deterministic inventory health sections computed via ad-hoc LLM Python, and a dropped silent-policy cleanup Needs Decision.

## What Changes
Four improvements to the alert-hygiene skill that make report output more actionable and deterministic:
1. Investigate template gains a conditional Proposed Config Diff section that preserves PR-ready config changes even when an item fails the Do Now gate.
2. compute-clusters.py produces per-cluster `total_open_hours` from actual incident durations instead of the inflated `raw * median` estimation.
3. compute-clusters.py outputs five new inventory-level fields (`zero_channel_policies`, `disabled_but_noisy_policies`, `silent_policy_count`, `silent_policy_total`, `condition_type_breakdown`) so report sections render from deterministic script output.
4. SKILL.md report skeleton mandates Dead/Orphaned Config, Inventory Health, and Silent Policy Cleanup sections from these fields.

## Capabilities

### Modified Capabilities
- `alert-hygiene`: Report quality improvements — deterministic inventory health, preserved config diffs on gate demotion, accurate open-incident hours, mandatory silent-policy cleanup trigger.

## Impact
- **compute-clusters.py** — 6 new output fields (1 per-cluster, 5 inventory-level). No breaking changes to existing fields.
- **SKILL.md** — Investigate template restructured; report skeleton sections updated. Existing Do Now template and gate rules unchanged.
- **Tests** — 23 new assertions across test-alert-hygiene-scripts.sh and test-alert-hygiene-skill-content.sh.
