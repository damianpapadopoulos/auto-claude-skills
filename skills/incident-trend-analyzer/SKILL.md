---
name: incident-trend-analyzer
description: On-demand postmortem trend analysis — recurrence grouping, trigger categorization, MTTR/MTTD from canonical docs/postmortems/ corpus
---

# Incident Trend Analyzer

On-demand analysis of historical postmortems from `docs/postmortems/`. Reads canonical postmortems produced by the incident-analysis skill, extracts normalized incident records, surfaces recurrence patterns, trigger distributions, and timing metrics. Terminal-first output with optional persistence on request.

## Step 1: Scan Corpus

Read `docs/postmortems/*.md` — **NON-RECURSIVE**. Do NOT descend into subdirectories (e.g., `docs/postmortems/trends/`). Filter to filenames matching `YYYY-MM-DD-*.md`. Report total files found.

**Minimum corpus:** 3 recurrence-eligible postmortems. If fewer than 3 qualify after Step 2, stop the entire analysis and report:

```
Not enough data for trend analysis.
Found N file(s) in docs/postmortems/:
  - <filename> (eligible: yes/no — reason)
Minimum required: 3 recurrence-eligible postmortems.
```

No partial metrics are reported below this threshold.

## Step 2: Parse and Classify Eligibility

For each file matching `YYYY-MM-DD-*.md`, extract the date from the filename and extract raw section text by heading boundaries (`## N. Heading`). Classify into eligibility tiers:

| Tier | Required | Enables |
|------|----------|---------|
| **Recurrence-eligible** | Valid filename + `## 1. Summary` + `## 4. Root Cause & Trigger` | Recurrence grouping, trigger categorization |
| **Timeline-eligible** | Recurrence-eligible + `## 3. Timeline` with parseable timestamps | Timing metric candidates |
| **MTTR-eligible** | Timeline-eligible + identifiable detection and recovery events | MTTR computation |
| **MTTD-eligible** | Timeline-eligible + identifiable trigger and detection events | MTTD computation |

**Parseable timestamps:** Absolute only. Accepted formats:
- ISO 8601: `2026-03-15T10:32:00Z`
- `HH:MM` or `HH:MM:SS` with date inferred from the filename
- `YYYY-MM-DD HH:MM`

Relative timestamps ("5 minutes later", "+10m") are NOT parseable. They produce `low` timing confidence and are excluded from MTTR/MTTD computation.

**Unparseable files:** Listed in coverage report, excluded from analysis. No fuzzy parsing.

## Step 3: Build Normalized Incident Records

For each recurrence-eligible postmortem, build one normalized record with these fields:

### Service Extraction (from Summary)

| Confidence | Rule |
|------------|------|
| **high** | Explicit service name in summary text (e.g., "auth-service experienced...", "checkout-service returned 500s") |
| **medium** | Filename slug — first segment of the kebab-case portion before a failure-mode word (e.g., `2026-01-12-auth-timeout.md` → `auth`) |
| **low** | No identifiable service → `unknown-service` |

### Failure Mode (from Root Cause & Trigger)

Match signal patterns in the `## 4. Root Cause & Trigger` section text against this vocabulary:

| Key | Signal patterns |
|-----|----------------|
| `timeout` | timeout, deadline exceeded, context cancelled |
| `oom` | OOM, out of memory, memory limit, killed |
| `config-change` | config, misconfiguration, feature flag, env var |
| `dependency-failure` | upstream, downstream, third-party, provider outage |
| `deploy-regression` | deploy, release, regression, rollback, bad merge |
| `traffic-overload` | spike, load, burst, capacity, scaling, rate limit |
| `infra-failure` | node, disk, network, DNS, certificate, zone |
| `unknown` | No confident match (0 signals or tie between keys) |

**Confidence:** high (2+ signal words match one key), medium (1 signal word), low → `unknown`.

Group on vocabulary key only. Show raw Root Cause text as evidence, never as grouping key. Wording differences must not fragment groups.

### Trigger Category (from Root Cause & Trigger)

Match signal patterns in the `## 4. Root Cause & Trigger` section text against this vocabulary:

| Category | Signal patterns |
|----------|----------------|
| `deployment` | deploy, release, rollout, version, merge |
| `config-change` | config, feature flag, env var, parameter |
| `dependency` | upstream, downstream, third-party, provider, API |
| `traffic` | spike, load, burst, capacity, scaling |
| `infrastructure` | node, disk, network, DNS, certificate |
| `unknown` | No clear match, or tie between categories |

Pick the category with the most signal words. If tied, use `unknown`.

