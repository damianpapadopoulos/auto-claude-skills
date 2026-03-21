# Incident Trend Analyzer: On-Demand Postmortem Trend Analysis (v2.0)

**Date:** 2026-03-21
**Status:** Draft
**Phase:** DESIGN
**Depends on:** incident-analysis v1.0+ (canonical postmortem schema)

## Problem Statement

The incident-analysis skill (v1.0–v1.2) handles reactive debugging: MITIGATE → INVESTIGATE → POSTMORTEM. It generates structured postmortems in `docs/postmortems/` with a consistent 7-section schema. But once those postmortems accumulate, nobody connects the dots — recurring failure modes go unnoticed, trigger patterns stay invisible, and MTTR/MTTD trends are never surfaced.

There is no skill that teaches Claude to read historical postmortems, extract normalized incident records, and surface recurrence patterns, trigger distributions, and timing metrics.

## Core Insight: Aggregation Is Not Investigation

The temptation is to add a "Stage 4" to the existing incident-analysis skill. But aggregation and investigation are fundamentally different interaction patterns:

| Dimension | Incident investigation | Trend analysis |
|-----------|----------------------|----------------|
| Input | Live logs, traces, metrics | Historical markdown files |
| Time pressure | High (active incident) | None (retrospective) |
| Query pattern | Narrow, scoped, iterative | Broad, batch, read-all |
| Output | Timeline + root cause + postmortem | Recurrence patterns + metrics |
| Tool tier | MCP > gcloud > guidance | File reads only |

This means the trend analyzer deserves its own skill boundary, its own routing triggers, and its own evolution path.

## Approach: Standalone Skill (`incident-trend-analyzer`)

A new `skills/incident-trend-analyzer/SKILL.md` that reads canonical postmortems, builds normalized incident records, and outputs trend analysis. Terminal-first, persist on request.

### Why standalone (not embedded in incident-analysis)

1. Different interaction pattern — reads files, not live systems
2. Different routing triggers — "what keeps breaking" vs "investigate this incident"
3. Keeps incident-analysis focused on its reactive debugging workflow (already 256 lines)
4. Clean composition boundary for v2.1+ (proactive advisory during postmortem generation)

## Parser Contract

### Corpus

- **Source:** `docs/postmortems/*.md` only
- **Filename required:** `YYYY-MM-DD-*.md` (date extracted from filename, not content)
- **Minimum corpus:** 3 recurrence-eligible postmortems. Below that, report "not enough data for trend analysis" and list what was found.
- **Unparseable files:** Listed in coverage report, excluded from analysis. No fuzzy parsing.

### Tiered Eligibility

Not all postmortems contain all sections. Rather than discarding an entire file because its timeline is weak, eligibility is tiered:

| Tier | Required headings | Enables |
|------|-------------------|---------|
| **Recurrence-eligible** | Valid filename + `## 1. Summary` + `## 4. Root Cause & Trigger` | Recurrence grouping, trigger categorization |
| **Timeline-eligible** | Recurrence-eligible + `## 3. Timeline` with parseable timestamps | Timing metric candidates |
| **MTTR-eligible** | Timeline-eligible + identifiable detection and recovery events | MTTR computation |
| **MTTD-eligible** | Timeline-eligible + identifiable trigger and detection events | MTTD computation |

### Optional Headings (enhance but not required)

| Heading | Extracts | Used for |
|---------|----------|----------|
| `## 2. Impact` | Duration, user count | Severity weighting (future) |
| `## 5. Resolution and Recovery` | Resolution method | Resolution pattern analysis (future) |
| `## 6. Lessons Learned` | Free text | Future enrichment |
| `## 7. Action Items` | Items + owners | Deferred to v2.1+ |

### Parser Responsibility

The parser extracts **raw data only**: section text and timeline rows. It does NOT interpret service names, failure modes, or trigger categories. That responsibility belongs to the analysis engine.

## Normalized Incident Record

The analysis engine builds one record per parseable postmortem from the parser's raw output:

| Field | Source | Confidence levels |
|-------|--------|-------------------|
| `date` | Filename `YYYY-MM-DD` | Always high |
| `service` | Summary section | high (explicit name, e.g., "auth-service experienced...") / medium (filename slug) / low → `unknown-service` |
| `failure_mode` | Root Cause & Trigger, vocabulary match | high (2+ signal words match one key) / medium (1 signal) / low → `unknown` |
| `trigger_category` | Root Cause & Trigger, category match | Same confidence rules as failure_mode |
| `incident_start` | Timeline: first causal event | Per timing_confidence |
| `detected_at` | Timeline: alert/page/noticed row | Per timing_confidence |
| `recovered_at` | Timeline: resolved/mitigated row | Per timing_confidence |
| `timing_confidence` | Count of parsed timestamps | high (3/3) / medium (2/3) / low (0–1) |
| `eligible_for` | Derived from above | `[recurrence, mttr, mttd]` flags |
| `raw_evidence` | Original section text | For audit trail |

