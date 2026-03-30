---
name: alert-hygiene
description: Use when facing flapping alerts, alert fatigue, recurring noisy incidents, threshold audits, or SLO-alert redesign questions for a GCP monitoring project.
---

# Alert Hygiene Analysis

Use when facing alert noise, flapping alerts, alert fatigue, threshold audits, or SLO-alert redesign questions. Analyzes alert policies and incident history for a single GCP monitoring project. Produces an action-class prescriptive report: Do Now items (PR-ready config changes with strict gating), Investigate items (bounded discovery with two-stage DoD), and Needs Decision items (strategy/policy choices with named owners). Runs straight through from data pull to final report.

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

Run the shared observability preflight before data access:

```bash
bash "$(dirname "$0")/../scripts/obs-preflight.sh"
```

If `gcloud` is `unauthenticated`, run `gcloud auth login` before proceeding. If `gcloud` is `missing`, fall to Tier 3.

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
6. **GitHub org for IaC links:** Check if recent conversation or CLAUDE.md names a GitHub org. If not, ask once: *"Which GitHub org hosts your monitoring IaC? (e.g., `oviva-ag`). Used for Search IaC links in the report — skip if not applicable."* Store as `{github_org}` for Stage 5 link construction. If the user skips, omit Search IaC links.

Fail early — do not proceed to Stage 1 with an empty or wrong project.

### Stage 1: Pull Data

Run pull-policies.py and pull-incidents.py with the validated project. Verify non-empty results. Report counts:
- Total policies (enabled/disabled)
- Total incidents in window
- Policies by squad label

#### Optional: SLO Config Enrichment

After pulling policies and incidents, attempt to fetch SLO service definitions from GitHub. This is optional enrichment — the core analysis runs without it.

**Preconditions:** `{github_org}` was provided in Stage 0 AND `gh` CLI is available AND authenticated (`gh auth status` succeeds). If any precondition fails, write fallback artifacts and skip.

**Flow:**

```bash
REPO="${github_org}/monitoring"

# Short-circuit if preconditions not met
if [ -z "${github_org:-}" ]; then
  echo '{"status":"unavailable","reason":"github_org_not_provided","count":0}' \
    > "$WORK_DIR/slo-source-status.json"
  echo '[]' > "$WORK_DIR/slo-services.json"
elif ! command -v gh &>/dev/null || ! gh auth status &>/dev/null 2>&1; then
  echo '{"status":"unavailable","reason":"gh_not_available","count":0}' \
    > "$WORK_DIR/slo-source-status.json"
  echo '[]' > "$WORK_DIR/slo-services.json"
else
  # Step 1: fetch (checked)
  if ! gh api "repos/$REPO/contents/tf/slo-config.yaml" \
       --jq '.content' > "$WORK_DIR/slo-raw-b64.txt" 2>"$WORK_DIR/slo-fetch-err.txt"; then
    echo '{"status":"unavailable","reason":"fetch_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  # Step 2: decode (checked)
  elif ! base64 -d < "$WORK_DIR/slo-raw-b64.txt" > "$WORK_DIR/slo-config.yaml" 2>/dev/null; then
    echo '{"status":"unavailable","reason":"decode_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  # Step 3: extract service names (checked — Ruby stdlib YAML, no PyYAML)
  elif ! ruby -ryaml -rjson -e '
    cfg = YAML.safe_load(File.read(ARGV[0])) || {}
    services = (cfg["services"] || []).map { |s| s["name"] }.compact
      .map { |n| n.downcase.gsub(/[_.]/, "-").gsub(/-(prod|staging|pta)$/, "") }
    File.write(ARGV[1], JSON.generate(services))
    File.write(ARGV[2], JSON.generate({
      status: services.empty? ? "empty" : "ok",
      count: services.length
    }))
  ' "$WORK_DIR/slo-config.yaml" "$WORK_DIR/slo-services.json" \
    "$WORK_DIR/slo-source-status.json" 2>"$WORK_DIR/slo-parse-err.txt"; then
    echo '{"status":"unavailable","reason":"parse_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  fi
  rm -f "$WORK_DIR/slo-raw-b64.txt"
fi
```

**On-disk artifacts (always written, every branch):**
- `slo-services.json` — normalized service name list or `[]`
- `slo-source-status.json` — `{"status": "ok|empty|unavailable", "reason": "...", "count": N}`

Names in `slo-services.json` are normalized with the same rules as `service_key` in compute-clusters.py: lowercase, strip environment suffixes (`-prod`, `-staging`, `-pta`), replace separators (`_`, `.`) with `-`.

**Stage 1 report line addition:** `"{M} services with SLO definitions"` when status is `ok`, `"SLO config: {reason}"` otherwise.

### Stage 2: Compute Cluster Stats

Run compute-clusters.py. This produces a structured output with three sections:

**Per-cluster fields (`clusters` array):**
- `raw_incidents`, `deduped_episodes`, `dedupe_window_sec`
- `distinct_resources`, `median_duration_sec`, `median_retrigger_sec`
- `tod_pattern`, `pattern` (flapping/chronic/recurring/burst/isolated)
- `noise_score`, `noise_reasons`, `label_inconsistency`
- `threshold_value`, `comparison`, `condition_filter`, `condition_query`, `condition_type`, `condition_match`
- `service_key` (normalized service identity from condition labels, or null), `signal_family` (error_rate/latency/availability/other)

**Inventory-level fields:**
- `metric_types_in_inventory` — deduplicated set of all metric types across all policy conditions
- `unlabeled_ranking` — top 20 enabled policies without squad/team/owner label, ranked by total raw incidents

### Stage 3: Classify and Prescribe

Read the cluster stats JSON. For each cluster, apply the prescriptive reasoning templates below to assign a verdict and specific recommended action.

**Threshold-aware prescriptions:** When the cluster data includes `threshold_value` and `comparison`, state the current config explicitly in the per-item output: *"Current: {comparison} {threshold_value}, eval window {eval_window_sec}s, auto_close {auto_close_sec}s"*. Use the actual value in recommendations: *"Raise threshold from 0 to >1000"* not *"Raise threshold to >1000"*. When `condition_match` is `"ambiguous"`, note all threshold values and flag which one the recommendation applies to. When `condition_filter` or `condition_query` is available, include a truncated excerpt (≤60 chars) in the per-item output for reviewer auditability.

### Stage 3b: Targeted Metric Validation

