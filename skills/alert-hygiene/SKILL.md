---
name: alert-hygiene
description: Use when facing flapping alerts, alert fatigue, recurring noisy incidents, threshold audits, or SLO-alert redesign questions for a GCP monitoring project.
---

# Alert Hygiene Analysis

Use when facing alert noise, flapping alerts, alert fatigue, threshold audits, or SLO-alert redesign questions. Analyzes alert policies and incident history for a single GCP monitoring project. Produces a confidence-grouped prescriptive report: high-confidence next actions (structural flaws, arithmetic mismatches), medium-confidence actions (pattern-only inferences), and needs-analyst items (ambiguous intent, SLO candidates). Runs straight through from data pull to final report.

**When NOT to use:**
- Active incident investigation — use incident-analysis instead (tiered log investigation with mitigation playbooks)
- SLO design from scratch — this skill identifies SLO-redesign *candidates*, it does not design SLOs or generate burn-rate PromQL
- Multi-project analysis — v1 is scoped to one monitoring project per invocation

## Behavioral Constraints

### 1. Scope Restriction

All queries are scoped to one monitoring project per invocation. The user must provide the monitoring project ID before analysis begins. If not provided, ask once.

### 2. Temp-File Execution Pattern

All bulk data operations write to session-scoped temp files via `mktemp`. This keeps large JSON payloads out of conversation context and makes the shell path debuggable:

```bash
WORK_DIR=$(mktemp -d /tmp/ah-XXXXXX)
```

All scripts read from and write to `$WORK_DIR`. Clean up at end of session.

### 3. No Checkpoint Gates

The analysis runs straight through from data pull to final report. The frequency table appears in the report appendix, not as a separate pause point. Do not ask the user for input mid-analysis.

### 4. Confidence Inline Flags

When an inference has less than high confidence (e.g., inferring a nightly batch from time-of-day concentration), state the inference and flag it inline: *"Inferred nightly batch from 100% h02 concentration — verify before applying mute window."* Do not gate the report on user confirmation.

## Tier Detection

### Tier 1 — REST API via scripts (default for inventory and bulk)

Default path for all data pull. Uses `gcloud auth print-access-token` for auth, `curl` for requests, Python scripts for pagination and extraction. MCP truncates at ~100K characters and cannot handle monitoring projects with >50 policies — REST has no such limits.

```bash
WORK_DIR=$(mktemp -d /tmp/ah-XXXXXX)
SCRIPTS_DIR="$(dirname "$0")/../skills/alert-hygiene/scripts"

python3 "$SCRIPTS_DIR/pull-policies.py" \
    --project "$MONITORING_PROJECT" \
    --output "$WORK_DIR/policies.json"

python3 "$SCRIPTS_DIR/pull-incidents.py" \
    --project "$MONITORING_PROJECT" \
    --days 14 \
    --output "$WORK_DIR/alerts.json"

python3 "$SCRIPTS_DIR/compute-clusters.py" \
    --policies "$WORK_DIR/policies.json" \
    --alerts "$WORK_DIR/alerts.json" \
    --output "$WORK_DIR/clusters.json"
```

### Tier 2 — MCP (targeted enrichment only)

If `list_time_series` or `list_alert_policies` MCP tools are available, use them **only** for targeted enrichment after cluster stats are computed:
- Single policy detail lookups (reading full PromQL query text)
- Time-series queries for metric validation on nominated clusters (< 50 results expected)

Never use MCP for bulk inventory pulls or incident history.

### Tier 3 — Guidance only

If neither gcloud nor MCP tools are available, provide manual Cloud Console instructions.

## Analysis Flow

### Stage 0: Validate Data Access

Before any analysis, discover and validate the monitoring project:

1. If the user provides a project ID, verify it is a **monitoring project** (has alert policies), not just a resource project. Run: `python3 pull-policies.py --project PROJECT --output /tmp/ah-check.json`.
2. **If zero policies returned:** The project is likely a resource project scoped under a different monitoring project. Provide actionable guidance: *"Project {X} returned 0 alert policies. This is likely a resource project, not the monitoring project. Try: (a) project ending in `-monitoring` (e.g., `{org}-monitoring`), (b) check Cloud Console > Monitoring > Settings > Metrics Scope to find which project hosts the alert policies, (c) run `gcloud alpha monitoring policies list --project={candidate}` to test candidates."* Do not just ask the user — give them the diagnostic path.
3. If the user does not provide a project, check if recent incident context or prior conversation names it. If not, ask once with the guidance above.
4. Verify incidents return non-empty: run pull-incidents.py with `--days 1` as a quick check. If zero incidents but policies exist, the window may be too narrow or incidents are in a different project — warn with specifics.
5. If both return data: `"Monitoring project: {project}, {N} policies found, incidents available. Proceeding with {days}-day analysis."`

