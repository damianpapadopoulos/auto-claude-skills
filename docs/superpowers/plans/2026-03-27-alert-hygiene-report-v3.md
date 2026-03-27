# Alert Hygiene Report v3 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the alert-hygiene report from confidence-band grouping into action-class structure (Do Now / Investigate / Needs Decision) with strict gating, two-stage investigation DoDs, and a verification scorecard.

**Architecture:** All changes are in SKILL.md (report template and classification instructions) and the content test file. The data pipeline (scripts, Stages 0-3b, Stage 4) is unchanged. The report skeleton, per-item templates, confidence levels, and several section names are replaced.

**Tech Stack:** Markdown (SKILL.md), Bash tests.

---

## File Structure

| File | Responsibility |
|------|---------------|
| Modify: `skills/alert-hygiene/SKILL.md` | Report Skeleton, Per-Item Templates, Confidence/Readiness levels, Stage 5 instructions, new sections |
| Modify: `tests/test-alert-hygiene-skill-content.sh` | Structural and behavioral contract assertions |

---

## Task 1: Write failing content tests for new report structure (RED phase)

**Files:**
- Modify: `tests/test-alert-hygiene-skill-content.sh`

- [ ] **Step 1: Replace old section-presence assertions with new v3 assertions**

In `tests/test-alert-hygiene-skill-content.sh`, replace lines 34-37 (confidence-grouped output):

```bash
# --- Confidence-grouped output ---
assert_contains "high confidence section" "High-Confidence Actions" "${SKILL_CONTENT}"
assert_contains "medium confidence section" "Medium-Confidence Actions" "${SKILL_CONTENT}"
assert_contains "analyst input section" "Needs Analyst Input" "${SKILL_CONTENT}"
```

With:

```bash
# --- Action-class grouped output (v3) ---
assert_contains "do now section" "Actionable Findings: Do Now" "${SKILL_CONTENT}"
assert_contains "investigate section" "Actionable Findings: Investigate" "${SKILL_CONTENT}"
assert_contains "needs decision section" "Needs Decision" "${SKILL_CONTENT}"
assert_contains "decision summary section" "Decision Summary" "${SKILL_CONTENT}"
assert_contains "systemic issues section" "Systemic Issues" "${SKILL_CONTENT}"
```

- [ ] **Step 2: Replace Track A/B assertions with Decision Summary assertions**

Replace lines 83-84:

```bash
assert_contains "dual track A" "Track A" "${SKILL_CONTENT}"
assert_contains "dual track B" "Track B" "${SKILL_CONTENT}"
```

With:

```bash
# --- Decision Summary table columns ---
assert_contains "summary category column" "Category" "${SKILL_CONTENT}"
assert_contains "summary target owner column" "Target Owner" "${SKILL_CONTENT}"
assert_contains "summary readiness column" "Confidence / Readiness" "${SKILL_CONTENT}"
assert_contains "summary expected outcome column" "Primary Expected Outcome" "${SKILL_CONTENT}"
assert_contains "summary next action column" "Next Action" "${SKILL_CONTENT}"
assert_contains "summary cap rule" "8-12" "${SKILL_CONTENT}"
assert_contains "summary selection rule" "non-empty category" "${SKILL_CONTENT}"
```

- [ ] **Step 3: Replace Verification Plan assertion with Verification Scorecard**

Replace line 86:

```bash
assert_contains "verification plan" "Verification Plan" "${SKILL_CONTENT}"
```

With:

```bash
assert_contains "verification scorecard" "Verification Scorecard" "${SKILL_CONTENT}"
assert_contains "global implementation standard" "Global Implementation Standard" "${SKILL_CONTENT}"
assert_contains "every mutated field" "every mutated field" "${SKILL_CONTENT}"
```

- [ ] **Step 4: Replace per-item template field assertions**

Replace lines 69-78:

```bash
# --- Per-item template fields ---
assert_contains "observed/inferred split" "Observed:" "${SKILL_CONTENT}"
assert_contains "inferred field" "Inferred:" "${SKILL_CONTENT}"
assert_contains "evidence basis field" "Evidence basis:" "${SKILL_CONTENT}"
assert_contains "owner routing field" "Owner:" "${SKILL_CONTENT}"
assert_contains "policy ID field" "Policy ID:" "${SKILL_CONTENT}"
assert_contains "notification reach field" "Notification reach:" "${SKILL_CONTENT}"
assert_contains "risk of change field" "Risk of change:" "${SKILL_CONTENT}"
assert_contains "rollback signal field" "Rollback signal:" "${SKILL_CONTENT}"
assert_contains "impact derivation field" "Impact derivation:" "${SKILL_CONTENT}"
assert_contains "to upgrade field for medium" "To upgrade:" "${SKILL_CONTENT}"
```

