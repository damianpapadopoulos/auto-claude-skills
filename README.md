# auto-claude-skills v3.0

Intelligent skill activation hook for Claude Code with **config-driven routing**, **role-based orchestration**, and **agent team support** across the design-plan-implement-review-ship pipeline.

## Quick start

Inside Claude Code:

```
/plugin marketplace add damianpapadopoulos/auto-claude-skills-marketplace
/plugin install auto-claude-skills@acsm
```

Then run the interactive setup to configure agent teams and download external skills:

```
/setup
```

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

## What gets installed

### Plugin install (automatic)

| Component | Path | Purpose |
|-----------|------|---------|
| Skill activation hook | `hooks/skill-activation-hook.sh` | Routes prompts to skills (`UserPromptSubmit`) |
| Session start hook | `hooks/session-start-hook.sh` | Builds skill registry, auto-installs cozempic (`SessionStart`) |
| Manifest fixer | `hooks/fix-plugin-manifests.sh` | Strips invalid keys from cached plugin manifests |
| TeammateIdle guard | `hooks/teammate-idle-guard.sh` | Conditional heartbeat for agent team teammates |
| Hook registration | `hooks/hooks.json` | Automatic hook wiring |
| Default triggers | `config/default-triggers.json` | Curated trigger patterns for all skills |
| Fallback registry | `config/fallback-registry.json` | Static fallback when jq is unavailable |
| Setup command | `commands/setup.md` | Interactive setup via `/setup` |

### Bundled skills

| Skill | Phase | Purpose |
|-------|-------|---------|
| `agent-team-execution` | IMPLEMENT | File-disjoint specialist delegation for parallel implementation |
| `agent-team-review` | REVIEW | Multi-perspective parallel review (security, quality, spec) |
| `design-debate` | DESIGN | Multi-Agent Debate with architect, critic, and pragmatist |

These are discovered automatically from `skills/` at session start. No manual installation needed.

### External skills (optional, via `/setup`)