Fail early — do not proceed to Stage 1 with an empty or wrong project.

### Stage 1: Pull Data

Run pull-policies.py and pull-incidents.py with the validated project. Verify non-empty results. Report counts:
- Total policies (enabled/disabled)
- Total incidents in window
- Policies by squad label

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

### Stage 3: Classify and Prescribe

Read the cluster stats JSON. For each cluster, apply the prescriptive reasoning templates below to assign a verdict and specific recommended action.

**Threshold-aware prescriptions:** When the cluster data includes `threshold_value` and `comparison`, state the current config explicitly in the per-item output: *"Current: {comparison} {threshold_value}, eval window {eval_window_sec}s, auto_close {auto_close_sec}s"*. Use the actual value in recommendations: *"Raise threshold from 0 to >1000"* not *"Raise threshold to >1000"*. When `condition_match` is `"ambiguous"`, note all threshold values and flag which one the recommendation applies to. When `condition_filter` or `condition_query` is available, include a truncated excerpt (≤60 chars) in the per-item output for reviewer auditability.

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

### Stage 4: Coverage Gap Check

Read `metric_types_in_inventory` from the compute-clusters output. Compare against the Coverage Gap Checklist below. For each gap:
- If the metric type exists in the inventory: check scope — is it applied to all relevant clusters/services, or only a subset? If partial, report "extend scope" with the specific uncovered projects.
- If the metric type does not exist: report "add new".
- Cross-reference each gap with existing noisy clusters that the gap metric would detect upstream (e.g., probe failure coverage → would provide early signal for pod restart clusters).

### Stage 5: Produce Report

Write the final report as markdown using the Report Skeleton template below. Group by confidence band, not by action type.

## Prescriptive Reasoning by Pattern

### Flapping (raw/episode > 3, raw > 10)

The alert fires and resolves repeatedly on the same resource. Root cause: threshold too close to baseline, or evaluation window too short.

Compare the configured threshold to the median retrigger interval and median duration:
- If median_duration < duration setting: raise duration to 2x median_duration
- If threshold is below observed baseline (from metric validation): raise threshold above p50 of the observed metric. State current vs recommended value.
- If auto_close is NOT SET and median_duration > 1h: set auto_close to 2x median_duration (capped at 86400s / 24h)
- If notification_channels > 0 and noise_score >= 5: recommend demoting to dashboard-only
- If raw/episode ratio > 10: the alert has a structural flap design — recommend auto_close or redesign

### Chronic (episodes >= 5, median_duration > 1h)

The alert fires and stays open for extended periods. The underlying issue is real and persistent.

This is "Fix the underlying issue". The alert is working correctly — the service has a problem:
- State specific investigation pointers based on metric_type and resource_type
- If auto_close is NOT SET: recommend setting it to match the evaluation window to prevent alert accumulation
- Do not recommend raising the threshold — the alert is detecting a real condition
- If distinct_resources is high (> 20): flag as systemic/cluster-wide, not single-service

### Recurring (episodes >= 5, median_duration < 1h)

The alert fires regularly but resolves within an hour. Could be deploy-time transients, batch jobs, or genuine intermittent issues.

- If tod_pattern shows > 50% concentration at a specific hour: infer scheduled job or deployment window. Recommend time-of-day mute for that window or extend duration to ride through the transient. Flag as low confidence if < 80% concentration.
- If noise_score >= 3: recommend raising threshold or adding a volume floor (e.g., minimum request count for error-rate alerts)
- If noise_score < 3 and episodes > 15: this is "Fix the underlying issue" — recurring real issue

### Burst (raw > 10, episodes <= 3)

Many raw incidents collapse to few episodes. Likely a single event with cascading re-fires.