With:

```bash
# --- Do Now per-item template fields (v3) ---
assert_contains "policy ID field" "Policy ID:" "${SKILL_CONTENT}"
assert_contains "target owner field" "Target Owner:" "${SKILL_CONTENT}"
assert_contains "scope field" "Scope:" "${SKILL_CONTENT}"
assert_contains "notification reach field" "Notification Reach:" "${SKILL_CONTENT}"
assert_contains "current policy snapshot" "Current Policy Snapshot" "${SKILL_CONTENT}"
assert_contains "iac location field" "IaC Location:" "${SKILL_CONTENT}"
assert_contains "config diff table" "Configuration Diff" "${SKILL_CONTENT}"
assert_contains "derivation column" "Derivation" "${SKILL_CONTENT}"
assert_contains "pre-change evidence field" "Pre-change Evidence:" "${SKILL_CONTENT}"
assert_contains "evidence basis field" "Evidence Basis:" "${SKILL_CONTENT}"
assert_contains "outcome dod field" "Outcome DoD:" "${SKILL_CONTENT}"
assert_contains "primary metric" "Primary:" "${SKILL_CONTENT}"
assert_contains "guardrail metric" "Guardrail:" "${SKILL_CONTENT}"
assert_contains "rollback signal field" "Rollback Signal:" "${SKILL_CONTENT}"

# --- Investigate per-item template fields (v3) ---
assert_contains "hypothesis field" "Hypothesis:" "${SKILL_CONTENT}"
assert_contains "stage 1 dod" "Stage 1 DoD" "${SKILL_CONTENT}"
assert_contains "stage 2 follow-up" "Stage 2" "${SKILL_CONTENT}"
assert_contains "to upgrade field" "To Upgrade:" "${SKILL_CONTENT}"

# --- Needs Decision per-item template fields (v3) ---
assert_contains "decision required field" "Decision Required:" "${SKILL_CONTENT}"
assert_contains "named decision owner" "Named Decision Owner:" "${SKILL_CONTENT}"
assert_contains "deadline field" "Deadline:" "${SKILL_CONTENT}"
assert_contains "default recommendation" "Default Recommendation:" "${SKILL_CONTENT}"
```

- [ ] **Step 5: Add Do Now gate behavioral contract assertions**

After the per-item template assertions, add:

```bash
# --- Do Now gate behavioral contract ---
assert_contains "do now gate" "Do Now Gate" "${SKILL_CONTENT}"
assert_contains "heuristic exclusion" "heuristic alone never qualifies for Do Now" "${SKILL_CONTENT}"
assert_contains "iac confirmed status" "Confirmed" "${SKILL_CONTENT}"
assert_contains "iac likely status" "Likely" "${SKILL_CONTENT}"
assert_contains "iac search required status" "Search Required" "${SKILL_CONTENT}"
assert_contains "iac unknown drops" "Unknown" "${SKILL_CONTENT}"
assert_contains "search req repo hint" "repo" "${SKILL_CONTENT}"
assert_contains "search req policy id" "policy ID" "${SKILL_CONTENT}"
assert_contains "search req replacement guidance" "replacement guidance" "${SKILL_CONTENT}"
```

- [ ] **Step 6: Add Investigate behavioral contract assertions**

```bash
# --- Investigate behavioral contract ---
assert_contains "investigate structural evidence" "measured|structural|heuristic" "${SKILL_CONTENT}"
assert_contains "two-stage dod rule" "Two-Stage DoD" "${SKILL_CONTENT}"
assert_contains "structurally proven gate-blocked" "Structurally Proven" "${SKILL_CONTENT}"
```

- [ ] **Step 7: Add Confidence/Readiness vocabulary assertions**

```bash
# --- Confidence/Readiness vocabulary ---
assert_contains "pr-ready readiness" "PR-Ready" "${SKILL_CONTENT}"
assert_contains "high stage 1 readiness" "High / Stage 1" "${SKILL_CONTENT}"
assert_contains "medium stage 1 readiness" "Medium / Stage 1" "${SKILL_CONTENT}"
assert_contains "decision pending readiness" "Decision Pending" "${SKILL_CONTENT}"
```

- [ ] **Step 8: Add Systemic Issues subsection assertions**

```bash
# --- Systemic Issues subsections ---
assert_contains "ownership routing debt" "Ownership/Routing Debt" "${SKILL_CONTENT}"
assert_contains "dead orphaned config" "Dead/Orphaned Config" "${SKILL_CONTENT}"
assert_contains "missing coverage" "Missing Coverage" "${SKILL_CONTENT}"
assert_contains "inventory health" "Inventory Health" "${SKILL_CONTENT}"
```

- [ ] **Step 9: Add metric families and open-incident hours assertions**