## Failure Mode Vocabulary (v2.0)

| Key | Signal patterns in Root Cause & Trigger |
|-----|----------------------------------------|
| `timeout` | timeout, deadline exceeded, context cancelled |
| `oom` | OOM, out of memory, memory limit, killed |
| `config-change` | config, misconfiguration, feature flag, env var |
| `dependency-failure` | upstream, downstream, third-party, provider outage |
| `deploy-regression` | deploy, release, regression, rollback, bad merge |
| `traffic-overload` | spike, load, burst, capacity, scaling, rate limit |
| `infra-failure` | node, disk, network, DNS, certificate, zone |
| `unknown` | No confident match |

Raw Root Cause sentence is shown as evidence in output, but **grouping uses vocabulary keys only**. No free-text grouping keys — wording differences must not fragment groups.

## Trigger Category Vocabulary (v2.0)

| Category | Signal patterns |
|----------|----------------|
| `deployment` | deploy, release, rollout, version, merge |
| `config-change` | config, feature flag, env var, parameter |
| `dependency` | upstream, downstream, third-party, provider, API |
| `traffic` | spike, load, burst, capacity, scaling |
| `infrastructure` | node, disk, network, DNS, certificate |
| `unknown` | No clear signal match |

If multiple categories match, pick the one with the most signal words. If tied, use `unknown`.

## Metric Definitions

| Metric | Formula | Requires |
|--------|---------|----------|
| **MTTD** | `detected_at - incident_start` | Both timestamps at timing_confidence >= medium |
| **MTTR** | `recovered_at - detected_at` | Both timestamps at timing_confidence >= medium |
| **Outage duration** | `recovered_at - incident_start` | Both timestamps |

**Headline stat: median.** Mean and range shown second.

### Timing Extraction Rules

- **incident_start:** Timeline row containing "deployed", "pushed", "config changed", "traffic spike", or first row if it describes a causal event
- **detected_at:** Timeline row containing "alert", "page", "noticed", "reported", "detected"
- **recovered_at:** Timeline row containing "resolved", "recovered", "mitigated", "restored"
- If a timestamp cannot be identified deterministically, the incident is excluded from the relevant metric and noted in coverage

## Recurrence Grouping

- Group by `(service, failure_mode)` — both from vocabulary, not free text
- **Minimum group size for recurrence:** 2
- Per cluster, show dominant `trigger_category` as annotation (NOT part of grouping key)
- Sorted by count descending
- **`unknown-service / unknown` clusters are excluded from headline recurrence output.** They appear in a separate coverage/uncategorized section to avoid surfacing false patterns.

## Insights Generation

The skill generates 2–4 insight bullets by applying simple rules:

- Top recurrence cluster + its dominant trigger → actionable observation
- Dominant trigger category if > 40% → systemic observation
- MTTD outliers (> 2x median) → detection gap observation
- Coverage gaps (< 60% eligible for any metric) → data quality observation

**Each insight bullet MUST cite the supporting count or rate** (e.g., "3x in 63 days", "4/9 incidents, 44%"). Insights are observations with citations, not prescriptions. The skill does NOT prescribe fixes — it surfaces patterns and lets the user decide.

## Output Format

### Terminal Summary (default)

```
## Incident Trend Analysis

Corpus: 12 files scanned, 9 recurrence-eligible, 6 MTTR-eligible, 5 MTTD-eligible
Period: 2026-01-12 to 2026-03-15 (63 days)

### Recurrence Patterns
  auth-service / timeout         — 3 incidents (Jan 12, Feb 8, Mar 15) | trigger: dependency
  checkout-service / oom         — 2 incidents (Jan 30, Mar 1) | trigger: traffic
  5 incidents showed no recurrence

### Trigger Distribution
  deployment       — 4 (44%)
  dependency       — 2 (22%)
  traffic          — 2 (22%)
  unknown          — 1 (11%)

### MTTR (6 of 9 eligible)
  Median: 47 min | Mean: 1h 12min | Range: 12 min – 4h 30min

### MTTD (5 of 9 eligible)
  Median: 8 min | Mean: 14 min | Range: 2 min – 45 min

### Coverage Gaps
  MTTD coverage is 5/9; 4 incidents lacked identifiable trigger→detection events

### Insights
- auth-service/timeout is the top recurrence (3x in 63 days) — all dependency-triggered
- Deployment is the leading trigger category (4/9 incidents, 44%)
```

### Persist Flow (on request only)

- **Trigger:** User explicitly requests ("save this", "save report", "persist")
- **Path:** `docs/postmortems/trends/YYYY-MM-DD-trend-report.md`
- **Collision:** Append `-2`, `-3`, etc. if same-day report already exists
- **Content:** Full terminal summary + per-incident record table for auditability
- **No auto-commit** — user decides when to commit
- Create `docs/postmortems/trends/` if it doesn't exist

