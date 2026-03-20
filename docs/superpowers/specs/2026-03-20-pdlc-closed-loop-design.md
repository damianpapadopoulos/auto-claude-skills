# PDLC Closed-Loop Orchestration — Phase 1: DISCOVER + LEARN

**Date:** 2026-03-20
**Status:** Draft
**Scope:** Phase 1 of Option C — two new phases (DISCOVER, LEARN), two new skills (product-discovery, outcome-review), routing engine updates, registry changes

## Problem

The plugin covers BUILD → TEST → REVIEW → SHIP well but has no coverage for the two highest-value lifecycle phases identified by McKinsey's AI-enabled PDLC framework: upstream **discovery** (why/what to build) and downstream **learning** (did it work). This means the plugin answers "how do we build this safely?" but cannot answer "why are we building this?" or "did it actually work?"

## Design Decisions (locked)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Architecture | Option C: new bookend phases, proven middle unchanged | Preserves battle-tested PLAN→IMPLEMENT→REVIEW; adds value at the edges |
| Phase 1 scope | product-discovery + outcome-review | Upstream problem selection and downstream learning are the highest-value gaps |
| Phase 2 scope | instrumentation-plan + progressive-rollout (GrowthBook) | Rollout discipline; deferred until Phase 1 proves the loop |
| LEARN default | Report + recommend, explicit gate before Jira creation | Safe trust calibration; auto-create via config flag later |
| DISCOVER routing | Automatic triggers (high threshold) + `/discover` hard override | Natural-language activation without false positives |
| LEARN timing | Lightweight baseline after SHIP; full analysis on demand | Captures timestamp for comparison; real analysis needs data maturity |
| MCP dependencies | Graceful degradation: detect → enrich → fall back → never hard-fail | Matches existing posture (incident-analysis, unified-context-stack) |

## Lifecycle After Phase 1

```
DISCOVER → DESIGN → PLAN → IMPLEMENT → REVIEW → SHIP → LEARN
    ^                                                    |
    +----------------------------------------------------+
                    (follow-up Jira work)
```

The LEARN → DISCOVER feedback loop is the core value proposition: shipping creates follow-up work that feeds back into discovery.

## 1. New Skills

### 1.1 product-discovery

**Phase:** DISCOVER
**Role:** process
**Primary MCP:** Atlassian (Jira + Confluence)
**Fallback:** guided manual mode (prompt user to paste context)

**What it does:**
1. Queries Jira for relevant issues, acceptance criteria, and linked context
2. Queries Confluence for related design docs, ADRs, prior decisions
3. Synthesizes a **discovery brief**: problem statement, user pain points, prior art, success criteria, constraints
4. Presents the brief for user validation before transitioning to DESIGN

**Trigger patterns:**
```
"(discover|backlog|user.problem|pain.point|what.to.build|sprint.plan|prioriti|what.should.we|which.issue|triage|next.sprint|roadmap)"
```

**Keywords:**
```
["what should we build", "backlog review", "sprint planning", "discovery session", "problem statement", "user needs"]
```

