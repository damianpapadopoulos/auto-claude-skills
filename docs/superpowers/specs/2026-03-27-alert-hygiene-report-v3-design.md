# Alert Hygiene Report v3 — Design Spec

**Goal:** Restructure the alert-hygiene report from confidence-band grouping (High/Medium/Needs Analyst) into an action-class structure (Do Now / Investigate / Needs Decision) with strict gating rules that guarantee Do Now items are PR-ready, investigations are bounded, and decisions have closure paths.

**Approach:** Changes are limited to SKILL.md Stage 5 (report template) and the Stage 3 classification instructions. The data pipeline (Stages 0-2), prescriptive reasoning templates, metric validation (Stage 3b), coverage gap check (Stage 4), and Python scripts are unchanged.

---

## 1. Report Skeleton

Replace the current skeleton (confidence bands + Track A/B) with:

```
# Alert Hygiene Analysis Report
**Monitoring project:** {project} | **Window:** {days} days ending {date}

## Executive Summary
  - Baseline metrics (measured): open-incident hours, routed volume, ownerless count
  - Modeled impact metrics (labeled as estimated, with scope and confidence stated)
  - Never override measured baselines with modeled projections

## Decision Summary
  (compact lead-facing table, capped at 8-12 items, anchor-linked to detailed sections)

## Methodology
  (unchanged from current — data source, scripts, window, dedupe, noise score, pattern classification, evidence basis, reproduction)

## Definitions
  (add: open-incident hours = sum of all incident durations in the analysis window, measured in hours; existing terms unchanged)

## Action Type Legend
  (unchanged — Tune, Fix, Redesign, Add/extend, No action)

## Systemic Issues
  - Ownership/Routing Debt
  - Dead/Orphaned Config
  - Missing Coverage
  - Inventory Health
  (thematic and non-exhaustive — does not duplicate detailed findings)

## Actionable Findings: Do Now
  Global Implementation Standard (immediate verification checklist)
  (strict PR-ready items only — must pass Do Now gate)

## Actionable Findings: Investigate
  (bounded Stage 1 discovery with two-stage DoD)

## Needs Decision
  (strategy/policy choices with named owner and advisory deadline)

## Keep — No Action Required
  (unchanged — 5-10 representative well-calibrated clusters)

## Verification Scorecard
  (rolled-up outcomes with merge date and review date)

## Evidence Ledger / Reproduction
  (scripts, evidence basis per finding, API limitations, rerun method)

## Appendix: Frequency Table
  (unchanged)

## Appendix: Evidence Coverage
  (unchanged)
```

### What moves where

| Current section | v3 destination |
|---|---|
| Track A: Config Changes (priority table) | Decision Summary table (Do Now rows) |
| Track B: Investigations (priority table) | Decision Summary table (Investigate rows) |
| High-Confidence Actions | Actionable Findings: Do Now |
| Medium-Confidence Actions | Actionable Findings: Investigate |
| Needs Analyst Input | Needs Decision |
| Label/Scope Inconsistencies | Systemic Issues: Ownership/Routing Debt |
| Coverage Gaps | Systemic Issues: Missing Coverage |
| Verification Plan | Verification Scorecard |

---

## 2. Decision Summary Table

One compact table at the top of the report. Capped at 8-12 items. Each row links to its detailed section via anchor.

| Column | Content |
|---|---|
| Category | Do Now / Investigate / Needs Decision |
| Finding | Short title (linked to detailed section) |
| Target Owner | Who should own the work (not current owner) |
| Confidence / Readiness | Standardized vocabulary (see below) |
| Effort | Low / Medium / High |
| Risk | Low / Medium / High |
| Primary Expected Outcome | Varies by category (see rules below) |
| Next Action | Execution pointer |

**Confidence / Readiness vocabulary:**
- `High / PR-Ready` — Do Now items
- `Medium / Stage 1` — Investigate items
- `High / Decision Pending` — Needs Decision items

