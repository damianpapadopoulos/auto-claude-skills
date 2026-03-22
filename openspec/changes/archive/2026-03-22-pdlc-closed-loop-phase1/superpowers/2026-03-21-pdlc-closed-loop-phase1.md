# PDLC Closed-Loop Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add DISCOVER and LEARN phases to the routing engine with two new skills (product-discovery, outcome-review), closing the product development feedback loop.

**Architecture:** Two new bookend phases (DISCOVER before DESIGN, LEARN after SHIP) with graceful MCP degradation. Registry-driven: new entries in default-triggers.json flow through the existing scoring engine unchanged. PostHog MCP detection added to session-start hook. Two SKILL.md files provide the skill behavior.

**Tech Stack:** Bash 3.2 (macOS), jq, existing hook infrastructure, Atlassian MCP (already connected), PostHog MCP (optional)

**Spec:** `docs/superpowers/specs/2026-03-20-pdlc-closed-loop-design.md`

---

### Task 1: Registry — Add new skills to default-triggers.json

**Files:**
- Modify: `config/default-triggers.json` (skills array, phase_guide, phase_compositions, plugins, methodology_hints)

- [ ] **Step 1: Add product-discovery skill entry**

Insert after the `brainstorming` entry (line 48) in the `skills` array:

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
}
```

- [ ] **Step 2: Add outcome-review skill entry**

Insert after the `incident-analysis` entry (at end of skills array):

```json
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

- [ ] **Step 3: Add DISCOVER and LEARN to phase_guide**

In `phase_guide` object (line 397), add two entries:

```json
"DISCOVER": "product-discovery (pull Jira/Confluence context, synthesize discovery brief)",
"LEARN": "outcome-review (query metrics, synthesize outcome report, create follow-up work)"
```

- [ ] **Step 4: Add DISCOVER and LEARN phase_compositions**

In `phase_compositions` object (line 807), add:

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

- [ ] **Step 5: Add SHIP composition LEARN hint**

In `phase_compositions.SHIP.hints` array (line 966), add:

```json
{
  "text": "LEARN BASELINE: A learn baseline has been saved. Use /learn or 'how did [feature] perform' later to review outcomes.",
  "when": "always"
}
```

- [ ] **Step 6: Add PostHog plugin entry**

In `plugins` array (after the `unified-context-stack` entry, line 805), add:

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

- [ ] **Step 7: Update Atlassian plugin entry**

Modify the existing `atlassian` plugin entry (line 740):
- Change `phase_fit` to: `["DISCOVER", "DESIGN", "PLAN", "REVIEW", "LEARN"]`
- Add to `mcp_tools`: `"createJiraIssue"`, `"addCommentToJiraIssue"`

- [ ] **Step 8: Add posthog-metrics methodology hint**

In `methodology_hints` array, add:

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

- [ ] **Step 9: Update atlassian-jira methodology hint**

Modify the existing `atlassian-jira` hint (line 449):
- Change `phases` to: `["DISCOVER", "DESIGN", "PLAN"]`
- Update `triggers` to: `["(ticket|story|epic|acceptance.criter|definition.of.done|requirement|user.story|jira|sprint|backlog|discover|triage|prioriti)"]`

- [ ] **Step 10: Validate JSON**

Run: `jq empty config/default-triggers.json`
Expected: no output (valid JSON)

