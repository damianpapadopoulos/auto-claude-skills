# Alert Hygiene SKILL.md Review Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply 3 writing-skills review fixes to the alert-hygiene SKILL.md: add "When NOT to use" block, fix Stage 5 description drift, move Priority Order to BLUF position.

**Architecture:** Single-file edits to `skills/alert-hygiene/SKILL.md`. No script or test file changes needed — existing 57 assertions continue to pass since fixes only move/modify content that's tested by string presence. One task, one commit.

**Tech Stack:** Markdown only.

---

## File Structure

| File | Responsibility |
|------|---------------|
| Modify: `skills/alert-hygiene/SKILL.md` | 4 targeted edits (add block, replace line, move section, update intro) |

---

## Task 1: Apply 3 writing-skills review fixes

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md`

- [ ] **Step 1: Run tests to verify baseline**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: PASS — 57/57 assertions

- [ ] **Step 2: Add "When NOT to use" block**

After line 8 (the overview paragraph ending "...from data pull to final report."), before `## Behavioral Constraints`, insert:

```markdown
**When NOT to use:**
- Active incident investigation — use incident-analysis instead (tiered log investigation with mitigation playbooks)
- SLO design from scratch — this skill identifies SLO-redesign *candidates*, it does not design SLOs or generate burn-rate PromQL
- Multi-project analysis — v1 is scoped to one monitoring project per invocation
```

- [ ] **Step 3: Fix Stage 5 description**

Replace line 110:
```
Write the final report as markdown. Structure: Executive Summary, High-Confidence Actions, Medium-Confidence Actions, Needs Analyst Input, Coverage Gaps, Label Inconsistencies, Priority Order, Frequency Table appendix. Group by confidence band, not by action type.
```

With:
```
Write the final report as markdown using the Report Skeleton template below. Group by confidence band, not by action type.
```

- [ ] **Step 4: Update Report Structure intro for BLUF**

Replace line 224:
```
The report is grouped by confidence band, not by verdict type. This lets the user act immediately on high-confidence items while knowing which items need their judgment. The Priority Order appears after the action sections, summarizing the top changes and investigations in a scannable table.
```

With:
```
The report is grouped by confidence band, not by verdict type. This lets the user act immediately on high-confidence items while knowing which items need their judgment. The Priority Order appears early (BLUF — Bottom Line Up Front) so an engineering manager can approve the top actions within 30 seconds.
```

- [ ] **Step 5: Move Priority Order to BLUF position in Report Skeleton**

In the Report Skeleton code block, move the `## Recommended Priority Order` section (with Track A and Track B tables) from its current position after `## Label/Scope Inconsistencies` to after `## Action Type Legend`, before `## High-Confidence Actions`.

**Before (current order):**
```
## Action Type Legend
## High-Confidence Actions
## Medium-Confidence Actions
## Needs Analyst Input
## Coverage Gaps
## Label/Scope Inconsistencies
## Recommended Priority Order    <-- HERE
## Keep — No Action Required
```

**After (BLUF order):**
```
## Action Type Legend
## Recommended Priority Order    <-- MOVED HERE
## High-Confidence Actions
## Medium-Confidence Actions
## Needs Analyst Input
## Coverage Gaps
## Label/Scope Inconsistencies
## Keep — No Action Required
```

The section content (Track A table, Track B table) moves unchanged.

- [ ] **Step 6: Run tests to verify no regressions**

Run: `bash tests/test-alert-hygiene-skill-content.sh`
Expected: PASS — 57/57 assertions (no assertion relies on section ordering)

- [ ] **Step 7: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All 15 test files pass

- [ ] **Step 8: Commit**

```bash
git add skills/alert-hygiene/SKILL.md
git commit -m "fix(alert-hygiene): apply writing-skills review fixes to SKILL.md

- Add 'When NOT to use' block (incident-analysis, SLO design, multi-project)
- Move Priority Order to BLUF position in report skeleton
- Replace Stage 5 inline section list with Report Skeleton reference"
```
