# PDLC Closed-Loop Orchestration — Phase 1: DISCOVER + LEARN

**Date:** 2026-03-20
**Status:** Ready for implementation
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

**Trigger patterns (two-tier for high threshold):**
```
"(discover|user.problem|pain.point|what.to.build|what.should.we|which.issue)"
"(backlog|sprint.plan|prioriti|triage|next.sprint|roadmap)"
```

The first pattern contains **strong discovery signals** — terms that unambiguously indicate discovery intent. The second contains **weaker signals** that could appear in non-discovery contexts ("update the backlog", "check the sprint").

**How the high threshold works:** The scoring engine awards points per trigger pattern matched. A prompt matching only the weak pattern scores 30 (trigger) + 35 (priority) = 65. A prompt matching both patterns scores 30+30+35 = 95. Brainstorming scores 30+30 (two trigger patterns) = 60 on build-verb prompts. This means:
- Strong discovery language ("discover what to build") → product-discovery wins clearly (65+ vs brainstorming 0)
- Weak + strong ("prioritize the backlog for discovery") → product-discovery wins decisively (95 vs brainstorming 0)
- Weak only + build verb overlap ("add items to the backlog") → product-discovery 65 vs brainstorming 60 — product-discovery wins by a narrow margin, which is correct
- Build verb only ("build a new auth service") → brainstorming wins (60+ vs product-discovery 0)

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
"(how.did.*(perform|do|go|work)|outcome|adoption|funnel|cohort|experiment.result|feature.impact|post.launch|post.ship|measure|did.it.work)"
```

Note: `learn`, `metric`, and `result` are intentionally excluded from triggers to avoid false positives (e.g. "learning", "test results", "metric config"). They are handled via keywords instead, which use exact substring matching and are less prone to noise.

**Keywords:**
```
["how did it perform", "check metrics", "feature impact", "post-launch review", "did it work", "adoption metrics", "what did we learn", "learn from this", "review the results", "metric results"]
```

**Priority:** 30

**Requires:** `[]` (no chain dependency — LEARN can be entered independently, days after shipping)

**Precedes:** `["product-discovery"]` (follow-up work feeds back into DISCOVER, completing the closed loop)

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
- **Auto-baseline after SHIP:** When SHIP phase completes, write a lightweight baseline artifact to `~/.claude/.skill-learn-baselines/{branch-name}.json` containing: feature name, ship timestamp, branch name, key metric names. Keyed by branch name (not session token) so that LEARN invocations in later sessions can discover the baseline. This is a PostHog annotation + local file, NOT a full metrics analysis.
- **Full analysis on demand:** When user revisits with "how did X perform?" or triggers LEARN explicitly, the skill searches `~/.claude/.skill-learn-baselines/` for matching baselines by feature/branch name and runs the full outcome analysis.
- **Cleanup:** Baselines older than 90 days are pruned on SHIP (opportunistic cleanup, not a separate job).

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

**Availability detection:** PostHog is an MCP server (`source: "mcp-server"`), not a plugin directory. It must be detected via `~/.claude.json` mcpServers, the same way Serena and Forgetful are detected today (session-start-hook.sh lines 640-656).

Add to the MCP fallback detection block in session-start-hook.sh:

```bash
# In the jq expression at line 643-655, add:
if .posthog == false and ($all_mcp | has("posthog")) then .posthog = true else . end
```

And extend CONTEXT_CAPS at line 630-637 to include PostHog:

```jq
($avail | index("posthog") != null) as $ph |
# ... existing fields ...
{context7:$c7, ..., posthog:$ph}
```

Then set the posthog plugin `available` flag based on CONTEXT_CAPS, the same way unified-context-stack is handled (line 660-663):

```bash
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.posthog == true' >/dev/null 2>&1; then
    PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq '
        map(if .name == "posthog" then .available = true else . end)
    ')"
