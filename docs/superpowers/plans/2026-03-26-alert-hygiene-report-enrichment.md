# Alert Hygiene Report Enrichment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 5 systematic gaps in the alert-hygiene skill: surface actual thresholds, validate baselines via metric queries, fix coverage gap detection, add methodology section, rank unlabeled policies.

**Architecture:** Scripts extract deterministic data (thresholds, metric types, unlabeled ranking), SKILL.md prescribes LLM judgment (metric validation, prescriptions). `compute-clusters.py` output changes from bare list to structured dict. All test fixtures updated for the new schema.

**Tech Stack:** Python 3, Bash tests, Markdown (SKILL.md).

---

## File Structure

| File | Responsibility |
|------|---------------|
| Modify: `skills/alert-hygiene/scripts/compute-clusters.py` | Threshold merging, output format, metric type extraction, unlabeled ranking |
| Modify: `skills/alert-hygiene/SKILL.md` | Stage 3 threshold instruction, Stage 3b (new), Stage 4 rewrite, Stage 5 template additions |
| Modify: `tests/test-alert-hygiene-scripts.sh` | Fixture enrichment, format migration, new assertions |

---

## Task 1: Update test fixtures and add new assertions (RED phase)

**Files:**
- Modify: `tests/test-alert-hygiene-scripts.sh`

- [ ] **Step 1: Enrich synthetic policy fixtures with conditionThreshold data**

In `tests/test-alert-hygiene-scripts.sh`, replace the `policies.json` fixture (lines 35-57) with:

```bash
cat > "${FIXTURES_DIR}/policies.json" << 'FIXTURE'
[
  {
    "name": "projects/test/alertPolicies/1",
    "displayName": "Test flapping alert",
    "enabled": true,
    "userLabels": {"squad": "staging_alerts"},
    "conditions": [{
      "displayName": "metric > 100",
      "type": "conditionThreshold",
      "filter": "metric.type=\"custom/metric\" AND resource.type=\"k8s_container\"",
      "query": "",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 100,
      "evaluationInterval": "60s",
      "duration": "300s",
      "aggregations": []
    }],
    "autoClose": "1800s",
    "notificationChannels": ["projects/test/notificationChannels/1"],
    "combiner": "OR"
  },
  {
    "name": "projects/test/alertPolicies/2",
    "displayName": "Test chronic alert",
    "enabled": true,
    "userLabels": {},
    "conditions": [{
      "displayName": "restarts > 5",
      "type": "conditionThreshold",
      "filter": "metric.type=\"kubernetes.io/container/restart_count\" AND resource.type=\"k8s_container\"",
      "query": "",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 5,
      "evaluationInterval": "60s",
      "duration": "600s",
      "aggregations": []
    }],
    "autoClose": "",
    "notificationChannels": ["projects/test/notificationChannels/1"],
    "combiner": "OR"
  }
]
FIXTURE
```

Note: Policy 2 changed from `"userLabels": {"squad": "prod_alerts"}` to `"userLabels": {}` (no squad) so it appears in unlabeled ranking.

- [ ] **Step 2: Migrate all cluster output reads to use `['clusters']`**

Replace every occurrence of `json.load(open('${FIXTURES_DIR}/clusters.json'))` with `json.load(open('${FIXTURES_DIR}/clusters.json'))['clusters']` in the test file. There are 8 occurrences in the main fixture block (lines 116, 121, 131, 139, 148, 157, 165, 173).

Also update these three specialized scenarios:
- Line 213 (`xproj-clusters.json`): `json.load(open('${FIXTURES_DIR}/xproj-clusters.json'))` → `json.load(open('${FIXTURES_DIR}/xproj-clusters.json'))['clusters']`
- Line 249 (`multicond-clusters.json`): same pattern
- Line 258 (`empty-clusters.json`): same pattern

- [ ] **Step 3: Add assertions for threshold extraction**

After the existing `EVAL_WINDOW` assertion block (line 170), add:

```bash
# Validate threshold value extraction
THRESHOLD_VAL=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['threshold_value'])
" 2>/dev/null)
assert_equals "flapping cluster threshold_value extracted" "100" "${THRESHOLD_VAL}"

THRESHOLD_COMP=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['comparison'])
" 2>/dev/null)
assert_equals "flapping cluster comparison extracted" "COMPARISON_GT" "${THRESHOLD_COMP}"

COND_MATCH=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['condition_match'])
" 2>/dev/null)
assert_equals "flapping cluster condition_match is single" "single" "${COND_MATCH}"

COND_FILTER=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print('yes' if 'custom/metric' in flap.get('condition_filter', '') else 'no')
" 2>/dev/null)
assert_equals "flapping cluster condition_filter contains metric type" "yes" "${COND_FILTER}"
```

- [ ] **Step 4: Add assertions for metric_types_in_inventory**

After the threshold assertions, add:

```bash
# Validate metric_types_in_inventory
METRIC_TYPES_COUNT=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(len(data['metric_types_in_inventory']))
" 2>/dev/null)
assert_equals "two metric types extracted from inventory" "2" "${METRIC_TYPES_COUNT}"

HAS_CUSTOM=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print('yes' if 'custom/metric' in data['metric_types_in_inventory'] else 'no')
" 2>/dev/null)
assert_equals "metric_types includes custom/metric" "yes" "${HAS_CUSTOM}"

HAS_RESTART=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print('yes' if 'kubernetes.io/container/restart_count' in data['metric_types_in_inventory'] else 'no')
" 2>/dev/null)
assert_equals "metric_types includes restart_count" "yes" "${HAS_RESTART}"
```

- [ ] **Step 5: Add assertions for unlabeled_ranking**

After the metric type assertions, add:

```bash
# Validate unlabeled_ranking
UNLABELED_COUNT=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(len(data['unlabeled_ranking']))
" 2>/dev/null)
assert_equals "one unlabeled policy in ranking" "1" "${UNLABELED_COUNT}"

UNLABELED_NAME=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(data['unlabeled_ranking'][0]['policy_name'])
" 2>/dev/null)
assert_equals "unlabeled policy is chronic alert" "Test chronic alert" "${UNLABELED_NAME}"

UNLABELED_RAW=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(data['unlabeled_ranking'][0]['total_raw'])
" 2>/dev/null)
assert_equals "unlabeled policy has 10 raw incidents" "10" "${UNLABELED_RAW}"
```

- [ ] **Step 6: Update empty-alerts assertion for new format**

Replace the existing empty-alerts assertion (line 258) with:

```bash
EMPTY_COUNT=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/empty-clusters.json'))['clusters']))" 2>/dev/null)
assert_equals "empty alerts produces zero clusters" "0" "${EMPTY_COUNT}"

# metric types still populated from policies even with zero alerts
EMPTY_METRICS=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/empty-clusters.json'))['metric_types_in_inventory']))" 2>/dev/null)
assert_equals "empty alerts still extracts metric types from policies" "2" "${EMPTY_METRICS}"
```

- [ ] **Step 7: Run tests to verify they fail**

Run: `bash tests/test-alert-hygiene-scripts.sh`
Expected: FAIL — `compute-clusters.py` still outputs bare list, new fields don't exist yet.

---

## Task 2: Implement compute-clusters.py changes (GREEN phase)

**Files:**
- Modify: `skills/alert-hygiene/scripts/compute-clusters.py`

- [ ] **Step 1: Add `extract_metric_types` function**

After the `check_label_inconsistency` function (line 99), add:

```python
def extract_metric_types(policies):
    """Extract all metric types referenced in policy conditions."""
    types = set()
    for p in policies:
        for c in p.get('conditions', []):
            filt = c.get('filter', '')
            if filt:
                m = re.search(r'metric\.type\s*=\s*"([^"]+)"', filt)
                if m:
                    types.add(m.group(1))
            query = c.get('query', '')
            if query:
                m = re.match(r'([\w][\w.:/\-]+)', query.strip())
                if m and '/' in m.group(1):
                    types.add(m.group(1))
    return sorted(types)
```

The `'/' in m.group(1)` check prevents capturing PromQL keywords (like `rate`, `sum`) as metric names — real GCP/Prometheus metric names contain `/` or `.`.