**Primary Expected Outcome rules by category:**
- **Do Now:** Primary success outcome aligned to finding type — incident reduction for noise tuning (e.g., "Raw incidents ~208 -> ~10"), median duration for auto_close fixes (e.g., "Median open duration < 24h"), owner/channel coverage for routing fixes (e.g., "Correct squad label on 2 policies")
- **Investigate:** Stage 1 closure result (e.g., "Hypothesis confirmed/refuted; follow-up created")
- **Needs Decision:** Decision closure (e.g., "Alerting strategy chosen by deadline")

**Sort order:** Do Now by impact descending, Investigate by urgency, Needs Decision by deadline ascending.

**No Status column.** The report is a static analysis artifact. If maintained as a live tracker, Status can be added, but that is not the default.

---

## 3. Do Now Finding Schema

Replaces the current High-Confidence per-item template.

```markdown
### {N}. {Action}: {policy_name} [High / PR-Ready]

**Policy ID:** projects/{project}/alertPolicies/{id} | **Condition:** {condition_name}
**Target Owner:** {current_label} -> {target_team}
**Scope:** {projects affected}
**Notification Reach:** {N} channels

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
- **Primary:** {numeric, time-bounded} (e.g., "raw incidents < 15 within 14d")
- **Guardrail:** {what must NOT degrade} (e.g., "no genuine backlog > 1000 goes undetected")

**Rollback Signal:** {derived threshold + timeframe for revert}
**Related:** {cross-references to other findings or systemic issues}
```

### Do Now Gate — all required

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
|---|---|---|
| **Confirmed** | Exact file path verified | Yes |
| **Likely** | Strong candidate path, search path explicit | Yes |
| **Search Required** | Must include ALL four: (1) likely repo/module hint, (2) policy ID as search token, (3) unique PromQL fragment, (4) exact replacement guidance | Yes |
| **Unknown** | Cannot identify owning repo/file | No — drops to Investigate |

### PromQL Change Spec Rules

- **Simple edits** (scalar threshold, window, auto_close): show exact current and proposed fragment
- **Complex edits** (multi-clause PromQL, aggregation changes): show full affected clause or precise change spec
- Never rely on blind copy-paste as the standard; aim for exact replacement guidance

---

## 4. Investigate Finding Schema

Replaces the current Medium-Confidence per-item template. Uses a two-stage DoD to prevent parking-lot investigations.

```markdown
### {N}. {investigation_title} [{confidence} / Stage 1]

**Policy ID:** projects/{project}/alertPolicies/{id}
**Target Owner:** {team}
**Scope:** {projects affected}
**Notification Reach:** {N} channels

**Situation:** {what is happening — 1-2 sentences}
**Impact:** {why it matters — incident counts, team effect}
**Hypothesis:** {explicit, testable hypothesis}

**Stage 1 DoD (Discovery — this ticket):**
- {specific diagnostic steps}
- **Closes when:** hypothesis confirmed/refuted AND follow-up action documented as a separate item
- **Timebox:** {N} days

**Stage 2 (Execution — spawned follow-up):**
- **If confirmed:** {specific action with its own numeric outcome DoD}
- **If refuted:** {alternative action or close with rationale}

**Evidence Basis:** {measured|structural|heuristic} — {current evidence}
**To Upgrade:** {specific step that would make this item Do Now-ready (e.g., locate IaC path, assign owner, validate metric baseline)}
```

### Two-Stage DoD Rules

- Stage 1 closes on hypothesis confirmed/refuted + explicit next action documented
- Stage 2 is a completely separate follow-up item with its own numeric, time-bounded outcome DoD
- This prevents mixing discovery work with delivery work in a single ticket

### Structurally Proven but Not-Yet-PR-Ready Items

Items with structural or measured evidence that fail the Do Now gate (e.g., missing IaC location, missing owner) land in Investigate with their full evidence preserved. The `To Upgrade` field states exactly which gate requirement is missing. Stage 1 for these items is not hypothesis validation — it is resolving the missing gate requirement (e.g., "locate IaC path," "assign owner"). Once resolved, the item can be promoted to Do Now in the next report cycle or follow-up.

