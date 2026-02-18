# auto-claude-skills

A [Claude Code](https://code.claude.com) plugin that automatically activates the right skills at the right time. Instead of remembering which skill to invoke for each task, this plugin matches your prompt to relevant skills and suggests them — so you stay in flow.

## Install

```
/plugin marketplace add damianpapadopoulos/auto-claude-skills-marketplace
/plugin install auto-claude-skills@acsm
/setup
```

The `/setup` command configures agent teams and optionally installs external skills.

## What it does

Every time you submit a prompt, the plugin classifies it and suggests relevant skills:

- **Fast path** — your prompt matches known trigger keywords → skills are suggested instantly
- **Fallthrough** — development-related but no keyword match → Claude assesses intent from context
- **Silent exit** — non-development prompt → no output, zero overhead

Suggestions follow a structured development pipeline:

```
DESIGN → PLAN → IMPLEMENT → REVIEW → SHIP
                    ↑
                  DEBUG (can interrupt any phase)
```

The plugin tracks which phase you're in and suggests skills accordingly. For example, if you have a design but no plan, it nudges you toward planning skills.

## Skill roles

Skills are classified into roles that determine how they compose:

| Role | What it does | Example |
|------|-------------|---------|
| **Process** | Drives the current phase (1 at a time) | brainstorming, TDD, systematic-debugging |
| **Domain** | Specialized knowledge (up to 2) | frontend-design, security-scanner |
| **Workflow** | Lifecycle actions (1 at a time) | finishing-a-dev-branch, agent-team-execution |

Up to 3 skills are suggested per prompt. Process skills drive, domain skills inform, workflow skills stand alone.

## Bundled skills

| Skill | Purpose |
|-------|---------|
| `agent-team-execution` | Parallel implementation with specialist agent teams |
| `agent-team-review` | Multi-perspective code review (security, quality, spec) |
| `design-debate` | Multi-Agent Debate with architect, critic, and pragmatist |

## Recommended plugins

The plugin auto-discovers skills from any installed plugin. These are good companions:

```
/plugin marketplace add anthropics/claude-plugins-official
/plugin marketplace add obra/superpowers-marketplace
```

```
/plugin install superpowers@superpowers-marketplace
/plugin install frontend-design@claude-plugins-official
/plugin install claude-md-management@claude-plugins-official
/plugin install pr-review-toolkit@claude-plugins-official
```

## Configuration

All configuration is optional. Without a config file you get the full curated experience.

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

Trigger override syntax: `"+keyword"` adds to defaults, `"-keyword"` removes from defaults, `"keyword"` (no prefix) replaces all defaults.

## Prerequisites

- [Claude Code](https://code.claude.com) CLI
- `jq` (auto-installed if missing)

## Uninstalling

```
/plugin uninstall auto-claude-skills@acsm
```
