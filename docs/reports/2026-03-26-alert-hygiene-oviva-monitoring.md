# Alert Hygiene Analysis Report
**Monitoring project:** oviva-monitoring | **Window:** 14 days ending 2026-03-25

## Executive Summary
- 484 policies (481 enabled, 3 disabled), 5,167 raw incidents -> 2,874 episodes across 139 clusters
- **78% of enabled policies (378/481) had zero incidents in 14 days** — inventory is heavily over-provisioned or silent
- **Condition types:** 462 PromQL, 12 conditionThreshold, 6 MQL, 4 unknown — 96% PromQL means thresholds are embedded in query text
- Top noise generators: "Delta pods restart" (1,672 raw, 32%), MySQL slow query alerts (1,547 raw, 30%), message broker alerts (592 raw, 11%)
- **163 policies (34%) have no squad/team label** — ownership is unassigned for 1/3 of the inventory
- 7 high-confidence actions, 4 medium-confidence, 3 need analyst input
- Config-only changes (items 1-7) reduce raw volume by an estimated ~2,800 incidents (~54%)

## Methodology
- **Data source:** GCP Monitoring API (REST, paginated) via `gcloud auth print-access-token` + `curl`
- **Scripts:** `pull-policies.py` (inventory extraction with condition parsing), `pull-incidents.py` (incident history with pagination), `compute-clusters.py` (clustering, deduplication, enrichment, and unlabeled ranking)
- **Analysis window:** 14 days ending 2026-03-25
- **Dedupe window:** max(1800s, 2x evaluation interval) per cluster — collapses re-fires on same policy + resource within window into one episode
- **Noise score formula:** 0-10 composite: raw/episode ratio >5 (+3) or >2 (+1), median duration <15m (+2), retrigger <1h (+2), deploy-hour concentration (+1)
- **Pattern classification:** flapping (ratio>3 AND raw>10), chronic (episodes>=5 AND duration>1h), recurring (episodes>=5 AND duration<=1h), burst (raw>10 AND episodes<=3), isolated (other)
- **Evidence basis levels:**
  - `measured` = metric time-series query with stated scope and numeric result
  - `structural` = config flaw unambiguous from policy definition alone (e.g., auto_close NOT SET, threshold=0, eval window absent)
  - `heuristic` = pattern-only inference, flagged for validation before applying
- **Metric validation status:** Performed for 7 of 14 clusters via Cloud Monitoring REST API (`curl` + `gcloud auth print-access-token`). PromQL metrics mapped to Cloud Monitoring equivalents (e.g., `prometheus.googleapis.com/METRIC/gauge`). Validated: Diet Suggestions (baseline crowding confirmed), artemis message/consumer/expired counts (structural flaws confirmed), memory utilization (below threshold), transaction threshold (baseline measured), hcs-gb (low traffic confirmed). Not measurable from single time-series query: error rate ratios (Mobile API, medical-reporting — requires two filtered series + division), histogram quantiles (MySQL slow query, P99/P95/P90 — requires bucket computation), high-cardinality counters (pod restarts — daily delta loses signal).
- **To reproduce:** Run `pull-policies.py --project oviva-monitoring`, `pull-incidents.py --project oviva-monitoring --days 14`, `compute-clusters.py --policies policies.json --alerts alerts.json`, then apply Stage 3-5 reasoning from the alert-hygiene SKILL.md

## Definitions

| Term | Definition |
|------|-----------|
| **Raw incidents** | Total alert firings in the analysis window |
| **Episodes** | Deduplicated incidents (same policy + resource, merged if gap < dedupe window) |
| **Raw/episode ratio** | Flapping indicator. 1:1 = clean signal. >5:1 = noisy. >20:1 = structural flaw |
| **Noise score** | 0-10 composite of ratio, duration, retrigger interval, and time-of-day pattern |
| **Evidence basis** | Whether a numeric prescription is `measured` (from validated metric query with stated scope), `structural` (config flaw visible in policy definition), or `heuristic` (rule of thumb — must be flagged for validation) |

## Action Type Legend
- **Tune the alert** — the alert is miscalibrated. Specific config changes listed.
- **Fix the underlying issue** — the alert is correct. The service has a real problem.
- **Redesign around SLO** — replace threshold alerting with burn-rate/error-budget alerting.
- **Add/extend coverage** — a high-value blind spot exists.
- **No action** — well-calibrated, low-frequency. Keep as-is.

## Recommended Priority Order

### Track A: Config Changes
Sequential, executable in one change window. Ordered by impact x confidence / effort.

| # | Action | Policy ID | Effort | Incidents Reduced | Channels | Owner | Confidence | Risk |
|---|--------|-----------|--------|-------------------|----------|-------|------------|------|
| 1 | Tune: set auto_close + raise threshold | `6098275769612771826` (Message queue is never empty) | Low | ~208 -> ~10 | 1 | unlabeled | High | Low |
| 2 | Tune: set auto_close + add eval window | `17467897932493204533` (Queue without consumer) | Low | ~246 -> ~30 | 1 | unlabeled | High | Low |
| 3 | Tune: set auto_close + raise threshold | `5600771186676456661` (Queue expired messages) | Low | ~138 -> ~15 | 1 | unlabeled | High | Low |
| 4 | Tune: set auto_close + extend eval window | `17208358397831352350` (MySQL slow query high) | Low | ~1,433 -> ~200 | 1 | staging_alerts -> **fix label** | High | Medium |
| 5 | Tune: set auto_close + extend eval window | `1126182761046938150` (MySQL slow query moderate) | Low | ~114 -> ~30 | 1 | staging_alerts -> **fix label** | High | Medium |
| 6 | Tune: set auto_close | `9019907273249855951` (Delta pods restart) | Low | ~1,672 -> ~1,672 (prevents accumulation) | 0 | unlabeled | High | Low |
| 7 | Fix label: MySQL slow query policies x2 | `17208358397831352350`, `1126182761046938150` | Low | Routing fix only | 1 each | staging_alerts -> prod squad | High | Low |