```bash
# --- Verification metric families ---
assert_contains "metric family noise" "Noise tuning" "${SKILL_CONTENT}"
assert_contains "metric family auto_close" "auto_close fixes" "${SKILL_CONTENT}"
assert_contains "metric family routing" "Routing/ownership" "${SKILL_CONTENT}"
assert_contains "finding-type-aligned outcome" "aligned to finding type" "${SKILL_CONTENT}"

# --- Definitions additions ---
assert_contains "open-incident hours defined" "open-incident hours" "${SKILL_CONTENT}"
```

- [ ] **Step 10: Run tests to verify they fail**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: FAIL — SKILL.md still has old structure (High-Confidence Actions, Track A/B, etc.)

---

## Task 2: Update SKILL.md Stage 5 instruction and Confidence Levels (GREEN phase, part 1)

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Replace Stage 5 instruction**

Replace line 227-229:

```markdown
### Stage 5: Produce Report

Write the final report as markdown using the Report Skeleton template below. Group by confidence band, not by action type.
```

With:

```markdown
### Stage 5: Produce Report

Write the final report as markdown using the Report Skeleton template below. Group findings by action class (Do Now / Investigate / Needs Decision), not by confidence band. Apply the Do Now Gate to determine which items qualify for the Do Now section. Items that fail the gate drop to Investigate regardless of confidence level.
```

- [ ] **Step 2: Replace Confidence Levels table**

Replace lines 333-339 (the Confidence Levels section):

```markdown
## Confidence Levels

| Level | Criteria | How to flag |
|-------|----------|-------------|
| High | Frequency pattern AND metric validation agree, or structural flaw is unambiguous (e.g., auto_close NOT SET with permanent-fire condition) | State recommendation directly. Evidence basis must be `measured` or `structural`. |
| Medium | Verdict based on frequency pattern only (no metric validation performed) | State recommendation, note "based on incident pattern only — validate {specific metric query} before applying". Add **To upgrade:** field with the specific diagnostic step. |
| Low | Data insufficient, inference from time-of-day concentration alone, or evidence contradicts | State recommendation with explicit inline flag: *"Low confidence — verify X before applying"*. Move to Needs Analyst Input if intent is ambiguous. |
```

With:

```markdown
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
```

- [ ] **Step 3: Run tests to check partial progress**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: Some new assertions now pass (readiness vocabulary, heuristic exclusion). Section-level assertions still fail.

---

## Task 3: Replace Per-Item Template and add Do Now Gate (GREEN phase, part 2)

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Replace the Report Structure preamble**

Replace lines 341-348:

```markdown
## Report Structure

The report is grouped by confidence band, not by verdict type. This lets the user act immediately on high-confidence items while knowing which items need their judgment. The Priority Order appears early (BLUF — Bottom Line Up Front) so an engineering manager can approve the top actions within 30 seconds.

### Per-Item Template

Every cluster item — in any confidence band — uses this standardized block. The structure must be scannable: a reviewer skimming headers and bold fields should understand the recommendation without reading prose.
```

With:

```markdown
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

### Do Now Per-Item Template
```

- [ ] **Step 2: Replace the old per-item template block**

Replace lines 349-382 (the old per-item template and its Medium/Analyst variants):

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
```

With the three new per-item templates:

````markdown
```
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
````

- [ ] **Step 3: Run tests to check progress**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: Per-item template assertions and gate assertions should now pass. Report skeleton assertions still fail.

---

## Task 4: Replace Report Skeleton (GREEN phase, part 3)

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Replace the Report Skeleton**

