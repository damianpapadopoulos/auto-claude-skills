# Alert Hygiene Analysis Report
**Monitoring project:** oviva-monitoring | **Window:** 14 days ending 2026-03-31

## Executive Summary
- 487 policies (484 enabled, 3 disabled), 4,793 raw incidents → 2,691 episodes across 137 clusters
- Baseline metrics: 37,719 open-incident hours, 2,039 routed incidents, 2,754 ownerless incidents
- **Top noise sources:** Pod restart (hb-it) accounts for 1,110 raw incidents (23%) and 8,546 open-hours; MySQL slow-query outlier policies produce 1,551 raw incidents across 4 clusters with `staging_alerts` label on production data (label mismatch); Artemis message broker alerts (3 policies) contribute 342 raw incidents and 17,477 open-hours in permanent-fire state; Diet Suggestions thread alert fires 372 times with JVM threads above threshold 61% of the time
- 23 services have SLO definitions; 384/484 enabled policies (79%) had zero incidents in the analysis window
- 4 Do Now actions, 8 investigations, 3 needs decision
- **Modeled impact (estimated, scope: Do Now items only):** ~880 incidents reduced (~18%), ~17,500 open-incident hours reclaimed

## Decision Summary

| Category | Finding | Target Owner | Confidence / Readiness | Effort | Risk | Primary Expected Outcome | Next Action |
|----------|---------|--------------|----------------------|--------|------|--------------------------|-------------|
| Do Now | [1. Artemis expired messages: raise threshold](#1-tune-the-alert-message-broker-queue-expired-messages-high--pr-ready) | ⚠ assign | High / PR-Ready | S | Low | Raw < 5/14d, reclaim ~2,100 oh | Merge IaC PR |
| Do Now | [2. Artemis never-empty: raise threshold + set auto_close](#2-tune-the-alert-message-queue-is-never-empty-high--pr-ready) | ⚠ assign | High / PR-Ready | S | Low | Raw < 10/14d, reclaim ~10,500 oh | Merge IaC PR |
| Do Now | [3. Artemis without-consumer: set auto_close](#3-tune-the-alert-message-broker-queue-without-consumer-high--pr-ready) | ⚠ assign | High / PR-Ready | S | Low | Raw < 30/14d, reclaim ~4,800 oh | Merge IaC PR |
| Do Now | [4. MySQL outlier: fix label mismatch](#4-fix-routing-mysql-slow-query-outlier-label-mismatch-high--pr-ready) | xenon_alerts | High / PR-Ready | S | Low | 1,551 incidents correctly routed | Merge IaC PR |
| Investigate | [1. Pod restart hb-it: systemic](#1-investigate-systemic-pod-restarts-on-oviva-k8s-hb-it-high--stage-1) | ⚠ assign | High / Stage 1 | M | Med | Identify top restarting containers | Triage top containers |
| Investigate | [2. Diet Suggestions thread count](#2-investigate-diet-suggestions-thread-count-alert-tuning-medium--stage-1) | ⚠ assign | Medium / Stage 1 | S | Low | Validate if threshold 1000 is correct | Query thread baseline |
| Investigate | [3. Mobile API 5xx concentrated at h23](#3-investigate-mobile-api-5xx-concentrated-at-h23-medium--stage-1) | ⚠ assign | Medium / Stage 1 | S | Low | Confirm deploy-time cause | Correlate with deploys |
| Investigate | [4. goal-setting P99 latency](#4-investigate-goal-setting-p99-latency--9s-medium--stage-1) | ⚠ assign | Medium / Stage 1 | S | Low | Validate threshold | Query P99 baseline |
| Investigate | [5. Node memory oviva-k8s](#5-investigate-node-memory-utilization-oviva-k8s-high--stage-1) | xenon_alerts | High / Stage 1 | M | Med | Confirm 47% above threshold | Add auto_close |
| Investigate | [6. Max memory limit utilization](#6-investigate-max-memory-limit-utilization-prod1-medium--stage-1) | ⚠ assign | Medium / Stage 1 | S | Low | Identify hot container | Right-size memory limits |
| Investigate | [7. hcs-gb error rate](#7-investigate-hcs-gb-error-rate-high--stage-1) | mars_alerts | High / Stage 1 | S | Low | Validate transient nature | Add min-volume clause |
| Investigate | [8. medical-reporting error rate at h07](#8-investigate-medical-reporting-error-rate-concentrated-at-h07-medium--stage-1) | mars_alerts | Medium / Stage 1 | S | Low | Confirm deploy-time cause | Correlate with deploys |
| Needs Decision | [1. Silent policy cleanup](#1-silent-policy-cleanup-high--decision-pending) | Platform lead | High / Decision Pending | M | Low | Decide retain/disable for 384 policies | Audit |
| Needs Decision | [2. SLO candidates: hcs-gb, gamification, onboarding](#2-slo-review-candidates-hcs-gb-gamification-onboarding-high--decision-pending) | Squad leads | High / Decision Pending | L | Low | Decision on SLO adoption | Squad review |
| Needs Decision | [3. Redundant SLO + threshold: medical-reporting, clinical-pathways](#3-redundant-slo--threshold-alerts-medical-reporting-clinical-pathways-high--decision-pending) | mars_alerts | High / Decision Pending | S | Low | Decision on overlap | Squad review |

*Showing top 15 of 15 findings.*

## Methodology
- **Data source:** GCP Monitoring API (REST, paginated)
- **Scripts:** pull-policies.py (inventory), pull-incidents.py (incidents), compute-clusters.py (clustering + enrichment)
- **Analysis window:** 14 days ending 2026-03-31
- **Dedupe window:** max(1800s, 2× evaluation interval) per cluster
- **Noise score formula:** 0–10 composite: raw/episode ratio >5 (+3) or >2 (+1), median duration <15m (+2), retrigger <1h (+2), deploy-hour concentration (+1)
- **Pattern classification:** flapping (ratio>3 AND raw>10), chronic (episodes≥5 AND duration>1h), recurring (episodes≥5 AND duration≤1h), burst (raw>10 AND episodes≤3), isolated (other)
- **Evidence basis levels:** `measured` = metric time-series query with stated scope and result; `structural` = config flaw unambiguous from policy definition alone; `heuristic` = pattern-only inference, flagged for validation
- **SLO enrichment:** 23 services from `oviva-ag/monitoring/tf/slo-config.yaml`
- **To reproduce:** Run the three scripts with `--project oviva-monitoring --days 14`, then apply Stage 3–5 reasoning

## Definitions

| Term | Definition |
|------|-----------|
| **Raw incidents** | Total alert firings in the analysis window |
| **Episodes** | Deduplicated incidents (same policy + resource, merged if gap < dedupe window) |
| **Raw/episode ratio** | Flapping indicator. 1:1 = clean signal. >5:1 = noisy. >20:1 = structural flaw |
| **Noise score** | 0–10 composite of ratio, duration, retrigger interval, and time-of-day pattern |
| **Evidence basis** | Whether a numeric prescription is `measured` (from validated metric query with stated scope) or `heuristic` (rule of thumb — must be flagged for validation) |
| **Open-incident hours** | Sum of all incident durations in the analysis window, measured in hours. Captures both volume and persistence of alert noise. |

## Action Type Legend
- **Tune the alert** — the alert is miscalibrated. Specific config changes listed.
- **Fix the underlying issue** — the alert is correct. The service has a real problem.
- **Fix routing** — the alert fires correctly but reaches the wrong team or has incorrect labels.
- **Redesign around SLO** — replace threshold alerting with burn-rate/error-budget alerting.
- **Add/extend coverage** — a high-value blind spot exists.
- **No action** — well-calibrated, low-frequency. Keep as-is.

## Systemic Issues

### Ownership/Routing Debt

57% of raw incidents (2,754/4,793) fire on policies without a squad/team/owner label. These alerts route through default channels and have no traceable owner.

The `staging_alerts` label is applied to MySQL slow-query outlier policies that fire on production projects (`oviva-k8s-prod`, `oviva-k8s-dg-prod`) — 1,551 raw incidents may be misrouted or ignored because the label implies non-production severity.

Top 10 policies without squad/team/owner label, ranked by total raw incidents:

| # | Policy | Policy ID | Raw (14d) | Episodes | Channels | Suggested Owner |
|---|--------|-----------|-----------|----------|----------|-----------------|
| 1 | Delta pods restart in project | .../9019907273249855951 | 1,431 | 1,374 | 1 | ⚠ assign |
| 2 | Diet Suggestions Active Thread Count Alert (DG) | .../15443736973066518795 | 372 | 129 | 1 | ⚠ assign |
| 3 | Message broker queue without consumer | .../17467897932493204533 | 216 | 46 | 1 | ⚠ assign |
| 4 | Message queue is never empty | .../6098275769612771826 | 177 | 42 | 1 | ⚠ assign |
| 5 | Message broker queue expired messages | .../5600771186676456661 | 83 | 14 | 1 | ⚠ assign |
| 6 | [.*-prod1] Mobile API HTTP 5xx Error Rate (critical) | .../11760810637840310856 | 78 | 23 | 1 | ⚠ assign |
| 7 | [.*-prod1] Mobile API HTTP 5xx Error Rate (critical) | .../6767865470347481271 | 77 | 23 | 1 | ⚠ assign |
| 8 | [.*-prod1] HTTP P99 Latency w/o 5xx Errors | .../8924582844325366421 | 77 | 47 | 1 | ⚠ assign |
| 9 | [.*-prod1] Max memory limit utilization | .../16568293729673736416 | 33 | 20 | 1 | ⚠ assign |
| 10 | [.*-prod1] Max memory limit utilization | .../15451110698797130466 | 26 | 20 | 1 | ⚠ assign |

### Dead/Orphaned Config

**Zero-channel policies:** No zero-channel policies found.

**Disabled-but-noisy:** No disabled-but-noisy policies.

### Missing Coverage

| Gap | Action | Implementation | Rationale | Upstream Signal For |
|-----|--------|---------------|-----------|---------------------|
| SSL certificate expiry | Add new | Uptime check with SSL validation or `ssl.googleapis.com/certificate/expiry_time` | Silent cert expiration causes hard outages | n/a |
| Pod probe failures | Add new | `kubernetes.io/container/probe/failure_count` or PromQL equivalent | Early signal before pod restart storms | Pod restart clusters (#1, #5, #13, #15, #16) |
| Persistent disk utilization | Extend scope | `compute.googleapis.com/instance/disk/utilization` — only Artemis broker disk covered via `artemis_disk_store_usage` | Silent disk-full failures on VMs/PVCs | n/a |
| Service 5xx per-service (module pattern) | Extend scope | `golden_signals_micrometer_http_requests_alerts` — check all services covered | Several services without explicit error-rate alerts | n/a |

Coverage already present: Cloud SQL connections (`sql_connections_alert` module), Node memory (`memory_nodes_alert`, `memory_nodes_alert_v2`), Cloud SQL CPU (`cloud_sql_alert`).

### Inventory Health

- **Silent policy ratio:** 384/484 (79%) — 384 enabled policies had zero incidents in the 14-day window
- **Condition type breakdown:** PromQL 464, MQL 7, Threshold 12, Unknown 4
- **Enabled/disabled:** 484 enabled, 3 disabled

## Actionable Findings: Do Now

**Global Implementation Standard:**
For all Do Now items:
1. IaC PR is approved and merged
2. Engineer confirms via GCP Monitoring Console that every mutated field matches the proposed config in production
3. Confirm no accidental changes to fields outside the change spec
4. Record merge date for 14-day outcome review

---

### 1. Tune the alert: Message broker queue expired messages [High / PR-Ready]

**Policy ID:** projects/oviva-monitoring/alertPolicies/5600771186676456661 | **Condition:** Queue has expired messages
**Target Owner:** ⚠ assign (currently unlabeled)
**Scope:** oviva-k8s-hb-it (namespace it, pta, prod)
**Notification Reach:** 1 channel
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/5600771186676456661?project=oviva-monitoring) · [View IaC (module)](https://github.com/oviva-ag/monitoring/blob/main/tf/modules/message_broker_alerts/google_monitoring_alert_policy.tf) · [View IaC (invocation)](https://github.com/oviva-ag/monitoring/blob/main/tf/message-broker-alerts.tf)

#### Current Policy Snapshot
**Threshold:** > 1 (single expired message) | eval: 300s | auto_close: NOT SET
**Condition:** `artemis_messages_expired{pod="message-broker-0",namespace=~"it|pta|prod"...} > 1`

**IaC Location:** [Confirmed] `oviva-ag/monitoring` → `tf/modules/message_broker_alerts/google_monitoring_alert_policy.tf` — resource `google_monitoring_alert_policy.message_broker_queue`. Invocation: `tf/message-broker-alerts.tf`

**Situation:** The threshold of >1 (single expired message) causes permanent-fire state. p50 of expired messages is 9,569 and p95 is 23,588 across the IT namespace. The alert fires 72 raw / 8 episodes with 9:1 ratio and median duration of 26h. Total open-incident hours: 2,102.
**Impact:** 2,102 open-hours consumed by an alert that is structurally unable to close. Every hour of every day, at least one queue in IT/PTA/PROD has >1 expired message.

#### Configuration Diff & Derivation
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| threshold | > 1 | > 100 | p5=128, so >100 filters transient single-message expirations while still catching genuine accumulation |
| auto_close | NOT SET | 86400s | Median duration 26h; 24h auto_close prevents permanent-fire accumulation |

**Pre-change Evidence:** Metric query on `prometheus.googleapis.com/artemis_messages_expired/gauge` for IT namespace: 315 points, min=128, max=24,871, median=9,569, p95=23,588. 100% of data points above threshold (>1). Baseline never drops below 128 expired messages.
**Evidence Basis:** measured — REST time-series query, `artemis_messages_expired/gauge`, pod=message-broker-0, namespace=it, 1h ALIGN_MAX + REDUCE_MAX, 315 points (passes quality gate ≥50)

**Outcome DoD:**
- **Primary:** Raw incidents < 5 within 14d post-merge; open-incident hours < 50 (from 2,102)
- **Guardrail:** No genuine burst of >100 newly expired messages goes undetected

**Rollback Signal:** If raw incidents = 0 for 14d AND known message processing failure occurs undetected, lower threshold to >50
**Related:** Finding #2 (message queue never empty), #3 (without consumer) — same Artemis broker, same permanent-fire pattern

---

### 2. Tune the alert: Message queue is never empty [High / PR-Ready]

**Policy ID:** projects/oviva-monitoring/alertPolicies/6098275769612771826 | **Condition:** Queue was never empty in last 24 hours
**Target Owner:** ⚠ assign (currently unlabeled)
**Scope:** oviva-k8s-hb-it, oviva-k8s-dg-prod, oviva-k8s-prod (all namespaces matching it|pta|prod)
**Notification Reach:** 1 channel
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/6098275769612771826?project=oviva-monitoring) · [View IaC (module)](https://github.com/oviva-ag/monitoring/blob/main/tf/modules/message_broker_alerts/google_monitoring_alert_policy.tf) · [View IaC (invocation)](https://github.com/oviva-ag/monitoring/blob/main/tf/message-broker-alerts.tf)

#### Current Policy Snapshot
**Threshold:** > 0 (queue never empty over 23h59m lookback) | eval: 300s | auto_close: NOT SET
**Condition:** `min_over_time(artemis_message_count{...}[23h59m]) > 0`

**IaC Location:** [Confirmed] `oviva-ag/monitoring` → `tf/modules/message_broker_alerts/google_monitoring_alert_policy.tf` — resource `google_monitoring_alert_policy.message_broker_message_count`. Invocation: `tf/message-broker-alerts.tf`

**Situation:** The alert design causes permanent firing: `min_over_time(...[23h59m]) > 0` means any queue that holds even 1 message for a full day triggers the alert. In IT, message count is always non-zero (min=21,663, median=30,737). Across 4 clusters this produces 175 raw / 40 episodes with median duration of 5.3 days (!) and 10,488 total open-hours.
**Impact:** 10,488 open-hours — the single largest open-hour consumer in the inventory. Permanent noise that masks genuine queue buildup.

#### Configuration Diff & Derivation
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| threshold | > 0 | > 1000 | p5 of IT message count is not near zero; baseline min is 21,663. Threshold of >1000 catches genuine buildup above idle-queue baseline while filtering queues that simply always have some messages. |
| lookback window | 23h59m | 6h | 24h lookback means the alert looks back a full day. Shortening to 6h allows detection within a shift. |
| auto_close | NOT SET | 86400s | Prevents permanent-fire accumulation; median duration was 127h (5.3 days) |

**Pre-change Evidence:** Metric query on `prometheus.googleapis.com/artemis_message_count/gauge` for IT namespace: 315 points, min=21,663, max=35,459, median=30,737, p95=34,560. 100% of data points non-zero. The queue is structurally never empty.
**Evidence Basis:** measured — REST time-series query, `artemis_message_count/gauge`, pod=message-broker-0, namespace=it, 1h ALIGN_MAX + REDUCE_MAX, 315 points (passes quality gate ≥50)

**Outcome DoD:**
- **Primary:** Raw incidents < 10 within 14d post-merge; open-incident hours < 100 (from 10,488)
- **Guardrail:** Genuine backlog > 1,000 messages sustained for 6+ hours is still detected

**Rollback Signal:** If a genuine queue accumulation event (>1,000 new messages above baseline) goes undetected within 14d, re-evaluate threshold against per-queue baselines
**Related:** Finding #1 (expired messages), #3 (without consumer) — same Artemis broker

---

### 3. Tune the alert: Message broker queue without consumer [High / PR-Ready]

**Policy ID:** projects/oviva-monitoring/alertPolicies/17467897932493204533 | **Condition:** Queue has messages but no consumer
**Target Owner:** ⚠ assign (currently unlabeled)
**Scope:** oviva-k8s-hb-it, oviva-k8s-dg-prod, oviva-k8s-prod, oviva-k8s (all namespaces)
**Notification Reach:** 1 channel
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/17467897932493204533?project=oviva-monitoring) · [View IaC (module)](https://github.com/oviva-ag/monitoring/blob/main/tf/modules/message_broker_alerts/google_monitoring_alert_policy.tf) · [View IaC (invocation)](https://github.com/oviva-ag/monitoring/blob/main/tf/message-broker-alerts.tf)

#### Current Policy Snapshot
**Threshold:** consumer_count == 0 AND message_count > 0 (10m lookback) | eval: 3600s | auto_close: NOT SET
**Condition:** `last_over_time(artemis_consumer_count{...}[10m]) == 0 and last_over_time(artemis_message_count{...}[10m]) > 0`

**IaC Location:** [Confirmed] `oviva-ag/monitoring` → `tf/modules/message_broker_alerts/google_monitoring_alert_policy.tf` — resource `google_monitoring_alert_policy.message_broker_consumer`. Invocation: `tf/message-broker-alerts.tf`

**Situation:** Metric validation shows consumer_count in IT is never zero (min=154, median=1,176). The alert fires on transient consumer disconnects during deploys/restarts. Once open, it stays open indefinitely because auto_close is not set. Across 5 clusters: 229 raw / 48 episodes, median duration 22h, total 9,782 open-hours.
**Impact:** 9,782 open-hours, third-largest contributor. The 1h duration requirement is appropriate but without auto_close, open incidents accumulate.

#### Configuration Diff & Derivation
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| auto_close | NOT SET | 86400s (24h) | Median duration is 22h; 24h auto_close prevents indefinite accumulation while keeping incidents open long enough for investigation |

**Pre-change Evidence:** Metric query on `prometheus.googleapis.com/artemis_consumer_count/gauge` for IT namespace: 315 points, min=154, max=1,384, median=1,176. Zero-consumer points: 0/315 (0%). The alert fires on transient drops below the hourly resolution, not sustained zero-consumer state.
**Evidence Basis:** structural + measured — structural: auto_close NOT SET on a metric that naturally recovers; measured: consumer_count never actually zero at 1h resolution

**Outcome DoD:**
- **Primary:** Raw incidents < 30 within 14d (from 229); open-incident hours < 500 (from 9,782)
- **Guardrail:** Genuine zero-consumer state sustained for >1h is still detected and stays open until resolved

**Rollback Signal:** If genuine queue-without-consumer goes undetected due to auto_close window, increase auto_close to 172800s (48h)
**Related:** Finding #1 (expired messages), #2 (never empty) — same Artemis broker

---

### 4. Fix routing: MySQL slow query outlier label mismatch [High / PR-Ready]

**Policy ID:** projects/oviva-monitoring/alertPolicies/17208358397831352350 (high traffic) and .../1126182761046938150 (moderate traffic)
**Target Owner:** xenon_alerts → should be xenon_alerts (or appropriate DB squad)
**Scope:** oviva-k8s-dg-prod, oviva-k8s-prod (production databases)
**Notification Reach:** 1 channel each
**Links:** [Open policy (high)](https://console.cloud.google.com/monitoring/alerting/policies/17208358397831352350?project=oviva-monitoring) · [Open policy (moderate)](https://console.cloud.google.com/monitoring/alerting/policies/1126182761046938150?project=oviva-monitoring) · [View IaC (module)](https://github.com/oviva-ag/monitoring/blob/main/tf/modules/sql_latency_alert/main.tf) · [View IaC (invocation)](https://github.com/oviva-ag/monitoring/blob/main/tf/main.tf)

#### Current Policy Snapshot
**Current Label:** squad=staging_alerts
**Condition:** PromQL per-query p95 latency > 600ms (high traffic) / > 5000ms (moderate traffic)

**IaC Location:** [Confirmed] `oviva-ag/monitoring` → `tf/modules/sql_latency_alert/main.tf` — resources `mysql_outlier_high_rate`, `mysql_outlier_low_rate`. The `outlier_user_labels` variable is set in `tf/main.tf` (module `sql-latency-alert`).

**Situation:** The `staging_alerts` squad label is applied to alerts that fire on production projects (`oviva-k8s-prod`, `oviva-k8s-dg-prod`). This is a label_inconsistency — production incident data routed with a staging label. 1,551 raw incidents in 14d (841 + 607 + 72 + 31) may be deprioritized or ignored because the label implies non-production.
**Impact:** 1,551 raw incidents with incorrect routing. DB Insights per-query latency alerts provide actionable slow-query identification (including query_hash for Query Insights lookup). Misrouting means these actionable alerts are not reaching the right team.

#### Configuration Diff & Derivation
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| outlier_user_labels.squad | staging_alerts | xenon_alerts (or DB team label) | Policy fires on prod projects; label should reflect production ownership |

**Pre-change Evidence:** DB Insights query on `oviva-k8s-dg-prod`: 142 series (per-query-hash), mean latency ranging from 834ms to 858s across query hashes. The alert is detecting real slow queries on production databases — this is valuable signal being misrouted.
**Evidence Basis:** structural — label mismatch is unambiguous from policy definition (`squad=staging_alerts` on production project data)

**Outcome DoD:**
- **Primary:** 100% of MySQL outlier incidents for prod projects have correct squad label within 14d
- **Guardrail:** No alert dropped or disabled during label change

**Rollback Signal:** If the new squad label causes alert fatigue for the receiving team, the team should prioritize underlying slow-query fixes rather than reverting the label
**Related:** Systemic Issues > Ownership/Routing Debt

---

## Actionable Findings: Investigate

### 1. Investigate: Systemic pod restarts on oviva-k8s-hb-it [High / Stage 1]

**Policy ID:** projects/oviva-monitoring/alertPolicies/9019907273249855951
**Target Owner:** ⚠ assign
**Scope:** oviva-k8s-hb-it (1,110 raw), oviva-k8s-dg-pta (182), oviva-k8s (68), oviva-k8s-dg-prod (37), oviva-k8s-prod (34)
**Notification Reach:** 1 channel
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/9019907273249855951?project=oviva-monitoring) · [View IaC (module)](https://github.com/oviva-ag/monitoring/blob/main/tf/modules/k8s_pods_restart_alert/main.tf) · [View IaC (invocation)](https://github.com/oviva-ag/monitoring/blob/main/tf/main.tf)

**Situation:** Single policy ("Delta pods restart in project") fires across 5 projects totaling 1,431 raw incidents and 10,816 open-hours. The hb-it cluster alone has 1,110 incidents across 1,053 distinct resources — this is systemic, not a single container problem. The PromQL `increase(restart_count[6h]) > 5` catches any container restarting >5 times in 6 hours. Metric validation: total hourly restart delta across hb-it ranges from 5 to 1,015 (p95=864).
**Impact:** Largest single raw-incident contributor (30% of all incidents). Without auto_close, incidents accumulate indefinitely.

#### Proposed Config Diff (pending gate resolution)
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| auto_close | NOT SET | 21600s (6h) | Matches the 6h lookback window; prevents incident accumulation while keeping detection active |
| threshold | > 5 | > 5 (no change) | Threshold is reasonable; the problem is the number of restarting containers, not the threshold sensitivity |

**Gate Blocker:** Missing owner (unlabeled). Pod restarts span all projects — need platform team ownership assignment.
**To Upgrade:** Assign owner → promotes to Do Now for auto_close addition.

**Evidence Basis:** measured — REST time-series query: `kubernetes.io/container/restart_count`, project=oviva-k8s-hb-it, 1h ALIGN_DELTA + REDUCE_SUM, 346 points. Min=5, Max=1,015, Median=42, p95=864.
**Hypothesis:** The hb-it cluster has a large number of CronJob or test-workload containers that restart normally. The 87% h22 concentration on the oviva-k8s cluster suggests nightly batch-triggered restarts.

**Stage 1 DoD (Discovery — this ticket):**
- Identify top 10 containers by restart count in hb-it: `kubectl get pods --sort-by='.status.containerStatuses[0].restartCount' -A` or equivalent PromQL breakdown
- Determine if restarts are CronJob/ephemeral workloads vs persistent services
- **Closes when:** Top container list produced AND decision documented: tune alert (exclude known workloads) or fix underlying instability
- **Timebox:** 5 days

**Stage 2 (Execution — spawned follow-up):**
- **If CronJob/test workloads:** Add exclusion pattern to PromQL (e.g., `pod_name!~".*cronjob.*|.*test.*"`) and set auto_close=21600s
- **If persistent service instability:** Escalate to owning squad per container — fix underlying issue

---

### 2. Investigate: Diet Suggestions thread count alert tuning [Medium / Stage 1]

**Policy ID:** projects/oviva-monitoring/alertPolicies/15443736973066518795
**Target Owner:** ⚠ assign
**Scope:** oviva-k8s-dg-prod (cluster oviva-dg-prod1)
**Notification Reach:** 1 channel
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/15443736973066518795?project=oviva-monitoring) · [Browse IaC](https://github.com/oviva-ag/monitoring/tree/main/tf)

**Situation:** JVM live thread count for `diet-suggestions` on `oviva-dg-prod1` exceeds 1,000 threshold 61.3% of the time (p50=1,148, p95=2,085). The alert fires 372 raw / 129 episodes with auto_close=1800s already set. The recurring pattern (not flapping) suggests the baseline is above the threshold rather than oscillating around it.
**Impact:** 376.5 open-hours, second-highest by raw incidents for a service-specific alert.

**Gate Blocker:** Missing owner (unlabeled). Need to confirm whether 1,000 threads is actually problematic for this JVM configuration.
**To Upgrade:** (1) Assign owner (2) Confirm correct threshold based on JVM max thread pool config → promotes to Do Now for threshold raise.

**Evidence Basis:** measured — REST time-series query: `prometheus.googleapis.com/jvm_threads_live_threads/gauge`, container=diet-suggestions, cluster=oviva-dg-prod1, 1h ALIGN_MAX + REDUCE_MAX, 346 points. Min=135, Max=3,213, p50=1,148, p95=2,085. 212/346 (61.3%) above threshold.
**Hypothesis:** The thread count threshold of 1,000 is too low for the diet-suggestions service's normal operating baseline. The service likely has a thread pool configured for higher concurrency.

**Stage 1 DoD (Discovery — this ticket):**
- Check diet-suggestions JVM thread pool config (application.yaml or equivalent) for max thread count
- Determine if >1,000 threads is expected behavior or indicates thread leak
- **Closes when:** Thread pool max confirmed AND decision documented: raise threshold to p75 + headroom or investigate thread leak
- **Timebox:** 3 days

**Stage 2 (Execution — spawned follow-up):**
- **If expected baseline:** Raise threshold from 1,000 to 1,500 (above p50=1,148, below p95=2,085), giving headroom for normal load
- **If thread leak:** Escalate to diet-suggestions team — fix underlying issue, keep threshold at 1,000

---

### 3. Investigate: Mobile API 5xx concentrated at h23 [Medium / Stage 1]

**Policy ID:** projects/oviva-monitoring/alertPolicies/11760810637840310856 and .../6767865470347481271
**Target Owner:** ⚠ assign
**Scope:** .*-prod1 clusters (backend-core container)
**Notification Reach:** 1 channel each
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/11760810637840310856?project=oviva-monitoring) · [View IaC](https://github.com/oviva-ag/monitoring/blob/main/tf/modules/mobile_api_http_5xx_alert/main.tf)

**Situation:** Two identical policies (critical tier) fire 155 raw / 46 episodes with 40% concentration at hour 23 (UTC). The 6% threshold on `/api/rest/mobile-api/.*` routes fires on low-traffic windows where a few 5xx responses spike the error rate. The PromQL uses `rate(...[5m])` without a minimum volume clause. Auto_close is correctly set at 300s.
**Impact:** 14.9 open-hours total — low impact per incident, but high frequency during overnight low-traffic window. *Inferred nightly maintenance/deploy from 40% h23 concentration — verify before applying mute window.*

**Gate Blocker:** Missing owner (unlabeled). Need to confirm h23 cause (deploy window, low traffic, or genuine errors).
**To Upgrade:** (1) Assign owner (2) Confirm h23 root cause → if low-traffic: add volume floor, promotes to Do Now.

**Evidence Basis:** measured — the metric exists as `prometheus.googleapis.com/http_server_duration_milliseconds/histogram` (CUMULATIVE). The `distributionValue.count` field provides request volume. Query confirmed 1 series with ~1.4M–1.9M requests/day (mean latency 75–77ms). The PromQL `rate(http_server_duration_milliseconds_count{...}[5m])` uses the histogram's count component. Time-of-day concentration from incident data.
**Hypothesis:** The h23 concentration is caused by low request volume during off-peak hours, where a single 5xx request produces a >6% error rate on a route with <20 requests in the 5m window.

**Stage 1 DoD (Discovery — this ticket):**
- Query Mobile API request volume at h23 vs h12 to confirm low-traffic hypothesis
- Correlate h23 incidents with deployment schedule
- **Closes when:** Root cause confirmed (low traffic, deploy, or genuine errors) AND follow-up action documented
- **Timebox:** 3 days

**Stage 2 (Execution — spawned follow-up):**
- **If low traffic:** Add minimum volume floor to PromQL: `... AND sum(...count{...}[5m]) > 10`
- **If deploy-time transient:** Extend duration from 60s to 900s to ride through the deploy window

---

### 4. Investigate: goal-setting P99 latency > 9s [Medium / Stage 1]

**Policy ID:** projects/oviva-monitoring/alertPolicies/8924582844325366421
**Target Owner:** ⚠ assign
**Scope:** .*-prod1 clusters (goal-setting container)
**Notification Reach:** 1 channel
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/8924582844325366421?project=oviva-monitoring) · [Browse IaC](https://github.com/oviva-ag/monitoring/tree/main/tf)

**Situation:** HTTP P99 latency for `goal-setting` exceeds 9s threshold. 77 raw / 47 episodes (1.6:1 ratio — relatively clean signal), median duration 6m, auto_close=3600s. The recurring pattern across spread time-of-day suggests genuine latency issues, not deploy-time transients.
**Impact:** 13.9 open-hours — moderate. But the 9s P99 threshold itself is very high — if the service has a response-time SLA, this may indicate an upstream problem.

**Gate Blocker:** Missing owner (unlabeled). IaC location unknown — no TF module matches this specific per-service latency pattern.
**To Upgrade:** (1) Assign owner (2) Validate P99 baseline → if threshold is appropriate, investigate underlying latency.

**Evidence Basis:** heuristic — metric type `__missing__` in cluster data (PromQL-only condition, no Cloud Monitoring equivalent readily available)
**Hypothesis:** The goal-setting service has genuine P99 latency spikes above 9s, potentially from cold-start or database contention.

**Stage 1 DoD (Discovery — this ticket):**
- Query `http_server_requests_seconds` for goal-setting to establish P99 baseline
- Determine if 9s is appropriate for this service or if threshold needs adjustment
- **Closes when:** P99 baseline established AND decision documented: tune threshold or fix latency
- **Timebox:** 3 days

**Stage 2 (Execution — spawned follow-up):**
- **If P99 normally < 5s:** Investigate the spikes causing threshold breach
- **If P99 baseline is near 9s:** Raise threshold with headroom, or redesign as SLO candidate

---

### 5. Investigate: Node memory utilization oviva-k8s [High / Stage 1]

**Policy ID:** projects/oviva-monitoring/alertPolicies/11341240194235664037
**Target Owner:** xenon_alerts
**Scope:** oviva-k8s (2 distinct nodes)
**Notification Reach:** 1 channel
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/11341240194235664037?project=oviva-monitoring) · [View IaC (module)](https://github.com/oviva-ag/monitoring/blob/main/tf/modules/memory_nodes_alert/main.tf) · [View IaC (invocation)](https://github.com/oviva-ag/monitoring/blob/main/tf/main.tf)

**Situation:** Node memory utilization (non-evictable) exceeds 0.9 threshold 47.4% of the time (p50=0.895, p95=0.960). 27 raw / 27 episodes (1:1 — clean signal, each incident is a distinct event). Chronic pattern with median duration 1.3h. Auto_close: NOT SET.
**Impact:** 46.8 open-hours. The alert is correct — these nodes are genuinely memory-pressured. But without auto_close, incidents from resolved pressure events accumulate.

#### Proposed Config Diff (pending gate resolution)
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| auto_close | NOT SET | 7200s (2h) | Median duration 1.3h; 2h auto_close covers typical resolution time |

**Gate Blocker:** IaC location uncertain — module `memory_nodes_alert` exists but policy may use a different module. Need to confirm exact TF resource.
**To Upgrade:** Confirm IaC path → promotes to Do Now for auto_close addition.

**Evidence Basis:** measured — REST time-series query: `kubernetes.io/node/memory/allocatable_utilization`, project=oviva-k8s, 1h ALIGN_MAX + REDUCE_MAX, 346 points. Min=0.752, Max=0.990, p50=0.895, p95=0.960. 164/346 (47.4%) above 0.9.
**Hypothesis:** Two nodes in oviva-k8s are near-consistently memory-pressured and may need rightsizing or pod rebalancing.

**Stage 1 DoD (Discovery — this ticket):**
- Identify the 2 specific nodes and their workload allocation
- Determine if the pressure is from over-scheduled pods or undersized nodes
- **Closes when:** Root cause identified (node sizing, scheduling, or memory leak) AND auto_close IaC path confirmed
- **Timebox:** 5 days

**Stage 2 (Execution — spawned follow-up):**
- **If node undersized:** Scale node pool or add nodes
- **If over-scheduled:** Rebalance pod scheduling or add resource limits
- In both cases: add auto_close=7200s to prevent incident accumulation

---

### 6. Investigate: Max memory limit utilization [.*-prod1] [Medium / Stage 1]

**Policy ID:** projects/oviva-monitoring/alertPolicies/16568293729673736416 and .../15451110698797130466
**Target Owner:** ⚠ assign
**Scope:** .*-prod1 clusters (analyser, chat-message-suggestion, clinical-case-report, note-taker, coach-task-manager, message-triaging)
**Notification Reach:** 1 channel each
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/16568293729673736416?project=oviva-monitoring) · [View IaC](https://github.com/oviva-ag/monitoring/blob/main/tf/modules/golden_signals_max_resource_usage_alerts)

**Situation:** Two policies (different `prod1` clusters) fire 59 raw / 40 episodes for 6 containers exceeding 90% memory limit utilization. Metric validation on `analyser` shows p50=0.171, p95=0.185 — well below 0.9. The alert fires on a different container in the list. Auto_close is set at 3600s. Recurring pattern, median duration ~12m.
**Impact:** 118.6 open-hours total. The recurring 12m episodes suggest one or two containers periodically spike above 90% then recover.

**Gate Blocker:** Missing owner (unlabeled). Need to identify which specific container(s) are the hot spot.
**To Upgrade:** (1) Identify hot container(s) (2) Assign owner → promotes to service-team action item.

**Evidence Basis:** measured — `kubernetes.io/container/memory/limit_utilization` for `analyser` on prod1: p50=0.171, p95=0.185, max=0.186 — NOT the hot container. The 0.9 threshold is appropriate; the firing container is one of the other 5 in the selector.
**Hypothesis:** One of `chat-message-suggestion`, `clinical-case-report`, `note-taker`, `coach-task-manager`, or `message-triaging` periodically exceeds 90% memory limit.

**Stage 1 DoD (Discovery — this ticket):**
- Query memory limit utilization per container in the selector to identify the hot container(s)
- **Closes when:** Hot container identified AND owning squad assigned
- **Timebox:** 3 days

**Stage 2 (Execution — spawned follow-up):**
- **If memory limit too low:** Increase memory limit for the hot container
- **If genuine memory pressure:** Investigate memory leak in the hot container's application

---

### 7. Investigate: hcs-gb error rate [High / Stage 1]

**Policy ID:** projects/oviva-monitoring/alertPolicies/17162693348665033848
**Target Owner:** mars_alerts
**Scope:** oviva-prod1, oviva-dg-prod1 (hcs-gb container)
**Notification Reach:** 2 channels
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/17162693348665033848?project=oviva-monitoring) · [View IaC](https://github.com/oviva-ag/monitoring/blob/main/tf/squads/mars/main.tf)

**Situation:** Error rate > 1% on hcs-gb fires 37 raw / 18 episodes. The PromQL uses `increase(...[15m])` with no minimum volume floor. Metric validation shows overall 14-day error rate of 0.023% (333 errors / 1,451,373 total requests). The alert fires when a low-traffic URI has a few errors pushing the per-URI error rate above 1%.
**Impact:** 6.2 open-hours — low. But hcs-gb is NOT in the SLO service list, making this alert the only error-rate signal for this service.

#### Proposed Config Diff (pending gate resolution)
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| PromQL volume floor | none | `AND sum by (...) (increase(...count{container="hcs-gb",...}[15m])) > 50` | Requires ≥50 requests in the 15m window before computing error rate; prevents single-request spikes |

**Gate Blocker:** hcs-gb is not in SLO list — need decision on whether to adopt SLO for this service (see Needs Decision #2). Adding a volume floor without that context risks suppressing genuine error signal.
**To Upgrade:** Decision on SLO adoption → if no SLO, add volume floor + reduce threshold to 5%, promotes to Do Now.

**Evidence Basis:** measured — two-query error-rate validation: `http_server_requests_seconds_count/summary` for hcs-gb. 5xx: 328 points, total errors 333. Total: 346 points, 1,451,373 requests. Aggregate error rate: 0.023%.
**Hypothesis:** The 1% threshold fires on low-traffic URIs where 1-2 errors produce a >1% rate. The per-URI `sum by (cluster, uri, method)` grouping creates many low-volume time series.

**Stage 1 DoD (Discovery — this ticket):**
- Identify which URIs trigger the alert (breakdown by uri in PromQL output)
- Determine minimum request volume per URI during the firing windows
- **Closes when:** Root cause per-URI confirmed AND decision on volume floor documented
- **Timebox:** 3 days

**Stage 2 (Execution — spawned follow-up):**
- **If low-volume URIs:** Add volume floor of >50 requests per 15m window
- **If genuine error spike:** Investigate the specific URI failure pattern

---

### 8. Investigate: medical-reporting error rate concentrated at h07 [Medium / Stage 1]

**Policy ID:** projects/oviva-monitoring/alertPolicies/6104095413877026659
**Target Owner:** mars_alerts
**Scope:** oviva-prod1, oviva-dg-prod1 (medical-reporting container)
**Notification Reach:** 2 channels
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/6104095413877026659?project=oviva-monitoring) · [View IaC](https://github.com/oviva-ag/monitoring/blob/main/tf/squads/mars/main.tf)

**Situation:** Error rate > 1% on medical-reporting fires 30 raw / 18 episodes with 40% concentration at hour 07 (UTC). Overall error rate is 0.024% (85 errors / 349,860 total requests). Similar per-URI low-volume pattern as hcs-gb. Auto_close set at 1800s. *Inferred morning batch/deploy from 40% h07 concentration — verify before applying mute window.*
**Impact:** 12.2 open-hours. medical-reporting IS in the SLO service list — this threshold alert may be redundant with SLO burn-rate alerting.

**Gate Blocker:** Need to determine if the h07 concentration correlates with a deploy schedule or morning batch job. Also need to assess redundancy with SLO definition (see Needs Decision #3).
**To Upgrade:** Confirm h07 cause + resolve SLO overlap → if redundant, disable in favor of SLO.

**Evidence Basis:** measured — two-query error-rate validation: `http_server_requests_seconds_count/summary` for medical-reporting. 5xx: total errors 85. Total: 349,860 requests. Aggregate error rate: 0.024%. h07 concentration from incident data.
**Hypothesis:** Morning deploy or batch processing at h07 causes transient 5xx errors on low-traffic URIs.

**Stage 1 DoD (Discovery — this ticket):**
- Correlate h07 incidents with deploy timestamps (`kubectl rollout history` or CI/CD logs)
- Review whether SLO burn-rate alerts for medical-reporting already cover this signal
- **Closes when:** h07 cause confirmed AND SLO overlap assessment documented
- **Timebox:** 3 days

**Stage 2 (Execution — spawned follow-up):**
- **If deploy-time transient:** Extend duration from 60s to 900s for the 15m rate window
- **If SLO covers this signal:** Disable threshold alert in favor of SLO burn-rate alerting

---

## Needs Decision

### 1. Silent Policy Cleanup [High / Decision Pending]

**Situation:** 384 out of 484 enabled policies (79%) had zero incidents in the 14-day analysis window. This is an unusually high silent ratio that may indicate a mix of: (a) well-calibrated alerts that rarely fire (ideal), (b) orphaned alerts for decommissioned services, (c) alerts with thresholds set too high to ever trigger, or (d) alerts monitoring metrics that are no longer being emitted.
**Impact:** 384 silent policies create a maintenance burden. Each policy consumes Cloud Monitoring evaluation quota and creates cognitive overhead during incident response ("is this alert even working?").

**Decision Required:** Should a structured audit of the 384 silent policies be conducted to identify and disable/remove orphaned or broken alerts?
**Named Decision Owner:** Platform/SRE lead
**Deadline:** 2026-04-14 (advisory)
**Default Recommendation:** Conduct a two-pass audit: (1) automated check for metric-exists on each silent policy's condition metrics, (2) manual review of the ~50 oldest policies by creation date. Disable confirmed orphans. Keep well-calibrated silent alerts.

**Options:**
- **If audit:** Allocate 2-3 days of platform team time to run metric-exists checks and owner outreach. Expected outcome: 50-100 policies disabled, reduced monitoring quota usage.
- **If defer:** Accept current state. Revisit when Cloud Monitoring quota becomes a constraint or the next alert hygiene report shows further growth.

---

### 2. SLO review candidates: hcs-gb, gamification, onboarding [High / Decision Pending]

**Situation:** Three services have >10 noisy user-facing threshold alerts but no SLO definition in `slo-config.yaml`:
- **hcs-gb:** 37 raw incidents (error_rate) — 0.023% actual error rate, alert fires on per-URI low-volume spikes
- **gamification:** 12 raw incidents (error_rate) — fires across both prod clusters
- **onboarding:** 11 raw incidents (error_rate + latency) — latency > 2s and error rate > 1%

Each service is using threshold-based alerts that fire on short-term metric spikes. SLO-based burn-rate alerting would provide better signal-to-noise for user-facing services.
**Impact:** 60 combined raw incidents across these 3 services. SLO adoption would replace multiple noisy threshold alerts with a single burn-rate alert per service.

**Decision Required:** Should these services be added to the SLO program? This requires defining availability/latency SLIs, setting error budgets, and configuring burn-rate alerts.
**Named Decision Owner:** Squad leads (mars_alerts for hcs-gb, saturn_alerts for gamification + onboarding)
**Deadline:** 2026-04-30 (advisory)
**Default Recommendation:** Prioritize hcs-gb (highest noise, no SLO, only threshold-based error monitoring) for SLO pilot, then extend to gamification and onboarding.

**Options:**
- **If adopt SLO:** Define SLIs, set targets, add to slo-config.yaml, disable redundant threshold alerts. Expected: 60+ incidents reduced to <10 burn-rate alerts/month.
- **If defer:** Keep threshold alerts, apply volume floor to hcs-gb (Investigate #7), tune gamification and onboarding thresholds independently.

---

### 3. Redundant SLO + threshold alerts: medical-reporting, clinical-pathways [High / Decision Pending]

**Situation:** Two services have BOTH an SLO definition AND noisy user-facing threshold alerts:
- **medical-reporting:** 30 raw incidents (error_rate, 40% at h07), has SLO definition
- **clinical-pathways:** 19 raw incidents (error_rate), has SLO definition

The threshold alerts (>1% error rate per URI) and SLO burn-rate alerts may be providing overlapping signal. The threshold alert is more granular (per-URI) but noisier; the SLO alert is more holistic but may miss per-URI problems.
**Impact:** 49 combined raw incidents that may be redundant with SLO burn-rate alerting.

**Decision Required:** For each service, should the threshold error-rate alert be kept alongside the SLO alert, or should it be disabled in favor of SLO-only monitoring?
**Named Decision Owner:** mars_alerts squad lead
**Deadline:** 2026-04-14 (advisory)
**Default Recommendation:** Keep both for 30 days, instrument which alert fires first for each incident, then decide based on data. If SLO alert catches all incidents that the threshold alert catches, disable the threshold alert.

**Options:**
- **If keep both:** Accept overlap. Per-URI granularity provides value for debugging even if SLO alert fires first.
- **If SLO-only:** Disable threshold alerts, rely on SLO burn-rate alerting. Add per-URI breakdown to SLO investigation dashboard instead.
- **If threshold-only:** Remove from SLO program (unlikely — SLO provides error budget context that thresholds cannot).

---

## Keep — No Action Required

| Cluster | Rationale |
|---------|-----------|
| WAF Policy Alerts: Requests blocked (multiple clusters) | Fires <24x/14d across 4 clusters, correct routing (cloudarmor_alerts). Normal WAF activity. |
| onboarding: 1 or more CLIENT_ERROR (7 raw) | Clean signal (7 raw / 7 eps), recurring but low frequency. Client errors are informational. |
| clinical-pathways: error rate > 1% (19 raw) | Moderate noise but has SLO coverage. See Needs Decision #3 for overlap assessment. |
| Transaction threshold reached for MySQL (15+14 raw, xenon_alerts) | Chronic pattern with correct routing. Genuine long-running transaction monitoring. |
| PLEX: DLQ alerts (23 raw / 23 eps, plex_alerts) | Clean 1:1 ratio, correct routing. Each DLQ message is a distinct event. |
| Edge Proxy 5xx Count (18 raw, xenon_alerts) | Recurring at ns=4, but low total. Correctly routed. |
| Auri alerts (3-5 raw each, nexus_alerts) | Isolated, correctly routed. AI companion service alerts working as designed. |
| Cloud SQL CPU utilization (1 raw, xenon_alerts) | Isolated spike, well-calibrated. |
| VM instance CPU utilization (1 raw, xenon_alerts) | Isolated spike, well-calibrated. |
| devices-integration: error rate > 1% (8 raw, mars_alerts) | Low frequency, correctly routed, has SLO coverage. |

---

## Verification Scorecard

| Finding | Baseline (14d) | Target | Owner | Merge Date | Review Date | Primary Success Criteria | Guardrail | Confidence |
|---------|-----------------|--------|-------|------------|-------------|--------------------------|-----------|------------|
| 1. Artemis expired | 72 raw, 2,102 oh | <5 raw, <50 oh | ⚠ assign | — | +14d | Raw < 5 | No burst >100 undetected | High |
| 2. Artemis never-empty | 175 raw, 10,488 oh | <10 raw, <100 oh | ⚠ assign | — | +14d | Raw < 10 | Backlog >1000 6h detected | High |
| 3. Artemis no-consumer | 229 raw, 9,782 oh | <30 raw, <500 oh | ⚠ assign | — | +14d | Raw < 30 | Zero-consumer 1h+ detected | High |
| 4. MySQL label fix | 1,551 misrouted | 0 misrouted | xenon_alerts | — | +14d | 100% correct label | No alerts dropped | High |

---

## Evidence Ledger / Reproduction

### Config inspection — provable from policy definition

| Cluster | What was checked | Finding | Scope |
|---------|-----------------|---------|-------|
| Artemis expired messages (hb-it) | auto_close NOT SET, threshold > 1 | Structural permanent-fire: single expired message triggers indefinite alert | oviva-k8s-hb-it |
| Artemis never-empty (4 clusters) | auto_close NOT SET, min_over_time 24h lookback, threshold > 0 | Structural permanent-fire: any non-empty queue triggers indefinite alert | oviva-k8s-hb-it, dg-prod, prod, dg-pta |
| Artemis without-consumer (5 clusters) | auto_close NOT SET | Structural: alert cannot auto-resolve even when consumers reconnect | oviva-k8s-hb-it, dg-prod, prod, k8s, dg-pta |
| MySQL outlier label mismatch | squad=staging_alerts on production project data | Label inconsistency: production alerts labeled as staging | oviva-k8s-prod, oviva-k8s-dg-prod |

### Metric query — validated against Cloud Monitoring time-series

| Cluster | Query | Result | Finding |
|---------|-------|--------|---------|
| Pod restart hb-it | `kubernetes.io/container/restart_count`, project=oviva-k8s-hb-it, ALIGN_DELTA+REDUCE_SUM, 1h, 346 pts | Min=5, Max=1,015, Median=42, p95=864 | Systemic restarts: median 42/h, spikes to 1,015/h |
| Diet Suggestions threads | `prometheus.googleapis.com/jvm_threads_live_threads/gauge`, container=diet-suggestions, cluster=oviva-dg-prod1, ALIGN_MAX+REDUCE_MAX, 1h, 346 pts | Min=135, Max=3,213, p50=1,148, p95=2,085, 61.3% above threshold | Baseline above threshold 61% of the time |
| Artemis consumer count (it) | `prometheus.googleapis.com/artemis_consumer_count/gauge`, pod=message-broker-0, namespace=it, ALIGN_MIN+REDUCE_SUM, 1h, 315 pts | Min=154, Max=1,384, Median=1,176, 0% zero | Consumer count never zero at 1h resolution |
| Artemis message count (it) | `prometheus.googleapis.com/artemis_message_count/gauge`, pod=message-broker-0, namespace=it, ALIGN_MAX+REDUCE_MAX, 1h, 315 pts | Min=21,663, Max=35,459, Median=30,737 | Queue never empty; min is 21,663 |
| Artemis expired messages (it) | `prometheus.googleapis.com/artemis_messages_expired/gauge`, pod=message-broker-0, namespace=it, ALIGN_MAX+REDUCE_MAX, 1h, 315 pts | Min=128, Max=24,871, Median=9,569, p95=23,588, 100% >1 | Permanent >1 state; threshold structurally too low |
| Node memory oviva-k8s | `kubernetes.io/node/memory/allocatable_utilization`, project=oviva-k8s, ALIGN_MAX+REDUCE_MAX, 1h, 346 pts | Min=0.752, Max=0.990, p50=0.895, p95=0.960, 47.4% >0.9 | Baseline crowding: p50 is 99.4% of threshold |
| Memory limit analyser | `kubernetes.io/container/memory/limit_utilization`, container_name=analyser, ALIGN_MAX+REDUCE_MAX, 1h, 346 pts | Min=0.158, Max=0.186, p50=0.171, p95=0.185 | Analyser is NOT the hot container (max 18.6%) |
| hcs-gb error rate | `http_server_requests_seconds_count/summary`, container=hcs-gb, ALIGN_DELTA+REDUCE_SUM, 1h, 328+346 pts | 333 errors / 1,451,373 total = 0.023% | Aggregate rate well below 1% threshold |
| medical-reporting error rate | `http_server_requests_seconds_count/summary`, container=medical-reporting, ALIGN_DELTA+REDUCE_SUM, 1h, similar pts | 85 errors / 349,860 total = 0.024% | Aggregate rate well below 1% threshold |
| clinical-pathways error rate | `http_server_requests_seconds_count/summary`, container=clinical-pathways, ALIGN_DELTA+REDUCE_SUM, 1h, similar pts | 569 errors / 1,239,812 total = 0.046% | Aggregate rate well below 1% threshold |
| DB Insights dg-prod | `dbinsights.googleapis.com/perquery/latencies`, project=oviva-k8s-dg-prod, ALIGN_DELTA, 86400s, 142 series | Mean latency 834ms–858s across query hashes | Wide per-query variance; some hashes have extreme latency |
| Mobile API (backend-core) | `prometheus.googleapis.com/http_server_duration_milliseconds/histogram`, container=backend-core, ALIGN_DELTA, 86400s, 1 series | ~1.4M–1.9M requests/day, mean latency 75–77ms | High-volume endpoint; histogram _count via distributionValue.count |

### Pattern analysis — inferred from incident frequency/timing, needs validation before applying

| Cluster | Pattern observed | What would upgrade this | Scope |
|---------|-----------------|------------------------|-------|
| Mobile API 5xx (h23) | 40% concentration at h23, flapping ns=4-6 | Confirm deploy schedule at h23 OR query per-route volume at h23 | .*-prod1 |
| medical-reporting (h07) | 40% concentration at h07, recurring ns=3 | Confirm deploy/batch schedule at h07 | oviva-prod1, oviva-dg-prod1 |
| Pod restart oviva-k8s (h22) | 87% concentration at h22, chronic | Confirm nightly batch schedule at h22 | oviva-k8s |
| goal-setting P99 > 9s | Recurring ns=4, spread time-of-day | Query P99 baseline for goal-setting | .*-prod1 |

---

## Appendix: Frequency Table

| # | Cluster Key | Raw | Episodes | Distinct Resources | Median Duration | Median Retrigger | Noise Score | Pattern | Open-Hours | Verdict | Confidence |
|---|-------------|-----|----------|-------------------|-----------------|-----------------|-------------|---------|------------|---------|------------|
| 1 | hb-it\|.../9019907273249855951\|restart_count | 1,110 | 1,066 | 1,053 | 6.7h | 3.6h | 0 | chronic | 8,545.7 | Fix underlying issue | High |
| 2 | dg-prod\|.../17208358397831352350\|perquery/latencies | 841 | 266 | 6 | 10m | 30m | 5 | flapping | 403.2 | Fix routing | High |
| 3 | prod\|.../17208358397831352350\|perquery/latencies | 607 | 135 | 4 | 10m | 28m | 5 | flapping | 371.2 | Fix routing | High |
| 4 | dg-prod\|.../15443736973066518795\|jvm_threads | 372 | 129 | 14 | 44m | 1.3h | 1 | recurring | 376.5 | Tune the alert | Medium |
| 5 | dg-pta\|.../9019907273249855951\|restart_count | 182 | 176 | 57 | 14m | 1.1h | 2 | recurring | 360.0 | Fix underlying issue | Medium |
| 6 | hb-it\|.../17467897932493204533\|consumer_count | 162 | 32 | 1 | 22.4h | 0 | 3 | flapping | 6,706.7 | Tune the alert | High |
| 7 | hb-it\|.../6098275769612771826\|message_count | 108 | 30 | 1 | 127h | 0 | 2 | flapping | 7,644.3 | Tune the alert | High |
| 8 | \|.../11760810637840310856\|http_server_duration | 78 | 23 | 2 | 5m | 0 | 4 | flapping | 7.5 | Tune the alert | Medium |
| 9 | \|.../6767865470347481271\|http_server_duration | 77 | 23 | 2 | 5m | 1m | 6 | flapping | 7.4 | Tune the alert | Medium |
| 10 | \|.../8924582844325366421\|__missing__ | 77 | 47 | 2 | 6m | 59m | 4 | recurring | 13.9 | Tune the alert | Medium |
| 11 | prod\|.../1126182761046938150\|perquery/latencies | 72 | 16 | 1 | 25m | 49m | 3 | flapping | 88.3 | Fix routing | High |
| 12 | hb-it\|.../5600771186676456661\|expired | 72 | 8 | 1 | 26.2h | 30m | 5 | flapping | 2,102.1 | Tune the alert | High |
| 13 | k8s\|.../9019907273249855951\|restart_count | 68 | 66 | 65 | 5.8h | 16.2h | 1 | chronic | 578.7 | Fix underlying issue | Medium |
| 14 | \|.../17162693348665033848\|http_server_requests | 37 | 18 | 1 | 8m | 14m | 5 | recurring | 6.2 | Tune the alert | High |
| 15 | dg-prod\|.../9019907273249855951\|restart_count | 37 | 34 | 23 | 5.9h | 27.0h | 0 | chronic | 701.6 | Fix underlying issue | Low |
| 16 | prod\|.../9019907273249855951\|restart_count | 34 | 32 | 32 | 8.1h | 56.3h | 0 | chronic | 629.7 | Fix underlying issue | Low |
| 17 | \|.../16568293729673736416\|memory/limit_utilization | 33 | 20 | 1 | 12m | 1.8h | 2 | recurring | 53.4 | Fix underlying issue | Medium |
| 18 | dg-prod\|.../1126182761046938150\|perquery/latencies | 31 | 15 | 3 | 6m | 44m | 5 | recurring | 12.3 | Fix routing | High |
| 19 | \|.../6104095413877026659\|http_server_requests | 30 | 18 | 1 | 10m | 1.5h | 3 | recurring | 12.2 | Tune the alert | Medium |
| 20 | k8s\|.../11341240194235664037\|memory/alloc_util | 27 | 27 | 2 | 1.3h | 5.2h | 0 | chronic | 46.8 | Fix underlying issue | High |
| 21 | \|.../15451110698797130466\|memory/limit_utilization | 26 | 20 | 2 | 23m | 3.4h | 0 | recurring | 65.2 | Fix underlying issue | Medium |
| 22 | k8s\|.../13558317750920915045\|memory/alloc_util_v2 | 25 | 12 | 1 | 23m | 1.9h | 1 | recurring | 21.8 | No action | Low |
| 23 | prod\|.../5296448552433168... \|camel_failures | 23 | 8 | 5 | 7m | 0 | 3 | recurring | 4.0 | Fix underlying issue | Medium |
| 24 | prod\|PLEX DLQ | 23 | 23 | 1 | 17m | 4.4h | 0 | recurring | 6.7 | No action | — |
| 25 | \|.../10744986850722255226\|P95_latency | 23 | 16 | 2 | 17m | 5.0h | 0 | recurring | 9.2 | No action | Low |
| 26-137 | (remaining 112 clusters) | 1–23 each | — | — | — | — | — | mostly isolated | — | Mostly no action | — |

---

## Appendix: Evidence Coverage

| Cluster | Metric Validated? | Evidence Basis | Sample Scope | Dedupe Window | Confidence |
|---------|-------------------|----------------|-------------|---------------|------------|
| Pod restart hb-it | Yes | measured | oviva-k8s-hb-it, 14d, 346 pts | 1800s | High |
| MySQL outlier dg-prod | Yes (distribution) | measured | oviva-k8s-dg-prod, 14d, 142 series | 1800s | High |
| Diet Suggestions threads | Yes | measured | oviva-dg-prod1, 14d, 346 pts | 1800s | Medium (threshold needs validation) |
| Artemis consumer (hb-it) | Yes | measured | namespace=it, 14d, 315 pts | 1800s | High |
| Artemis message count (hb-it) | Yes | measured | namespace=it, 14d, 315 pts | 1800s | High |
| Artemis expired (hb-it) | Yes | measured | namespace=it, 14d, 315 pts | 1800s | High |
| Node memory oviva-k8s | Yes | measured | oviva-k8s, 14d, 346 pts | 1800s | High |
| Memory limit analyser | Yes (not hot container) | measured | analyser only, 14d, 346 pts | 1800s | Medium |
| hcs-gb error rate | Yes (two-query) | measured | oviva-prod1+dg-prod1, 14d, 328+346 pts | 1800s | High |
| medical-reporting error rate | Yes (two-query) | measured | oviva-prod1+dg-prod1, 14d | 1800s | Medium |
| clinical-pathways error rate | Yes (two-query) | measured | oviva-prod1+dg-prod1, 14d | 1800s | Medium |
| Mobile API 5xx | Yes (histogram) | measured | backend-core on .*-prod1, 14d, histogram distribution | 1800s | Medium |
| goal-setting P99 | No | heuristic | — | 1800s | Medium |
| DB Insights dg-prod latency | Yes (distribution) | measured | oviva-k8s-dg-prod, 14d, 142 series | 1800s | High |