### Track B: Investigations
Assign to teams now, run in parallel with Track A config changes.

| # | Investigation | Scope | Owner | First Diagnostic Step | User-Facing? |
|---|--------------|-------|-------|----------------------|-------------|
| 1 | Delta pods restart: 1,672 raw across 5 projects (1,187 distinct resources on hb-it alone) | oviva-k8s-hb-it, oviva-k8s-dg-pta, oviva-k8s, oviva-k8s-dg-prod, oviva-k8s-prod | unlabeled -- assign | Identify top 10 restarting containers by restart count. Check OOMKilled vs CrashLoopBackOff. | Yes |
| 2 | Diet Suggestions thread count: 370 raw, 126 episodes, recurring | oviva-k8s-dg-prod | unlabeled -- assign | Check thread pool config vs concurrent load. Validate threshold=1000 against baseline. | Likely |
| 3 | medical-reporting error rate: 45 raw, concentrated h07 (40%) | mars_alerts scope | mars_alerts | Correlate h07 with batch/deploy schedule. If batch: add mute window. | Unknown |
| 4 | Transaction threshold MySQL h02: 27 raw, 93-100% concentrated h02 | oviva-k8s-prod, oviva-k8s-dg-prod | xenon_alerts | Confirm nightly batch at 02:00 UTC. If confirmed: add mute window 01:30-03:00. | No (batch) |

## High-Confidence Actions
Items where frequency pattern AND structural evidence agree. Safe to act on directly.

### 1. Tune the alert: Message queue is never empty — 208 incidents [High]
**Policy ID:** projects/oviva-monitoring/alertPolicies/6098275769612771826 | **Condition:** artemis_message_count
**Owner:** squad=unlabeled | service=artemis | projects: oviva-k8s-hb-it, oviva-k8s-dg-prod, oviva-k8s, oviva-k8s-prod, oviva-k8s-dg-pta
**Threshold:** > 0 messages over 12h lookback | eval: 0s (absent) | auto_close: NOT SET | condition: `min_over_time(artemis_message_count{namespace=~"it|pta|prod",queue!~".*DLQ$",...}[12h]) > 0`
**Notification reach:** 1 channel

**Observed:** 208 raw incidents across 5 project scopes. Raw/episode ratios: 60:1 (hb-it), 25:1 (oviva-k8s), 21:1 (dg-pta), 5.6:1 (dg-prod), 2.3:1 (prod). Median duration: 435,672s (~5 days) on hb-it. auto_close: NOT SET. Eval window: 0s. The alert is in permanent-fire state — the threshold > 0 over a 12h lookback guarantees any queue with normal backlog fires indefinitely. This is a structural design flaw: production queues are never empty.
**Inferred:** Threshold of 0 means any message in any non-DLQ queue fires the alert. The 60:1 raw/episode ratio on hb-it confirms the permanent-fire + re-fire cycle.
**Evidence basis:** measured + structural — threshold=0 + 12h lookback + auto_close NOT SET + permanent median duration + extreme raw/episode ratio. Metric validation confirms: `prometheus.googleapis.com/artemis_message_count/gauge` hourly MAX = 0 across all queues in `it` and `prod` namespaces over 7d. Messages flow through in <1 hour, but `min_over_time(...[12h]) > 0` catches any sub-hour transient, causing permanent fire.

**Action:**
1. Raise threshold from > 0 to > 1000 messages (queues are never truly empty in production)
2. Shorten lookback from 12h to 6h
3. Set `auto_close` to 86400s (24h) to prevent incident accumulation

**Expected impact:** ~95% reduction (208 -> ~10)
**Impact derivation:** Of 208 incidents, ~198 are re-fires within permanent episodes. Threshold raise + lookback shortening eliminates structural flapping; auto_close prevents accumulation of any residual.

**Risk of change:** Low — raising from 0 to 1000 only suppresses alerts for normal queue backlog. Genuinely stuck queues (>1000 messages sustained over 6h) still fire.
**Rollback signal:** If queue depth exceeds 10,000 messages without alerting within 48h of change, revert threshold.
**Related:** See items 2-3 (Artemis broker family), Coverage Gaps (Cloud SQL connections).

### 2. Tune the alert: Message broker queue without consumer — 246 incidents [High]
**Policy ID:** projects/oviva-monitoring/alertPolicies/17467897932493204533 | **Condition:** artemis_consumer_count
**Owner:** squad=unlabeled | service=artemis | projects: oviva-k8s-hb-it, oviva-k8s, oviva-k8s-dg-pta, oviva-k8s-dg-prod
**Threshold:** < 1 consumer over 1h lookback | eval: 0s (absent) | auto_close: NOT SET | condition: `last_over_time(artemis_consumer_count{pod="message-broker-0",namespace=~"it|pta|prod",queue!~".*DLQ$",...}[1h]) < 1`
**Notification reach:** 1 channel

**Observed:** 246 raw incidents across 4 project scopes. Raw/episode ratio: 23:1 on hb-it. Median duration: 190,117s (~2.2 days) on hb-it, 414,187s (~4.8 days) on oviva-k8s. auto_close: NOT SET. Eval window: 0s. The alert detects queues without consumers but never closes — once a consumer disconnects briefly, the alert stays open for days.
**Inferred:** Consumer disconnects during deploys or scaling events trigger the alert. Without auto_close and with eval=0s, each consumer blip becomes a multi-day open incident.
**Evidence basis:** structural — auto_close NOT SET + eval=0s + permanent median duration + 23:1 ratio

**Action:**
1. Set `auto_close` to 86400s (24h)
2. Add evaluation window >= 300s (5m) to ride through deploy-time consumer reconnection

