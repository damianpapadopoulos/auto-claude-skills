# Alert Hygiene Report Update + Skill Metric Validation Fix

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the Mar 31 report with correct IaC paths and JVM thread baseline, then fix the alert-hygiene skill's Stage 3b instructions to prevent metric query inconsistencies in future reports.

**Architecture:** Two independent changes: (1) report edits to existing markdown, (2) SKILL.md Stage 3b section rewrite with mandatory query parameters, result quality gate, and standardized metric class table. Test additions to verify the new behavioral contracts.

**Tech Stack:** Markdown (report + SKILL.md), Bash (content tests)

---

### Task 1: Update report — Executive Summary and Decision Summary

**Files:**
- Modify: `docs/reports/alert-hygiene-2026-03-31.md:1-30`

- [ ] **Step 1: Replace executive summary IaC and Do Now lines**

Replace lines 12-13 of the report:
```
- No IaC terraform files found in `oviva-ag` GitHub org — **0 Do Now items** (all fail IaC Location gate). All actionable items are Investigate or Needs Decision.
- **0 Do Now** actions, **12 investigations**, **4 needs decision**
```
with:
```
- IaC confirmed at `oviva-ag/monitoring` (private repo, 172 .tf files). IaC Location gate now satisfied for all findings with structural/measured evidence.
- **6 Do Now** actions, **6 investigations**, **3 needs decision**
```

- [ ] **Step 2: Rewrite Decision Summary table**

Replace the full Decision Summary table (lines 17-30) with the updated version that promotes items 1-5 and 8 to Do Now (those with structural/measured evidence + confirmed IaC), keeps items 6-7 and 9-12 as Investigate (missing owner or heuristic evidence), removes Needs Decision #4 (IaC location — now resolved), and updates next actions from "Locate IaC" to "IaC PR".

The promoted Do Now items are:
1. Pod restart auto_close (structural: auto_close NOT SET) → `tf/modules/k8s_pods_restart_alert/main.tf`
2. MySQL slow query label mismatch (measured: mean > threshold) → `tf/modules/sql_latency_alert/main.tf`
3. Message queue never empty (structural: threshold > 0 with 24h lookback) → `tf/modules/message_broker_alerts/google_monitoring_alert_policy.tf`
4. Queue without consumer auto_close (structural: auto_close NOT SET) → same file
5. Expired messages threshold (structural: threshold > 1, ratio 11.7x) → same file
8. hcs-gb error rate volume floor (measured: 0.028% vs 1% threshold) → `tf/modules/golden_signals_micrometer_http_requests_alerts/` (via `for_each`)

Items staying Investigate:
6. JVM threads — needs correct threshold derivation from corrected data (p95=2,121)
7. Mobile API 5xx — heuristic only (h23 pattern), needs deploy correlation
9. Node memory — measured but aggregated, needs per-node validation
10. medical-reporting — heuristic (h07 pattern)
11. Memory limits — no owner
12. Goal-setting latency — no owner

- [ ] **Step 3: Commit**

```bash
git add docs/reports/alert-hygiene-2026-03-31.md
git commit -m "fix(report): update decision summary with IaC paths and promotions"
```

### Task 2: Update report — JVM thread evidence and finding detail

