# auto-claude-skills

Intelligent skill activation hook for Claude Code with **phase-aware routing** across the design-plan-implement-review-ship pipeline.

## How it works

The hook uses a **two-tier classification** system. Regex catches obvious intents fast. For everything else, Claude itself is the classifier -- it already has full conversation context.

```
User prompt
  |
  |-- Tier 1: FAST PATH (regex, <100ms)
  |   Keywords match? --> pre-select skills + phase checkpoint
  |
  |-- Tier 2: FALLTHROUGH (dev-related but no keyword match)
  |   --> emit phase checkpoint only, 0 pre-selected skills
  |   --> Claude assesses intent from conversation context
  |
  |-- Tier 3: SILENT EXIT (not dev-related)
  |   "what time is it" --> no output, no context cost
  |
  |-- Phase checkpoint (always present for Tier 1 + 2):
  |   Claude assesses: "We have a design but no plan --> PLAN phase
  |   --> I'll activate writing-plans. Sound good?"
  |
  '-- User confirms, adjusts, or skips to a different phase
```

Cross-cutting overlays (security, frontend, docs, meta, parallel) fire additively when their keywords appear.

## Quick start

### Plugin install (recommended)

Inside Claude Code:

```
/plugin install auto-claude-skills
```

Then optionally download external skills:

```
/setup
```

### Manual install (legacy)

```bash
git clone https://github.com/damianpapadopoulos/auto-claude-skills.git
cd auto-claude-skills
./install.sh
```

## What gets installed

### Plugin install

| Component | Location |
|-----------|----------|
| Hook script | Managed by plugin system (`hooks/skill-activation-hook.sh`) |
| Hook registration | Automatic via `hooks/hooks.json` |
| Setup command | `/setup` — downloads external skills on demand |

### External skills (optional, via `/setup` or `install.sh`)

| Skill | Source |
|-------|--------|
| doc-coauthoring | `~/.claude/skills/doc-coauthoring/` |
| webapp-testing | `~/.claude/skills/webapp-testing/` |
| security-scanner | `~/.claude/skills/security-scanner/` |

## Recommended plugins

First add the marketplaces:

```
/plugin marketplace add anthropics/claude-plugins-official
/plugin marketplace add obra/superpowers-marketplace
```

Then install the plugins:

```
/plugin install superpowers@superpowers-marketplace
/plugin install frontend-design@claude-plugin-directory
/plugin install claude-code-setup@claude-plugin-directory
/plugin install claude-md-management@claude-plugin-directory
/plugin install ralph-loop@claude-plugin-directory
/plugin install pr-review-toolkit@claude-plugin-directory
```

> These provide 15+ additional skills for the full pipeline. The hook detects them by their install path under `~/.claude/plugins/cache/claude-plugins-official/`.

## The development pipeline

The phase checkpoint maps to Superpowers' designed sequence:

```
DESIGN --> PLAN --> IMPLEMENT --> REVIEW --> SHIP
                       ^
                     DEBUG (reactive -- can interrupt any phase)
```

| Phase | Skills activated | Transition to next |
|-------|-----------------|-------------------|
| **DESIGN** | brainstorming -> *chains to writing-plans* | Design approved by user |
| **PLAN** | writing-plans -> *chains to execution* | Plan saved to docs/plans/ |
| **IMPLEMENT** | subagent-driven-development, executing-plans, TDD | All tasks complete, tests passing |
| **REVIEW** | requesting-code-review, receiving-code-review | Review approved |
| **SHIP** | verification-before-completion, finishing-a-development-branch | Merged/deployed |
| **DEBUG** *(reactive)* | systematic-debugging, TDD | Fix verified -> return to interrupted phase |

At every phase transition, Claude confirms with the user before proceeding.

## Routing examples

| You say | What happens | Claude says |
|---------|-------------|-------------|
| "build a login system" | Fast path: Build New, 2 skills. Claude assesses DESIGN. | "I'll start by brainstorming the design. Let me ask some questions..." |
| "looks good, plan it out" | Fallthrough: dev-related, 0 skills. Claude assesses PLAN. | "I'll create an implementation plan. Ready to proceed?" |
| "continue the implementation" | Fast path: Plan Execution, 2 skills. Claude assesses IMPLEMENT. | "Starting task 1 of the plan using TDD..." |
| "the email sender throws errors" | Fast path: Fix/Debug, 2 skills. Claude assesses DEBUG. | "Switching to systematic debugging. I'll return to the plan after." |
| "all green, merge to main" | Fast path: Ship, 2 skills. Claude assesses SHIP. | "Running verification, then merge options." |
| "thanks for the help" | Silent exit. No output, no context cost. | *(normal response)* |

## Skill inventory (18 skills)

### Primary intent (regex pre-filter)

| Phase | Skills | Priority |
|-------|--------|----------|
| **Fix / Debug** | systematic-debugging, TDD | 1st |
| **Plan Execution** | subagent-driven-dev, executing-plans | 2nd |
| **Build New** | brainstorming, TDD | 3rd |
| **Review** | requesting-code-review, receiving-code-review | 4th |
| **Ship / Complete** | verification, finishing-a-dev-branch | 5th |

### Cross-cutting overlays

| Overlay | Skills | Triggers |
|---------|--------|----------|
| Security | security-scanner | secure, vulnerability, OWASP, HIPAA, XSS |
| Frontend | frontend-design, webapp-testing | UI, frontend, dashboard, CSS |
| Documentation | doc-coauthoring | proposal, spec, RFC |
| Meta | claude-automation-recommender, claude-md-improver, writing-skills | CLAUDE.md, skill, hook, MCP |
| Parallel | dispatching-parallel-agents, using-git-worktrees | parallel, multiple failures, independent |

### Methodology hints (if plugins installed)

| Plugin | When suggested |
|--------|--------------|
| Ralph Loop | migrate, batch, overnight, iterate, "until tests pass" |
| PR Review Toolkit | review, PR, pull request |

## Performance

| Scenario | Time | Context cost |
|----------|------|-------------|
| Early exit (/command, short) | ~30ms | 0 tokens |
| Silent exit (non-dev prompt) | ~70ms | 0 tokens |
| Fallthrough (dev, no keyword) | ~80ms | ~105 tokens |
| Fast path (simple match) | ~90ms | ~140 tokens |
| Fast path (5 skills) | ~100ms | ~158 tokens + skill files |

## Prerequisites

- [Claude Code](https://code.claude.com) CLI
- `jq` -- `brew install jq` / `sudo apt install jq`
- `git` (for external skills download)

## Uninstalling

Plugin install:
```
/plugin uninstall auto-claude-skills
```

Legacy install:
```bash
./uninstall.sh
```