- Recommend auto_close if NOT SET
- Check if the burst correlates with a deploy or scaling event
- Usually "Tune the alert" — the alert design amplifies a single event into many notifications

### Isolated (everything else)

Low-frequency, distinct, potentially well-calibrated.

- If raw <= 3: "No action" — keep as-is
- If raw >= 5 and noise_score >= 3: "Tune the alert" — review threshold
- Otherwise: "No action" — monitor

## Prescriptive Reasoning by Alert Type

### Error-rate alerts (error rate > X%)

- Check if the PromQL/MQL includes a minimum request volume clause. If not, recommend adding one (e.g., `AND total_requests > 200` in the 15m window).
- If the threshold is <= 1% and retrigger interval < 5m: the alert fires on single-request errors on low-traffic endpoints. Recommend raising to 3-5%.
- If concentrated at deploy hours: recommend extending duration from current to 900s.
- Check cluster selector: if it targets test clusters but routes to a prod squad, flag the mismatch.

### Latency alerts (P99/P95/P90 > Xms)

- If multiple percentile alerts exist for the same service (P90, P95, P99), the lower percentile dominates. Recommend consolidating to one.
- If the alert has high noise_score: route to **Needs Analyst Input** as SLO-redesign candidate. The skill cannot determine whether the service is user-facing or what SLI/SLO targets are appropriate. Frame as: *"This latency alert is a candidate for SLO burn-rate redesign if the service is user-facing. Analyst must confirm SLI target and error budget."*

### Queue/message broker alerts

- "Queue without consumer": if auto_close is NOT SET and median_duration > 24h, the alert is in permanent-fire state. Set auto_close=86400s.
- "Queue never empty": if the lookback window exceeds 12h and threshold is 0, the design causes permanent firing. Raise threshold to >1000 and shorten lookback to 6h.
- "Expired messages": if threshold is 1 (single message), raise to >100 or convert to rate-based.

### Pod restart alerts

- The threshold (>N restarts in Xh) is usually reasonable. If distinct_resources > 100, the problem is systemic — don't tune the alert, investigate the cluster.
- If auto_close is NOT SET: set to match the evaluation window.

### WAF/blocked-request alerts

- If chronic: review WAF rules for false positives.
- If burst at specific hours: may correlate with bot traffic patterns.

## Coverage Gap Checklist

Check the policy inventory for coverage of these high-value signals. For each, first search existing policies for the metric type. If found: recommend "extend scope" or "retune". If not found: recommend "add new".

| Gap | Metric to check | Why |
|-----|-----------------|-----|
| SSL certificate expiry | `ssl.googleapis.com/certificate/expiry_time` or uptime check SSL | Silent cert expiration causes hard outages |
| Pod probe failures | `kubernetes.io/container/probe/failure_count` or PromQL equivalent | Early signal before pod restart storms |
| Node memory/disk pressure | `kubernetes.io/node/status/condition` or `node/memory/allocatable_utilization` | Cascading pod evictions from node pressure |
| Cloud SQL connection saturation | `cloudsql.googleapis.com/database/network/connections` | Connection exhaustion causes app-level errors |
| Service 5xx coverage (per service) | Per-service HTTP error rate | Blind spots for services without error monitoring |
| Persistent disk utilization | `compute.googleapis.com/instance/disk/utilization` | Silent disk-full failures |

## Key Terms

Include a Definitions section in every report (after Executive Summary, before Priority Order) with these terms:

| Term | Definition |
|------|-----------|
| **Raw incidents** | Total alert firings in the analysis window |
| **Episodes** | Deduplicated incidents (same policy + resource, merged if gap < dedupe window) |
| **Raw/episode ratio** | Flapping indicator. 1:1 = clean signal. >5:1 = noisy. >20:1 = structural flaw |
| **Noise score** | 0-10 composite of ratio, duration, retrigger interval, and time-of-day pattern |
| **Evidence basis** | Whether a numeric prescription is `measured` (from validated metric query with stated scope) or `heuristic` (rule of thumb — must be flagged for validation) |

## Confidence Levels