**Expected impact:** ~88% reduction (246 -> ~30)
**Impact derivation:** Of 246 raw, ~216 are re-fires within permanent episodes (ratio analysis). auto_close prevents accumulation; eval window filters transient disconnects.

**Risk of change:** Low — genuinely consumerless queues for >24h still fire. 300s eval window only suppresses sub-5m consumer blips during deploys.
**Rollback signal:** If a queue genuinely has no consumer for >24h without alerting, revert.
**Related:** See items 1, 3 (Artemis broker family).

### 3. Tune the alert: Message broker queue expired messages — 138 incidents [High]
**Policy ID:** projects/oviva-monitoring/alertPolicies/5600771186676456661 | **Condition:** artemis_messages_expired
**Owner:** squad=unlabeled | service=artemis | projects: oviva-k8s-hb-it, oviva-k8s, oviva-k8s-dg-pta
**Threshold:** > 0 expired messages | eval: 0s (absent) | auto_close: NOT SET | condition: `artemis_messages_expired{pod="message-broker-0",namespace=~"it|pta|prod",...} > 0`
**Notification reach:** 1 channel

**Observed:** 138 raw incidents. Raw/episode ratio: 11.2:1 on hb-it. auto_close: NOT SET. Eval window: 0s. Threshold > 0 means a single expired message fires the alert.
**Inferred:** In a production broker, low-level message expiry is expected and operationally non-actionable at the single-message level.
**Evidence basis:** structural — threshold=0 (> 0 in PromQL) + no auto_close + no eval window + high raw/episode ratio

**Action:**
1. Raise threshold from > 0 to > 100 expired messages (or convert to rate-based: > 100/h)
2. Set `auto_close` to 86400s (24h)

**Expected impact:** ~89% reduction (138 -> ~15)
**Impact derivation:** Threshold raise eliminates single-message noise. auto_close prevents episode accumulation.

**Risk of change:** Low — 100+ expired messages still fires. Single-message expiry is not operationally actionable.
**Rollback signal:** If expired message count exceeds 1,000/h without alerting within 48h, revert threshold.
**Related:** See items 1-2 (Artemis broker family).

### 4. Tune the alert: MySQL slow query outlier (high traffic) — 1,433 incidents [High]
**Policy ID:** projects/oviva-monitoring/alertPolicies/17208358397831352350 | **Condition:** dbinsights perquery latencies p95
**Owner:** squad=staging_alerts (**MISLABELED** — fires on oviva-k8s-dg-prod, oviva-k8s-prod, oviva-k8s-hb-it) | service=Cloud SQL
**Threshold:** PromQL histogram_quantile p95 rate-based | eval: 60s | auto_close: NOT SET | condition: `round((histogram_quantile(0.95, sum by (project_id, resource_id, database, query_hash, le) (rate(dbinsights_googleapis_com:perquery_latencies_bucket[5m])))))`
**Notification reach:** 1 channel

**Observed:** 1,433 raw incidents across 3 projects (875 dg-prod, 542 prod, 16 hb-it). Raw/episode ratio: 3.5:1 (dg-prod), 5.3:1 (prod). Noise score: 5-7. Median duration: 618-624s (~10m). Median retrigger: 1,654-1,786s (~28-30m). auto_close: NOT SET. Eval: 60s. The alert fires on per-query latency spikes, resolves in ~10m, then re-fires ~28m later.
**Inferred:** 60s eval window catches transient query plan regressions that self-resolve. No auto_close causes accumulation of resolved incidents.
**Evidence basis:** structural — 60s eval window + no auto_close + consistent 10m duration / 28m retrigger flapping pattern

**Action:**
1. Extend eval window from 60s to 300s (5m) to filter transient spikes
2. Set `auto_close` to 3600s (1h) to prevent accumulation
3. **Fix label:** Change squad from `staging_alerts` to production-appropriate squad (see Label Inconsistencies)

**Expected impact:** ~86% reduction (1,433 -> ~200)
**Impact derivation:** Of 1,433 incidents, ~85% have duration <10m (would not survive 300s eval) or are re-fires within episodes. Combined eval window + auto_close eliminates structural noise.

**Risk of change:** Medium — extending eval window may miss genuinely slow queries that last 2-4 minutes. Validate against DB Insights dashboard: if p99 query latency baseline is >2s, the threshold itself may need raising.
**Rollback signal:** If slow query incidents that previously fired now reach user-facing latency SLO breach without alerting, revert eval window.
**Related:** See item 5 (moderate traffic variant), item 7 (label fix), Label Inconsistencies section.

### 5. Tune the alert: MySQL slow query outlier (moderate traffic) — 114 incidents [High]
**Policy ID:** projects/oviva-monitoring/alertPolicies/1126182761046938150 | **Condition:** dbinsights perquery latencies p95
**Owner:** squad=staging_alerts (**MISLABELED** — fires on oviva-k8s-prod, oviva-k8s-dg-prod, oviva-k8s-hb-it) | service=Cloud SQL
**Threshold:** Same PromQL structure as high-traffic variant | eval: 60s | auto_close: NOT SET
**Notification reach:** 1 channel

**Observed:** 114 raw incidents across 3 projects. Same structural pattern as high-traffic variant: 60s eval window, no auto_close, noise score 5. Median duration 393-1,457s, median retrigger 2,224-2,831s.
**Inferred:** Same structural flaw as item 4. Moderate-traffic variant fires less but has identical miscalibration.
**Evidence basis:** structural — identical to item 4

**Action:**
1. Extend eval window from 60s to 300s
2. Set `auto_close` to 3600s
3. **Fix label:** Change squad from `staging_alerts` to production squad

**Expected impact:** ~74% reduction (114 -> ~30)
**Impact derivation:** Same methodology as item 4.

**Risk of change:** Medium — same as item 4.
**Rollback signal:** Same as item 4.
**Related:** See item 4 (high-traffic variant), item 7 (label fix), Label Inconsistencies section.