### Timing Extraction (from Timeline)

For timeline-eligible postmortems only. Extract these timestamps from `## 3. Timeline` rows:

| Field | Signal patterns in timeline row |
|-------|---------------------------------|
| `incident_start` | "deployed", "pushed", "config changed", "traffic spike", or first row if it describes a causal event |
| `detected_at` | "alert", "page", "noticed", "reported", "detected" |
| `recovered_at` | "resolved", "recovered", "mitigated", "restored" |

**timing_confidence:** high (3/3 timestamps found), medium (2/3), low (0–1). If a timestamp cannot be identified deterministically, the incident is excluded from the relevant metric and noted in coverage.

### Full Record Schema

| Field | Source | Confidence levels |
|-------|--------|-------------------|
| `date` | Filename `YYYY-MM-DD` | Always high |
| `service` | Summary section | high / medium / low → `unknown-service` |
| `failure_mode` | Root Cause & Trigger, vocabulary match | high / medium / low → `unknown` |
| `trigger_category` | Root Cause & Trigger, category match | Same rules as failure_mode |
| `incident_start` | Timeline: first causal event | Per timing_confidence |
| `detected_at` | Timeline: alert/page/noticed row | Per timing_confidence |
| `recovered_at` | Timeline: resolved/mitigated row | Per timing_confidence |
| `timing_confidence` | Count of parsed timestamps | high (3/3) / medium (2/3) / low (0–1) |
| `eligible_for` | Derived from above | `[recurrence, mttr, mttd]` flags |
| `raw_evidence` | Original section text | For audit trail |

## Step 4: Compute Metrics

### Recurrence Grouping

- Group by `(service, failure_mode)` — both from vocabulary keys, not free text
- Minimum group size for recurrence: 2
- Per cluster, show dominant `trigger_category` as annotation (NOT part of grouping key)
- Sort by count descending
- **`unknown-service` / `unknown` failure_mode clusters are excluded from headline recurrence output.** They appear in a separate Uncategorized section to avoid surfacing false patterns.

### Trigger Distribution

- Count each `trigger_category` across all recurrence-eligible incidents
- Show count and percentage
- Sort descending by count

### MTTR (Mean Time to Recovery)

- Formula: `recovered_at - detected_at`
- Both timestamps require `timing_confidence >= medium`
- Report: **median** (headline), mean, range
- Show eligible count vs total recurrence-eligible

### MTTD (Mean Time to Detection)

- Formula: `detected_at - incident_start`
- Both timestamps require `timing_confidence >= medium`
- Report: **median** (headline), mean, range
- Show eligible count vs total recurrence-eligible

## Step 5: Generate Output

### Terminal Summary (default)

Print this exact structure:

```
## Incident Trend Analysis

Corpus: N files scanned, X recurrence-eligible, Y MTTR-eligible, Z MTTD-eligible
Period: YYYY-MM-DD to YYYY-MM-DD (N days)

### Recurrence Patterns
  service / failure_mode  — N incidents (dates) | trigger: category
  ...
  N incidents showed no recurrence

### Trigger Distribution
  category  — N (PP%)
  ...

### MTTR (Y of X eligible)
  Median: Xm | Mean: Xm | Range: Xm – Xm

### MTTD (Z of X eligible)
  Median: Xm | Mean: Xm | Range: Xm – Xm

### Coverage Gaps
  (Report any metric with < 60% eligibility)

### Insights
- (2–4 cited observations)
```

### Insights Rules

Generate 2–4 insight bullets by applying these rules:

1. **Top recurrence cluster** + its dominant trigger → observation
2. **Dominant trigger category** if > 40% of incidents → systemic observation
3. **MTTD outliers** > 2x median → detection gap observation
4. **Coverage gaps** < 60% eligible for any metric → data quality observation

**Every insight bullet MUST cite the supporting count or rate** (e.g., "3x in 63 days", "4/9 incidents, 44%"). Insights are observations with citations, NOT prescriptions. The skill does NOT prescribe fixes — it surfaces patterns and lets the user decide.

## Step 6: Persist (on request only)

Persistence is triggered ONLY when the user explicitly requests it ("save this", "save report", "persist"). Do NOT auto-persist.

1. Create `docs/postmortems/trends/` if it does not exist
2. Write to `docs/postmortems/trends/YYYY-MM-DD-trend-report.md`
3. If a same-day report already exists, append `-2`, `-3`, etc. (e.g., `2026-03-21-trend-report-2.md`)
4. Content: full terminal summary + per-incident record table for auditability
5. **No auto-commit** — the user decides when to commit
