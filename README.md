# auto-claude-skills v2.0

Intelligent skill activation hook for Claude Code with **config-driven routing** and **role-based orchestration** across the design-plan-implement-review-ship pipeline.

## How it works

The hook uses a **three-tier classification** system powered by a dynamic skill registry. Trigger patterns are defined in config, not hardcoded. Claude itself is the final classifier — it already has full conversation context.

```
User prompt
  |
  |-- Tier 1: FAST PATH (registry trigger match, <100ms)
  |   Triggers match? --> pre-select skills + phase checkpoint
  |
  |-- Tier 2: FALLTHROUGH (dev-related but no trigger match)
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

Matched skills are grouped by role — a **process** skill drives the phase, **domain** skills inform it, and **workflow** skills fire independently when their moment arrives.

## Quick start

### Plugin install (recommended)

Inside Claude Code:

```
/plugin marketplace add damianpapadopoulos/auto-claude-skills-marketplace
/plugin install auto-claude-skills@acsm
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
| Skill activation hook | `hooks/skill-activation-hook.sh` — runs on every prompt (`UserPromptSubmit`) |
| Session start hook | `hooks/session-start-hook.sh` — builds the skill registry at startup (`SessionStart`) |
| Manifest fixer hook | `hooks/fix-plugin-manifests.sh` — runs on startup (`SessionStart`), strips invalid keys from cached plugin manifests |
| Hook registration | Automatic via `hooks/hooks.json` |
| Default triggers | `config/default-triggers.json` — curated trigger patterns for all skills |
| Fallback registry | `config/fallback-registry.json` — static fallback for degraded environments |
| Setup command | `/setup` — downloads external skills on demand |

### External skills (optional, via `/setup` or `install.sh`)

| Skill | Source |
|-------|--------|
| doc-coauthoring | `~/.claude/skills/doc-coauthoring/` |
| webapp-testing | `~/.claude/skills/webapp-testing/` |
| security-scanner | `~/.claude/skills/security-scanner/` |

## Architecture

```
SessionStart:
  session-start-hook.sh scans three sources:
    1. ~/.claude/plugins/cache/*/     (installed plugins)
    2. ~/.claude/skills/*/SKILL.md    (user-installed skills)
    3. Built-in defaults              (shipped with auto-claude-skills)
  --> builds ~/.claude/.skill-registry-cache.json

UserPromptSubmit:
  skill-activation-hook.sh reads the cached registry
  --> matches prompt against trigger patterns
  --> scores and ranks matches (exact +3, partial +1, phase-aligned +2)
  --> caps by role (1 process, 2 domain, 1 workflow)
  --> emits context with invocation hints

Fallback:
  If registry cache is missing or corrupt, falls back to
  config/fallback-registry.json (bundled static registry)
```

The registry is built once at session start and cached. The routing engine reads the cache on every prompt — no re-scanning, no external API calls.

## Skill roles

Skills are classified into three roles that determine how they compose:

| Role | Behavior | Cap | Examples |
|------|----------|-----|---------|
| **Process** | Drives the current phase. One active at a time. Selected by phase + trigger match. | 1 | brainstorming, writing-plans, TDD, systematic-debugging |
| **Domain** | Specialized knowledge. Active alongside any process skill. Phase-independent. | 2 | frontend-design, security-scanner, doc-coauthoring |
| **Workflow** | Lifecycle actions. Triggered by specific moments. Standalone. | 1 | finishing-a-dev-branch, dispatching-parallel-agents |

Maximum 3 skills suggested per prompt (configurable).

### How roles compose

Process skills drive. Domain skills inform. Workflow skills stand alone.

When multiple roles match, the context output shows their relationship:

```
SKILL ACTIVATION (3 skills | Build Dashboard)

Process: brainstorming -> Skill(superpowers:brainstorming)
  INFORMED BY: frontend-design -> Skill(frontend-design:frontend-design)
  INFORMED BY: security-scanner -> Read ~/.claude/skills/security-scanner/SKILL.md

Evaluate: **Phase: DESIGN** | brainstorming YES/NO, frontend-design YES/NO, security-scanner YES/NO
```

Composition keywords:
- `INFORMED BY` — domain skill provides context within the process skill's workflow
- `THEN` — sequential process skill handoff (e.g., brainstorming THEN writing-plans)
- `WITH` — co-active skills in the same phase

## Recommended plugins

First add the marketplaces:

```
/plugin marketplace add anthropics/claude-plugins-official
/plugin marketplace add obra/superpowers-marketplace
```

Then install the plugins:

```
/plugin install superpowers@superpowers-marketplace
/plugin install frontend-design@claude-plugins-official
/plugin install claude-code-setup@claude-plugins-official
/plugin install claude-md-management@claude-plugins-official
/plugin install ralph-loop@claude-plugins-official
/plugin install pr-review-toolkit@claude-plugins-official
```