- [ ] **Step 2: Add `compute_unlabeled_ranking` function**

After `extract_metric_types`, add:

```python
def compute_unlabeled_ranking(policies, clusters):
    """Rank unlabeled policies by incident volume for actionable reporting."""
    policy_raw = defaultdict(int)
    policy_eps = defaultdict(int)
    for c in clusters:
        pfn = c.get('policy_full_name', '')
        policy_raw[pfn] += c.get('raw_incidents', 0)
        policy_eps[pfn] += c.get('deduped_episodes', 0)

    ranking = []
    for p in policies:
        labels = p.get('userLabels', {})
        has_owner = any(k in labels for k in ('squad', 'team', 'owner'))
        if not has_owner and p.get('enabled', True):
            pfn = p['name']
            ranking.append({
                'policy_name': p.get('displayName', ''),
                'policy_id': pfn,
                'total_raw': policy_raw.get(pfn, 0),
                'total_episodes': policy_eps.get(pfn, 0),
            })
    ranking.sort(key=lambda x: -x['total_raw'])
    return ranking[:20]
```

- [ ] **Step 3: Add threshold merging in the cluster-building loop**

In the cluster-building loop, after the line `pi = plookup.get(pfn, {})` (line 154), add condition matching logic:

```python
        # Match condition to get threshold data
        conditions = pi.get('conditions', [])
        if len(conditions) == 1:
            matched_cond = conditions[0]
            cond_match = 'single'
        elif len(conditions) > 1:
            matched_cond = conditions[0]
            cond_match = 'ambiguous'
        else:
            matched_cond = None
            cond_match = 'none'
```

Then in the `results.append({...})` block, add these fields after `'condition_name'`:

```python
            'threshold_value': matched_cond.get('thresholdValue') if matched_cond else None,
            'comparison': matched_cond.get('comparison', '') if matched_cond else '',
            'condition_filter': matched_cond.get('filter', '') if matched_cond else '',
            'condition_query': matched_cond.get('query', '') if matched_cond else '',
            'condition_type': matched_cond.get('type', '') if matched_cond else '',
            'condition_match': cond_match,
```

- [ ] **Step 4: Change output format to structured dict**

Replace the output block at the end of `main()` (lines 221-223):

```python
    results.sort(key=lambda x: -x['raw_incidents'])
    metric_types = extract_metric_types(policies)
    unlabeled = compute_unlabeled_ranking(policies, results)
    output = {
        'clusters': results,
        'metric_types_in_inventory': metric_types,
        'unlabeled_ranking': unlabeled,
    }
    with open(args.output, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"Computed {len(results)} clusters from {len(alerts)} incidents across {len(policies)} policies")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/test-alert-hygiene-scripts.sh`
Expected: PASS — all existing assertions + new assertions pass.

- [ ] **Step 6: Commit**

```bash
git add skills/alert-hygiene/scripts/compute-clusters.py tests/test-alert-hygiene-scripts.sh
git commit -m "feat(alert-hygiene): enrich cluster output with thresholds, metric types, unlabeled ranking

- Surface threshold_value, comparison, condition_filter from policy conditions
- Output format: bare list -> {clusters, metric_types_in_inventory, unlabeled_ranking}
- extract_metric_types() parses filter strings and PromQL queries
- compute_unlabeled_ranking() ranks owner-less policies by incident volume
- Test fixtures enriched with conditionThreshold data, all assertions updated"
```

---

## Task 3: Update SKILL.md — Stage 2 field list

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Update Stage 2 cluster field list**

Replace lines 99-103 (the Stage 2 bullet list):

```markdown
### Stage 2: Compute Cluster Stats

Run compute-clusters.py. This produces per-cluster:
- `raw_incidents`, `deduped_episodes`, `dedupe_window_sec`
- `distinct_resources`, `median_duration_sec`, `median_retrigger_sec`
- `tod_pattern`, `pattern` (flapping/chronic/recurring/burst/isolated)
- `noise_score`, `noise_reasons`, `label_inconsistency`
```

