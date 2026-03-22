# Design: PDLC Closed-Loop Phase 1

## Architecture
Option C: new bookend phases with the proven PLAN-IMPLEMENT-REVIEW middle unchanged. Two new process skills (product-discovery, outcome-review) are added to the registry and scored by the existing routing engine. No changes to the core scoring algorithm. The composition chain walker naturally handles the new precedes/requires links. PostHog MCP detection follows the established Serena/Forgetful pattern in the session-start hook.

Lifecycle: DISCOVER -> DESIGN -> PLAN -> IMPLEMENT -> REVIEW -> SHIP -> LEARN -> (loop back to DISCOVER)

## Dependencies
- Atlassian MCP (already connected) for DISCOVER phase Jira/Confluence queries
- PostHog MCP (optional, detected at session-start) for LEARN phase analytics queries
- No new packages or CLI tools required

## Decisions & Trade-offs

### Option C over Option A (all-new phases) and Option B (enrich existing)
Option C preserves the battle-tested middle while adding value at the edges. Option A would require rewriting phase detection for all phases. Option B would cram "Learn" into a third SHIP step, which is conceptually wrong.

### SHIP-to-LEARN as data link, not chain link
LEARN happens days/weeks after SHIP. Wiring it into the SHIP composition chain would show "[NEXT] outcome-review" at ship time, which is misleading. Instead, SHIP writes an advisory hint and LEARN is entered independently via trigger scoring or /learn.

### Two-tier DISCOVER triggers
Strong signals (discover, user.problem, pain.point) are separated from weak signals (backlog, sprint.plan, prioriti) into two patterns. This creates a natural scoring threshold: prompts matching both patterns score much higher than those matching only the weak pattern.

### Keywords over regex for ambiguous terms
`learn`, `metric`, and `result` are handled via keywords (exact substring match) rather than regex triggers to avoid false positives from "learning", "test results", "metric config". This was a critical review finding that prevented Bash 3.2 POSIX ERE incompatibility from a `(?!ing)` lookahead.