## Routing

### Skill Entry (`default-triggers.json`)

```json
{
  "name": "incident-trend-analyzer",
  "role": "domain",
  "phase": "SHIP",
  "triggers": [
    "(incident.trend|postmortem.trend|what.keeps.breaking|recurring.incident|failure.pattern|incident.pattern|analyze.postmortems)"
  ],
  "trigger_mode": "regex",
  "keywords": ["postmortem trends", "recurring incidents", "incident patterns", "what keeps breaking"],
  "priority": 20,
  "precedes": [],
  "requires": [],
  "description": "On-demand postmortem trend analysis: recurrence grouping, trigger categorization, MTTR/MTTD from canonical docs/postmortems/ corpus.",
  "invoke": "Skill(auto-claude-skills:incident-trend-analyzer)"
}
```

- **`phase: "SHIP"`** (singular) — retrospective/historical analysis. Uses explicit trigger routing, not hard phase gating.
- **No methodology hint changes** — the existing `gcp-observability` hint may co-fire on some prompts (it triggers on `incident|postmortem`). This is acceptable co-guidance.
- **Keywords tightened** — no bare `pattern` or `trend` to avoid false positives.

### Phase Composition (v2.0 — no changes)

No changes to phase compositions. The trend analyzer is on-demand only. Composition into postmortem generation (proactive advisory) is deferred to v2.1+.

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `skills/incident-trend-analyzer/SKILL.md` | **Create** | Full skill: parser contract, analysis engine, output format, persist flow |
| `config/default-triggers.json` | **Modify** | Add `incident-trend-analyzer` skill entry |
| `config/fallback-registry.json` | **Auto-regenerated** | Auto-synced by `session-start-hook.sh` on next session start |
| `tests/test-routing.sh` | **Modify** | Add trigger matching, non-overlap with incident-analysis, co-firing tests |
| `tests/test-registry.sh` | **Modify** | Add fallback parity check for `incident-trend-analyzer` |

### What's NOT Touched

- `skills/incident-analysis/SKILL.md` — no changes, stays focused on reactive debugging
- `hooks/session-start-hook.sh` — no changes, no new capability detection needed
- `skills/unified-context-stack/` — no changes (Historical Truth already covers postmortem reading)
- Phase compositions — no changes until v2.1+

## Test Strategy

### Routing Tests (`tests/test-routing.sh`)

1. **Trigger matching:** Feed `incident trend`, `what keeps breaking`, `recurring incidents`, `analyze postmortems` → verify `incident-trend-analyzer` scores and appears
2. **Phase label:** Verify skill has `phase: "SHIP"`
3. **Non-overlap with incident-analysis:** Feed `investigate this incident` → verify `incident-analysis` fires but `incident-trend-analyzer` does NOT
4. **Co-firing:** Feed `incident trend analysis for this outage` → verify both skills can appear (both domain role, 2 domain slots)

### Registry Tests (`tests/test-registry.sh`)

5. **Fallback parity:** Verify `incident-trend-analyzer` appears in fallback registry with correct invoke path after session-start

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Weak/inconsistent postmortem data | Tiered eligibility + coverage reporting + minimum corpus threshold |
| Service name guessing from filename | Confidence-aware extraction; `unknown-service` preferred over bad guess |
| Failure mode fragmentation | Fixed vocabulary; raw text as evidence only, not grouping key |
| Unknown clusters dominating output | Excluded from headline recurrence; shown in coverage section |
| Same-day report collision | Append `-2`, `-3` suffix |
| False recurrence from small corpus | Minimum 3 recurrence-eligible postmortems required |
| MTTR/MTTD computed from bad timestamps | timing_confidence gate; medium+ required for inclusion |

## What's NOT in v2.0

- Proactive advisory during postmortem generation (v2.1+)
- Hand-written postmortem compatibility mode (v2.2+)
- Action-item completion tracking (v2.1+)
- Git history / issue tracker correlation
- Backend-agnostic support (v3.0)
- Helper scripts (evaluate need after v2.0 real-world usage)

## Evolution Path

```
v1.0  Single-service investigation + structured postmortem [SHIPPED]
v1.1  One-hop trace correlation [SHIPPED]
v1.2  Postmortem permalinks [SHIPPED]
v2.0  On-demand trend analyzer (this design)
v2.1  Proactive advisory: bounded recurrence check during postmortem generation
v2.2  Best-effort compat for hand-written postmortems matching minimum schema
v3.0  Backend-agnostic (Datadog, Splunk)
```

## Decision

Approach selected through iterative brainstorming (5 rounds of clarification, 4 design sections with refinements). Standalone skill chosen over embedded Stage 4 because aggregation and investigation are fundamentally different interaction patterns. Parser/engine separation chosen for auditability. Tiered eligibility chosen to avoid discarding partial data. Terminal-first output chosen for low friction, with optional persistence for organizational learning.
