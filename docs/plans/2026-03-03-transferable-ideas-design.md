# Design: Transferable Ideas from SuperClaude & Oviva

**Date**: 2026-03-03
**Status**: Implemented
**Method**: Multi-Agent Debate (architect, critic, pragmatist)

## Problem Statement

Evaluate 7 candidate ideas from SuperClaude Framework (21k stars) and oviva-ag/claude-code-plugin for incorporation into auto-claude-skills. Ideas must deliver significant value (performance, token savings, time savings) over the current state with acceptable maintenance cost.

## Candidates Evaluated

| # | Candidate | Round 1 | Round 2 | Final |
|---|-----------|---------|---------|-------|
| 1 | Externalized trigger rules (JSON) | ALREADY DONE (3/3) | -- | **SKIP** |
| 2 | Batch scripting skill | BUILD (3/3) | Scope refined | **BUILD** |
| 3 | End-to-end workflow (issue->PR) | Split (1 recommend, 2 skip) | Architect conceded; critic counter-proposed issue-intake | **CONTESTED** |
| 4 | Confidence scoring (numeric) | SKIP (3/3) | -- | **SKIP** |
| 5 | Anti-hallucination red flags | Enhance existing (3/3) | Scope refined | **BUILD (enhancement)** |
| 6 | Selective plugin marketplace | SKIP (3/3) | -- | **SKIP** |
| 7 | Data-driven activation hook | ALREADY DONE (3/3) | -- | **SKIP** |

## Recommended: Batch Scripting Skill (#2)

**Consensus**: Unanimous BUILD across all three debaters.

**Why**: Fills a genuine gap — the system has no skill for bulk file operations using `claude -p`. Users hand-roll these loops every time they need large-scale transforms, migrations, or bulk refactoring.

**Scope** (pragmatist's scoping, endorsed by all):
- Single file: `skills/batch-scripting/SKILL.md` (~90 lines)
- Role: `workflow`, Phase: `IMPLEMENT`
- Triggers: `(batch|bulk|mass|across.*files|every.*file|all.*files|migrate|transform|refactor.*all|sweep|codemod|claude.?-p|headless)`

**The skill teaches 5 patterns**:
1. **Manifest first** — enumerate targets via Glob/Grep, confirm with user before processing
2. **Dry run** — transform 2-3 files, show diffs, get approval
3. **Loop with logging** — `claude -p` per file, append pass/fail to a text log
4. **Retry from log** — grep FAIL lines, pipe back into the loop (this IS resume)
5. **Verify** — run tests/linter after full batch, review git diff

**Explicitly excluded** (over-engineering):
- No JSON state files or atomic write infrastructure
- No rate-limit backoff logic (CLI handles its own limits)
- No checkpoint IDs or resume tokens
- No progress bars or fancy output
- No rollback infrastructure (git IS rollback)

**Key insight from critic**: "The skill is a recipe, not a runtime. Claude generates the actual bash each time, adapted to the specific task."

**Effort**: ~2 hours, 1 new file + registry entry.

## Recommended: Anti-Hallucination Red Flags (#5)

**Consensus**: Unanimous BUILD as an enhancement to `verification-before-completion`, not a standalone skill.

**Why**: False completion claims are a documented, recurring problem. A concrete checklist catches real failures that vague instructions miss.

**Implementation** (architect's Option A, endorsed by all):
Add ~15 lines to `skill-activation-hook.sh` — when `verification-before-completion` is in the selected skill set, append the red flags checklist to `additionalContext`:

```
HALT if any Red Flag is true:
- Claiming "tests pass" without showing test runner output
- Claiming "everything works" without running verification commands
- Referencing files/functions that were never read with the Read tool
- Claiming to have executed commands without corresponding Bash tool calls
- Saying "no changes needed" on code the user flagged as broken
- Skipping verification steps listed in the skill instructions
- Generating placeholder/stub/TODO implementations as final output
```

**Effort**: ~1 hour, modification to existing hook + optionally upstream PR to superpowers.

## Contested: Issue Intake (#3)

The architect conceded the full end-to-end workflow but the critic proposed a narrower alternative. The pragmatist rejected even the narrower version.

**Critic's counter-proposal**: Build an `issue-intake` skill (role: process, phase: DESIGN, ~50 lines) that parses a ticket URL, extracts requirements, creates a branch, and hands off to brainstorming via the existing `precedes` chain. This plugs into the composition system rather than competing with it.

**Pragmatist's counter**: Skip entirely. The gap is two shell commands (`gh issue view`, `EnterWorktree`). Add a 3-line methodology hint instead:
```json
{
  "triggers": ["(issue|ticket|story|feature.request|bug.report)"],
  "hint": "ISSUE-FIRST: Consider creating a GitHub issue (gh issue create) then a worktree (EnterWorktree) for isolated development."
}
```

**Trade-off**: The critic's version adds ~50 lines of skill + a registry entry but provides structured ticket parsing and context bootstrapping. The pragmatist's version adds 3 lines and covers 80% of the value.

**Decision needed from user**: methodology hint (3 lines, zero risk) vs. issue-intake skill (50 lines, more capable but couples to external tools).

## Rejected Ideas

### Confidence Scoring (#4) — SKIP (unanimous)
- LLMs are poorly calibrated — numeric confidence gives false precision
- Users anchor on meaningless numbers ("it said 95% but was wrong")
- The existing verification-before-completion skill checks concrete conditions (tests pass, lint clean) which is strictly better than self-assessed confidence

### Selective Plugin Marketplace (#6) — SKIP (unanimous)
- The existing `enabled`/`available` flags in the registry already handle toggling
- A marketplace requires versioning, dependency resolution, security review, compatibility matrices — enormous infrastructure for ~20 skills
- Third-party skills are effectively untrusted prompt injection — security nightmare
- Revisit when skill count exceeds 50

## Dissenting Views

- **Architect** initially pushed for #3 (end-to-end issue solver) as a "showcase for the composition system." Conceded after critic and pragmatist argued this fights the interactive phase-gate design and creates brittle coupling to external tools.
- **Critic** proposed the issue-intake skill as a compromise on #3. Pragmatist rejected this as unnecessary given methodology hints.

## Decision

Pending user approval. Recommendations:

1. **BUILD**: Batch scripting skill — new `SKILL.md` + registry entry (~2h)
2. **BUILD**: Red flags checklist — enhance hook + verification skill (~1h)
3. **DECIDE**: Issue intake — methodology hint (minimal) vs. skill (more capable)