**Priority:** 35 (above brainstorming's 30 — DISCOVER should win over DESIGN when discovery language is present)

**Precedes:** `["brainstorming"]` (flows into DESIGN)

**MCP tool usage:**
- `searchJiraIssuesUsingJql` — find issues by project, status, priority, labels
- `getJiraIssue` — pull acceptance criteria, description, comments, linked issues
- `searchConfluenceUsingCql` — find related design docs, ADRs
- `getConfluencePage` — read full doc content

**Graceful degradation:**
- If Atlassian MCP unavailable: prompt user to paste Jira ticket IDs or problem description; synthesize from pasted context
- If no Jira context found: proceed with prompt-driven discovery (current brainstorming behavior, but framed as discovery)

**Output artifact:** Discovery brief (markdown), presented in conversation. Not persisted to file unless user requests.

### 1.2 outcome-review

**Phase:** LEARN
**Role:** process
**Primary MCP:** PostHog + Atlassian
**Fallback:** guided manual mode (prompt user to check dashboards + paste findings)

**What it does:**
1. Queries PostHog for metrics related to the shipped feature: adoption, funnel performance, error rates, experiment results
2. Synthesizes an **outcome report**: what was shipped, what metrics moved, what regressed, what's inconclusive
3. Presents recommendations: "looks good — close the loop" vs "regression detected — investigate" vs "insufficient data — revisit in N days"
4. On user approval, creates follow-up Jira issues for regressions or next iterations (gated, not automatic)

**Trigger patterns:**
```
"(how.did.*(perform|do|go|work)|outcome|metric|adoption|result|funnel|cohort|experiment.result|feature.impact|post.launch|post.ship|learn|retro(?!spective)|measure)"
```

**Keywords:**
```
["how did it perform", "check metrics", "feature impact", "post-launch review", "did it work", "adoption metrics"]
```

**Priority:** 30

**Requires:** `[]` (no chain dependency — LEARN can be entered independently, days after shipping)

**Precedes:** `["brainstorming"]` (follow-up work feeds back into DISCOVER/DESIGN)

**MCP tool usage (PostHog):**
- `query-run` with HogQL — adoption metrics, event counts, error rates
- `get-experiment` / `list-experiments` — experiment results if applicable
- `get-feature-flag` — flag status, rollout percentage
- `create-annotation` — mark ship events on timelines

**MCP tool usage (Atlassian):**
- `createJiraIssue` — create follow-up tickets (gated by user approval)
- `addCommentToJiraIssue` — annotate original ticket with outcome summary

**Graceful degradation:**
- If PostHog MCP unavailable: prompt user to paste metrics or dashboard screenshots; synthesize from pasted data
- If Atlassian MCP unavailable: output follow-up recommendations as text; user creates tickets manually

**LEARN timing behavior:**
- **Auto-baseline after SHIP:** When SHIP phase completes, write a lightweight baseline artifact to `~/.claude/.skill-learn-baseline-{session}` containing: feature name, ship timestamp, key metric names. This enables later LEARN invocations to compare against baseline. The baseline write is a PostHog annotation + local file, NOT a full metrics analysis.
- **Full analysis on demand:** When user revisits with "how did X perform?" or triggers LEARN explicitly, the skill runs the full outcome analysis against the baseline.

## 2. Routing Engine Changes

### 2.1 New phases in phase_guide

```json
"phase_guide": {
  "DISCOVER": "product-discovery (pull Jira/Confluence context, synthesize discovery brief)",
  "DESIGN": "brainstorming (ask questions, get approval)",
  "PLAN": "writing-plans (break into tasks, confirm before execution)",
  "IMPLEMENT": "executing-plans or subagent-driven-development",
  "REVIEW": "requesting-code-review",
  "SHIP": "verification-before-completion + openspec-ship + finishing-a-development-branch",
  "LEARN": "outcome-review (query metrics, synthesize outcome report, create follow-up work)",
  "DEBUG": "systematic-debugging, then return to current phase"
}
```

### 2.2 New phase_compositions

```json
"DISCOVER": {
  "driver": "product-discovery",
  "parallel": [
    {
      "plugin": "atlassian",
      "use": "mcp:searchJiraIssuesUsingJql + getConfluencePage",
      "when": "installed",
      "purpose": "Pull problem context, acceptance criteria, related design docs from Jira and Confluence"
    },
    {
      "plugin": "unified-context-stack",
      "use": "tiered context retrieval (Historical Truth, Intent Truth)",
      "when": "installed AND any context_capability is true",
      "purpose": "Check past decisions and existing specs before discovery synthesis"
    }
  ],
  "hints": [
    {
      "plugin": "atlassian",
      "text": "ATLASSIAN: Pull Jira issues and Confluence docs to ground discovery in real backlog context.",
      "when": "installed"
    }
  ]
},
"LEARN": {
  "driver": "outcome-review",
  "parallel": [
    {
      "plugin": "posthog",
      "use": "mcp:query-run + get-experiment + create-annotation",
      "when": "installed",
      "purpose": "Query adoption metrics, experiment results, and annotate ship events"
    },
    {
      "plugin": "atlassian",
      "use": "mcp:createJiraIssue + addCommentToJiraIssue",
      "when": "installed AND user approves follow-up creation",
      "purpose": "Create follow-up tickets and annotate original issues with outcome data"
    }
  ],
  "hints": []
}
```

### 2.3 New plugin entries

```json
{
  "name": "posthog",
  "source": "mcp-server",
  "provides": {
    "commands": [],
    "skills": [],
    "agents": [],
    "hooks": [],
    "mcp_tools": [
      "query-run",
      "get-experiment",
      "list-experiments",
      "get-feature-flag",
      "list-feature-flags",
      "create-annotation"
    ]
  },
  "phase_fit": ["LEARN", "SHIP", "DEBUG"],
  "description": "PostHog analytics, experiments, and feature flags via MCP. Query adoption metrics, experiment results, and error rates."
}
```

### 2.4 New methodology hints

```json
{
  "name": "posthog-metrics",
  "triggers": [
    "(metric|adoption|funnel|cohort|experiment|feature.flag|a.?b.test|conversion|retention|churn|engagement|posthog)"
  ],
  "trigger_mode": "regex",
  "hint": "POSTHOG: If PostHog MCP tools are available, query analytics and experiment results directly. Use outcome-review skill for structured post-ship analysis.",
  "phases": ["LEARN", "SHIP", "DEBUG"]
}
```

### 2.5 Composition chain integration

The DISCOVER → DESIGN link works via `precedes`:
- product-discovery.precedes = `["brainstorming"]`
- When the user is in DISCOVER and completes the discovery brief, the composition chain naturally advances to brainstorming

The SHIP → LEARN link works via the baseline artifact:
- SHIP's finishing-a-development-branch completes the chain
- outcome-review has NO `requires` dependency on SHIP (it can be entered independently days later)
- The SHIP composition's final step writes the baseline artifact that LEARN later reads

### 2.6 Label updates in _determine_label_phase

Add to the `process` case in `_determine_label_phase`:

```bash
product-discovery)            PLABEL="Discover" ;;
outcome-review)               PLABEL="Learn / Measure" ;;
```

### 2.7 SHIP baseline artifact

After `finishing-a-development-branch` completes in the SHIP composition, write:

```json
// ~/.claude/.skill-learn-baseline-{session}
{
  "feature": "<feature name from plan>",
  "shipped_at": "<ISO timestamp>",
  "branch": "<branch name>",
  "spec_path": "<path to openspec doc if exists>",
  "suggested_metrics": ["<list from plan/spec if available>"]
}
```

This is consumed by outcome-review when LEARN is invoked later. The file is session-scoped and lightweight.

## 3. Registry Changes

### 3.1 default-triggers.json

Add two new skill entries to the `skills` array:

```json
{
  "name": "product-discovery",
  "role": "process",
  "phase": "DISCOVER",
  "triggers": [
    "(discover|backlog|user.problem|pain.point|what.to.build|sprint.plan|prioriti|what.should.we|which.issue|triage|next.sprint|roadmap)"
  ],
  "keywords": [
    "what should we build",
    "backlog review",
    "sprint planning",
    "discovery session",
    "problem statement",
    "user needs"
  ],
  "trigger_mode": "regex",
  "priority": 35,
  "precedes": ["brainstorming"],
  "requires": [],
  "description": "Pull Jira/Confluence context, synthesize discovery brief, validate problem framing before design.",
  "invoke": "Skill(auto-claude-skills:product-discovery)"
},
{
  "name": "outcome-review",
  "role": "process",
  "phase": "LEARN",
  "triggers": [
    "(how.did.*(perform|do|go|work)|outcome|metric|adoption|result|funnel|cohort|experiment.result|feature.impact|post.launch|post.ship|learn(?!ing)|measure|did.it.work)"
  ],
  "keywords": [
    "how did it perform",
    "check metrics",
    "feature impact",
    "post-launch review",
    "did it work",
    "adoption metrics"
  ],
  "trigger_mode": "regex",
  "priority": 30,
  "precedes": ["brainstorming"],
  "requires": [],
  "description": "Query PostHog metrics, synthesize outcome report, create follow-up Jira work (gated). Entered independently post-ship.",
  "invoke": "Skill(auto-claude-skills:outcome-review)"
}
```

### 3.2 fallback-registry.json

Mirror the same entries with `"available": true, "enabled": true`.

### 3.3 Atlassian plugin phase_fit update

Extend the existing atlassian plugin entry:

```json
"phase_fit": ["DISCOVER", "DESIGN", "PLAN", "REVIEW", "LEARN"]
```

### 3.4 Existing Jira/Confluence methodology hints

Extend the `atlassian-jira` hint phases to include DISCOVER:

```json
"phases": ["DISCOVER", "DESIGN", "PLAN"]
```

Add DISCOVER triggers to the existing Jira hint:

```json
"triggers": ["(ticket|story|epic|acceptance.criter|definition.of.done|requirement|user.story|jira|sprint|backlog|discover|triage|prioriti)"]
```

## 4. Slash Command Entry Points

`/discover` and `/learn` should be explicit command-style entry points that force phase selection without depending on trigger scoring. These are implemented as skill invocations:

- `/discover` → `Skill(auto-claude-skills:product-discovery)`
- `/learn` → `Skill(auto-claude-skills:outcome-review)`

These bypass the activation hook entirely (slash commands are already excluded by the hook's early exit: `[[ "$PROMPT" =~ ^[[:space:]]*/ ]] && exit 0`).

## 5. Skill File Structure

```
skills/
  product-discovery/
    SKILL.md          # Main skill definition
  outcome-review/
    SKILL.md          # Main skill definition
```

Both skills follow the existing pattern: YAML frontmatter + markdown body with structured instructions.

## 6. Test Plan

### 6.1 Routing tests (test-routing.sh)

- DISCOVER trigger scoring: "what should we build next sprint" → product-discovery selected
- DISCOVER trigger scoring: "review the backlog for prioritization" → product-discovery selected
- DISCOVER vs DESIGN disambiguation: "build a new auth service" → brainstorming (DESIGN), NOT discovery
- LEARN trigger scoring: "how did the auth feature perform" → outcome-review selected
- LEARN trigger scoring: "check metrics for last release" → outcome-review selected
- LEARN vs DEBUG disambiguation: "something is wrong with metrics" → systematic-debugging (DEBUG), NOT learn
- Composition chain: product-discovery → brainstorming → writing-plans (full forward walk)
- `/discover` slash command: early exit, no hook activation (existing behavior)

### 6.2 Registry tests (test-registry.sh)

- New skills present in default-triggers.json with correct phase, role, triggers
- New skills present in fallback-registry.json with available/enabled flags
- PostHog plugin entry present with correct MCP tools
- Phase guide includes DISCOVER and LEARN entries
- Phase compositions include DISCOVER and LEARN entries

### 6.3 Context tests (test-context.sh)

- DISCOVER phase composition renders correct parallel hints
- LEARN phase composition renders correct parallel hints
- Label display: "Discover" for product-discovery, "Learn / Measure" for outcome-review

## 7. Out of Scope (Phase 2)

- **instrumentation-plan** skill (PLAN enrichment, requires GrowthBook MCP)
- **progressive-rollout** skill (SHIP enrichment, requires GrowthBook MCP)
- GrowthBook plugin entry and methodology hints
- SHIP composition changes for rollout mechanics
- Auto-create Jira work in LEARN (Phase 1 is gated; auto-create is a config flag for later)

## 8. Risk & Mitigations

| Risk | Mitigation |
|------|------------|
| DISCOVER false positives from casual "backlog" mentions | High-threshold triggers + `/discover` hard override |
| LEARN "learn" substring matches "learning" in normal text | Regex uses negative lookahead: `learn(?!ing)` |
| PostHog MCP not installed for most users | Graceful degradation to guided manual mode |
| Baseline artifact from SHIP gets stale | Session-scoped file; LEARN skill checks age and warns if >30 days |
| DISCOVER → DESIGN transition unclear | Composition chain shows `[NEXT] brainstorming`; directive says "invoke brainstorming after discovery" |
