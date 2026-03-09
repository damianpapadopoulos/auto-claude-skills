# Design: Native Memory System Integration

**Date**: 2026-03-09
**Status**: Approved
**Method**: Brainstorming → Multi-Agent Debate (architect, critic, pragmatist)
**Trigger**: Analysis of Google's Always-On Memory Agent repo identified patterns for persistent memory. Debate evaluated what transfers to our CLI plugin context.

## Context: Google's Always-On Memory Agent

Google published an open-source memory agent using ADK + Gemini 3.1 Flash-Lite with three specialist subagents (ingest, consolidate, query), SQLite storage, and 30-minute background consolidation. The key insight: background consolidation of session data into higher-level insights.

## Key Finding: Claude Code Already Has the Memory Layer

| Google Pattern | Our Equivalent | Gap? |
|---|---|---|
| Persistent storage (SQLite) | Claude Code auto-memory (`~/.claude/projects/*/memory/`) + CLAUDE.md | No |
| Background consolidation | Nothing — `/revise-claude-md` is manual-only | **Yes** |
| Structured memory schema | `skill-config.json` + session state files | No |
| No-vector-DB retrieval | Flat files + jq + Claude reasoning | No |

The real gap is not storage — it's **prompting users to maintain their memory**.

## What Was Explored and Rejected

### Cross-session learning (Google-style consolidation) — REJECTED
**Reason**: Claude Code's auto-memory already does this at the platform level. Building a second memory system duplicates functionality, confuses users about where preferences live, and adds maintenance burden with no clear value ceiling.

### Stop hook nudge (B1) — REJECTED after debate
The architect proposed a `session-stop-hook.sh` (~40 lines) that checks prompt count >= 8 and nudges users to run `/revise-claude-md`.

The critic landed five challenges:
1. **Prompt count is a bad proxy.** A 15-prompt debugging session doesn't need CLAUDE.md updates. A 3-prompt architectural decision does.
2. **Worst timing.** Session end = user is leaving. Suggesting more work fights psychology.
3. **Companion dependency.** `/revise-claude-md` requires `claude-md-management` plugin. Nudging toward an unavailable command is a UX landmine.
4. **No feedback loop.** No mechanism to learn if nudges were useful.
5. **Precedent.** Stop hook becomes a dumping ground for exit-time suggestions.

The critic proposed a **methodology hint** as a strictly better alternative:
- Fires during the session when context exists
- Uses existing infrastructure (zero new code)
- Claude can reason about relevance
- No new hook, no new state files

The pragmatist confirmed the methodology hint approach and raised a potentially fatal unknown: whether Stop hook output even surfaces to users.

### Project-scoped skill config — DEFERRED
Real problem, but premature. If the methodology hint + auto-memory path works, Claude naturally captures "in this project I always use X" without formal config. Revisit only if explicit per-project skill preferences are requested by users.

## Approved Design

### Change 1: Add CLAUDE.md to auto-claude-skills (dogfooding)

**Why**: The project is complex enough to need one (~2500 lines of hooks, custom scoring, composition chains, bash 3.2 constraints). Anyone working on this repo in Claude Code gets zero project context without it.

**Content** (~25 lines): Commands, architecture summary, style constraints (bash 3.2, 50ms budget, field separators), gotchas (regex exit codes, jq optional, session-token scoping).

**File**: `CLAUDE.md` at project root, checked into git.

**Maintenance**: Near-zero. Project structure is stable. The file itself is now a target for `claude-md-improver` and `/revise-claude-md`, creating a self-maintaining loop.

### Change 2: Methodology hint for CLAUDE.md maintenance

**Why**: Users who change project conventions or architecture during a session should be reminded to capture those changes. Methodology hints fire in-context when Claude can reason about relevance.

**Implementation**: Add a JSON entry to `config/default-triggers.json` in the `methodology_hints` array:

```json
{
  "name": "claude-md-maintenance",
  "triggers": ["(refactor|restructur|new.convention|architecture.change|reorganize|rename.*(module|package|directory))"],
  "hint": "CLAUDE.MD: If this session changed project conventions or structure, consider /revise-claude-md",
  "skill": "claude-md-improver",
  "phases": ["IMPLEMENT", "SHIP"]
}
```

**Behavior**: When the user's prompt matches the trigger regex AND the current phase is IMPLEMENT or SHIP, the hint appears in the skill-activation output. Claude sees it as context and can decide whether to act on it.

**Why not a new hook**: Methodology hints use the existing `skill-activation-hook.sh` pipeline. Zero new files, zero new state management, zero new test surface area.

## Dissenting Views

- **Critic**: The CLAUDE.md "dogfooding" framing is misleading — the real justification is project complexity. Accepted; design doc reflects this.
- **Pragmatist**: Stop hook output surfacing is unverified. Accepted; Stop hook was dropped.
- **Architect**: Proposed a 4-hour cooldown and session-state cleanup in the Stop hook. Rendered moot by switching to methodology hints.

## Trade-offs Accepted

1. **Methodology hints are prompt-dependent.** If the user never says "refactor" or "restructure," the hint never fires. We accept this because: the trigger regex can be expanded over time, and users who don't mention these terms likely aren't making CLAUDE.md-worthy changes.
2. **No automatic CLAUDE.md drift detection.** We accept staleness risk on the new CLAUDE.md because the project structure is stable and the file is small enough to verify manually during reviews.
3. **No Stop hook.** We lose the "session boundary" signal. We accept this because in-context hints are strictly more actionable than exit-time notifications.
