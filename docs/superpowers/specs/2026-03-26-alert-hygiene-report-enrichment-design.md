# Alert Hygiene Report Enrichment — Design Spec

**Goal:** Fix 5 systematic gaps in the alert-hygiene skill so that reports include actual thresholds, validated baselines, reliable coverage gap detection, reproducible methodology, and actionable unlabeled-policy findings.

**Approach:** Scripts extract data (deterministic, testable), SKILL.md prescribes judgment (LLM interprets baselines, writes prescriptions). Fixes go into the skill, not into individual reports. Re-running the skill on any project produces an enriched report.

---

## 1. `compute-clusters.py` — Surface threshold data into cluster output

### Problem
`pull-policies.py` already extracts `thresholdValue`, `comparison`, `filter`, `query`, `duration` per condition (lines 54-66). But `compute-clusters.py` only uses `eval_window_sec` and `auto_close_sec` from the policy lookup — threshold data is discarded.

### Change
In the cluster-building loop (lines 146-219), merge condition details from `plookup[pfn]['conditions']` into each cluster record.

**Condition matching logic:**
1. If the cluster's `condition_name` is non-empty: match against `conditions[*].displayName` in the policy. Note: `condition_name` from incidents is a full path like `projects/.../conditions/123` while policy conditions have `displayName`. Match by checking if the incident's condition name from the `conditionName` field in the incident corresponds to the conditions list — since the API doesn't expose condition IDs in the policy list, fall back to index-based matching or single-condition shortcut.
2. If `condition_name` is empty AND policy has exactly 1 condition: use that condition.
3. If `condition_name` is empty AND policy has multiple conditions: include all conditions as a list. Flag `condition_match: "ambiguous"` in the output.

**New fields per cluster:**
```json
{
  "threshold_value": 0.5,
  "comparison": "COMPARISON_GT",
  "condition_filter": "metric.type=\"kubernetes.io/...\" AND resource.type=\"k8s_container\"",
  "condition_query": "",
  "condition_type": "conditionThreshold",
  "condition_match": "single"
}
```

When `condition_match` is `"ambiguous"`, `threshold_value` becomes a list of all condition thresholds. The SKILL.md prescriptive reasoning handles ambiguous matches by noting all values.

### Test impact
Existing test fixtures use conditions without `conditionThreshold` — they have `displayName`, `evaluationInterval`, `duration` only. Update fixtures to include `type: "conditionThreshold"`, `filter`, `thresholdValue`, `comparison` fields. New threshold fields appear in cluster output — add assertions for them.

---

## 2. `compute-clusters.py` — Output format change

### Problem
Output is currently a bare JSON list. Adding coverage gaps and unlabeled ranking requires additional top-level keys.

### Change
Output becomes:
```json
{
  "clusters": [...],
  "metric_types_in_inventory": ["kubernetes.io/container/restart_count", ...],
  "unlabeled_ranking": [
    {"policy_name": "...", "policy_id": "...", "total_raw": 1230, "total_episodes": 1192}
  ]
}
```

**`metric_types_in_inventory`:** Extracted from all policy conditions by parsing `metric.type="X"` from `filter` fields and extracting metric references from `query` fields (PromQL). This is a flat unique set. Coverage gap comparison happens at the SKILL.md level (Stage 4), keeping the gap checklist in one place.

**`unlabeled_ranking`:** Policies where `userLabels` has no `squad`, `team`, or `owner` key, ranked by total raw incident volume across all clusters for that policy. Top 20 max.

### Breaking change
All test assertions that do `json.load(open(clusters.json))` expecting a list must change to `json.load(...)['clusters']`. Affected: lines 116-117, 120-125, 129-135, 138-144, 147-153, 156-162, 164-170, 172-178, 213, 249, 258 in `test-alert-hygiene-scripts.sh`.

The empty-alerts test (line 252-259) should verify `{"clusters": [], "metric_types_in_inventory": [...], "unlabeled_ranking": []}` — metric types still come from policies even with zero alerts.

---

## 3. `compute-clusters.py` — Metric type extraction