| Level | Criteria | How to flag |
|-------|----------|-------------|
| High | Frequency pattern AND metric validation agree, or structural flaw is unambiguous (e.g., auto_close NOT SET with permanent-fire condition) | State recommendation directly. Evidence basis must be `measured` or `structural`. |
| Medium | Verdict based on frequency pattern only (no metric validation performed) | State recommendation, note "based on incident pattern only — validate {specific metric query} before applying". Add **To upgrade:** field with the specific diagnostic step. |
| Low | Data insufficient, inference from time-of-day concentration alone, or evidence contradicts | State recommendation with explicit inline flag: *"Low confidence — verify X before applying"*. Move to Needs Analyst Input if intent is ambiguous. |

## Report Structure

The report is grouped by confidence band, not by verdict type. This lets the user act immediately on high-confidence items while knowing which items need their judgment. The Priority Order appears early (BLUF — Bottom Line Up Front) so an engineering manager can approve the top actions within 30 seconds.

### Per-Item Template

Every cluster item — in any confidence band — uses this standardized block. The structure must be scannable: a reviewer skimming headers and bold fields should understand the recommendation without reading prose.

```
### {N}. {Action}: {policy_name} — {raw} incidents [{confidence}]
**Policy ID:** projects/{project}/alertPolicies/{id} | **Condition:** {condition_name}
**Owner:** squad={label} | service={name} | project={resource_project}
**Threshold:** {comparison} {threshold_value} | eval: {eval_window_sec}s | auto_close: {auto_close_sec}s | condition: `{condition_filter_excerpt_60chars}`
**Notification reach:** {N} channels (count only — channel type resolution requires separate API calls not in v1)

**Observed:** {only what the data shows — metrics, timestamps, counts, ratios}
**Inferred:** {hypotheses from patterns, each with confidence qualifier}
**Evidence basis:** {measured|heuristic} — {query text or reasoning}

**Action:**
1. {specific config change with exact old -> new values}
2. ...

**Expected impact:** ~{X}% reduction ({from} -> ~{to})
**Impact derivation:** {one-line method, e.g., "Of N incidents, M (X%) had duration <Y — these would not fire under proposed config"}

**Risk of change:** {low|medium} — {what could go wrong, e.g., "may miss transient sub-2s queries"}
**Rollback signal:** If {metric} exceeds {value} within 48h of change, revert.
**Related:** {cross-references to other sections mentioning this policy, if any}
```

For **Medium-Confidence** items, add after the block:
```
**To upgrade:** {specific diagnostic step that would make this high-confidence, e.g., "Run `fetch cloud_sql | p95(query_latency) | last 14d` to validate baseline"}
```

For **Needs Analyst Input** items, replace Action/Impact/Risk with:
```
**Question:** {specific question the analyst must answer}
**If yes:** {action A with specific values}
**If no:** {action B}
```

### Report Skeleton