With:

```markdown
### Stage 2: Compute Cluster Stats

Run compute-clusters.py. This produces a structured output with three sections:

**Per-cluster fields (`clusters` array):**
- `raw_incidents`, `deduped_episodes`, `dedupe_window_sec`
- `distinct_resources`, `median_duration_sec`, `median_retrigger_sec`
- `tod_pattern`, `pattern` (flapping/chronic/recurring/burst/isolated)
- `noise_score`, `noise_reasons`, `label_inconsistency`
- `threshold_value`, `comparison`, `condition_filter`, `condition_query`, `condition_type`, `condition_match`

**Inventory-level fields:**
- `metric_types_in_inventory` — deduplicated set of all metric types across all policy conditions
- `unlabeled_ranking` — top 20 enabled policies without squad/team/owner label, ranked by total raw incidents
```

- [ ] **Step 2: Run content tests to verify no regressions**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: PASS — content tests check for string presence, not exact line positions.

---

## Task 4: Update SKILL.md — Stage 3 threshold-aware prescriptions

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Add threshold instruction to Stage 3**

After line 107 (`Read the cluster stats JSON. For each cluster, apply the prescriptive reasoning templates below to assign a verdict and specific recommended action.`), insert:

```markdown

**Threshold-aware prescriptions:** When the cluster data includes `threshold_value` and `comparison`, state the current config explicitly in the per-item output: *"Current: {comparison} {threshold_value}, eval window {eval_window_sec}s, auto_close {auto_close_sec}s"*. Use the actual value in recommendations: *"Raise threshold from 0 to >1000"* not *"Raise threshold to >1000"*. When `condition_match` is `"ambiguous"`, note all threshold values and flag which one the recommendation applies to. When `condition_filter` or `condition_query` is available, include a truncated excerpt (≤60 chars) in the per-item output for reviewer auditability.
```

- [ ] **Step 2: Run content tests**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: PASS

---

## Task 5: Update SKILL.md — Stage 3b metric validation (new)

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Insert Stage 3b after Stage 3**

After the Stage 3 block (after the threshold instruction added in Task 4), before `### Stage 4: Coverage Gap Check`, insert:

```markdown

### Stage 3b: Targeted Metric Validation

For the **top 5 clusters by raw incidents** where the evidence basis would be "heuristic" (not "structural" — structural flaws like auto_close NOT SET don't need metric validation):

1. Use MCP `list_time_series` (Tier 1) or `gcloud monitoring read` (Tier 2) to query the metric over the analysis window for the affected resource(s). Scope the query to the cluster's `resource_type` and `resource_project`.
2. Compute p50 and p95 of the observed metric values.
3. Compare against the configured `threshold_value`:
   - If p95 < threshold: the alert rarely fires legitimately. Recommend lowering threshold to p95 + 20% headroom. State: *"p95={X}, threshold={Y}, headroom={Z}%"*.
   - If p50 > 0.8 × threshold: the baseline is close to threshold. This confirms the flapping diagnosis. State: *"p50={X} is {Y}% of threshold={Z} — baseline crowding"*.
   - Record the query used and numeric result in the cluster's `Evidence basis` field. Mark as `measured`.
4. If MCP/gcloud unavailable, or the metric type doesn't support direct query (PromQL custom metrics without a direct Cloud Monitoring equivalent): note *"metric validation skipped — {reason}"* and keep `heuristic` basis.
5. If the query returns no data (metric not reporting): note *"metric validation failed — no data returned for {metric_type} on {resource_project}"*. This itself is a finding — the metric may be misconfigured.

**Cap:** Maximum 5 validation queries per run. Prioritize clusters where the recommendation involves a specific numeric threshold change (not just "set auto_close").
```

- [ ] **Step 2: Run content tests**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: PASS

---

## Task 6: Update SKILL.md — Stage 4 rewrite (script-driven coverage gaps)

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Replace Stage 4 body**

Replace lines 109-111:

```markdown
### Stage 4: Coverage Gap Check

Scan the policy inventory against the coverage gap checklist. For each gap candidate, check whether an existing policy already covers the metric type. Recommend "extend scope" or "add new" accordingly.
```