> These provide 15+ additional skills for the full pipeline. The registry discovers them automatically from `~/.claude/plugins/cache/`.

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

## User configuration

All configuration is optional. No config file = full curated experience.

Create `~/.claude/skill-config.json` to customize behavior:

```json
{
  "overrides": {
    "brainstorming": {
      "triggers": ["+prototype", "+spike", "-design"],
      "enabled": true
    },
    "security-scanner": {
      "enabled": false
    }
  },
  "custom_skills": [
    {
      "name": "my-team-conventions",
      "role": "domain",
      "invoke": "Skill(my-team-conventions)",
      "triggers": ["review", "refactor", "new file"],
      "description": "Team-specific coding standards"
    }
  ],
  "settings": {
    "max_suggestions": 3,
    "verbosity": "normal"
  }
}
```

### Trigger override syntax

- `"+keyword"` — add to existing defaults
- `"-keyword"` — remove from defaults
- `"keyword"` (no prefix) — replace all defaults

### Settings

- `max_suggestions` — cap on total skills per prompt (default 3)
- `verbosity` — `"minimal"` | `"normal"` | `"verbose"`

### Priority guide

Within each role, higher priority wins when multiple skills match the same prompt:

| Role | Skills (highest priority first) |
|------|-------------------------------|
| Process | systematic-debugging (50) > writing-plans (40) > brainstorming (30) > code-review (25) > TDD (20) > executing-plans (15) |
| Workflow | verification (20) > finishing-branch (19) > parallel-agents (15) > worktrees (14) |
| Domain | frontend/security/docs (15) > webapp-testing/automation (12) > claude-md (10) |

### Merge order

static fallback -> dynamic discovery -> starter pack triggers -> user config overrides

## Testing

83 tests across 4 test files, no dependencies beyond bash and jq:

```bash
bash tests/run-tests.sh
```

| Test file | What it validates |
|-----------|------------------|
| `tests/test-registry.sh` | Registry build from all sources, caching, fallback, user config |
| `tests/test-routing.sh` | Prompt-to-skill matching, scoring, role caps, graceful degradation |
| `tests/test-context.sh` | Context injection format (zero/compact/full), JSON validity |
| `tests/test-install.sh` | File presence, JSON validity, hook registration |

Tests are isolated — each creates a temp directory with mock plugin caches. No dependency on actual installed skills.

## File listing

| File | Purpose |
|------|---------|
| `hooks/skill-activation-hook.sh` | Routing engine — reads registry, matches prompts |
| `hooks/session-start-hook.sh` | Registry builder + health check |
| `hooks/fix-plugin-manifests.sh` | Strips invalid keys from cached plugin manifests |
| `hooks/hooks.json` | Hook registration |
| `config/default-triggers.json` | Curated trigger patterns for all skills |
| `config/fallback-registry.json` | Static fallback for degraded environments |
| `tests/run-tests.sh` | Test runner |
| `tests/test-registry.sh` | Registry build tests |
| `tests/test-routing.sh` | Prompt-to-skill matching tests |
| `tests/test-context.sh` | Context injection format tests |
| `tests/test-install.sh` | Install/uninstall tests |
| `tests/test-helpers.sh` | Shared test utilities |

## Performance

| Scenario | Time | Context cost |
|----------|------|-------------|
| Early exit (/command, short) | ~30ms | 0 tokens |
| Silent exit (non-dev prompt) | ~70ms | 0 tokens |
| Fallthrough (dev, no keyword) | ~80ms | ~105 tokens |
| Fast path (simple match) | ~90ms | ~140 tokens |
| Fast path (5 skills) | ~100ms | ~158 tokens + skill files |

## Companion tools

### Cozempic (recommended for long sessions)

[Cozempic](https://github.com/Ruya-AI/cozempic) prevents context bloat from killing sessions that use subagents or agent teams. It checkpoints team/subagent state and protects it from compaction pruning.

```bash
pip install cozempic
cozempic init
```

Zero conflicts with auto-claude-skills — they use different hook events. See [docs/integrations/agent-teams-and-cozempic.md](docs/integrations/agent-teams-and-cozempic.md) for details.

### Agent teams (future)

Native Claude Code agent teams support is stubbed in `default-triggers.json` (disabled). When agent teams exit experimental status and the compaction bug ([#23620](https://github.com/anthropics/claude-code/issues/23620)) is fixed, the `agent-team-execution` skill can be activated. See [docs/integrations/agent-teams-and-cozempic.md](docs/integrations/agent-teams-and-cozempic.md) for the activation checklist.

## Prerequisites

- [Claude Code](https://code.claude.com) CLI
- `jq` -- `brew install jq` / `sudo apt install jq`
- `git` (for external skills download)

## Uninstalling

Plugin install:
```
/plugin uninstall auto-claude-skills@acsm
```

Legacy install:
```bash
./uninstall.sh
```