fi
```

This ensures plugin-gated hints and compositions only fire when PostHog MCP is actually configured.

### 2.4 New methodology hints

```json
{
  "name": "posthog-metrics",
  "triggers": [
    "(metric|adoption|funnel|cohort|experiment|feature.flag|a.?b.test|conversion|retention|churn|engagement|posthog)"
  ],
  "trigger_mode": "regex",
  "hint": "POSTHOG: If PostHog MCP tools are available, query analytics and experiment results directly. Use outcome-review skill for structured post-ship analysis.",
  "plugin": "posthog",
  "phases": ["LEARN", "SHIP", "DEBUG"]
}
```

### 2.5 Composition chain integration

**DISCOVER → DESIGN** works via `precedes`:
- product-discovery.precedes = `["brainstorming"]`
- The composition chain walker finds this link and renders: `[CURRENT] product-discovery → [NEXT] brainstorming → [LATER] writing-plans → ...`
- The composition directive says: "After completing product-discovery, invoke brainstorming"

**SHIP → LEARN** is a **data link, not a chain link.** Rationale: LEARN happens days/weeks after SHIP — it would be wrong to show `[NEXT] outcome-review` at SHIP time, since the user won't invoke it immediately. Instead:

- SHIP's `finishing-a-development-branch` writes the baseline artifact (Section 2.7) and completes the SHIP chain
- outcome-review has NO `requires` dependency and NO chain link from SHIP
- The SHIP composition gets a new **hint** that fires after SHIP completes:

```json
// Added to phase_compositions.SHIP.hints:
{
  "text": "LEARN BASELINE: A learn baseline has been saved. Use /learn or 'how did [feature] perform' later to review outcomes.",
  "when": "always"
}
```

This hint is advisory. It informs the user that LEARN is available without forcing it into the SHIP chain. The actual LEARN invocation happens in a later session via trigger scoring or `/learn`.

**LEARN → DISCOVER** works via `precedes`:
- outcome-review.precedes = `["product-discovery"]`
- When the user completes an outcome review and follow-up work is identified, the directive says: "invoke product-discovery to begin the next cycle"
- This closes the loop: LEARN creates follow-up work → DISCOVER picks it up

### 2.6 Label updates in _determine_label_phase

Add to the `process` case in `_determine_label_phase`:

```bash
product-discovery)            PLABEL="Discover" ;;
outcome-review)               PLABEL="Learn / Measure" ;;
```

Also update the no-registry fallback message (line 70 of skill-activation-hook.sh) to include DISCOVER and LEARN:

```bash
"Phase: assess current phase (DISCOVER/DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/LEARN/DEBUG)"
```

### 2.8 Red flags for new phases

Add DISCOVER and LEARN cases to the red-flag enforcement block:

**DISCOVER red flags:**
- Skipping Jira/Confluence context pull when Atlassian MCP is available
- Jumping to design without presenting a discovery brief
- Writing code during the DISCOVER phase

**LEARN red flags:**
- Creating Jira follow-up tickets without user approval
- Skipping metrics analysis and going straight to recommendations
- Editing code during the LEARN phase

### 2.7 SHIP baseline artifact

After `finishing-a-development-branch` completes in the SHIP composition, write:

```json
// ~/.claude/.skill-learn-baselines/{branch-name}.json
{
  "feature": "<feature name from plan>",
  "shipped_at": "<ISO timestamp>",
  "branch": "<branch name>",
  "spec_path": "<path to openspec doc if exists>",
  "suggested_metrics": ["<list from plan/spec if available>"],
  "jira_ticket": "<Jira ticket ID if available from discovery>"
}
```

**Key design choices:**
- Keyed by **branch name** (sanitized: slashes → dashes), not session token. This allows LEARN to find baselines across sessions, since session tokens change per conversation.
- The `finishing-a-development-branch` skill writes the baseline as its final step before cleanup.
- outcome-review discovers baselines by listing `~/.claude/.skill-learn-baselines/` and matching on feature name, branch name, or Jira ticket.
- Baselines older than 90 days are pruned opportunistically during SHIP.
- The `jira_ticket` field enables LEARN to annotate the original ticket with outcome data.

## 3. Registry Changes

### 3.1 default-triggers.json

Add two new skill entries to the `skills` array:

```json
{
  "name": "product-discovery",
  "role": "process",
  "phase": "DISCOVER",
  "triggers": [
    "(discover|user.problem|pain.point|what.to.build|what.should.we|which.issue)",
    "(backlog|sprint.plan|prioriti|triage|next.sprint|roadmap)"
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
    "(how.did.*(perform|do|go|work)|outcome|adoption|funnel|cohort|experiment.result|feature.impact|post.launch|post.ship|measure|did.it.work)"
  ],
  "keywords": [
    "how did it perform",
    "check metrics",
    "feature impact",
    "post-launch review",
    "did it work",
    "adoption metrics",
    "what did we learn",
    "learn from this",
    "review the results",
    "metric results"
  ],
  "trigger_mode": "regex",
  "priority": 30,
  "precedes": ["product-discovery"],
  "requires": [],
  "description": "Query PostHog metrics, synthesize outcome report, create follow-up Jira work (gated). Entered independently post-ship.",
  "invoke": "Skill(auto-claude-skills:outcome-review)"
}
```

### 3.2 fallback-registry.json

Mirror the same entries with `"available": true, "enabled": true`.

### 3.3 Atlassian plugin updates

Extend the existing atlassian plugin entry's phase_fit:

```json
"phase_fit": ["DISCOVER", "DESIGN", "PLAN", "REVIEW", "LEARN"]
```

Add write-side MCP tools needed for LEARN follow-up creation:

```json
"mcp_tools": [
  "searchJiraIssuesUsingJql",
  "getJiraIssue",
  "getConfluencePage",
  "searchConfluenceUsingCql",
  "createJiraIssue",
  "addCommentToJiraIssue"
]
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

