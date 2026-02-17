# Superpowers Workflow Analysis

How the Skill Activation Hook aligns with Superpowers' designed pipeline.

## The Designed Pipeline

Superpowers has a strict linear sequence for feature development. Each skill chains to the next internally:

```
brainstorming -> writing-plans -> [executing-plans | subagent-driven-development]
                                           |
                                verification-before-completion
                                           |
                              finishing-a-development-branch
```

### Internal chaining evidence (from SKILL.md files):

- **brainstorming**: "Terminal state is invoking writing-plans. Do NOT invoke frontend-design, mcp-builder, or any other implementation skill."
- **writing-plans**: Plan header says "REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task"
- **subagent-driven-development**: REQUIRES requesting-code-review (after each task), finishing-a-development-branch (Step 7). Subagents MUST USE test-driven-development.
- **executing-plans**: "Ask for clarification rather than guessing. Don't force through blockers -- stop and ask."

### Reactive skills (can interrupt any phase):

- **systematic-debugging** -- "Use when encountering any bug, test failure, or unexpected behavior, BEFORE proposing fixes."
- **test-driven-development** -- Red-green-refactor. Used BY subagents during execution, not standalone.
- **dispatching-parallel-agents** -- "Use when facing 3+ independent failures."

## Hook Architecture: Two-Tier Classification

### The core insight

Claude Code is already an LLM running on every prompt. We don't need a separate API call for intent classification -- Claude IS the classifier. The hook's job is to inject the right context so Claude can make informed routing decisions.

### Tier 1: Fast path (regex)

Keywords catch obvious intents in <100ms with zero cost:

```
Priority: Fix/Debug > Execute Plan > Build New > Review > Ship
```

Why this order?
- **Fix first** -- broken code is always the immediate concern.
- **Execute Plan second** -- explicit plan continuation is very specific.
- **Build New third** -- most common intent. Prevents "build & review" -> Review.
- **Review fourth** -- only fires when nothing constructive matched.
- **Ship last** -- requires explicit shipping verbs (merge, deploy, ship). "Finish implementing" correctly routes to Build.

### Tier 2: Fallthrough (Claude classifies)

When regex misses but the prompt contains dev-related vocabulary (code, test, api, migration, schema, feature, task, etc.), the hook still emits the phase checkpoint with 0 pre-selected skills. Claude reads the phase map and self-navigates using conversation context.

This handles prompts like:
- "looks good, plan it out" -- brainstorming already loaded, Claude chains to writing-plans
- "ok what about the database schema" -- Claude checks context, continues implementation
- "this feature is ready for testing" -- Claude assesses REVIEW phase

### Tier 3: Silent exit

Non-dev prompts ("what time is it", "thanks") produce no output. Zero context cost.

### Cross-cutting overlays (additive)

Security, frontend, documentation, meta, and parallel skills fire on top of any primary intent. "Implement a secure dashboard" gets Build New + Security + Frontend.

### Phase checkpoint (the real classifier)

Always present for Tier 1 and 2. Tells Claude to:

1. **Assess phase** from conversation context (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)
2. **Evaluate skills** against that assessment (YES/NO for each)
3. **Confirm with the user** before proceeding
4. **Activate** approved skills and follow their internal chain

This matches Superpowers' core behavioral contract:
- brainstorming: "Present design, get approval before moving on"
- writing-plans: chains to executing-plans after plan is saved
- executing-plans: "Ask for clarification rather than guessing"
- receiving-code-review: "Need clarification on 4 and 5 before proceeding"

## Why not a separate LLM call?

We considered calling Haiku from the hook for better classification. The numbers work (~500ms, ~$0.00006/call), but it's unnecessary:

- Claude Code already has full conversation context for intent assessment
- Adding a pre-call means asking one LLM to decide what another LLM should do
- Requires API key configuration -- breaks zero-config install
- Network dependency -- fails offline or rate-limited
- The regex fast path catches ~80% of prompts correctly; the fallthrough + phase checkpoint handles the rest

The hybrid approach gets the best of both: fast regex for obvious cases, Claude's own intelligence for ambiguous ones, no extra infrastructure.

## Skill Coverage (18 skills)

### Primary intent skills

| Phase | Skills |
|-------|--------|
| Fix / Debug | systematic-debugging, test-driven-development |
| Plan Execution | subagent-driven-development, executing-plans |
| Review | requesting-code-review, receiving-code-review |
| Build New | brainstorming, test-driven-development |
| Ship / Complete | verification-before-completion, finishing-a-development-branch |

### Cross-cutting overlays

| Overlay | Skills |
|---------|--------|
| Security | security-scanner |
| Frontend | frontend-design, webapp-testing |
| Documentation | doc-coauthoring |
| Meta | claude-automation-recommender, claude-md-improver, writing-skills |
| Parallel | dispatching-parallel-agents, using-git-worktrees |

### Methodology hints (plugins)

| Plugin | Purpose |
|--------|---------|
| Ralph Loop | Autonomous iteration (/ralph-loop) |
| PR Review Toolkit | Structured review (/pr-review) |

## Design Decisions

**Q: Why is test-driven-development in both "Fix/Debug" and "Build New"?**
TDD verifies both fixes (failing test for the bug, then fix) and new features (red-green-refactor). Runtime deduplication ensures it appears once.

**Q: Why doesn't the hook track state between prompts?**
State tracking requires persistence (files, env vars), adding failure modes. Claude already has full conversation context -- the phase checkpoint turns that into explicit routing decisions.

**Q: What if Claude's phase assessment is wrong?**
The user overrides. "Skip the design, just code it" or "go back to planning" are explicitly supported.

**Q: Why priority-order the regex intents?**
Without priority, "fix this and deploy" matches both Fix and Ship. Fix wins because broken code takes priority. Ship requires explicit verbs so "finish implementing" routes to Build, not Ship.

**Q: What happens when regex misses entirely?**
If the prompt contains dev vocabulary, the fallthrough emits the phase checkpoint with 0 pre-selected skills. Claude assesses intent itself. If not dev-related, silent exit -- zero context cost.