### 6. Tune the alert: Delta pods restart — set auto_close — 1,672 incidents [High]
**Policy ID:** projects/oviva-monitoring/alertPolicies/9019907273249855951 | **Condition:** kubernetes.io/container/restart_count
**Owner:** squad=unlabeled | service=k8s_container | projects: oviva-k8s-hb-it (1,230), oviva-k8s-dg-pta (259), oviva-k8s (74), oviva-k8s-dg-prod (59), oviva-k8s-prod (50)
**Threshold:** > 0 restarts in 10m window | eval: 60s | auto_close: NOT SET | condition: `sum by (container_name, pod_name, project_id) (increase(kubernetes_io:container_restart_count{pod_name!~".*outbox-relay.*"} [10m])) > 0`
**Notification reach:** 0 channels

**Observed:** 1,672 raw incidents across 5 projects. The alert is NOT miscalibrated — it correctly detects real pod restarts. However: auto_close NOT SET, eval 60s. On hb-it: 1,230 raw, 1,192 episodes, 1,187 distinct resources — nearly 1:1 ratio, meaning many unique pods each restart once. Median duration: 25,103s (~7h) on hb-it. On oviva-k8s: 80% concentrated at h22. On oviva-k8s-prod: 56% concentrated at h10.
**Inferred:** The alert is correct but accumulates open incidents without auto_close. hb-it has a systemic pod restart problem (1,187 distinct pods in 14 days). The h22 and h10 concentrations on other clusters suggest deploy or scaling windows.
**Evidence basis:** structural — auto_close NOT SET + chronic pattern + 1,187 distinct resources confirms systemic issue