```markdown
# Alert Hygiene Analysis Report
**Monitoring project:** {project} | **Window:** {days} days ending {date}

## Executive Summary
- {total_policies} policies ({enabled} enabled, {disabled} disabled), {total_incidents} raw incidents -> {total_episodes} episodes across {cluster_count} clusters
- Top findings (3-5 bullets with incident counts)
- {high_count} high-confidence actions, {medium_count} medium-confidence, {analyst_count} needs analyst input
- Config-only changes (items 1-N) reduce raw volume by an estimated {X} incidents ({Y}%)

## Methodology
- **Data source:** GCP Monitoring API (REST, paginated)
- **Scripts:** pull-policies.py (inventory), pull-incidents.py (incidents), compute-clusters.py (clustering + enrichment)
- **Analysis window:** {days} days ending {date}
- **Dedupe window:** max(1800s, 2× evaluation interval) per cluster
- **Noise score formula:** 0-10 composite: raw/episode ratio >5 (+3) or >2 (+1), median duration <15m (+2), retrigger <1h (+2), deploy-hour concentration (+1)
- **Pattern classification:** flapping (ratio>3 AND raw>10), chronic (episodes≥5 AND duration>1h), recurring (episodes≥5 AND duration≤1h), burst (raw>10 AND episodes≤3), isolated (other)
- **Evidence basis levels:** `measured` = metric time-series query with stated scope and result; `structural` = config flaw unambiguous from policy definition alone; `heuristic` = pattern-only inference, flagged for validation
- **To reproduce:** Run the three scripts with same `--project` and `--days`, then apply Stage 3-5 reasoning from this skill

## Definitions
(Key Terms table from the skill — raw incidents, episodes, raw/episode ratio with severity bands, noise score, evidence basis)

## Action Type Legend
- **Tune the alert** — the alert is miscalibrated. Specific config changes listed.
- **Fix the underlying issue** — the alert is correct. The service has a real problem.
- **Redesign around SLO** — replace threshold alerting with burn-rate/error-budget alerting.
- **Add/extend coverage** — a high-value blind spot exists.
- **No action** — well-calibrated, low-frequency. Keep as-is.

## Recommended Priority Order

### Track A: Config Changes
Sequential, executable in one change window. Ordered by impact * confidence / effort.

| # | Action | Policy ID | Effort | Incidents Reduced | Channels | Owner | Confidence | Risk |
|---|--------|-----------|--------|-------------------|----------|-------|------------|------|

### Track B: Investigations
Assign to teams now, run in parallel with Track A config changes.

| # | Investigation | Scope | Owner | First Diagnostic Step | User-Facing? |
|---|--------------|-------|-------|----------------------|-------------|

## High-Confidence Actions
Items where frequency pattern AND metric/structural evidence agree. Safe to act on directly.

### 1. {Action}: {policy_name} — {raw} incidents [High]
(full per-item template)

## Medium-Confidence Actions
Items based on frequency pattern only. Likely correct but validate the specific values before applying.

### 1. {Action}: {policy_name} — {raw} incidents [Medium]
(full per-item template + **To upgrade:** field)

## Needs Analyst Input
Items where the skill cannot determine intent — SLO redesign candidates (requires knowing which services are user-facing and what SLI/SLO targets are appropriate), ambiguous label ownership, intentional-state questions. SLO items default here unless the report can prove user-facing criticality and a validated current baseline.

### 1. {policy_name} — {raw} incidents
(per-item template with Question/If-yes/If-no variant)

## Coverage Gaps
| Gap | Action | Implementation | Rationale | Upstream Signal For |
(last column cross-references existing clusters this gap would detect earlier)

## Label/Scope Inconsistencies
| Policy | Policy ID | Current Label | Fires On | Incidents Affected | Required Fix | Related |

### Unlabeled Policies by Incident Volume
Top 10 policies without squad/team/owner label, ranked by total raw incidents (source: `unlabeled_ranking` from compute-clusters output):

| # | Policy | Policy ID | Raw ({days}d) | Episodes | Channels | Suggested Owner |
|---|--------|-----------|--------------|----------|----------|----------------|

"Suggested Owner" is left as "⚠ assign" unless resource project or metric type implies a specific team.

## Keep — No Action Required
Brief section with 5-10 representative well-calibrated clusters and one-liner rationale for each (e.g., "fires <2x/14d, threshold well above baseline, correct routing"). Demonstrates the analysis evaluated the full inventory.

## Verification Plan
Re-run this analysis in {days} days. Expected results per top cluster:
- {cluster_1}: <{target} (from {current})
- {cluster_2}: <{target} (from {current})
- Total raw: <{target} (from {current})

## Appendix: Frequency Table
Full cluster table sorted by raw incidents: cluster key, raw, episodes, distinct resources, median duration, median retrigger, noise score, pattern, verdict, confidence.

## Appendix: Evidence Coverage
| Cluster | Metric Validated? | Evidence Basis | Sample Scope | Dedupe Window | Confidence |
(lets reviewer see which recommendations rest on metric validation vs pattern-only inference)
```

## Action Types

Each cluster gets one of these action types (can appear in any confidence band). Include the Action Type Legend in every report for reviewer reference.

| Action | Meaning | Default Confidence Band |
|--------|---------|------------------------|
| **Tune the alert** | The alert is miscalibrated. Specific config changes listed (threshold, duration, auto_close, volume floor, mute window). | High or Medium (depends on evidence basis) |
| **Fix the underlying issue** | The alert is correct. The service has a real problem. Investigation pointers provided. | High or Medium |
| **Redesign around SLO** | Replace threshold alerting with burn-rate/error-budget alerting. | Needs Analyst Input (unless user-facing criticality and current baseline are proven) |
| **Add/extend coverage** | A high-value blind spot exists or current coverage is scoped incorrectly. | Medium (unless gap is linked to existing incident cluster) |
| **No action** | Well-calibrated, low-frequency. Keep as-is. | High (report in Keep section) |