For the **top 5 clusters by raw incidents** where the evidence basis would be "heuristic" (not "structural" — structural flaws like auto_close NOT SET don't need metric validation):

**Step 1 — Map PromQL metric names to Cloud Monitoring equivalents.**

Most PromQL conditions use metrics that ARE queryable via Cloud Monitoring under a mapped name:

| PromQL pattern | Cloud Monitoring equivalent | Example |
|---|---|---|
| `kubernetes_io:METRIC_PATH` | `kubernetes.io/METRIC_PATH` | `kubernetes_io:container_restart_count` → `kubernetes.io/container/restart_count` |
| `SERVICE_COM:METRIC` | `SERVICE.com/METRIC` | `dbinsights_googleapis_com:perquery_latencies` → `dbinsights.googleapis.com/perquery/latencies` |
| `METRIC_NAME` (custom) | `prometheus.googleapis.com/METRIC_NAME/SUFFIX` | `jvm_threads_live_threads` → `prometheus.googleapis.com/jvm_threads_live_threads/gauge` |

For custom Prometheus metrics, the suffix depends on the metric type: try `/gauge` first, then `/counter`, `/summary`, `/histogram` if no data returns. If none return data, list metric descriptors with `filter=metric.type = starts_with("prometheus.googleapis.com/METRIC_PREFIX")` to find the actual suffix.

**Label discovery from PromQL:** Cloud Monitoring labels don't always match what you'd guess. Read the PromQL query from `policies.json` to find the actual label names used. For example, `http_server_requests_seconds_count{container="hcs-gb"}` tells you the Cloud Monitoring filter needs `metric.labels.container = "hcs-gb"` — not `metric.labels.application` or `metric.labels.service`. Always check the PromQL before constructing filters. PromQL labels on the metric selector map to `metric.labels.X` in Cloud Monitoring.

**Step 2 — Extract threshold from PromQL query text.**

When `threshold_value` is null (PromQL conditions), extract from the query string. PromQL thresholds appear as a comparison operator at the end or after a closing parenthesis: `... > 1000`, `... < 0.01`, `... == 0`. Match with: `[><=!]+\s*([\d.]+)\s*$` on the query text.

**Step 3 — Query the metric.**

Use MCP `list_time_series` (Tier 1) or REST API via temp-file pattern (Tier 2). Use `ALIGN_MAX` (hourly) for threshold comparison, `ALIGN_MEAN` for baseline assessment.

**Tier 2 query pattern** (uses session temp file per Behavioral Constraint 2):

```bash
WORK_DIR="${WORK_DIR:-$(mktemp -d /tmp/ah-XXXXXX)}"
FILTER_FILE=$(mktemp "$WORK_DIR/ts-filter-XXXXXX.txt")
cat > "$FILTER_FILE" << 'FILTER'
metric.type = "prometheus.googleapis.com/jvm_threads_live_threads/gauge"
AND metric.labels.container = "diet-suggestions"
AND resource.labels.cluster = "oviva-dg-prod1"
FILTER

TOKEN=$(gcloud auth print-access-token)
FILTER_ENC=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(open(sys.argv[1]).read().strip().replace('\n', ' ')))" "$FILTER_FILE")

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/$PROJECT/timeSeries?filter=$FILTER_ENC&interval.startTime=${START_TIME}&interval.endTime=${END_TIME}&aggregation.alignmentPeriod=3600s&aggregation.perSeriesAligner=ALIGN_MAX&pageSize=20" \
  -o "$WORK_DIR/ts-result.json" ; rm -f "$FILTER_FILE"
```

Write results to `$WORK_DIR`, not to conversation context. Parse with `python3` one-liner to extract p50/p95.

**Step 4 — Compare against threshold.**

- If p95 < threshold: the alert rarely fires legitimately. Recommend lowering threshold to p95 + 20% headroom. State: *"p95={X}, threshold={Y}, headroom={Z}%"*.
- If p50 > 0.8 × threshold: baseline crowding. State: *"p50={X} is {Y}% of threshold={Z} — baseline crowding"*.
- Record the query used and numeric result in the cluster's `Evidence basis` field. Mark as `measured`.

**Step 5 — Handle failures.**

If the metric type cannot be mapped, the query returns no data, or the suffix is wrong: note the reason and keep `heuristic` basis. A no-data result is itself a finding — the metric may be misconfigured or the resource labels may not match.

**Scope:** Query all clusters, not just heuristic-basis. Structural items also benefit from measurement (e.g., confirming queue baselines are zero proves the `> 0` threshold fires on transients). If API errors or rate limits occur, prioritize by raw incident count.

**Multi-query patterns** — these are NOT limitations, they are standard approaches. Use them:

| Metric kind | Approach | Example |
|---|---|---|
| **CUMULATIVE DISTRIBUTION** (e.g., perquery latencies) | `ALIGN_DELTA` extracts the delta distribution per period. Read `distributionValue.mean` for average latency and `distributionValue.count` for query volume. | `dbinsights.googleapis.com/perquery/latencies` + ALIGN_DELTA daily → mean latency per day |
| **Error rate ratios** (5xx / total) | Two queries: (1) filter by status label for errors, (2) unfiltered for total. Divide in Python. Write both results to `$WORK_DIR`. | Query with `metric.labels.status=starts_with("5")` for errors, without for total. Compute `error_count / total_count`. |
| **High-cardinality counters** (e.g., 1,000+ containers) | Use `aggregation.crossSeriesReducer=REDUCE_SUM` to aggregate across all series. Gives total restart rate without enumerating each container. | `kubernetes.io/container/restart_count` + ALIGN_DELTA 1h + REDUCE_SUM → total restarts/hour across all containers |
| **Custom PromQL with no Cloud Monitoring equivalent** | Rare — most Prometheus metrics map via `prometheus.googleapis.com/METRIC/SUFFIX`. Try `/gauge`, `/counter`, `/summary`, `/histogram` suffixes. If none return data, list metric descriptors with `starts_with` filter. | `metricDescriptors?filter=metric.type = starts_with("prometheus.googleapis.com/METRIC_PREFIX")` |

**Tier 2 two-query ratio pattern** (error rate example):

```bash
WORK_DIR="${WORK_DIR:-$(mktemp -d /tmp/ah-XXXXXX)}"

# Query 1: error count (5xx)
FILTER_ERR=$(mktemp "$WORK_DIR/ts-err-XXXXXX.txt")
cat > "$FILTER_ERR" << 'FILTER'
metric.type = "prometheus.googleapis.com/http_server_requests_seconds_count/summary"
AND metric.labels.status = starts_with("5")
AND metric.labels.application = "SERVICE_NAME"
FILTER
# ... curl to $WORK_DIR/ts-err-result.json

# Query 2: total count
FILTER_TOTAL=$(mktemp "$WORK_DIR/ts-total-XXXXXX.txt")
cat > "$FILTER_TOTAL" << 'FILTER'
metric.type = "prometheus.googleapis.com/http_server_requests_seconds_count/summary"
AND metric.labels.application = "SERVICE_NAME"
FILTER
# ... curl to $WORK_DIR/ts-total-result.json

# Compute ratio
python3 -c "
import json
err = sum(float(pt['value']['doubleValue']) for s in json.load(open('$WORK_DIR/ts-err-result.json')).get('timeSeries',[]) for pt in s['points'] if 'doubleValue' in pt.get('value',{}))
total = sum(float(pt['value']['doubleValue']) for s in json.load(open('$WORK_DIR/ts-total-result.json')).get('timeSeries',[]) for pt in s['points'] if 'doubleValue' in pt.get('value',{}))
print(f'error_rate={err/total*100:.2f}% ({err:.0f}/{total:.0f})') if total > 0 else print('no data')
"
rm -f "$FILTER_ERR" "$FILTER_TOTAL"
```

If a multi-query approach is available but not executed (e.g., auth expired), state the approach and mark as "not attempted — auth expired" rather than claiming an API limitation.

### Stage 4: Coverage Gap Check

Read `metric_types_in_inventory` from the compute-clusters output. Compare against the Coverage Gap Checklist below. For each gap:
- If the metric type exists in the inventory: check scope — is it applied to all relevant clusters/services, or only a subset? If partial, report "extend scope" with the specific uncovered projects.
- If the metric type does not exist: report "add new".
- Cross-reference each gap with existing noisy clusters that the gap metric would detect upstream (e.g., probe failure coverage → would provide early signal for pod restart clusters).

#### Routing Validation

Check for routing and ownership gaps using policy-level and cluster-level data from `$WORK_DIR`.

**Zero-channel policies (policy-level):**
Scan `policies.json` for entries where `notificationChannels` is empty AND `enabled` is true. These fire but notify nobody — invisible failures.
- Policies with `raw_incidents > 10` (cross-reference against `clusters.json`): promote to **Investigate** with action: *"Silent alert — fires but has no notification channels. Add a notification channel or disable."*
- Policies with low/zero incidents: surface in **Systemic Issues > Dead/Orphaned Config** — *"Zero-channel policy: {displayName} — enabled but no notification path."*

**Unlabeled high-noise policies (policy-level):**
The existing `unlabeled_ranking` table stays in Systemic Issues. Additionally, for top entries with `raw_incidents > 10`:
- Promote to **Investigate** with ownership language: *"No squad/team/owner label — ownership is implicit and unauditable. {N} incidents in {days}d have no traceable owner."*
- Do not reference org-specific routing fallback channels. The skill is generic.
- Leave suggested owner as "⚠ assign" — the skill does not infer squad ownership from service names.

**Label inconsistency promotion (cluster-level):**
For clusters where `label_inconsistency` is true AND `raw_incidents > 5`:
- Promote to **Investigate** as a cluster-level finding: *"Label mismatch — staging/test label on a production resource. {N} incidents may be misrouted or ignored."*
- Do NOT merge into the policy-level unlabeled table — entity types stay separate.

#### SLO Coverage Cross-Reference

Only run this section when `$WORK_DIR/slo-source-status.json` has `"status": "ok"`. Read `$WORK_DIR/slo-services.json` (normalized service names) and cross-reference against cluster data.

**Service grouping:** Group clusters by `service_key` from `clusters.json`. Skip clusters where `service_key` is `null`. Only consider clusters with `signal_family` in (`error_rate`, `latency`, `availability`) — exclude `other`.

**SLO migration candidates:**
For each service_key with `total_raw_incidents > 20` across user-facing clusters AND NOT in `slo-services.json`:
- Surface in **Coverage Gaps** table: *"SLO review candidate — {service_key} has {N} noisy user-facing threshold alerts ({families}), no SLO definition."*

**SLO review candidates (redundancy check):**
For each service_key that IS in `slo-services.json` AND has noisy user-facing threshold alerts:
- Surface as **Needs Decision** item: *"Service {service_key} has an SLO definition and also {N} noisy user-facing threshold alerts; review for redundancy or intentional overlap."*
- Do not claim same-signal overlap — `slo-services.json` carries service names only, not signal coverage metadata.

**Matching rules:** Both `service_key` and SLO service names are normalized (lowercase, env suffixes stripped, separators unified). Only exact-match after normalization. Unmatched service_keys are excluded, not fuzzy-guessed.

### Stage 5: Produce Report

Write the final report as markdown using the Report Skeleton template below. Group findings by action class (Do Now / Investigate / Needs Decision), not by confidence band. Apply the Do Now Gate to determine which items qualify for the Do Now section. Items that fail the gate drop to Investigate regardless of confidence level.

#### IaC Location Resolution via GitHub Search

During Do Now gate evaluation, attempt to upgrade IaC Location tier for candidates using `gh search code`. This is optional enrichment — if it adds nothing, the report is identical to the version without it.

**Preconditions:** `{github_org}` was provided AND `gh` is available AND authenticated (`gh auth status`). If any fail, skip entirely. This prevents avoidable fallback churn on private repos where `gh` exists but lacks auth.

**When to search:** Only for items that pass all other Do Now gate requirements (config diff, named owner, outcome DoD, measured/structural evidence, rollback signal) but have IaC Location of Search Required or Unknown.

**Rate limit:** `gh search code` allows 10 requests/minute. Cap at top 10 candidates by raw incident count. Remaining items keep their existing IaC Location tier.

**Search strategy per item:**

```bash
# Primary: policy ID (bare numeric ID — matches both inline resources and module refs)
gh search code --owner "$github_org" "{policy_id}" \
  --extension tf --json path,repository --limit 5 \
  > "$WORK_DIR/iac-search-${policy_id}.json" 2>/dev/null

# Secondary: only if primary returned 0 results
PRIMARY_HITS=$(python3 -c "import json; print(len(json.load(open('$WORK_DIR/iac-search-${policy_id}.json'))))" 2>/dev/null || echo 0)
if [ "$PRIMARY_HITS" = "0" ]; then
  # Use the PromQL fragment, condition filter string, or label key
  # already captured in Stage 3 for the Search Required spec
  gh search code --owner "$github_org" "{identifying_fragment}" \
    --extension tf --json path,repository --limit 5 \
    > "$WORK_DIR/iac-search-${policy_id}.json" 2>/dev/null
fi
```

Do not search by `display_name` — too generic and noisy.

**Result interpretation:**
- **1+ plausible results:** Upgrade to IaC Location = **Likely**. Include top `repo:path` in the finding. Add note: *"Search match at {repo}:{path} — verify before applying."*
- **0 results after both tokens:** **Preserve original tier.** Search Required stays Search Required. Unknown stays Unknown. A failed search must NOT upgrade Unknown to Search Required — that would incorrectly make a Do-Now-ineligible item eligible.
- **Confirmed is not achievable from search alone** — would require opening the file and verifying match context.

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
- If the alert has high noise_score: route to **Needs Decision** as SLO-redesign candidate. The skill cannot determine whether the service is user-facing or what SLI/SLO targets are appropriate. Frame as: *"This latency alert is a candidate for SLO burn-rate redesign if the service is user-facing. Analyst must confirm SLI target and error budget."*

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

Include a Definitions section in every report (after Methodology, before Action Type Legend) with these terms:

| Term | Definition |
|------|-----------|
| **Raw incidents** | Total alert firings in the analysis window |
| **Episodes** | Deduplicated incidents (same policy + resource, merged if gap < dedupe window) |
| **Raw/episode ratio** | Flapping indicator. 1:1 = clean signal. >5:1 = noisy. >20:1 = structural flaw |
| **Noise score** | 0-10 composite of ratio, duration, retrigger interval, and time-of-day pattern |
| **Evidence basis** | Whether a numeric prescription is `measured` (from validated metric query with stated scope) or `heuristic` (rule of thumb — must be flagged for validation) |
| **Open-incident hours** | Sum of all incident durations in the analysis window, measured in hours. Captures both volume and persistence of alert noise. |

## Confidence Levels and Readiness

Confidence determines evidence quality. Readiness determines action class. An item can be high-confidence but not Do Now-ready if it fails a gate requirement.

| Confidence | Evidence Criteria | Readiness | Action Class |
|------------|------------------|-----------|--------------|
| High | Frequency + metric/structural evidence agree, or structural flaw unambiguous | PR-Ready (all gate requirements met) | Do Now |
| High | Structural/measured evidence strong, but missing gate requirement (IaC location, owner, etc.) | Stage 1 (gate requirement resolution) | Investigate |
| Medium | Frequency pattern only, no metric validation | Stage 1 (hypothesis validation) | Investigate |
| High | Skill cannot determine intent — SLO redesign, ambiguous ownership, policy strategy | Decision Pending | Needs Decision |
| Low | Data insufficient, inference from time-of-day alone, or evidence contradicts | Stage 1 | Investigate (with inline low-confidence flag) |

**Confidence / Readiness vocabulary for Decision Summary:**
- `High / PR-Ready` — Do Now items
- `High / Stage 1` — Investigate items that are structurally proven or measured but failed a Do Now gate requirement
- `Medium / Stage 1` — Investigate items based on heuristic evidence or requiring hypothesis validation
- `High / Decision Pending` — Needs Decision items

**Heuristic alone never qualifies for Do Now.** Evidence basis must be `measured` or `structural` to pass the Do Now gate.

## Report Structure

The report is grouped by action class (Do Now / Investigate / Needs Decision), not by confidence band. The Decision Summary appears early (BLUF) so an engineering lead can triage the top actions within 30 seconds. Detailed finding sections provide the execution-ready schemas below.

### Do Now Gate — All Required

An item qualifies for Do Now only if it has ALL of the following:

1. Exact current -> proposed config diff with derivation for every proposed value
2. Named target owner (not "unlabeled" or "service owner")
3. Numeric, time-bounded Outcome DoD with both primary and guardrail metrics
4. Pre-change evidence (measured or structural — **heuristic alone never qualifies for Do Now**)
5. Rollback signal with a derived threshold (not arbitrary)
6. IaC Location status of Confirmed, Likely, or Search Required

If any are missing, the item drops to Investigate regardless of confidence level.

### IaC Location Rules

| Status | Meaning | Do Now eligible? |
|--------|---------|-----------------|
| **Confirmed** | Exact file path verified | Yes |
| **Likely** | Strong candidate path, search path explicit | Yes |
| **Search Required** | Must include ALL four: (1) likely repo/module hint, (2) policy ID as search token, (3) unique identifying fragment appropriate to the policy type (PromQL fragment, condition filter string, label key, or channel name), (4) exact replacement guidance | Yes |
| **Unknown** | Cannot identify owning repo/file | No — drops to Investigate |

### PromQL Change Spec Rules

- **Simple edits** (scalar threshold, window, auto_close): show exact current and proposed fragment
- **Complex edits** (multi-clause PromQL, aggregation changes): show full affected clause or precise change spec
- Never rely on blind copy-paste as the standard; aim for exact replacement guidance

### Metric Families by Finding Type

| Finding type | Primary metric | Guardrail metric |
|---|---|---|
| Noise tuning | Raw incidents or open-incident hours | Detection latency for real incidents |
| auto_close fixes | Median open duration | N/A when change cannot hide signal |
| Routing/ownership | Correct owner/channel coverage | No alert dropped during transition |
| Orphaned alerts | Explicit close/remove/route decision | N/A |
| Coverage gaps | Implementation milestone | N/A |

Guardrail thresholds must be derived from evidence, not arbitrary. Guardrail = N/A only when the change cannot plausibly hide a real signal.

### Contextual Action Links

Every Do Now and Investigate finding gets one `**Links:**` line directly after `**Notification Reach:**`. No links in Decision Summary, Needs Decision, Verification Scorecard, or Evidence Ledger. Max 3 links per finding, separator ` · `.

**Link construction** (see templates below for placement):

| Label | URL pattern | When |
|-------|-------------|------|
| Open policy | `https://console.cloud.google.com/monitoring/alerting/policies/{id}?project={monitoring_project}` | Concrete policy ID available |
| Open alert policies | `https://console.cloud.google.com/monitoring/alerting?project={monitoring_project}` | No concrete policy ID (fallback) |
| Search IaC | `https://github.com/search?q=org%3A{github_org}+{id}&type=code` | `{github_org}` provided in Stage 0 |
| Incident history | `https://console.cloud.google.com/monitoring/alerting/incidents?project={monitoring_project}` | Investigate only: next step is reviewing firing/timing patterns |
| Validate metric | `https://console.cloud.google.com/monitoring/metrics-explorer?project={monitoring_project}` | Investigate only: next step is metric validation AND report has enough query detail |

**Do Now:** Open policy + Search IaC (2 links).
**Investigate:** Open policy + Search IaC + optional contextual third link (max 3). Omit third link if it would require inventing missing query details.
**Do not** embed URLs in `Policy ID` or `IaC Location` fields — keep those plain text.

### Do Now Per-Item Template

```
### {N}. {Action}: {policy_name} [High / PR-Ready]

**Policy ID:** projects/{project}/alertPolicies/{id} | **Condition:** {condition_name}
**Target Owner:** {current_label} -> {target_team}
**Scope:** {projects affected}
**Notification Reach:** {N} channels
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/{id}?project={project}) · [Search IaC](https://github.com/search?q=org%3A{github_org}+{id}&type=code)

#### Current Policy Snapshot
(Include fields relevant to the finding type. Not all fields apply to every finding.)

**For threshold/query changes:**
**Threshold:** {comparison} {threshold_value} | eval: {eval_window_sec}s | auto_close: {auto_close_sec}s
**Condition:** `{condition_filter_or_query_excerpt_60chars}`

**For routing/ownership changes:**
**Current Label:** squad={current} | **Current Channels:** {channel list or count}

**For all Do Now items:**
**IaC Location:** [{Confirmed|Likely|Search Required}] {path or search guidance}

**Situation:** {what is happening — 1-2 sentences}
**Impact:** {why it matters — incident counts, duration, team effect}

#### Configuration Diff & Derivation
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| {param}   | {value} | {value}  | {why this value was chosen} |

**Pre-change Evidence:** {metric query result or structural proof with stated scope}
**Evidence Basis:** {measured|structural} — {query text or reasoning}

**Outcome DoD:**
- **Primary:** {numeric, time-bounded, aligned to finding type} (e.g., "raw incidents < 15 within 14d")
- **Guardrail:** {what must NOT degrade} (e.g., "no genuine backlog > 1000 goes undetected")

**Rollback Signal:** {derived threshold + timeframe for revert}
**Related:** {cross-references to other findings or systemic issues}
```

### Investigate Per-Item Template

```
### {N}. {investigation_title} [{High|Medium} / Stage 1]

**Policy ID:** projects/{project}/alertPolicies/{id}
**Target Owner:** {team}
**Scope:** {projects affected}
**Notification Reach:** {N} channels
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/{id}?project={project}) · [Search IaC](https://github.com/search?q=org%3A{github_org}+{id}&type=code)

**Situation:** {what is happening — 1-2 sentences}
**Impact:** {why it matters — incident counts, team effect}

#### Proposed Config Diff (pending gate resolution)
> Include this section ONLY when evidence basis is `measured` or `structural` AND a specific
> config diff is derivable. Omit entirely for heuristic-only items.

| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| {param}   | {value} | {value}  | {why this value was chosen} |

**Gate Blocker:** {which Do Now gate requirement is missing}
**To Upgrade:** {resolve blocker} → promotes to Do Now

**Evidence Basis:** {measured|structural|heuristic} — {current evidence}
**Hypothesis:** {explicit, testable hypothesis}

**Stage 1 DoD (Discovery — this ticket):**
- {specific diagnostic steps}
- **Closes when:** hypothesis confirmed/refuted AND follow-up action documented as a separate item
- **Timebox:** {N} days

**Stage 2 (Execution — spawned follow-up):**
- **If confirmed:** {specific action with its own numeric outcome DoD}
- **If refuted:** {alternative action or close with rationale}
```

### Two-Stage DoD Rules

- Stage 1 closes on hypothesis confirmed/refuted + explicit next action documented
- Stage 2 is a completely separate follow-up item with its own numeric, time-bounded outcome DoD
- This prevents mixing discovery work with delivery work in a single ticket

### Structurally Proven but Not-Yet-PR-Ready Items

Items with structural or measured evidence that fail the Do Now gate (e.g., missing IaC location, missing owner) land in Investigate with their full evidence preserved. The `To Upgrade` field states exactly which gate requirement is missing. Stage 1 for these items is not hypothesis validation — it is resolving the missing gate requirement (e.g., "locate IaC path," "assign owner"). Once resolved, the item can be promoted to Do Now in the next report cycle or follow-up.

### Needs Decision Per-Item Template

```
### {N}. {decision_title} [High / Decision Pending]

**Situation:** {what is happening — 1-2 sentences}
**Impact:** {why it matters — incident counts, redundancy, team effect}

**Decision Required:** {specific question that must be answered}
**Named Decision Owner:** {person or role — not generic "product owner"}
**Deadline:** {date — advisory, not auto-enforced}
**Default Recommendation:** {what the report recommends if no decision is made}

**Options:**
- **If A:** {action with expected outcome}
- **If B:** {action with expected outcome}
```

### Needs Decision Rules

- Deadline is advisory — the report does not auto-execute changes
- Default Recommendation is guidance for the decision owner, not an ultimatum
- Every Needs Decision item must have a named owner, not a generic role

### Mandatory Needs Decision Triggers

The following Needs Decision items are mandatory when their trigger condition is met:

- **Silent Policy Cleanup:** If `silent_policy_total > 0` and `silent_policy_count / silent_policy_total > 0.5` (more than half of enabled policies had zero incidents in the analysis window), include a "Silent Policy Cleanup" Needs Decision item with exact counts from compute-clusters output.

### Report Skeleton

```markdown
# Alert Hygiene Analysis Report
**Monitoring project:** {project} | **Window:** {days} days ending {date}

## Executive Summary
- {total_policies} policies ({enabled} enabled, {disabled} disabled), {total_incidents} raw incidents -> {total_episodes} episodes across {cluster_count} clusters
- Baseline metrics: {open_incident_hours} open-incident hours, {routed_volume} routed incidents, {ownerless_count} ownerless alerts
- Top findings (3-5 bullets with incident counts)
- {do_now_count} Do Now actions, {investigate_count} investigations, {decision_count} needs decision
- Modeled impact (estimated, scope: Do Now items only): {X} incidents reduced ({Y}%), {Z} open-incident hours reclaimed
- Note: modeled impact must never override measured baseline metrics. Always label projections as estimated with scope and confidence.

## Decision Summary
Capped at 8-12 items. Each Finding is linked to detailed section via anchor. Every non-empty category gets at least 1 row. After minimum representation, remaining rows filled in global priority order: Do Now by impact, then Investigate by urgency, then Needs Decision by deadline.

| Category | Finding (linked to detailed section) | Target Owner | Confidence / Readiness | Effort | Risk | Primary Expected Outcome | Next Action |
|----------|---------|--------------|----------------------|--------|------|--------------------------|-------------|

Primary Expected Outcome rules:
- Do Now: primary success outcome aligned to finding type (incident reduction, median duration, owner coverage)
- Investigate: Stage 1 closure result
- Needs Decision: decision closure

If more than 12 items total: *"Showing top {N} of {total} findings. See detailed sections below for complete list."*

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
(Key Terms table from the skill — raw incidents, episodes, raw/episode ratio with severity bands, noise score, evidence basis, open-incident hours)

| Term | Definition |
|------|-----------|
| **Open-incident hours** | Sum of all incident durations in the analysis window, measured in hours. Captures both volume and persistence of alert noise. |

(Plus existing terms: raw incidents, episodes, raw/episode ratio, noise score, evidence basis)

## Action Type Legend
- **Tune the alert** — the alert is miscalibrated. Specific config changes listed.
- **Fix the underlying issue** — the alert is correct. The service has a real problem.
- **Redesign around SLO** — replace threshold alerting with burn-rate/error-budget alerting.
- **Add/extend coverage** — a high-value blind spot exists.
- **No action** — well-calibrated, low-frequency. Keep as-is.

## Systemic Issues
Thematic and non-exhaustive — surfaces structural debt patterns without duplicating detailed findings.

### Ownership/Routing Debt
- Unlabeled policies ranked by incident volume (source: `unlabeled_ranking` from compute-clusters output)
- Misrouted alerts (e.g., prod alerts labeled as staging)

Top 10 policies without squad/team/owner label, ranked by total raw incidents:

| # | Policy | Policy ID | Raw ({days}d) | Episodes | Channels | Suggested Owner |
|---|--------|-----------|--------------|----------|----------|----------------|

"Suggested Owner" is left as "⚠ assign" unless resource project or metric type implies a specific team.

### Dead/Orphaned Config
Read from compute-clusters output — do not compute ad-hoc.

**Zero-channel policies:** Read `zero_channel_policies` array. If non-empty, render table:

| Policy | Policy ID | Raw ({days}d) | Squad |
|--------|-----------|---------------|-------|

If empty: *"No zero-channel policies found."*

**Disabled-but-still-noisy:** Read `disabled_but_noisy_policies` array. If non-empty, render table with same columns. If empty: *"No disabled-but-noisy policies."*

### Missing Coverage
Coverage gaps from comparison of `metric_types_in_inventory` against Coverage Gap Checklist:

| Gap | Action | Implementation | Rationale | Upstream Signal For |
(last column cross-references existing clusters this gap would detect earlier)

### Inventory Health
Read from compute-clusters output — do not compute ad-hoc.

- **Silent policy ratio:** `silent_policy_count` / `silent_policy_total` from compute-clusters output
- **Condition type breakdown:** render `condition_type_breakdown` dict from compute-clusters output
- **Enabled/disabled counts:** from Stage 1 policy pull (no change)

## Actionable Findings: Do Now
Items ordered by impact descending.

**Global Implementation Standard:**
For all Do Now items, the following standard applies:
1. IaC PR is approved and merged
2. Engineer confirms via GCP Monitoring Console that **every mutated field** matches the proposed config in production:
   - For threshold/query changes: verify PromQL condition, thresholds, eval window, auto_close
   - For routing/label changes: verify squad/team labels, notification channels
   - For scope changes: verify project/resource selectors
3. Confirm no accidental changes to fields outside the change spec (scope, channels, labels, conditions)
4. Record merge date for 14-day outcome review

Per-finding Immediate Verification is added only when the verification steps are non-obvious or high-risk (scope moves across projects, duplicate policy consolidation, multi-policy edits, channel rewiring).

### 1. {Action}: {policy_name} [High / PR-Ready]
(Do Now per-item template)

## Actionable Findings: Investigate
Items ordered by urgency.

### 1. {investigation_title} [{High|Medium} / Stage 1]
(Investigate per-item template with Two-Stage DoD)

## Needs Decision
Items ordered by deadline ascending.

### 1. {decision_title} [High / Decision Pending]
(Needs Decision per-item template)

## Keep — No Action Required
Brief section with 5-10 representative well-calibrated clusters and one-liner rationale for each (e.g., "fires <2x/14d, threshold well above baseline, correct routing"). Demonstrates the analysis evaluated the full inventory.

## Verification Scorecard
Rolled-up outcomes for all Do Now items. Re-run analysis in {days} days to verify.

| Finding | Baseline | Target | Owner | Merge Date | Review Date | Primary Success Criteria | Guardrail | Confidence |
|---------|----------|--------|-------|------------|-------------|--------------------------|-----------|------------|

## Evidence Ledger / Reproduction
Grouped by validation method. Reviewer action: `metric query` and `config inspection` items are audit-complete; `pattern analysis` items need reviewer judgment before applying.

### Config inspection — provable from policy definition
| Cluster | What was checked | Finding | Scope |

### Metric query — validated against Cloud Monitoring time-series
| Cluster | Query | Result | Finding |

### Pattern analysis — inferred from incident frequency/timing, needs validation before applying
| Cluster | Pattern observed | What would upgrade this | Scope |

### Not attempted — specific API limitation
| Cluster | Limitation | Why it can't be a single query |

## Appendix: Frequency Table
Full cluster table sorted by raw incidents: cluster key, raw, episodes, distinct resources, median duration, median retrigger, noise score, pattern, verdict, confidence.

## Appendix: Evidence Coverage
| Cluster | Metric Validated? | Evidence Basis | Sample Scope | Dedupe Window | Confidence |
(lets reviewer see which recommendations rest on metric validation vs pattern-only inference)
```