### Problem
Coverage gap detection failed because the ad-hoc regex for extracting metric types from condition filters didn't match. The extraction was done inline by the LLM instead of by the script.

### Change
New function `extract_metric_types(policies)`:
1. For `conditionThreshold` / `conditionAbsent`: parse `metric.type="X"` from the `filter` field using regex `metric\.type\s*=\s*"([^"]+)"`
2. For `conditionPrometheusQueryLanguage`: extract metric names from `query` field. Prometheus metric names are the first token before `{` in common patterns. Best-effort — flag unrecognized patterns as `__unparsed__`.
3. For `conditionMonitoringQueryLanguage`: extract from `fetch` statements: `fetch\s+(\w+)\s*::\s*(\S+)` → resource::metric.
4. Return a deduplicated set.

### Test additions
- Fixture with `conditionThreshold` + known filter string → verify metric type extracted
- Fixture with `conditionPrometheusQueryLanguage` + query → verify metric extracted
- Fixture with no parseable metric → verify `__unparsed__` or empty, no crash

---

## 4. SKILL.md — Stage 3 threshold-aware prescriptions

### Problem
Stage 3 says "apply prescriptive reasoning templates" but doesn't instruct the LLM to use actual threshold values from the enriched cluster data.

### Change
Add to Stage 3, after "For each cluster, apply the prescriptive reasoning templates":

> **Threshold-aware prescriptions:** When the cluster data includes `threshold_value` and `comparison`, state the current config explicitly in the per-item output: *"Current: {comparison} {threshold_value}, eval window {eval_window_sec}s, auto_close {auto_close_sec}s"*. Use the actual value in recommendations: *"Raise threshold from 0 to >1000"* not *"Raise threshold to >1000"*. When `condition_match` is `"ambiguous"`, note all threshold values and flag which one the recommendation applies to.

No structural change to Stage 3 — this is an additive instruction.

---

## 5. SKILL.md — Stage 3b metric validation (new)

### Problem
Every item in the report had evidence basis "heuristic" or "structural" — no metric validation was performed. The skill's Tier 2 section mentions MCP for targeted enrichment but doesn't operationalize it.

### Change
Insert new **Stage 3b: Targeted Metric Validation** between Stage 3 and Stage 4.

Content:
> For the **top 5 clusters by raw incidents** where the evidence basis is "heuristic" (not "structural"):
>
> 1. Use MCP `list_time_series` (Tier 1) or `gcloud monitoring read` (Tier 2) to query the metric over the analysis window for the affected resource(s).
> 2. Compute p50 and p95 of the observed metric values.
> 3. Compare against the configured threshold:
>    - If p95 < threshold: the alert rarely fires legitimately. Recommend lowering threshold to p95 + 20% headroom.
>    - If p50 > 0.8 × threshold: the baseline is close to threshold. This confirms the flapping diagnosis.
>    - State the query used and the numeric result in the cluster's `Evidence basis` field. Mark as "measured".
> 4. If MCP/gcloud unavailable, or the metric type doesn't support direct query (PromQL custom metrics without a direct Cloud Monitoring equivalent): note "metric validation skipped — {reason}" and keep "heuristic" basis.
>
> **Cap:** Maximum 5 validation queries per run. Prioritize clusters where the recommendation involves a specific numeric threshold change (not just "set auto_close").

---

## 6. SKILL.md — Stage 4 script-driven coverage gaps

### Problem
Stage 4 tells the LLM to scan the policy inventory against the checklist. In practice, the LLM wrote ad-hoc Python with a broken regex. The enriched script output now provides `metric_types_in_inventory`.

### Change
Replace the Stage 4 instruction body with:

> Read `metric_types_in_inventory` from the compute-clusters output. Compare against the Coverage Gap Checklist below. For each gap:
> - If the metric type exists in the inventory: check scope — is it applied to all relevant clusters/services, or only a subset? Report "extend scope" if partial.
> - If the metric type does not exist: report "add new".
> - Cross-reference each gap with existing noisy clusters that the gap metric would detect upstream (e.g., probe failures → pod restart clusters).

