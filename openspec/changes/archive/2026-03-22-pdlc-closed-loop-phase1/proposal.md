# Proposal: PDLC Closed-Loop Phase 1

## Problem Statement
The plugin covers BUILD, TEST, REVIEW, and SHIP well but has no coverage for the two highest-value lifecycle phases identified by McKinsey's AI-enabled PDLC framework: upstream discovery (why/what to build) and downstream learning (did it work). The plugin answers "how do we build this safely?" but cannot answer "why are we building this?" or "did it actually work?"

## Proposed Solution
Add two new bookend phases to the routing engine: DISCOVER (before DESIGN) and LEARN (after SHIP). DISCOVER uses Atlassian MCP to pull Jira/Confluence context and synthesize discovery briefs. LEARN uses PostHog MCP to query analytics and synthesize outcome reports. Both degrade gracefully when MCPs are unavailable.

## Out of Scope
- GrowthBook integration (Phase 2: instrumentation-plan + progressive-rollout)
- Auto-create Jira follow-up tickets (Phase 1 is gated by user approval)
- SHIP baseline artifact saving code (hint is advisory only in Phase 1)