Replace lines 384-489 (the entire Report Skeleton code block, from `### Report Skeleton` through the closing ` ``` `):

````markdown
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

## Decision Summary
Capped at 8-12 items. Every non-empty category gets at least 1 row. After minimum representation, remaining rows filled in global priority order: Do Now by impact, then Investigate by urgency, then Needs Decision by deadline.

| Category | Finding | Target Owner | Confidence / Readiness | Effort | Risk | Primary Expected Outcome | Next Action |
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
- Zero-channel policies (no notification path)
- Disabled-but-still-noisy policies

### Missing Coverage
Coverage gaps from comparison of `metric_types_in_inventory` against Coverage Gap Checklist:

| Gap | Action | Implementation | Rationale | Upstream Signal For |
(last column cross-references existing clusters this gap would detect earlier)

### Inventory Health
- Silent policy ratio (zero incidents in analysis window)
- Condition type breakdown (PromQL vs conditionThreshold vs MQL)
- Enabled/disabled counts

## Actionable Findings: Do Now

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

### 1. {investigation_title} [{High|Medium} / Stage 1]
(Investigate per-item template with Two-Stage DoD)

## Needs Decision

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
````

- [ ] **Step 2: Update the Key Terms section to add open-incident hours**

In the Key Terms section (line 321-331), add a row to the table after the `Evidence basis` row:

```markdown
| **Open-incident hours** | Sum of all incident durations in the analysis window, measured in hours. Captures both volume and persistence. |
```

- [ ] **Step 3: Update the Latency alerts reference from "Needs Analyst Input" to "Needs Decision"**

Replace in the Latency alerts section (line 290):

```markdown
- If the alert has high noise_score: route to **Needs Analyst Input** as SLO-redesign candidate.
```

With:

```markdown
- If the alert has high noise_score: route to **Needs Decision** as SLO-redesign candidate.
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: All new assertions pass. Check for any remaining old assertions that reference removed content.

---

## Task 5: Remove the old Action Types table and update remaining references (GREEN phase, part 4)

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Remove the standalone Action Types section**

Delete lines 491-501 (the Action Types section after the report skeleton). This table duplicates the Action Type Legend already inside the report skeleton. Keep only the one inside the skeleton.

```markdown
## Action Types

Each cluster gets one of these action types (can appear in any confidence band). Include the Action Type Legend in every report for reviewer reference.

| Action | Meaning | Default Confidence Band |
|--------|---------|------------------------|
| **Tune the alert** | The alert is miscalibrated. Specific config changes listed (threshold, duration, auto_close, volume floor, mute window). | High or Medium (depends on evidence basis) |
| **Fix the underlying issue** | The alert is correct. The service has a real problem. Investigation pointers provided. | High or Medium |
| **Redesign around SLO** | Replace threshold alerting with burn-rate/error-budget alerting. | Needs Analyst Input (unless user-facing criticality and current baseline are proven) |
| **Add/extend coverage** | A high-value blind spot exists or current coverage is scoped incorrectly. | Medium (unless gap is linked to existing incident cluster) |
| **No action** | Well-calibrated, low-frequency. Keep as-is. | High (report in Keep section) |
```

- [ ] **Step 2: Run full content test suite**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: PASS — all assertions pass.

- [ ] **Step 3: Run full test suite to verify no regressions**

Run: `bash tests/run-tests.sh`
Expected: All test files pass.

- [ ] **Step 4: Commit all changes**

```bash
git add skills/alert-hygiene/SKILL.md tests/test-alert-hygiene-skill-content.sh
git commit -m "feat(alert-hygiene): restructure report to Do Now / Investigate / Needs Decision

Report v3: action-class structure replaces confidence-band grouping.

- Decision Summary table (8-12 items, lead-facing, anchor-linked)
- Do Now gate: config diff + derivation + owner + outcome DoD + evidence + IaC location
- Investigate: two-stage DoD (bounded discovery + separate execution follow-up)
- Needs Decision: named owner + advisory deadline + default recommendation
- Verification Scorecard with primary + guardrail metrics per finding
- Systemic Issues consolidates ownership debt, dead config, coverage gaps, inventory health
- Global Implementation Standard for immediate verification
- Heuristic evidence alone never qualifies for Do Now
- IaC Location: Confirmed / Likely / Search Required / Unknown
- Confidence/Readiness vocabulary: PR-Ready, High/Medium Stage 1, Decision Pending
- Open-incident hours added to Definitions"
```

---

## Self-Review Checklist

| Spec requirement | Implementing task |
|---|---|
| Report Skeleton restructured (Do Now/Investigate/Needs Decision) | Task 4 |
| Decision Summary table with columns, cap, selection rule | Task 4 (skeleton) |
| Do Now Gate with 6 requirements | Task 3 |
| Do Now per-item template with Config Diff & Derivation | Task 3 |
| Heuristic exclusion from Do Now | Task 2 (Confidence Levels) + Task 3 (gate) |
| IaC Location rules (4 statuses) | Task 3 |
| Search Required definition (4 components) | Task 3 |
| PromQL Change Spec rules | Task 3 |
| Investigate template with Two-Stage DoD | Task 3 |
| Structurally Proven but Not-Yet-PR-Ready path | Task 3 |
| Needs Decision template with owner/deadline/default | Task 3 |
| Confidence/Readiness vocabulary | Task 2 |
| Verification Scorecard | Task 4 (skeleton) |
| Global Implementation Standard | Task 4 (skeleton) |
| Metric Families by Finding Type | Task 3 |
| Systemic Issues section (4 subsections) | Task 4 (skeleton) |
| Open-incident hours definition | Task 4 |
| Latency alerts reference updated | Task 4 |
| Content test structural assertions | Task 1 |
| Content test behavioral contract assertions | Task 1 |
| Finding-type-aligned outcomes | Task 3 (metric families) + Task 4 (summary rules) |
