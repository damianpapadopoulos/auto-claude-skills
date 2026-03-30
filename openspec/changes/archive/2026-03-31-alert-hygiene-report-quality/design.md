# Design: Alert Hygiene Report Quality Improvements

## Architecture
The alert-hygiene skill has two layers: a Python data pipeline (pull-policies.py, pull-incidents.py, compute-clusters.py) and a SKILL.md template that instructs the LLM how to render the report. The root cause of the quality gaps was that inventory health data was computed ad-hoc by the LLM during report generation, producing inconsistent results between runs. The fix moves all inventory computations into compute-clusters.py so the SKILL.md template reads deterministic fields from script output.

The Investigate template gained a conditional Proposed Config Diff section positioned after Impact and before Hypothesis. The section is only rendered when evidence basis is measured or structural and a config diff is derivable. Evidence Basis, Gate Blocker, and To Upgrade fields sit inside this conditional block, while the Evidence Basis line also appears unconditionally after the block for heuristic items.

## Dependencies
No new packages. Uses existing stdlib `Counter` (already imported) and `defaultdict`.

## Decisions & Trade-offs

**Do Now gate strictness (Option B chosen):** Rather than relaxing the Do Now gate to accept unassigned owners (Option A) or keeping the status quo (Option C), we added a Proposed Config Diff section to the Investigate template. This preserves the gate's integrity while keeping the most valuable artifact (the config diff) visible even when an item can't qualify as Do Now.

**Open-incident hours formula:** Chose actual duration sum (Option B) over `episodes * median_duration` (Option A). The data was already computed in the per-cluster loop — one additional line. Option A would still be an estimate; Option B is ground truth.

**policy_raw deduplication:** The `compute_unlabeled_ranking` function previously built its own `policy_raw` dict. Refactored to accept it as a parameter from `main()`, eliminating duplicate O(n) computation and a maintenance risk.
