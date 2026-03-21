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