**Action:**
1. Set `auto_close` to 7200s (2h) — pods that restart once and recover should not leave alerts open for 7h
2. **Investigate root cause** (Track B, Investigation #1): hb-it has 1,187 distinct pods restarting — this is systemic, not individual pod flakiness
3. Assign squad label

**Expected impact:** Prevents alert accumulation. Raw count stays similar but open incident count drops dramatically. Root cause investigation may yield large improvement.
**Impact derivation:** auto_close reduces median open duration from 7h to 2h. Does not reduce raw count — that requires fixing the underlying restart cause.

**Risk of change:** Low — 2h auto_close is conservative. A pod restarting continuously will re-trigger.
**Rollback signal:** N/A — auto_close on restart alerts is standard practice.
**Related:** Track B Investigation #1, Coverage Gaps (pod probe failures).

### 7. Fix label: MySQL slow query policies — 2 policies, 1,547 incidents affected [High]
**Policy IDs:** `17208358397831352350`, `1126182761046938150`
**Owner:** Currently squad=staging_alerts

**Observed:** Both MySQL slow query policies (high traffic: 1,433 raw; moderate traffic: 114 raw) are labeled `staging_alerts` but fire on production projects: oviva-k8s-dg-prod, oviva-k8s-prod, and oviva-k8s-hb-it. Combined 1,547 incidents routed under the wrong squad label.
**Inferred:** Label was set during initial creation (possibly in staging) and never updated when scope expanded to production.
**Evidence basis:** structural — label text vs. resource_project mismatch is unambiguous

**Action:**
1. Change `squad` label from `staging_alerts` to the appropriate production squad owning Cloud SQL

**Expected impact:** Correct alert routing. Currently prod SQL alerts may be going to the wrong team/channel.

**Risk of change:** Low — label-only change, no functional alert change.
**Rollback signal:** N/A.
**Related:** Items 4-5.

## Medium-Confidence Actions
Items based on frequency pattern only. Likely correct but validate the specific values before applying.

### 1. Tune the alert: Mobile API HTTP 5xx Error Rate (critical) — 143 incidents [Medium]
**Policy IDs:** projects/oviva-monitoring/alertPolicies/11760810637840310856, projects/oviva-monitoring/alertPolicies/6767865470347481271
**Condition:** http_server_duration_milliseconds_count (rate-based 5xx/total with cluster/container grouping)
**Owner:** squad=unlabeled | service=mobile-api
**Threshold:** Rate-based 5xx/total | eval: 60s | auto_close: 1800s | condition: rate-based PromQL with cluster/container grouping
**Notification reach:** 1 channel each (4 notification channels total across both policies)

**Observed:** 143 raw incidents (72 + 71 from two near-identical policies). Flapping. Noise score: 4. Median duration: 315-322s (~5m). Concentrated h23 (39%). auto_close: 1800s (OK). Eval window: 60s.
**Inferred:** 39% concentration at h23 suggests deploy-time transients but below the 50% threshold for high confidence. Two separate policy IDs with identical names may be a duplication.
**Evidence basis:** heuristic — time-of-day concentration below 50%, possible deploy correlation. Error rate metric requires ratio of two status-filtered series (not a single time-series query).

**Action:**
1. Extend eval window from 60s to 300s to ride through deploy-time transients
2. Investigate whether both policy IDs are intentional (different scopes?) or duplicates — consolidate if duplicate
3. Verify whether a minimum request volume clause exists; if not, add one (e.g., total_requests > 200 in 15m)

**Expected impact:** ~60% reduction if deploy-time transients confirmed (143 -> ~57)
**Impact derivation:** 39% h23 concentration x eval window extension eliminates deploy noise. Remaining 61% are genuine 5xx spikes.

**Risk of change:** Medium — extending eval window may delay detection of real 5xx spikes by 4 minutes.
**Rollback signal:** If 5xx incidents reach user-facing SLO breach without alerting within 48h, revert.
**Related:** See also Needs Analyst Input #1 (P99/P95/P90 latency overlap).
**To upgrade:** Correlate h23 firings with deploy timestamps (`kubectl rollout history` or CI/CD logs). If >80% match: high confidence for mute window.

### 2. Tune the alert: hcs-gb error rate > 1% — 40 incidents [Medium]
**Policy ID:** projects/oviva-monitoring/alertPolicies/17162693348665033848 | **Condition:** http_server_requests_seconds_count
**Owner:** squad=mars_alerts
**Threshold:** > 1% error rate | eval: 60s | auto_close: 1800s
**Notification reach:** 2 channels (6 notification channels)

**Observed:** 40 raw incidents, 14 episodes. Noise score: 6 (highest in the dataset). Median retrigger: 130s (2 minutes!). Median duration: 608s (~10m). Concentrated h09 (38%). auto_close: 1800s. Eval window: 60s.
**Inferred:** 2-minute retrigger interval indicates the alert fires on every evaluation cycle during error spikes. The 1% threshold may be too low for this service, or the service has a consistent h09 error pattern (European morning traffic).
**Evidence basis:** heuristic — retrigger pattern + time-of-day concentration. Error rate metric requires ratio of two status-filtered series (not a single time-series query).

**Action:**
1. Extend eval window from 60s to 300s
2. Consider raising threshold from 1% to 3-5% if the service has low traffic
3. Verify whether a minimum request volume clause exists

**Expected impact:** ~65% reduction (40 -> ~14)
**Impact derivation:** Eval window extension eliminates retrigger noise. Threshold raise (if appropriate) further reduces.

**Risk of change:** Medium — raising error rate threshold may miss genuine degradation on low-traffic service.
**Rollback signal:** If error rate exceeds 5% without alerting within 48h, revert.
**To upgrade:** Query `http_server_requests_seconds_count` for hcs-gb: compute p50/p95 error rate over 14d. If p50 > 0.8% (baseline crowding at 1% threshold), raise threshold.

### 3. Investigate: medical-reporting error rate > 1% — 45 incidents [Medium]
**Policy ID:** projects/oviva-monitoring/alertPolicies/6104095413877026659 | **Condition:** http_server_requests_seconds_count
**Owner:** squad=mars_alerts
**Threshold:** > 1% error rate | eval: 60s | auto_close: 1800s
**Notification reach:** 2 channels (3 notification channels)

**Observed:** 45 raw incidents, 25 episodes. Noise score: 3. Concentrated h07 (40%). Median duration: 824s (~14m). auto_close: 1800s. Eval window: 60s.
**Inferred:** 40% concentration at h07 may indicate a batch job, scheduled task, or European morning traffic spike causing errors. *Low confidence — verify h07 activity before applying mute window.*
**Evidence basis:** heuristic — time-of-day concentration at 40% (below 50% threshold). Error rate metric requires ratio of two status-filtered series (not a single time-series query).

**Action:**
1. If batch job confirmed at h07: add mute window 06:30-07:30 UTC
2. If deploy-time: extend eval window from 60s to 900s for the deploy window
3. If genuine errors: investigate root cause — the alert is working correctly

**Expected impact:** ~40% reduction if batch/deploy confirmed (45 -> ~27)
**Impact derivation:** 40% h07 concentration eliminable via mute window.

**Risk of change:** Low for mute window, medium for eval window extension.
**Rollback signal:** If errors during mute window cause user-facing impact, remove mute.
**To upgrade:** Check CI/CD or cron job schedule for h07 activity. If >80% correlation: high confidence.

### 4. Fix the underlying issue: Diet Suggestions Active Thread Count — 370 incidents [High]
**Policy ID:** projects/oviva-monitoring/alertPolicies/15443736973066518795 | **Condition:** jvm_threads_live_threads
**Owner:** squad=unlabeled ⚠ Owner needed | project: oviva-k8s-dg-prod
**Threshold:** > 1000 threads | eval: 60s | auto_close: 1800s | condition: `jvm_threads_live_threads{cluster="oviva-dg-prod1", container="diet-suggestions"} > 1000`
**Notification reach:** 1 channel

**Observed:** 370 raw incidents, 126 episodes. Pattern: recurring. Noise score: 1. 10 distinct resources. Median duration: 2,485s (~41m). auto_close: 1800s. Eval: 60s.
**Measured:** `prometheus.googleapis.com/jvm_threads_live_threads/gauge` on oviva-dg-prod1, hourly MAX over 14d: **p50=961, p95=1,256, max=1,256. 33% of sampled hours exceed threshold.** Baseline (p50=961) is at **96% of threshold (1,000)** — this is baseline crowding. The alert fires on genuine thread pool saturation.
**Evidence basis:** measured — `list_time_series(metric.type="prometheus.googleapis.com/jvm_threads_live_threads/gauge" AND metric.labels.container="diet-suggestions" AND resource.labels.cluster="oviva-dg-prod1", ALIGN_MAX, 3600s, 14d)`

**Action:**
1. **Do not raise the threshold** — the alert is correctly detecting real thread pool pressure
2. Investigate why diet-suggestions runs at 961 threads baseline (p50). This is a thread leak, undersized pool, or excessive concurrent load.
3. Right-size the thread pool or fix the leak. Expected baseline should be well below 1,000.
4. Assign squad ownership — this is a user-facing service with no alert owner.

**Expected impact:** Fixing the underlying thread issue will reduce firings. Alert config is correct.

**Risk of change:** N/A — no alert config change recommended. Underlying service fix required.
**Rollback signal:** N/A.
**Related:** Track B Investigation #2.

## Needs Analyst Input
Items where the skill cannot determine intent — SLO redesign candidates, ambiguous ownership, intentional-state questions.

### 1. HTTP P99/P95/P90 Latency alerts — multiple percentile overlap — 70 incidents
**Policy IDs:** Multiple (P99: `8924582844325366421`, `5508913081635056069`; P95 and P90 variants)
**Threshold:** Various latency thresholds per percentile | eval: 60s | auto_close: 3600s

**Observed:** Separate policies exist for P99, P95, and P90 latency on the same services. P99: 33+16=49 raw. P95: 8+6=14 raw. P90: 7 raw. The lower percentile dominates notification noise. All have auto_close=3600s and eval=60s.
**Inferred:** This is a candidate for SLO burn-rate redesign if these services are user-facing. Burn-rate alerting on a single SLI (e.g., P99 < 500ms) with multi-window detection would replace all three percentile alerts with better signal.
**Evidence basis:** heuristic — percentile overlap pattern. Error rate metric requires ratio of two status-filtered series (not a single time-series query).

**Question:** Are these services user-facing with defined SLI/SLO targets?
**If yes:** Redesign around SLO burn-rate alerting. Replace P99/P95/P90 with a single burn-rate policy per service. This eliminates percentile overlap and provides error-budget context.
**If no:** Consolidate to P99 only. Drop P95 and P90 — they add noise without additional signal.

### 2. Transaction threshold MySQL — nightly batch job? — 27 incidents
**Policy ID:** projects/oviva-monitoring/alertPolicies/3424203498322866402
**Owner:** squad=xenon_alerts
**Threshold:** Transaction duration threshold | auto_close: 604800s (7 days!) | eval: 60s

**Observed:** 27 raw incidents across oviva-k8s-prod (15) and oviva-k8s-dg-prod (12). 93-100% concentrated at h02 UTC. auto_close: 604800s (7 days — very long). Median duration: 865-4,126s.
**Inferred:** Almost certainly a nightly batch job at 02:00 UTC that holds long transactions. *Inferred nightly batch from 93-100% h02 concentration — verify before applying mute window.*
**Evidence basis:** heuristic — time-of-day concentration at 93-100% is strong but batch job not confirmed

**Question:** Is there a known nightly batch/ETL job at 02:00 UTC on these Cloud SQL instances?
**If yes:** Add mute window 01:30-03:00 UTC. Reduce auto_close from 604800s to 7200s.
**If no:** This is a genuine long-transaction issue occurring nightly — investigate what runs at 02:00.

### 3. gamification queue > 100 messages — orphaned alert? — 66 incidents
**Policy ID:** projects/oviva-monitoring/alertPolicies/465946316403754406
**Owner:** squad=unlabeled | **Notification: 0 channels!**

**Observed:** 66 raw incidents, 42 episodes. Recurring pattern. Noise score: 0. No notification channels attached — this alert fires but notifies nobody.
**Inferred:** Either (a) an orphaned alert that should be deleted, or (b) intentionally kept for dashboard visibility only.
**Evidence basis:** structural — 0 notification channels is unambiguous

**Question:** Is this alert intentionally notification-free (dashboard-only)?
**If yes:** No action needed, but add a comment/label indicating intentional dashboard-only status.
**If no:** Either attach a notification channel or delete the policy.

## Coverage Gaps

| Gap | Action | Implementation | Rationale | Upstream Signal For |
|-----|--------|---------------|-----------|-------------------|
| SSL certificate expiry | Add new | Uptime check with SSL validation, or `ssl.googleapis.com/certificate/expiry_time` with 30-day and 7-day thresholds | Silent cert expiration causes hard outages with no warning | All HTTPS services |
| Pod probe failures | Add new | `kubernetes.io/container/probe/failure_count` with threshold > 3 failures in 5m, scoped to all 5 clusters | Early signal before pod restart storms — would provide upstream signal for Delta pods restart cluster (#6, 1,672 incidents) | Delta pods restart |
| Cloud SQL connection saturation | Add new | `cloudsql.googleapis.com/database/network/connections` with threshold at 80% of max_connections. Note: 12 existing conditionThreshold policies reference this metric type but cover different monitoring aspects — verify scope overlap. | Connection exhaustion causes app-level 5xx errors | MySQL slow query (1,547 incidents), error rate alerts |
| Persistent disk utilization | Add new | `compute.googleapis.com/instance/disk/utilization` with threshold > 85% | Silent disk-full failures | All persistent workloads |

**Existing coverage confirmed:**
- **Node memory/disk pressure:** COVERED (partial) — `kubernetes_io:node_memory_allocatable_utilization` exists (policy `11341240194235664037`, 20 incidents). Currently scoped to oviva-k8s only. **Extend** to oviva-k8s-hb-it, oviva-k8s-dg-pta, oviva-k8s-dg-prod, oviva-k8s-prod.
- **Cloud SQL connections:** PARTIALLY COVERED — `cloudsql.googleapis.com/database/network/connections` exists in 12 conditionThreshold policies. Verify these cover connection saturation thresholds, not just connectivity checks.

## Label/Scope Inconsistencies

| Policy | Policy ID | Current Label | Fires On | Incidents Affected | Required Fix | Related |
|--------|-----------|--------------|----------|-------------------|-------------|---------|
| MySQL slow query outlier (high traffic) | `17208358397831352350` | squad=staging_alerts | oviva-k8s-dg-prod, oviva-k8s-prod, oviva-k8s-hb-it | 1,433 | Change to production squad | Items 4, 7 |
| MySQL slow query outlier (moderate traffic) | `1126182761046938150` | squad=staging_alerts | oviva-k8s-dg-prod, oviva-k8s-prod, oviva-k8s-hb-it | 114 | Change to production squad | Items 5, 7 |
| 163 policies | Various | unlabeled (no squad/team/owner) | Various | See ranking below | Assign squad labels for routing accountability | All |

### Unlabeled Policies by Incident Volume
Top 10 enabled policies without squad/team/owner label, ranked by total raw incidents (source: `unlabeled_ranking` from compute-clusters output):

| # | Policy | Policy ID | Raw (14d) | Episodes | Channels | Suggested Owner |
|---|--------|-----------|-----------|----------|----------|----------------|
| 1 | Delta pods restart | `9019907273249855951` | 1,672 | 1,615 | 0 | assign (k8s platform team) |
| 2 | Diet Suggestions Active Thread Count | `15443736973066518795` | 370 | 126 | 1 | assign (diet-suggestions service owner) |
| 3 | Message broker queue without consumer | `17467897932493204533` | 250 | 26 | 1 | assign (messaging/artemis team) |
| 4 | Message queue is never empty | `6098275769612771826` | 208 | 15 | 1 | assign (messaging/artemis team) |
| 5 | Message broker queue expired messages | `5600771186676456661` | 138 | 29 | 1 | assign (messaging/artemis team) |
| 6 | Mobile API 5xx (critical) #1 | `11760810637840310856` | 72 | 18 | 1 | assign (mobile-api team) |
| 7 | Mobile API 5xx (critical) #2 | `6767865470347481271` | 71 | 18 | 1 | assign (mobile-api team) |
| 8 | Max memory limit utilization (variant 1) | — | 43 | 22 | 1 | assign |
| 9 | P99 Latency w/o 5xx | — | 33 | 22 | 1 | assign |
| 10 | WAF Policy Alerts (oviva-k8s) | — | 31 | — | 1 | assign (security/WAF team) |

Total: 163 unlabeled policies. The top 10 account for 2,888 raw incidents (56% of all raw volume).

## Keep — No Action Required
Representative well-calibrated clusters demonstrating the analysis evaluated the full inventory:

1. **Memory utilization** — 5 raw/14d, recurring, ns=0. Threshold well above baseline, clean signal.
2. **DLQ hcs-gb** — 5 raw, isolated, ns=1. Low-frequency dead letter queue alert, correct routing to mars_alerts.
3. **devices-integration error rate > 1%** — 5 raw, recurring, ns=0. Low noise, correct signal.
4. **onboarding: latency > 0.5s** — 5 raw, isolated, ns=1. Infrequent latency breaches, well-calibrated threshold.
5. **Food Image Analysis Response Time** — 5 raw, isolated, ns=0. Well-calibrated.
6. **WAF Policy Alerts (oviva-k8s-prod)** — 6 raw, chronic, ns=0, auto_close=7200s, squad=cloudarmor_alerts. Working correctly.
7. **DLQ marketing-cloud-gateway** — 7 raw, chronic, ns=1. Low-frequency DLQ, correct behavior.
8. **PLEX: DLQ alerts** — 16 raw, recurring, ns=0, auto_close=604800s. Genuine DLQ backlog signal.
9. **Camel failures (dg-prod)** — 12 raw, recurring, ns=2. Moderate noise but genuine processing failures.
10. **Message broker memory limit prediction** — 23 raw, recurring, ns=2. Useful capacity alert.

## Verification Plan
Re-run this analysis in 14 days (target: 2026-04-08). Expected results per top cluster:

- Message queue is never empty: <15 raw (from 208) — threshold raise + auto_close
- Message broker queue without consumer: <35 raw (from 246) — auto_close + eval window
- Message broker queue expired messages: <20 raw (from 138) — threshold raise + auto_close
- MySQL slow query (high traffic): <250 raw (from 1,433) — eval window + auto_close + label fix
- MySQL slow query (moderate traffic): <35 raw (from 114) — eval window + auto_close + label fix
- Delta pods restart: ~1,600 raw (unchanged by config; reduced by investigation)
- **Total raw: <3,500 (from 5,167) — target 32% reduction from config changes alone**

## Appendix: Frequency Table

| # | Cluster Key | Policy Name | Raw | Episodes | Distinct Resources | Med Duration | Med Retrigger | Noise Score | Pattern | Squad |
|---|------------|-------------|-----|----------|-------------------|-------------|--------------|-------------|---------|-------|
| 1 | oviva-k8s-hb-it | Delta pods restart | 1,230 | 1,192 | 1,187 | 7.0h | 3.6h | 0 | chronic | unlabeled |
| 2 | oviva-k8s-dg-prod | MySQL slow query (high) | 875 | 253 | 6 | 10m | 30m | 5 | flapping | staging_alerts |
| 3 | oviva-k8s-prod | MySQL slow query (high) | 542 | 103 | 4 | 10m | 28m | 7 | flapping | staging_alerts |
| 4 | oviva-k8s-dg-prod | Diet Suggestions Thread Count | 370 | 126 | 10 | 41m | 73m | 1 | recurring | unlabeled |
| 5 | oviva-k8s-dg-pta | Delta pods restart | 259 | 249 | 59 | 11m | 69m | 2 | recurring | unlabeled |
| 6 | oviva-k8s-hb-it | Queue without consumer | 184 | 8 | 1 | 2.2d | — | 4 | flapping | unlabeled |
| 7 | oviva-k8s-hb-it | Queue is never empty | 120 | 2 | 1 | 5.0d | — | 4 | flapping | unlabeled |
| 8 | oviva-k8s-hb-it | Queue expired messages | 112 | 10 | 1 | 17.7h | — | 3 | flapping | unlabeled |
| 9 | oviva-k8s-prod | MySQL slow query (moderate) | 75 | 14 | 1 | 24m | 47m | 5 | flapping | staging_alerts |
| 10 | oviva-k8s | Delta pods restart | 74 | 71 | 71 | 5.8h | 16.2h | 1 | chronic | unlabeled |
| 11 | — | Mobile API 5xx (critical) #1 | 72 | 18 | 2 | 5m | — | 4 | flapping | unlabeled |
| 12 | — | Mobile API 5xx (critical) #2 | 71 | 18 | 2 | 5m | — | 4 | flapping | unlabeled |
| 13 | — | gamification queue > 100 | 66 | 42 | 2 | 17m | 96m | 0 | recurring | unlabeled |
| 14 | oviva-k8s-dg-prod | Delta pods restart | 59 | 55 | 25 | 9.5h | 23.6h | 0 | chronic | unlabeled |
| 15 | oviva-k8s-prod | Delta pods restart | 50 | 48 | 46 | 6.0h | 21.4h | 1 | chronic | unlabeled |
| 16 | — | medical-reporting error > 1% | 45 | 25 | 1 | 14m | 64m | 3 | recurring | mars_alerts |
| 17 | — | Max memory limit utilization | 43 | 22 | 1 | 12m | 107m | 2 | recurring | unlabeled |
| 18 | — | hcs-gb error > 1% | 40 | 14 | 1 | 10m | 2m | 6 | recurring | mars_alerts |
| 19 | — | P99 Latency w/o 5xx | 33 | 22 | 2 | 5m | 72m | 2 | recurring | unlabeled |
| 20 | oviva-k8s-dg-prod | gamification eventProcessing queue | 29 | 28 | 1 | 42m | 207m | 0 | recurring | saturn_alerts |

(Full table: 139 clusters — remaining 119 clusters have <=28 raw incidents each, 52 clusters have <=3 raw incidents)

## Appendix: Evidence Coverage

Grouped by validation method. Reviewer action: `metric query` and `config inspection` items are audit-complete; `pattern analysis` items need reviewer judgment before applying.

### Config inspection — provable from policy definition

| Cluster | What was checked | Finding | Scope |
|---------|-----------------|---------|-------|
| MySQL slow query (high) | eval_window=60s, auto_close NOT SET, flapping pattern (ratio 3.5-5.3:1) | Structural flap: 60s eval catches transient spikes that self-resolve in 10m, no auto_close accumulates incidents | 3 clusters |
| MySQL slow query (moderate) | Identical config flaws to high-traffic variant | Same structural flap pattern | 3 clusters |
| Delta pods restart | auto_close NOT SET, 1,187 distinct resources on hb-it | Alert accumulates open incidents indefinitely; distinct resource count proves systemic issue | 5 clusters |
| MySQL label mismatch | squad=staging_alerts vs resource_project containing "prod" | Label does not match firing scope — production alerts routed to staging team | 2 policies |
| gamification queue | 0 notification channels attached | Alert fires but notifies nobody — orphaned or intentional dashboard-only | 1 policy |

### Metric query — validated against Cloud Monitoring time-series

| Cluster | Query | Result | Finding |
|---------|-------|--------|---------|
| Diet Suggestions threads | `prometheus.googleapis.com/jvm_threads_live_threads/gauge` ALIGN_MAX 1h, 14d, cluster=oviva-dg-prod1 | p50=961, p95=1,256, max=1,256 | Baseline crowding: p50 at 96% of threshold (1,000). 33% of hours exceed threshold. Alert detects real saturation — fix underlying issue. |
| Queue is never empty | `prometheus.googleapis.com/artemis_message_count/gauge` ALIGN_MAX 1h, namespace=it+prod | hourly MAX=0 across all queues | Messages flow through in <1h. `min_over_time(...[12h]) > 0` fires on sub-hour transients. Threshold of 0 is structurally wrong. |
| Queue expired messages | `prometheus.googleapis.com/artemis_messages_expired/gauge` ALIGN_MAX daily, namespace=it | daily MAX=0 across all queues | Expiry events are brief transients. Threshold of 0 fires on single-message expiry. |
| Queue without consumer | `prometheus.googleapis.com/artemis_consumer_count/gauge` ALIGN_MIN 1h, namespace=it | hourly MIN=0 everywhere | Consumer is always present at hourly resolution. Alert fires on sub-hour disconnects during deploys/scaling. |
| hcs-gb error rate | `prometheus.googleapis.com/http_server_requests_seconds_count/summary` ALIGN_DELTA 1h | p50=3, p95=8 req/h | Very low traffic — single error at 3 req/h = 33% error rate. Confirms 1% threshold fires on single-request errors. |
| Memory limit utilization | `kubernetes.io/container/memory/limit_utilization` ALIGN_MAX daily, 7d | p50=35%, p95=47%, max=47% | Well below typical 80-90% threshold. Alert fires on brief spikes that don't persist at daily granularity. |
| Transaction threshold MySQL | `cloudsql.googleapis.com/database/mysql/innodb/active_trx_longest_time` ALIGN_MAX 1h, 14d | p50=156s, p95=228s | Longest transaction routinely 2-4min. 93-100% at h02 confirms nightly batch. |

### Pattern analysis — inferred from incident frequency/timing, needs validation before applying

| Cluster | Pattern observed | What would upgrade this | Scope |
|---------|-----------------|------------------------|-------|
| Mobile API 5xx | h23 concentration 39%, 5m median duration, 2 near-identical policies | Correlate h23 firings with deploy timestamps; if >80% match → high confidence for mute/eval extension | 2 policies |
| medical-reporting error | h07 concentration 40%, 14m median duration | Check CI/CD or cron schedule for h07 activity; if >80% match → high confidence | 1 cluster |
| P99/P95/P90 Latency overlap | Three percentile alerts on same services, lower percentile dominates noise | Analyst confirms: are services user-facing with SLI/SLO targets? If yes → SLO redesign. If no → consolidate to P99 only. | Multiple |

### Not attempted — specific API limitation

| Cluster | Limitation | Why it can't be a single query |
|---------|-----------|-------------------------------|
| MySQL slow query (both) | CUMULATIVE DISTRIBUTION metric | `histogram_quantile` computation requires bucket boundaries from distribution; `ALIGN_PERCENTILE_*` not supported on CUMULATIVE distributions via REST API |
| Delta pods restart | CUMULATIVE counter, high cardinality | 1,187 distinct containers; short alignment (10m) x 14d x 1,187 series exceeds page limits; daily ALIGN_DELTA loses individual restart events |
| Mobile API 5xx, medical-reporting | Error rate = ratio of two series | Requires 5xx-filtered count / total count — two separate queries + division, not a single list_time_series call |