`/discover` and `/learn` are explicit command-style entry points that force phase selection without trigger scoring.

- `/discover` → `Skill(auto-claude-skills:product-discovery)`
- `/learn` → `Skill(auto-claude-skills:outcome-review)`

**How they work:** Slash commands bypass the activation hook entirely (`[[ "$PROMPT" =~ ^[[:space:]]*/ ]] && exit 0`). The Skill tool loads the SKILL.md directly. This means:

1. No signal file (`~/.claude/.skill-last-invoked-{session}`) is written by the hook
2. No composition state is written by the hook
3. The next prompt won't have context-bonus for successor skills

**Mitigation:** Each SKILL.md includes an explicit transition directive at the end of its workflow:

- product-discovery's SKILL.md ends with: *"Discovery complete. Invoke Skill(superpowers:brainstorming) to begin design."*
- outcome-review's SKILL.md ends with: *"If follow-up work is needed, invoke Skill(auto-claude-skills:product-discovery) or Skill(superpowers:brainstorming) to begin the next cycle."*

This is the same pattern used by existing skills (brainstorming ends with "invoke writing-plans"). The composition chain is advisory context for trigger-scored prompts; slash-command invocations rely on the skill's own transition directives instead. No signal file is needed because Claude follows the skill's explicit instructions.

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
- LEARN false-positive guard: "show me test results" → NOT outcome-review (result excluded from triggers)
- LEARN false-positive guard: "I'm learning about bash" → NOT outcome-review (learn handled via keywords only)
- Composition chain: product-discovery → brainstorming → writing-plans (full forward walk)
- Composition chain: outcome-review → product-discovery (LEARN → DISCOVER loop)
- `/discover` slash command: early exit, no hook activation (existing behavior)

### 6.1.1 Regex compilation validation

All trigger patterns in the registry must compile under Bash 3.2 POSIX ERE. Test:
```bash
# For each trigger in default-triggers.json:
trigger="$pattern"
[[ "test" =~ $trigger ]]
status=$?
# status 0 = match, status 1 = no match (both OK)
# status 2 = compilation failure = FAIL
[[ $status -le 1 ]] || fail "Trigger pattern fails to compile: $pattern"
```
This prevents future regressions from non-POSIX regex features (lookahead, lookbehind, etc.).

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
| DISCOVER false positives from casual "backlog" mentions | Two-tier triggers: strong signals (discover, user.problem) in pattern 1, weak signals (backlog, sprint) in pattern 2; weak-only match scores lower but still wins over brainstorming due to priority:35. `/discover` as hard override for ambiguous cases. |
| LEARN "learn" substring matches "learning" in normal text | `learn` handled via keywords only (exact substring match), not regex triggers |
| PostHog MCP not installed for most users | Graceful degradation to guided manual mode |
| Baseline artifact from SHIP gets stale | Branch-keyed file in `~/.claude/.skill-learn-baselines/`; LEARN warns if >30 days; 90-day opportunistic cleanup |
| DISCOVER → DESIGN transition unclear | Composition chain shows `[NEXT] brainstorming`; directive says "invoke brainstorming after discovery" |