- [ ] **Step 11: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: add DISCOVER + LEARN phases to default-triggers registry"
```

---

### Task 2: Registry — Update fallback-registry.json

**Files:**
- Modify: `config/fallback-registry.json`

- [ ] **Step 1: Add product-discovery to fallback skills array**

Same entry as Task 1 Step 1, with added fields: `"available": true, "enabled": true`

- [ ] **Step 2: Add outcome-review to fallback skills array**

Same entry as Task 1 Step 2, with added fields: `"available": true, "enabled": true`

- [ ] **Step 3: Add PostHog plugin to fallback plugins array**

Same entry as Task 1 Step 6.

- [ ] **Step 4: Update Atlassian plugin in fallback**

Mirror the changes from Task 1 Step 7.

- [ ] **Step 5: Update phase_guide in fallback**

Mirror the changes from Task 1 Step 3.

- [ ] **Step 6: Update phase_compositions in fallback**

Mirror the changes from Task 1 Steps 4-5.

- [ ] **Step 7: Update methodology_hints in fallback**

Mirror the changes from Task 1 Steps 8-9.

- [ ] **Step 8: Validate JSON**

Run: `jq empty config/fallback-registry.json`
Expected: no output (valid JSON)

- [ ] **Step 9: Commit**

```bash
git add config/fallback-registry.json
git commit -m "feat: mirror DISCOVER + LEARN into fallback registry"
```

---

### Task 3: Tests — Registry validation for new phases

**Files:**
- Modify: `tests/test-registry.sh`

- [ ] **Step 1: Write test for new skills in registry**

Add after the existing registry tests:

```bash
test_discover_learn_skills_in_registry() {
    echo "-- test: DISCOVER and LEARN skills present in registry --"
    setup_test_env

    local output
    output="$(run_hook)"

    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    assert_file_exists "cache file created" "${cache_file}"

    # product-discovery exists with correct phase and role
    local pd_phase pd_role
    pd_phase="$(jq -r '.skills[] | select(.name == "product-discovery") | .phase' "${cache_file}")"
    pd_role="$(jq -r '.skills[] | select(.name == "product-discovery") | .role' "${cache_file}")"
    assert_equals "product-discovery phase" "DISCOVER" "${pd_phase}"
    assert_equals "product-discovery role" "process" "${pd_role}"

    # outcome-review exists with correct phase and role
    local or_phase or_role
    or_phase="$(jq -r '.skills[] | select(.name == "outcome-review") | .phase' "${cache_file}")"
    or_role="$(jq -r '.skills[] | select(.name == "outcome-review") | .role' "${cache_file}")"
    assert_equals "outcome-review phase" "LEARN" "${or_phase}"
    assert_equals "outcome-review role" "process" "${or_role}"

    # Phase guide includes DISCOVER and LEARN
    local pg_discover pg_learn
    pg_discover="$(jq -r '.phase_guide.DISCOVER // empty' "${cache_file}")"
    pg_learn="$(jq -r '.phase_guide.LEARN // empty' "${cache_file}")"
    assert_not_empty "phase_guide has DISCOVER" "${pg_discover}"
    assert_not_empty "phase_guide has LEARN" "${pg_learn}"

    # Phase compositions include DISCOVER and LEARN
    local pc_discover pc_learn
    pc_discover="$(jq -r '.phase_compositions.DISCOVER.driver // empty' "${cache_file}")"
    pc_learn="$(jq -r '.phase_compositions.LEARN.driver // empty' "${cache_file}")"
    assert_equals "DISCOVER composition driver" "product-discovery" "${pc_discover}"
    assert_equals "LEARN composition driver" "outcome-review" "${pc_learn}"

    # PostHog plugin entry exists
    local ph_name
    ph_name="$(jq -r '.plugins[] | select(.name == "posthog") | .name // empty' "${cache_file}")"
    assert_equals "PostHog plugin exists" "posthog" "${ph_name}"

    teardown_test_env
}
```

- [ ] **Step 2: Write test for regex compilation validation**

```bash
test_all_triggers_compile() {
    echo "-- test: all trigger patterns compile under Bash 3.2 ERE --"

    local triggers
    triggers="$(jq -r '.skills[].triggers[]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
    triggers="${triggers}
$(jq -r '.methodology_hints[].triggers[]' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"

    local fail_count=0
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        local test_status
        [[ "test_string_for_compilation" =~ $pattern ]]
        test_status=$?
        if [[ "$test_status" -eq 2 ]]; then
            _record_fail "regex compilation" "Pattern fails to compile: ${pattern}"
            fail_count=$((fail_count + 1))
        fi
    done <<< "${triggers}"

    if [[ "$fail_count" -eq 0 ]]; then
        _record_pass "all trigger patterns compile"
    fi
}
```

- [ ] **Step 3: Add tests to the runner**

Add `test_discover_learn_skills_in_registry` and `test_all_triggers_compile` to the test invocation block at the bottom of `test-registry.sh`.

- [ ] **Step 4: Run registry tests**

Run: `bash tests/test-registry.sh`
Expected: all new tests PASS

- [ ] **Step 5: Commit**

```bash
git add tests/test-registry.sh
git commit -m "test: add DISCOVER + LEARN registry validation tests"
```

---

### Task 4: Tests — Routing tests for trigger scoring and disambiguation

**Files:**
- Modify: `tests/test-routing.sh`

- [ ] **Step 1: Add product-discovery and outcome-review to test registry**

In the `install_registry` function, add to the skills array inside the heredoc:

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
  "invoke": "Skill(auto-claude-skills:product-discovery)",
  "available": true,
  "enabled": true
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
  "invoke": "Skill(auto-claude-skills:outcome-review)",
  "available": true,
  "enabled": true
}
```

Also add `phase_guide` entries for DISCOVER and LEARN, and `phase_compositions` for DISCOVER and LEARN (follow the existing format in the test registry).

- [ ] **Step 2: Write DISCOVER trigger scoring tests**

```bash
test_discover_trigger_scoring() {
    echo "-- test: DISCOVER trigger scoring --"
    setup_test_env
    install_registry

    # Strong discovery signal
    local output ctx
    output="$(run_hook "what should we build next sprint")"
    ctx="$(extract_context "${output}")"
    assert_contains "discovery strong+weak" "product-discovery" "${ctx}"

    # Weak signal only
    output="$(run_hook "review the backlog for prioritization")"
    ctx="$(extract_context "${output}")"
    assert_contains "discovery weak trigger" "product-discovery" "${ctx}"

    teardown_test_env
}
```

- [ ] **Step 3: Write DISCOVER vs DESIGN disambiguation test**

```bash
test_discover_vs_design_disambiguation() {
    echo "-- test: DISCOVER vs DESIGN disambiguation --"
    setup_test_env
    install_registry

    # Build verb -> brainstorming, not discovery
    local output ctx
    output="$(run_hook "build a new auth service")"
    ctx="$(extract_context "${output}")"
    assert_contains "build -> brainstorming" "brainstorming" "${ctx}"
    assert_not_contains "build -> not discovery" "product-discovery" "${ctx}"

    teardown_test_env
}
```

- [ ] **Step 4: Write LEARN trigger scoring tests**

```bash
test_learn_trigger_scoring() {
    echo "-- test: LEARN trigger scoring --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "how did the auth feature perform")"
    ctx="$(extract_context "${output}")"
    assert_contains "learn trigger" "outcome-review" "${ctx}"

    output="$(run_hook "check metrics for last release")"
    ctx="$(extract_context "${output}")"
    assert_contains "learn keyword" "outcome-review" "${ctx}"

    teardown_test_env
}
```

- [ ] **Step 5: Write LEARN false-positive guard tests**

```bash
test_learn_false_positive_guards() {
    echo "-- test: LEARN false-positive guards --"
    setup_test_env
    install_registry

    # "test results" should NOT trigger outcome-review (result not in triggers)
    local output ctx
    output="$(run_hook "show me the test results")"
    ctx="$(extract_context "${output}")"
    assert_not_contains "test results -> not learn" "outcome-review" "${ctx}"

    # "learning about bash" should NOT trigger outcome-review (learn in keywords requires exact substring)
    output="$(run_hook "I am learning about bash scripting")"
    ctx="$(extract_context "${output}")"
    assert_not_contains "learning -> not learn" "outcome-review" "${ctx}"

    teardown_test_env
}
```

- [ ] **Step 6: Write LEARN vs DEBUG disambiguation test**

```bash
test_learn_vs_debug_disambiguation() {
    echo "-- test: LEARN vs DEBUG disambiguation --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "something is wrong with the metrics dashboard")"
    ctx="$(extract_context "${output}")"
    assert_contains "wrong metrics -> debug" "systematic-debugging" "${ctx}"

    teardown_test_env
}
```

- [ ] **Step 7: Write composition chain tests**

```bash
test_discover_composition_chain() {
    echo "-- test: DISCOVER -> DESIGN composition chain --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "what should we build for the next sprint")"
    ctx="$(extract_context "${output}")"
    # Chain should show product-discovery -> brainstorming -> writing-plans
    assert_contains "chain has brainstorming" "brainstorming" "${ctx}"
    assert_contains "chain has writing-plans" "writing-plans" "${ctx}"

    teardown_test_env
}

test_learn_composition_chain() {
    echo "-- test: LEARN -> DISCOVER composition chain --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "how did the auth feature perform after launch")"
    ctx="$(extract_context "${output}")"
    # Chain should show outcome-review -> product-discovery
    assert_contains "chain has product-discovery" "product-discovery" "${ctx}"

    teardown_test_env
}
```

- [ ] **Step 8: Write slash-command early-exit test**

```bash
test_slash_command_early_exit() {
    echo "-- test: /discover slash command exits early --"
    setup_test_env
    install_registry

    local output
    output="$(run_hook "/discover")"
    # Slash commands produce no output (early exit)
    assert_equals "slash command no output" "" "${output}"

    teardown_test_env
}
```

- [ ] **Step 9: Add all tests to the runner block**

Add all new test functions to the invocation block at the bottom of `test-routing.sh`.

- [ ] **Step 10: Run routing tests**

Run: `bash tests/test-routing.sh`
Expected: all new tests PASS, all existing tests still PASS

- [ ] **Step 11: Commit**

```bash
git add tests/test-routing.sh
git commit -m "test: add DISCOVER + LEARN routing and disambiguation tests"
```

---

### Task 5: Routing engine — Label updates and red flags

**Files:**
- Modify: `hooks/skill-activation-hook.sh`

- [ ] **Step 1: Add label cases for new process skills**

In `_determine_label_phase` (around line 492), inside the `process)` case block, add:

```bash
product-discovery)            PLABEL="Discover" ;;
outcome-review)               PLABEL="Learn / Measure" ;;
```

- [ ] **Step 2: Update no-registry fallback message**

At line 70, change:
```bash
"Phase: assess current phase (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)"
```
to:
```bash
"Phase: assess current phase (DISCOVER/DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/LEARN/DEBUG)"
```

- [ ] **Step 3: Add DISCOVER and LEARN red flags**

In the red-flag enforcement block (find the `case "${PRIMARY_PHASE}"` section), add:

```bash
DISCOVER)
    _RED_FLAGS="HALT if any Red Flag is true:
- Skipping Jira/Confluence context pull when Atlassian MCP is available
- Jumping to design without presenting a discovery brief
- Writing code during the DISCOVER phase" ;;
LEARN)
    _RED_FLAGS="HALT if any Red Flag is true:
- Creating Jira follow-up tickets without user approval
- Skipping metrics analysis and going straight to recommendations
- Editing code during the LEARN phase" ;;
```

- [ ] **Step 4: Syntax check**

Run: `bash -n hooks/skill-activation-hook.sh`
Expected: no output (valid syntax)

- [ ] **Step 5: Run routing tests to verify**

Run: `bash tests/test-routing.sh`
Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/skill-activation-hook.sh
git commit -m "feat: add DISCOVER + LEARN labels, fallback message, and red flags"
```

---

### Task 6: Session-start hook — PostHog MCP detection

**Files:**
- Modify: `hooks/session-start-hook.sh`

- [ ] **Step 1: Add PostHog to CONTEXT_CAPS detection**

In the single jq call at line 630-637 that builds CONTEXT_CAPS, add:

```jq
($avail | index("posthog") != null) as $ph |
```

And extend the output object to include `posthog:$ph`.

- [ ] **Step 2: Add PostHog to MCP fallback detection**

In the MCP fallback jq expression at line 643-655, add:

```jq
if .posthog == false and ($all_mcp | has("posthog")) then .posthog = true else . end
```

- [ ] **Step 3: Set PostHog plugin available flag**

After the unified-context-stack available override (line 660-663), add:

```bash
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.posthog == true' >/dev/null 2>&1; then
    PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq '
        map(if .name == "posthog" then .available = true else . end)
    ')"
fi
```

- [ ] **Step 4: Syntax check**

Run: `bash -n hooks/session-start-hook.sh`
Expected: no output (valid syntax)

- [ ] **Step 5: Run registry tests to verify**

Run: `bash tests/test-registry.sh`
Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: add PostHog MCP detection to session-start hook"
```

---

### Task 7: Skill — product-discovery SKILL.md

**Files:**
- Create: `skills/product-discovery/SKILL.md`

- [ ] **Step 1: Write the skill file**

```markdown
---
name: product-discovery
description: Pull Jira/Confluence context, synthesize discovery brief, validate problem framing before design
---

# Product Discovery

Synthesize a discovery brief from Jira tickets, Confluence docs, and conversation context. Present the brief for user validation before transitioning to design.

## Step 1: Detect Available Tools

Check which MCP tools are available:

**Tier 1 — Atlassian MCP:**
If you have access to `searchJiraIssuesUsingJql`, `getJiraIssue`, `searchConfluenceUsingCql`, or `getConfluencePage` as MCP tools, use Tier 1.

**Tier 2 — Manual Context:**
If no Atlassian MCP tools are available, ask the user to provide context directly:
> "I don't have Atlassian MCP access. Please share any of the following:
> - Jira ticket IDs or URLs for the work you're considering
> - Problem statements or user pain points
> - Acceptance criteria or success metrics
> - Links to relevant Confluence docs or ADRs"

## Step 2: Gather Context

**Tier 1 (Atlassian MCP available):**

1. Ask the user what area, project, or problem they want to explore
2. Query Jira for relevant issues:
   - `searchJiraIssuesUsingJql` with project, status, priority, labels
   - `getJiraIssue` for full details on top candidates
3. Query Confluence for related docs:
   - `searchConfluenceUsingCql` for design docs, ADRs, prior decisions
   - `getConfluencePage` to read full content of relevant pages
4. Note any linked issues, parent epics, or blocked dependencies

**Tier 2 (Manual):**

1. Ask the user to describe the problem space
2. Ask for any existing ticket IDs, doc links, or context
3. Synthesize from what the user provides

## Step 3: Synthesize Discovery Brief

Present a structured brief covering:

### Discovery Brief

**Problem Statement:** What user pain point or business need are we addressing?

**Prior Art:** What has been tried before? What related work exists? (from Jira history, Confluence docs)

**Acceptance Criteria:** What does success look like? (from Jira tickets or user input)

**Constraints:** Known limitations — timeline, dependencies, technical constraints

**Open Questions:** What needs to be answered before design can begin?

## Step 4: User Validation

Present the brief and ask:
> "Does this discovery brief capture the problem accurately? Should I adjust anything before we move to design?"

Wait for user confirmation. If they request changes, revise and re-present.

## Step 5: Transition to Design

Once the user approves the discovery brief:

> "Discovery complete. Invoke Skill(superpowers:brainstorming) to begin design."

This is a hard transition. Do not begin design work within the discovery skill.
```

- [ ] **Step 2: Verify file exists**

Run: `test -f skills/product-discovery/SKILL.md && echo "exists"`
Expected: `exists`

- [ ] **Step 3: Commit**

```bash
git add skills/product-discovery/SKILL.md
git commit -m "feat: add product-discovery skill (DISCOVER phase)"
```

---

### Task 8: Skill — outcome-review SKILL.md

**Files:**
- Create: `skills/outcome-review/SKILL.md`

- [ ] **Step 1: Write the skill file**

```markdown
---
name: outcome-review
description: Query PostHog metrics, synthesize outcome report, create follow-up Jira work (gated)
---

# Outcome Review

Query analytics for a shipped feature, synthesize an outcome report, and optionally create follow-up Jira work. Entered independently after shipping — days or weeks later.

## Step 1: Detect Available Tools

Check which MCP tools are available:

**Tier 1 — PostHog MCP:**
If you have access to `query-run`, `get-experiment`, `list-experiments`, `get-feature-flag`, or `create-annotation` as MCP tools, use Tier 1.

**Tier 2 — Manual Metrics:**
If no PostHog MCP tools are available, ask the user to provide metrics directly:
> "I don't have PostHog MCP access. Please share any of the following:
> - Dashboard screenshots or metric summaries
> - Adoption numbers, funnel data, or error rates
> - Experiment results if applicable
> - Any specific concerns about the shipped feature"

## Step 2: Identify the Feature

1. Check for a learn baseline file in `~/.claude/.skill-learn-baselines/`:
   - List files, match by feature name or branch name from the user's prompt
   - If found, use the baseline's `shipped_at`, `suggested_metrics`, and `jira_ticket` fields
2. If no baseline found, ask the user:
   > "Which feature should I review? Please provide the feature name, branch name, or Jira ticket ID."

## Step 3: Gather Metrics

**Tier 1 (PostHog MCP available):**

1. Query adoption metrics via `query-run` with HogQL:
   - Event counts for the feature's key events since `shipped_at`
   - Compare to the period before shipping (same duration)
2. Check experiment results if applicable:
   - `list-experiments` to find experiments linked to the feature
   - `get-experiment` for results, significance, and variant performance
3. Check feature flag status:
   - `get-feature-flag` for rollout percentage and targeting rules
4. Check error rates:
   - `query-run` for error events associated with the feature

**Tier 2 (Manual):**

1. Ask the user to share metrics from their dashboards
2. Ask about any observed regressions or improvements
3. Synthesize from what the user provides

## Step 4: Synthesize Outcome Report

Present a structured report:

### Outcome Report

**Feature:** [name] | **Shipped:** [date] | **Branch:** [name]

**Adoption:** [metrics summary — event counts, trend direction, comparison to pre-ship baseline]

**Quality:** [error rates, regression indicators]

**Experiments:** [results if applicable — significance, winning variant, effect size]

**Assessment:** One of:
- **Positive** — Metrics improved, no regressions. Close the loop.
- **Regression detected** — [specific metric] degraded by [amount]. Investigate.
- **Inconclusive** — Insufficient data. Revisit in [N] days.
- **Mixed** — [positive metrics] improved but [negative metrics] regressed. Judgment call.

**Recommendations:** Specific next actions based on the assessment.

## Step 5: User Decision Gate

Present the report and ask:
> "Based on this outcome review, would you like me to:
> 1. **Close the loop** — no follow-up needed
> 2. **Create follow-up Jira tickets** — I'll draft tickets for the recommended actions (requires your approval before creation)
> 3. **Investigate further** — dig deeper into a specific metric or regression"

Wait for the user's choice.

## Step 6: Follow-Up Actions

**If "Create follow-up tickets" (and Atlassian MCP available):**
1. Draft the ticket(s) — title, description, acceptance criteria, priority
2. Present each draft to the user for approval
3. Only after explicit approval: `createJiraIssue` to create the ticket
4. `addCommentToJiraIssue` on the original ticket with the outcome summary

**If Atlassian MCP unavailable:**
> "I don't have Atlassian MCP access. Here are the recommended follow-up tickets — please create them manually:
> [formatted ticket descriptions]"

## Step 7: Transition

If follow-up work was identified:
> "If follow-up work is needed, invoke Skill(auto-claude-skills:product-discovery) or Skill(superpowers:brainstorming) to begin the next cycle."

If the loop is closed:
> "Outcome review complete. The feature loop is closed."
```

- [ ] **Step 2: Verify file exists**

Run: `test -f skills/outcome-review/SKILL.md && echo "exists"`
Expected: `exists`

- [ ] **Step 3: Commit**

```bash
git add skills/outcome-review/SKILL.md
git commit -m "feat: add outcome-review skill (LEARN phase)"
```

---

### Task 9: Tests — Context rendering for new phases

**Files:**
- Modify: `tests/test-context.sh`

- [ ] **Step 1: Write label display tests**

Add tests that verify the activation hook output shows correct labels:

```bash
test_discover_label() {
    echo "-- test: DISCOVER label display --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "what should we discover about user problems")"
    ctx="$(extract_context "${output}")"
    assert_contains "discover label" "Discover" "${ctx}"

    teardown_test_env
}

test_learn_label() {
    echo "-- test: LEARN label display --"
    setup_test_env
    install_registry

    local output ctx
    output="$(run_hook "how did the feature perform after launch")"
    ctx="$(extract_context "${output}")"
    assert_contains "learn label" "Learn / Measure" "${ctx}"

    teardown_test_env
}
```

Note: `test-context.sh` may need its own `install_registry` and `run_hook` helpers. Check the existing file structure and add the necessary helpers if not present (they may already be sourced from `test-helpers.sh`).

- [ ] **Step 2: Run context tests**

Run: `bash tests/test-context.sh`
Expected: all new tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/test-context.sh
git commit -m "test: add DISCOVER + LEARN context rendering tests"
```

---

### Task 10: Integration — Run full test suite and verify

**Files:** None (read-only verification)

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: all tests PASS, no regressions

- [ ] **Step 2: Syntax-check all hooks**

Run: `bash -n hooks/skill-activation-hook.sh && bash -n hooks/session-start-hook.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 3: Validate both registries**

Run: `jq empty config/default-triggers.json && jq empty config/fallback-registry.json && echo "OK"`
Expected: `OK`

- [ ] **Step 4: Smoke test — DISCOVER routing**

Run: `echo '{"prompt":"what should we build for the next sprint"}' | CLAUDE_PLUGIN_ROOT=. bash hooks/skill-activation-hook.sh 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' | head -5`
Expected: output contains `product-discovery`

- [ ] **Step 5: Smoke test — LEARN routing**

Run: `echo '{"prompt":"how did the auth feature perform after launch"}' | CLAUDE_PLUGIN_ROOT=. bash hooks/skill-activation-hook.sh 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' | head -5`
Expected: output contains `outcome-review`

- [ ] **Step 6: Smoke test — disambiguation preserved**

Run: `echo '{"prompt":"build a new login page"}' | CLAUDE_PLUGIN_ROOT=. bash hooks/skill-activation-hook.sh 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' | head -5`
Expected: output contains `brainstorming`, NOT `product-discovery`

- [ ] **Step 7: Commit (if any fixes needed)**

Only if smoke tests revealed issues that required fixes.