With:

```markdown
### Stage 4: Coverage Gap Check

Read `metric_types_in_inventory` from the compute-clusters output. Compare against the Coverage Gap Checklist below. For each gap:
- If the metric type exists in the inventory: check scope — is it applied to all relevant clusters/services, or only a subset? If partial, report "extend scope" with the specific uncovered projects.
- If the metric type does not exist: report "add new".
- Cross-reference each gap with existing noisy clusters that the gap metric would detect upstream (e.g., probe failure coverage → would provide early signal for pod restart clusters).
```

- [ ] **Step 2: Run content tests**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: PASS

---

## Task 7: Update SKILL.md — Stage 5 report template additions

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Add Methodology section to Report Skeleton**

In the Report Skeleton code block (starting line 271), after the `## Executive Summary` section (line 279) and before `## Definitions` (line 281), insert:

```markdown

## Methodology
- **Data source:** GCP Monitoring API (REST, paginated)
- **Scripts:** pull-policies.py (inventory), pull-incidents.py (incidents), compute-clusters.py (clustering + enrichment)
- **Analysis window:** {days} days ending {date}
- **Dedupe window:** max(1800s, 2× evaluation interval) per cluster
- **Noise score formula:** 0-10 composite: raw/episode ratio >5 (+3) or >2 (+1), median duration <15m (+2), retrigger <1h (+2), deploy-hour concentration (+1)
- **Pattern classification:** flapping (ratio>3 AND raw>10), chronic (episodes≥5 AND duration>1h), recurring (episodes≥5 AND duration≤1h), burst (raw>10 AND episodes≤3), isolated (other)
- **Evidence basis levels:** `measured` = metric time-series query with stated scope and result; `structural` = config flaw unambiguous from policy definition alone; `heuristic` = pattern-only inference, flagged for validation
- **To reproduce:** Run the three scripts with same `--project` and `--days`, then apply Stage 3-5 reasoning from this skill
```

- [ ] **Step 2: Add Threshold line to Per-Item Template**

In the Per-Item Template (line 236-254), after the `**Owner:**` line (line 238), insert:

```markdown
**Threshold:** {comparison} {threshold_value} | eval: {eval_window_sec}s | auto_close: {auto_close_sec}s | condition: `{condition_filter_excerpt_60chars}`
```

- [ ] **Step 3: Add Unlabeled Policies sub-section to Label/Scope Inconsistencies**

In the Report Skeleton, after the `## Label/Scope Inconsistencies` table (line 328), add:

```markdown

### Unlabeled Policies by Incident Volume
Top 10 policies without squad/team/owner label, ranked by total raw incidents (source: `unlabeled_ranking` from compute-clusters output):

| # | Policy | Policy ID | Raw ({days}d) | Episodes | Channels | Suggested Owner |
|---|--------|-----------|--------------|----------|----------|----------------|

"Suggested Owner" is left as "⚠ assign" unless resource project or metric type implies a specific team.
```

- [ ] **Step 4: Run content tests**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: PASS

---

## Task 8: Run full test suite and commit

**Files:**
- All modified files from Tasks 3-7

- [ ] **Step 1: Run alert-hygiene content tests**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: PASS — all 57+ assertions pass

- [ ] **Step 2: Run alert-hygiene script tests**

Run: `bash tests/test-alert-hygiene-scripts.sh`
Expected: PASS — all existing + new assertions pass

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 15 test files pass

- [ ] **Step 4: Commit SKILL.md changes**

```bash
git add skills/alert-hygiene/SKILL.md
git commit -m "feat(alert-hygiene): add threshold-aware prescriptions, metric validation, methodology

- Stage 2: document enriched output format (thresholds, metric types, unlabeled ranking)
- Stage 3: threshold-aware prescription instruction (state current -> recommended)
- Stage 3b: targeted metric validation for top 5 heuristic-basis clusters
- Stage 4: script-driven coverage gap check using metric_types_in_inventory
- Stage 5: Methodology section, Threshold line in per-item template, unlabeled ranking table"
```