**Files:**
- Modify: `docs/reports/alert-hygiene-2026-03-31.md` (finding #6 section, Evidence Ledger)

- [ ] **Step 1: Update finding #6 (JVM threads) with corrected measurement**

In the Investigate finding #6 section, replace the evidence with the corrected REDUCE_MAX query results:
- Old: p50=184, p95=764, max=764, 2 series, 14 points
- New: p50=1,188, p95=2,121, max=3,213, 1 series (REDUCE_MAX), 336 points, 58.6% above threshold

Update the threshold recommendation from >1200 to >2,200 (p95=2,121 + ~4% headroom).

Update the Stage 1 DoD to reflect that the 30-day validation is less critical now (14-day data already has 336 points), and the primary question is whether the thread pool max is a known limit.

- [ ] **Step 2: Update Evidence Ledger metric query entry for JVM threads**

In the "Metric query" table, replace:
```
| JVM threads (diet-suggestions) | `prometheus.googleapis.com/jvm_threads_live_threads/gauge` ALIGN_MAX 1h for diet-suggestions on oviva-dg-prod1: 2 series, 14 data points. p50=184, p95=764, max=764. Threshold 1000. p95/threshold = 76.4%. |
```
with:
```
| JVM threads (diet-suggestions) | `prometheus.googleapis.com/jvm_threads_live_threads/gauge` ALIGN_MAX 1h REDUCE_MAX for diet-suggestions on oviva-dg-prod1: 1 reduced series, 336 data points. p50=1,188, p95=2,121, max=3,213. Threshold 1000. 58.6% of hours above threshold — baseline above threshold. |
```

Also update the Evidence Coverage appendix entry from "Medium" to "High" confidence.

- [ ] **Step 3: Commit**

```bash
git add docs/reports/alert-hygiene-2026-03-31.md
git commit -m "fix(report): correct JVM thread measurement with REDUCE_MAX (336 pts, p50=1188)"
```

### Task 3: Update report — IaC paths in all findings

**Files:**
- Modify: `docs/reports/alert-hygiene-2026-03-31.md` (Do Now section, Investigate findings, Needs Decision #4)

- [ ] **Step 1: Replace "Actionable Findings: Do Now" empty section**

Replace the current empty Do Now section (which says "No items qualify for Do Now") with the promoted findings. Each promoted finding needs:
- IaC Location line with confirmed path (e.g., `[Confirmed] oviva-ag/monitoring :: tf/modules/k8s_pods_restart_alert/main.tf`)
- Remove "Gate Blocker: IaC Location = Unknown" and "To Upgrade" fields
- Add Rollback Signal and Pre-change Evidence fields (required for Do Now)
- Keep the existing Proposed Config Diff tables

Findings to promote to Do Now with their IaC paths:
1. Pod restart → `tf/modules/k8s_pods_restart_alert/main.tf` (add `alert_strategy { auto_close = "43200s" }`)
2. MySQL slow query label → `tf/modules/sql_latency_alert/main.tf` (change `var.outlier_user_labels`)
3. Queue never empty → `tf/modules/message_broker_alerts/google_monitoring_alert_policy.tf` (change threshold, lookback, add auto_close)
4. Queue without consumer → same file (add `alert_strategy { auto_close = "43200s" }`)
5. Expired messages → same file (change threshold, add auto_close)
8. hcs-gb error rate → `tf/modules/golden_signals_micrometer_http_requests_alerts/main.tf` or squad-level instantiation (add volume floor to PromQL)

- [ ] **Step 2: Update remaining Investigate items with IaC paths**

For items staying as Investigate, add IaC Location = Confirmed or Likely with the path, and update "To Upgrade" to reflect what's actually missing (owner assignment, metric validation, etc.) rather than "locate IaC".

- [ ] **Step 3: Remove Needs Decision #4 (IaC location)**

Delete the "Establish IaC location for monitoring policies" Needs Decision item — it's resolved. Update the Needs Decision count from 4 to 3 in the Executive Summary.

- [ ] **Step 4: Commit**

```bash
git add docs/reports/alert-hygiene-2026-03-31.md
git commit -m "fix(report): add confirmed IaC paths, promote 6 items to Do Now"
```

### Task 4: Fix SKILL.md — Mandatory query parameters in Stage 3b

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md:210-233`

- [ ] **Step 1: Add mandatory query parameter table after Step 2**

After the "Step 2 — Extract threshold" section (line 208) and before "Step 3 — Query the metric" (line 210), insert a new section:

```markdown
**Mandatory Query Parameters by Metric Class:**

Every metric validation query MUST specify ALL THREE aggregation parameters. Omitting `crossSeriesReducer` when multiple series exist produces sparse, unrepresentative samples.

| Metric class | perSeriesAligner | alignmentPeriod | crossSeriesReducer | Expected points (14d) |
|---|---|---|---|---|
| Gauge (JVM threads, memory util, disk util) | ALIGN_MAX | 3600s | REDUCE_MAX | ~336 |
| Counter/delta (request count, restart count) | ALIGN_DELTA | 3600s | REDUCE_SUM | ~336 |
| Distribution (DB Insights latency) | ALIGN_DELTA | 86400s | — (per-hash) | ~14 |
| Error rate (ratio of two counters) | ALIGN_DELTA + REDUCE_SUM | 3600s | REDUCE_SUM (per query) | ~336 each |

When in doubt, use REDUCE_MAX for gauges and REDUCE_SUM for counters. Never omit the reducer for metrics that may have multiple series (per-pod, per-container, per-node).
```

- [ ] **Step 2: Fix the Tier 2 query template**

Replace the curl command at line 228-230:
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/$PROJECT/timeSeries?filter=$FILTER_ENC&interval.startTime=${START_TIME}&interval.endTime=${END_TIME}&aggregation.alignmentPeriod=3600s&aggregation.perSeriesAligner=ALIGN_MAX&pageSize=20" \
  -o "$WORK_DIR/ts-result.json" ; rm -f "$FILTER_FILE"
```
with:
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/$PROJECT/timeSeries?filter=$FILTER_ENC&interval.startTime=${START_TIME}&interval.endTime=${END_TIME}&aggregation.alignmentPeriod=3600s&aggregation.perSeriesAligner=ALIGN_MAX&aggregation.crossSeriesReducer=REDUCE_MAX&pageSize=100000" \
  -o "$WORK_DIR/ts-result.json" ; rm -f "$FILTER_FILE"
```

Changes: `pageSize=20` → `pageSize=100000`, added `&aggregation.crossSeriesReducer=REDUCE_MAX`.

- [ ] **Step 3: Commit**

```bash
git add skills/alert-hygiene/SKILL.md
git commit -m "fix(alert-hygiene): mandatory crossSeriesReducer + pageSize=100000 in Stage 3b"
```

### Task 5: Fix SKILL.md — Result quality gate

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md:233-244`

- [ ] **Step 1: Add result quality gate after the query template**

After the line "Write results to `$WORK_DIR`, not to conversation context. Parse with `python3` one-liner to extract p50/p95." (line 233), insert:

```markdown
**Result Quality Gate — MANDATORY before using any metric result:**

After every query, validate the result before computing percentiles:

1. **Point count check:** For a 14-day window with 1h alignment, expect ~336 points per reduced series. If fewer than 50 points are returned, flag the result as `insufficient sample` and note the actual count. Do NOT use sparse results to derive threshold recommendations — they produce unreliable percentiles.
2. **Series count check:** After REDUCE_MAX/REDUCE_SUM, expect exactly 1 series. If >1 series is returned, the reducer was not applied — re-query with the correct reducer.
3. **Pagination check:** If the response contains `nextPageToken`, the result is truncated. Re-query with higher `pageSize` or paginate. Do NOT compute percentiles from truncated data.
4. **Evidence block logging:** Every metric validation result MUST log in the Evidence Ledger: metric type, filter, aligner, reducer, alignment period, series count, point count, and numeric results. This makes cross-report comparisons auditable.

If a query fails the quality gate, mark the evidence basis as `heuristic (insufficient sample: N points)` instead of `measured`. Do not promote to Do Now based on insufficient samples.
```

- [ ] **Step 2: Update Step 5 (Handle failures) to reference quality gate**

Replace the existing Step 5 text:
```
If the metric type cannot be mapped, the query returns no data, or the suffix is wrong: note the reason and keep `heuristic` basis. A no-data result is itself a finding — the metric may be misconfigured or the resource labels may not match.
```
with:
```
If the metric type cannot be mapped, the query returns no data, the suffix is wrong, or the result fails the quality gate: note the reason and keep `heuristic` basis. A no-data result is itself a finding — the metric may be misconfigured or the resource labels may not match. An insufficient-sample result (< 50 points) means the query parameters need adjustment (missing reducer, low pageSize, or metric sparsity) — do not treat it as measured evidence.
```

- [ ] **Step 3: Commit**

```bash
git add skills/alert-hygiene/SKILL.md
git commit -m "fix(alert-hygiene): add result quality gate — reject sparse metric samples"
```

### Task 6: Add content tests for new behavioral contracts

**Files:**
- Modify: `tests/test-alert-hygiene-skill-content.sh:213-233`

- [ ] **Step 1: Add test assertions for new SKILL.md content**

Before the `print_summary` line (line 233), add:

```bash
# --- Metric validation query standardization (v5) ---
assert_contains "mandatory query params table" "Mandatory Query Parameters" "${SKILL_CONTENT}"
assert_contains "crossSeriesReducer in template" "crossSeriesReducer=REDUCE_MAX" "${SKILL_CONTENT}"
assert_contains "pageSize 100000 in template" "pageSize=100000" "${SKILL_CONTENT}"
assert_contains "REDUCE_MAX for gauges" "REDUCE_MAX" "${SKILL_CONTENT}"
assert_contains "REDUCE_SUM for counters" "REDUCE_SUM" "${SKILL_CONTENT}"
assert_contains "result quality gate" "Result Quality Gate" "${SKILL_CONTENT}"
assert_contains "point count check" "fewer than 50 points" "${SKILL_CONTENT}"
assert_contains "series count check" "exactly 1 series" "${SKILL_CONTENT}"
assert_contains "pagination check" "nextPageToken" "${SKILL_CONTENT}"
assert_contains "evidence block logging" "series count, point count" "${SKILL_CONTENT}"
assert_contains "insufficient sample basis" "insufficient sample" "${SKILL_CONTENT}"
```

- [ ] **Step 2: Run tests**

```bash
bash tests/test-alert-hygiene-skill-content.sh
```
Expected: all assertions PASS including the new ones.

- [ ] **Step 3: Commit**

```bash
git add tests/test-alert-hygiene-skill-content.sh
git commit -m "test(alert-hygiene): add assertions for query standardization and quality gate"
```

### Task 7: Run full test suite

**Files:** (none modified)

- [ ] **Step 1: Run all alert-hygiene tests**

```bash
bash tests/test-alert-hygiene-scripts.sh
bash tests/test-alert-hygiene-skill-content.sh
```
Expected: all tests pass.

- [ ] **Step 2: Syntax-check SKILL.md link integrity**

```bash
bash -n skills/alert-hygiene/SKILL.md 2>&1 || true
# Also verify no broken markdown by checking section headers are balanced
grep -c '^#' skills/alert-hygiene/SKILL.md
```
