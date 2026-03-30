# Tasks: Alert Hygiene Report Quality Improvements

## Completed

- [x] 1.1 Add `total_open_hours` per cluster from actual durations (compute-clusters.py)
- [x] 1.2 Add inventory-level enrichment fields: `zero_channel_policies`, `disabled_but_noisy_policies`, `silent_policy_count`, `silent_policy_total`, `condition_type_breakdown` (compute-clusters.py)
- [x] 1.3 Add Proposed Config Diff section to Investigate Per-Item Template (SKILL.md)
- [x] 1.4 Update report skeleton: Dead/Orphaned Config, Inventory Health, Mandatory Needs Decision Triggers (SKILL.md)
- [x] 1.5 Code review: deduplicate `policy_raw`, fix Evidence Basis field placement
- [x] 1.6 Add 23 new test assertions across test-alert-hygiene-scripts.sh and test-alert-hygiene-skill-content.sh