The Coverage Gap Checklist table in SKILL.md stays as the single source of truth. The script provides the inventory; the SKILL.md provides the checklist; the LLM compares.

---

## 7. SKILL.md — Stage 5 report template additions

### 7a. Methodology section
Add to Report Skeleton after Executive Summary, before Definitions:

```markdown
## Methodology
- **Data source:** GCP Monitoring API (REST, paginated)
- **Scripts:** pull-policies.py v{X} (inventory), pull-incidents.py v{X} (incidents), compute-clusters.py v{X} (clustering + enrichment)
- **Analysis window:** {days} days ending {date}
- **Dedupe window:** max(1800s, 2x evaluation interval) per cluster
- **Noise score formula:** 0-10 composite: raw/episode ratio >5 (+3) or >2 (+1), median duration <15m (+2), retrigger <1h (+2), deploy-hour concentration (+1)
- **Pattern classification:** flapping (ratio>3 AND raw>10), chronic (episodes>=5 AND duration>1h), recurring (episodes>=5 AND duration<=1h), burst (raw>10 AND episodes<=3), isolated (other)
- **Evidence basis levels:** "measured" = metric time-series query with stated scope and result; "structural" = config flaw unambiguous from policy definition alone; "heuristic" = pattern-only inference, flagged for validation
- **To reproduce:** Run the three scripts with same --project and --days, then apply Stage 3-5 reasoning from this skill
```

### 7b. Per-item template threshold field
Add after the `**Owner:**` line:

```
**Threshold:** {comparison} {threshold_value} | eval window: {eval_window_sec}s | auto_close: {auto_close_sec}s | condition: `{condition_filter_excerpt_40chars}`
```

When `condition_match` is `"ambiguous"`, show all thresholds.

### 7c. Unlabeled policy ranking
In the Label/Scope Inconsistencies section, add a sub-section:

```markdown
### Unlabeled Policies by Incident Volume
Top 10 policies without squad/team/owner label, ranked by total raw incidents:

| # | Policy | Policy ID | Raw (14d) | Episodes | Notification Channels | Suggested Owner |
```

Source: `unlabeled_ranking` from compute-clusters output. "Suggested Owner" is left as "⚠ assign" unless the resource project or metric type implies a team.

---

## 8. Test updates

### Fixture enrichment
Update synthetic policies in `test-alert-hygiene-scripts.sh` to include full condition data:

```json
{
  "name": "projects/test/alertPolicies/1",
  "displayName": "Test flapping alert",
  "conditions": [{
    "displayName": "metric > 100",
    "type": "conditionThreshold",
    "filter": "metric.type=\"custom/metric\" AND resource.type=\"k8s_container\"",
    "thresholdValue": 100,
    "comparison": "COMPARISON_GT",
    "evaluationInterval": "60s",
    "duration": "300s"
  }],
  ...
}
```

### New assertions
- Threshold value extracted into cluster output
- `metric_types_in_inventory` contains expected types from fixtures
- `unlabeled_ranking` populated for policies without squad label
- Output format is dict with `clusters` key (not bare list)
- Empty alerts + policies with conditions → `metric_types_in_inventory` still populated

### Updated assertions
All existing assertions that read `json.load(open(clusters.json))` change to `json.load(...)['clusters']`.

---

## Files changed

| File | Change |
|------|--------|
| Modify: `skills/alert-hygiene/scripts/compute-clusters.py` | Threshold merging, output format, metric type extraction, unlabeled ranking |
| Modify: `skills/alert-hygiene/SKILL.md` | Stage 3 threshold instruction, Stage 3b (new), Stage 4 rewrite, Stage 5 template additions |
| Modify: `tests/test-alert-hygiene-scripts.sh` | Fixture enrichment, format migration, new assertions |

No new files created. `pull-policies.py` and `pull-incidents.py` unchanged — they already extract what's needed.

---

## Out of scope

- Script versioning (referenced as `v{X}` in methodology — deferred to when versioning is needed)
- PromQL query parsing for exotic patterns — best-effort extraction, `__unparsed__` fallback
- Automated re-run on oviva-monitoring — done manually after skill changes land