| Skill | Source |
|-------|--------|
| doc-coauthoring | [anthropics/skills](https://github.com/anthropics/skills) |
| webapp-testing | [anthropics/skills](https://github.com/anthropics/skills) |
| security-scanner | [matteocervelli/llms](https://github.com/matteocervelli/llms) |

## Architecture

```
SessionStart:
  session-start-hook.sh scans four sources:
    1. ~/.claude/plugins/cache/*/superpowers/*/skills/   (superpowers plugin)
    2. ~/.claude/plugins/cache/*/                        (other official plugins)
    3. ${PLUGIN_ROOT}/skills/                            (bundled skills)
    4. ~/.claude/skills/*/SKILL.md                       (user-installed skills)
  --> merges with config/default-triggers.json
  --> builds ~/.claude/.skill-registry-cache.json

UserPromptSubmit:
  skill-activation-hook.sh reads the cached registry
  --> matches prompt against trigger patterns
  --> scores and ranks matches (word-boundary +3, substring +1)
  --> caps by role (1 process, 2 domain, 1 workflow)
  --> emits context with invocation hints

TeammateIdle:
  teammate-idle-guard.sh checks for unfinished tasks
  --> nudge if teammate owns in_progress tasks, allow idle otherwise

Fallback:
  If jq is missing, attempts auto-install via brew/apt.
  If still unavailable, falls back to config/fallback-registry.json.
```

The registry is built once at session start and cached. The routing engine reads the cache on every prompt — no re-scanning, no external API calls.

## Skill roles

Skills are classified into three roles that determine how they compose:

| Role | Behavior | Cap | Examples |
|------|----------|-----|---------|
| **Process** | Drives the current phase. One active at a time. | 1 | brainstorming, writing-plans, TDD, systematic-debugging |
| **Domain** | Specialized knowledge. Active alongside any process skill. | 2 | frontend-design, security-scanner, doc-coauthoring |
| **Workflow** | Lifecycle actions. Triggered by specific moments. | 1 | finishing-a-dev-branch, agent-team-execution |

Maximum 3 skills suggested per prompt (configurable).

### How roles compose

Process skills drive. Domain skills inform. Workflow skills stand alone.

```
SKILL ACTIVATION (3 skills | Build Dashboard)

Process: brainstorming -> Skill(superpowers:brainstorming)
  INFORMED BY: frontend-design -> Skill(frontend-design:frontend-design)
  INFORMED BY: security-scanner -> Skill(security-scanner)

Evaluate: **Phase: DESIGN** | brainstorming YES/NO, frontend-design YES/NO, security-scanner YES/NO
```

## The development pipeline

```
DESIGN --> PLAN --> IMPLEMENT --> REVIEW --> SHIP
                       ^
                     DEBUG (reactive -- can interrupt any phase)
```

| Phase | Skills activated | Transition |
|-------|-----------------|------------|
| **DESIGN** | brainstorming, design-debate (opt-in MAD) | Design approved |
| **PLAN** | writing-plans | Plan saved to docs/plans/ |
| **IMPLEMENT** | subagent-driven-development, executing-plans, TDD; agent-team-execution (3+ tasks) | All tasks complete |
| **REVIEW** | requesting-code-review, receiving-code-review; agent-team-review (5+ files) | Review approved |
| **SHIP** | verification-before-completion, finishing-a-development-branch | Merged/deployed |
| **DEBUG** | systematic-debugging, TDD | Fix verified, return to prior phase |

## Recommended plugins

```
/plugin marketplace add anthropics/claude-plugins-official
/plugin marketplace add obra/superpowers-marketplace
```

```
/plugin install superpowers@superpowers-marketplace
/plugin install frontend-design@claude-plugins-official
/plugin install claude-code-setup@claude-plugins-official
/plugin install claude-md-management@claude-plugins-official
/plugin install ralph-loop@claude-plugins-official
/plugin install pr-review-toolkit@claude-plugins-official
```

These provide 15+ additional skills. The registry discovers them automatically.

## User configuration

All configuration is optional. No config file = full curated experience.

Create `~/.claude/skill-config.json` to customize:

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

## Testing

```bash
bash tests/run-tests.sh
```

| Test file | What it validates |
|-----------|------------------|
| `test-registry.sh` | Registry build from all sources, caching, fallback, user config |
| `test-routing.sh` | Prompt-to-skill matching, scoring, role caps, degradation |
| `test-context.sh` | Context injection format, JSON validity |
| `test-install.sh` | Plugin structure: hooks, configs, bundled skills |

Tests are isolated — each creates a temp directory with mock plugin caches.

## File listing

```
auto-claude-skills/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata
├── commands/
│   └── setup.md                 # /setup command (agent teams opt-in, external skills)
├── config/
│   ├── default-triggers.json    # Trigger patterns, roles, priorities for all skills
│   └── fallback-registry.json   # Static fallback when jq is unavailable
├── hooks/
│   ├── hooks.json               # Hook registration (SessionStart, UserPromptSubmit, TeammateIdle)
│   ├── session-start-hook.sh    # Registry builder, cozempic/jq auto-install
│   ├── skill-activation-hook.sh # Routing engine
│   ├── fix-plugin-manifests.sh  # Plugin manifest cleanup
│   └── teammate-idle-guard.sh   # Conditional teammate heartbeat
├── skills/
│   ├── agent-team-execution/    # Parallel specialist teams (Lead/Specialist/Reviewer)
│   │   ├── SKILL.md
│   │   ├── lead-prompt.md
│   │   ├── specialist-prompt.md
│   │   ├── reviewer-prompt.md
│   │   └── shared-contracts-template.md
│   ├── agent-team-review/       # Multi-perspective parallel code review
│   │   └── SKILL.md
│   └── design-debate/           # Multi-Agent Debate for design decisions
│       └── SKILL.md
├── tests/
│   ├── run-tests.sh
│   ├── test-helpers.sh
│   ├── test-registry.sh
│   ├── test-routing.sh
│   ├── test-context.sh
│   └── test-install.sh
└── docs/
    └── integrations/
        └── agent-teams-and-cozempic.md
```

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
- `jq` — auto-installed via brew/apt if missing; manual: `brew install jq` / `sudo apt install jq`
- `git` (optional, for external skills via `/setup`)

## Uninstalling

```
/plugin uninstall auto-claude-skills@acsm
```
