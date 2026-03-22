# PDLC Closed-Loop — Delta

## ADDED Requirements

### Requirement: DISCOVER Phase Routing
The routing engine MUST detect discovery-intent prompts and select the product-discovery skill. Two-tier trigger patterns SHALL be used: strong signals (discover, user.problem, pain.point, what.to.build, what.should.we, which.issue) and weak signals (backlog, sprint.plan, prioriti, triage, next.sprint, roadmap). Priority MUST be 35, role MUST be process.

#### Scenario: Strong discovery trigger
Given a prompt "what should we build for the next sprint"
When the activation hook scores skills
Then product-discovery MUST be selected with label "Discover"

#### Scenario: Disambiguation against DESIGN
Given a prompt "build a new auth service"
When the activation hook scores skills
Then brainstorming MUST be selected, not product-discovery

### Requirement: LEARN Phase Routing
The routing engine MUST detect outcome-review-intent prompts and select the outcome-review skill. Triggers SHALL include: how.did.*(perform|do|go|work), outcome, adoption, funnel, cohort, experiment.result, feature.impact, post.launch, post.ship, measure, did.it.work. Keywords MUST handle ambiguous terms (learn, metric, result). Priority MUST be 30, role MUST be process.

#### Scenario: LEARN trigger
Given a prompt "how did the auth feature perform after launch"
When the activation hook scores skills
Then outcome-review MUST be selected with label "Learn / Measure"

#### Scenario: False positive guard
Given a prompt "show me the test results"
When the activation hook scores skills
Then outcome-review MUST NOT be selected

### Requirement: Composition Chain Integration
product-discovery.precedes MUST equal ["brainstorming"] (DISCOVER -> DESIGN). outcome-review.precedes MUST equal ["product-discovery"] (LEARN -> DISCOVER loop). The SHIP composition SHALL include an advisory LEARN reminder hint.

#### Scenario: DISCOVER forward chain
Given product-discovery is the current skill
When the composition chain walker renders the chain
Then brainstorming MUST appear as NEXT in the chain

#### Scenario: LEARN forward chain
Given outcome-review is the current skill
When the composition chain walker renders the chain
Then product-discovery MUST appear as NEXT in the chain

### Requirement: PostHog MCP Detection
The session-start hook MUST detect PostHog MCP via ~/.claude.json mcpServers and SHALL set the posthog plugin available flag, following the established Serena/Forgetful pattern.

#### Scenario: PostHog detected from mcpServers
Given ~/.claude.json contains a "posthog" key in mcpServers
When the session-start hook runs
Then CONTEXT_CAPS.posthog MUST be true

### Requirement: Graceful Degradation
Both skills MUST detect MCP availability at invocation. Tier 1 SHALL use MCP tools. Tier 2 SHALL prompt the user for manual context. The skills MUST NOT hard-fail on missing MCPs.

#### Scenario: Atlassian MCP unavailable
Given no Atlassian MCP tools are available
When product-discovery is invoked
Then the skill MUST prompt the user for manual context

### Requirement: Red Flags
DISCOVER phase red flags MUST include: no code writing, no skipping Jira context when available, no jumping to design without discovery brief. LEARN phase red flags MUST include: no Jira ticket creation without approval, no skipping metrics analysis, no code editing.

#### Scenario: DISCOVER red flags present
Given the routing engine selects product-discovery
When the activation hook renders the output
Then DISCOVER red flags MUST be included in the output