---

## 5. Needs Decision Schema

Replaces the current Needs Analyst Input template. Enforces closure to prevent the parking-lot effect.

```markdown
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

---

## 6. Verification Model

### Per Do Now Finding

Each Do Now item includes:
- **Pre-change Evidence** — why we believe the alert is miscalibrated (finding-specific)
- **Outcome DoD** — Primary Success Metric + Guardrail Metric (finding-specific, numeric, time-bounded)
- **Rollback Signal** — derived threshold for revert (finding-specific)

### Report-Level

**Global Implementation Standard** — appears once at the top of the Do Now section:

> For all Do Now items, the following standard applies:
> 1. IaC PR is approved and merged
> 2. Engineer confirms via GCP Monitoring Console that **every mutated field** matches the proposed config in production:
>    - For threshold/query changes: verify PromQL condition, thresholds, eval window, auto_close
>    - For routing/label changes: verify squad/team labels, notification channels
>    - For scope changes: verify project/resource selectors
> 3. Confirm no accidental changes to fields outside the change spec (scope, channels, labels, conditions)
> 4. Record merge date for 14-day outcome review

Per-finding Immediate Verification is added only when the verification steps are **non-obvious or high-risk** (scope moves across projects, duplicate policy consolidation, multi-policy edits, channel rewiring).

**Verification Scorecard** — rolled-up table at report level:

| Finding | Baseline | Target | Owner | Merge Date | Review Date | Primary Success Criteria | Guardrail | Confidence |
|---------|----------|--------|-------|------------|-------------|--------------------------|-----------|------------|

### Metric Families by Finding Type

| Finding type | Primary metric | Guardrail metric |
|---|---|---|
| Noise tuning | Raw incidents or open-incident hours | Detection latency for real incidents |
| auto_close fixes | Median open duration | N/A when change cannot hide signal |
| Routing/ownership | Correct owner/channel coverage | No alert dropped during transition |
| Orphaned alerts | Explicit close/remove/route decision | N/A |
| Coverage gaps | Implementation milestone | N/A |

Guardrail thresholds must be derived from evidence, not arbitrary. Guardrail = N/A only when the change cannot plausibly hide a real signal.

---

## 7. Systemic Issues Section

Consolidates current Label/Scope Inconsistencies and Coverage Gaps into one themed section. This section is **thematic and non-exhaustive** — it surfaces structural debt patterns without duplicating the detailed findings.

### Ownership/Routing Debt
- Unlabeled policies ranked by incident volume (source: `unlabeled_ranking` from compute-clusters)
- Misrouted alerts (e.g., prod alerts labeled as staging)

### Dead/Orphaned Config
- Zero-channel policies (no notification path)
- Disabled-but-still-noisy policies

### Missing Coverage
- From Coverage Gap Checklist comparison against `metric_types_in_inventory`
- Each gap cross-references existing noisy clusters it would detect upstream

### Inventory Health
- Silent policy ratio (zero incidents in analysis window)
- Condition type breakdown (PromQL vs conditionThreshold vs MQL)
- Enabled/disabled counts

---

## 8. What Changes in SKILL.md

### Changes required

| SKILL.md area | Current | Proposed change |
|---|---|---|
| Report Skeleton (Stage 5) | Confidence bands + Track A/B | Do Now / Investigate / Needs Decision + Decision Summary |
| Per-Item Template | Observed/Inferred/Evidence + Action list | Config Diff & Derivation table + Pre-change Evidence + Outcome DoD |
| Confidence Levels table | High/Medium/Low -> band assignment | High/Medium/Low -> readiness label + Do Now gate check |
| Stage 5 instructions | "Group by confidence band" | "Group by action class; apply Do Now gate" |
| Verification Plan section | Report-level expected results | Verification Scorecard with primary + guardrail per finding |
| Label/Scope Inconsistencies | Standalone section | Merged into Systemic Issues: Ownership/Routing Debt |
| Coverage Gaps | Standalone section | Merged into Systemic Issues: Missing Coverage |

### No changes required

| Area | Reason |
|---|---|
| Stages 0-2 (data pipeline) | Data extraction is unchanged |
| Stage 3 (prescriptive reasoning) | Pattern/alert-type reasoning unchanged; threshold-aware prescriptions already added |
| Stage 3b (metric validation) | Metric validation logic unchanged |
| Stage 4 (coverage gap check) | Logic unchanged; output moves to Systemic Issues |
| Python scripts | No script changes |
| Evidence basis levels | measured/structural/heuristic unchanged |
| Action types | Tune/Fix/Redesign/Add/No action unchanged |
| Prescriptive reasoning templates | By-pattern and by-alert-type templates unchanged |
| Methodology section | Unchanged |
| Definitions section | Add open-incident hours definition; existing terms unchanged |
| Keep section | Unchanged |
| Appendices | Unchanged |

---

## 9. Acceptance Criteria

- A lead can triage the report in under 30 seconds from the Decision Summary table
- An engineer can open a PR from any Do Now item without asking another question
- A reviewer can see why each proposed value was chosen (Derivation column)
- A 14-day follow-up can verify outcomes numerically from the Verification Scorecard
- High-confidence but underspecified findings are prevented from entering Do Now
- Heuristic-only evidence never appears in Do Now
- Every Investigate item has a bounded Stage 1 and an explicit Stage 2 path
- Every Needs Decision item has a named owner and a default recommendation
- No finding in the report lacks a closure path

---

## 10. Assumptions

- Primary audience is operators; leads are secondary readers
- The monitoring project may be analyzed separately from the infra repo — Search Required is a valid Do Now state
- Modeled impact is useful when clearly labeled with scope and confidence, but never overrides measured baselines
- Default Recommendation in Needs Decision is guidance, not automatic enforcement
- The report is a static analysis artifact (no Status column by default)
- Existing report enrichment (thresholds, metric types, unlabeled ranking from prior spec) is a prerequisite

---

## Files Changed

| File | Change |
|------|--------|
| Modify: `skills/alert-hygiene/SKILL.md` | Report Skeleton, Per-Item Template, Confidence Levels, Stage 5 instructions, new sections (Decision Summary, Systemic Issues, Verification Scorecard, Global Implementation Standard) |
| Modify: `tests/test-alert-hygiene-skill-content.sh` | Structural and behavioral contract assertions (see below) |

No new files created. No script changes.

### Test Coverage for Content Tests

Beyond updating string-presence assertions for renamed sections, the content tests must verify:

**Structural assertions (section presence):**
- Decision Summary section exists with column spec
- Do Now section references Global Implementation Standard
- Investigate section references two-stage DoD
- Needs Decision section references named owner + deadline + default recommendation
- Systemic Issues section with four subsections
- Verification Scorecard section exists
- Current Policy Snapshot referenced in Do Now template

**Behavioral contract assertions:**
- Do Now gate: all six gate requirements listed (config diff, owner, outcome DoD, evidence, rollback, IaC location)
- Heuristic exclusion: "heuristic alone never qualifies for Do Now" or equivalent
- IaC Location: all four statuses defined (Confirmed, Likely, Search Required, Unknown)
- Search Required: four required components listed (repo hint, policy ID, PromQL fragment, replacement guidance)
- Investigate: `structural` included in evidence basis options (not just measured|heuristic)
- Investigate: "To Upgrade" field references Do Now gate requirements
- Verification: "every mutated field" or equivalent generalized verification language
- Confidence/Readiness: standardized vocabulary present (PR-Ready, Stage 1, Decision Pending)
- Decision Summary: capped at 8-12 items
- Outcome rules: finding-type-aligned outcomes (not just incident reduction)

---

## Out of Scope

- Data pipeline changes (Stages 0-2, Python scripts)
- Prescriptive reasoning template changes (Stage 3)
- Metric validation changes (Stage 3b)
- CI/CD automation for scheduled report generation
- Automatic Jira ticket creation
- Real toil measurement from Slack/PagerDuty data
- Noise budget operating rules