# PDLC Closed-Loop — Delta

## ADDED Requirements

### Requirement: DISCOVER Phase Routing
The routing engine must detect discovery-intent prompts and select the product-discovery skill. Two-tier trigger patterns: strong signals (discover, user.problem, pain.point, what.to.build, what.should.we, which.issue) and weak signals (backlog, sprint.plan, prioriti, triage, next.sprint, roadmap). Priority 35, role process.

#### Scenario: Strong discovery trigger
Given a prompt "what should we build for the next sprint"
When the activation hook scores skills
Then product-discovery is selected with label "Discover"

#### Scenario: Disambiguation against DESIGN
Given a prompt "build a new auth service"
When the activation hook scores skills
Then brainstorming is selected, not product-discovery

### Requirement: LEARN Phase Routing
The routing engine must detect outcome-review-intent prompts and select the outcome-review skill. Triggers: how.did.*(perform|do|go|work), outcome, adoption, funnel, cohort, experiment.result, feature.impact, post.launch, post.ship, measure, did.it.work. Keywords handle ambiguous terms (learn, metric, result). Priority 30, role process.

#### Scenario: LEARN trigger
Given a prompt "how did the auth feature perform after launch"
When the activation hook scores skills
Then outcome-review is selected with label "Learn / Measure"

#### Scenario: False positive guard
Given a prompt "show me the test results"
When the activation hook scores skills
Then outcome-review is NOT selected

### Requirement: Composition Chain Integration
product-discovery.precedes = ["brainstorming"] (DISCOVER -> DESIGN).
outcome-review.precedes = ["product-discovery"] (LEARN -> DISCOVER loop).
SHIP composition includes advisory LEARN reminder hint.

### Requirement: PostHog MCP Detection
Session-start hook detects PostHog MCP via ~/.claude.json mcpServers and sets posthog plugin available flag, following the established Serena/Forgetful pattern.

### Requirement: Graceful Degradation
Both skills detect MCP availability at invocation. Tier 1: use MCP tools. Tier 2: prompt user for manual context. Never hard-fail on missing MCPs.

### Requirement: Red Flags
DISCOVER phase: no code writing, no skipping Jira context, no jumping to design without discovery brief.
LEARN phase: no Jira ticket creation without approval, no skipping metrics analysis, no code editing.
