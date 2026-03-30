# Alert Hygiene Report Quality Improvements

**Date:** 2026-03-30
**Status:** Design approved
**Scope:** SKILL.md + compute-clusters.py (2 files, 4 improvements)

## Problem

Cross-report comparison (Mar-26 → Mar-27 → Mar-30) identified four reproducible quality gaps:

1. **Config diffs lost on Do Now gate demotion.** Items with measured/structural evidence and specific PromQL change specs were demoted to Investigate when missing a named owner. The Investigate template has no place for config diffs, so the most actionable artifact was lost.
2. **Open-incident hours inflated 2.7x.** The report estimated `raw_incidents * median_duration`, but raw includes retriggers within the same episode. Mar-30 reported 38,734h vs Mar-27's 14,323h for similar data.
3. **Zero-channel detection and inventory health non-deterministic.** Zero-channel policies, silent policy ratio, and condition type breakdown were computed via ad-hoc LLM Python during report generation. Results varied between runs (Mar-27 found 3 zero-channel policies; Mar-30 found 0 — possibly real data change, but the check itself was fragile).
4. **Silent policy cleanup Needs Decision dropped.** Mar-27 included it; Mar-30 didn't. No mandatory trigger in the skill.

## Design

### Change 1: Investigate template — Proposed Config Diff section

Add a conditional section to the Investigate per-item template in SKILL.md. Used only when an item has structural/measured evidence and a derivable config change but fails a Do Now gate requirement.

**Inserted after `**Impact:**`, before `**Hypothesis:**`:**

```markdown
#### Proposed Config Diff (pending gate resolution)
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| {param}   | {value} | {value}  | {why}      |

**Evidence Basis:** {measured|structural} — {detail}
**Gate Blocker:** {which requirement is missing}
**To Upgrade:** {resolve blocker} → promotes to Do Now
```

**Rules:**
- Only present when evidence basis is `measured` or `structural` AND a specific config diff is derivable
- Heuristic-only items never get this section
- The "Gate Blocker" field explicitly names what's missing (e.g., "Named target owner — policy is unlabeled")
- This section replaces the current free-text `**To Upgrade:**` line for these items

### Change 2: compute-clusters.py — Per-cluster `total_open_hours`

Add `total_open_hours` to each cluster output dict, computed from the already-calculated `durations` list:

```python
'total_open_hours': round(sum(durations) / 3600, 1) if durations else 0,
```

The report's Executive Summary reads `sum(c['total_open_hours'] for c in clusters)` instead of estimating from raw * median.

### Change 3: compute-clusters.py — Inventory-level enrichment

Add five new fields to the output JSON alongside existing `metric_types_in_inventory` and `unlabeled_ranking`:

```python
'zero_channel_policies': [
    {
        'policy_name': p['displayName'],
        'policy_id': p['name'],
        'enabled': p.get('enabled', True),
        'raw_incidents': policy_raw.get(p['name'], 0),
        'squad': p.get('userLabels', {}).get('squad', '-'),
    }
    for p in policies
    if len(p.get('notificationChannels', [])) == 0 and p.get('enabled', True)
],
'disabled_but_noisy_policies': [
    {
        'policy_name': p['displayName'],
        'policy_id': p['name'],
        'raw_incidents': policy_raw.get(p['name'], 0),
        'squad': p.get('userLabels', {}).get('squad', '-'),
    }
    for p in policies
    if not p.get('enabled', True) and policy_raw.get(p['name'], 0) > 0
],
'silent_policy_count': len(silent),  # enabled policies not appearing in any cluster
'silent_policy_total': len(enabled_policies),
'condition_type_breakdown': dict(Counter(
    c.get('type', 'unknown') for p in policies for c in p.get('conditions', [])
)),
```

### Change 4: SKILL.md — Mandatory report sections from script output

**A) Systemic Issues > Dead/Orphaned Config:** Read `zero_channel_policies` and `disabled_but_noisy_policies` from compute-clusters output. Each artifact carries `policy_name`, `policy_id`, `raw_incidents`, and `squad` — sufficient to render the report table directly without joins.

- If `zero_channel_policies` is non-empty: render table (policy name, policy ID, raw incidents, squad)
- If empty: state "No zero-channel policies found"
- If `disabled_but_noisy_policies` is non-empty: render separate table
- If empty: state "No disabled-but-noisy policies"

**B) Needs Decision — Silent policy cleanup trigger:** If `silent_policy_total > 0` and `silent_policy_count / silent_policy_total > 0.5`, include a "Silent Policy Cleanup" Needs Decision item using the standard template with counts from the script output. If `silent_policy_total == 0`, do not emit the item.

**C) Inventory Health:** Read all three fields from compute-clusters output:
- Silent policy ratio: `silent_policy_count` / `silent_policy_total` (deterministic, replaces ad-hoc computation)
- Condition type breakdown: render `condition_type_breakdown` directly
- Enabled/disabled counts remain from Stage 1 policy pull (no change)

## Files Touched

| File | Changes |
|------|---------|
| `skills/alert-hygiene/scripts/compute-clusters.py` | Add `total_open_hours` per cluster; add `zero_channel_policies`, `disabled_but_noisy_policies`, `silent_policy_count`, `silent_policy_total`, `condition_type_breakdown` to output |
| `skills/alert-hygiene/SKILL.md` | Add Proposed Config Diff to Investigate template; update report skeleton for Dead/Orphaned Config, Inventory Health, and Silent Policy Cleanup sections |

## Test Strategy

- `python3 -m py_compile skills/alert-hygiene/scripts/compute-clusters.py` — Python syntax check (matches existing test harness)
- Run compute-clusters.py against the existing Mar-30 data (policies.json + alerts.json) and verify new fields appear in output
- Verify new fields: `total_open_hours` per cluster, `zero_channel_policies`, `disabled_but_noisy_policies`, `silent_policy_count`, `silent_policy_total`, `condition_type_breakdown` all present
- Spot-check: the new `total_open_hours` sum across all clusters should be significantly less than 38,734h (the inflated Mar-30 estimate)
- Run existing test suite: `bash tests/run-tests.sh`

## Out of Scope

- **Artemis metric query repeatability** — runtime LLM query construction, not a script/skill structural gap
- **Per-container restart breakdown** — runtime LLM judgment on query granularity
- **Unlabeled ranking display** — the Mar-30 display bug was in ad-hoc code using wrong field names (`raw_incidents` vs `total_raw`), not a script bug
