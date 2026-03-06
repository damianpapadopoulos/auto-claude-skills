# auto-claude-skills

A [Claude Code](https://code.claude.com) plugin that automatically activates the right skills at the right time. Instead of remembering which skill to invoke for each task, the plugin matches your prompt to relevant skills and suggests them — so you stay in flow.

## Install

```
/plugin marketplace add damianpapadopoulos/auto-claude-skills-marketplace
/plugin install auto-claude-skills@acsm
/setup
```

`/setup` walks you through installing companion plugins, skills, and MCP integrations. On each session start:

```
SessionStart: 24 skills active (7 of 14 plugins). Run /setup for the full experience.
```

## How it works

Every prompt is classified and matched to up to 3 relevant skills:

- **Fast path** — prompt matches trigger keywords, skills suggested instantly
- **Fallthrough** — development-related but no keyword match, Claude assesses from context
- **Silent exit** — non-development prompt, no output

The plugin tracks your position in a structured SDLC pipeline and suggests skills accordingly:

```
DESIGN -> PLAN -> IMPLEMENT -> REVIEW -> SHIP
                      |
                    DEBUG (can interrupt any phase)
```

When companion plugins and MCP integrations are available (Jira, GitHub, Context7, GCP, Playwright, etc.), the routing engine injects contextual hints to use them at the right phase.

## What's included

**4 bundled skills:** agent-team-execution, agent-team-review, design-debate, batch-scripting

**23 total routed skills** from superpowers, official plugins, and external skill sources — covering brainstorming, TDD, debugging, code review, planning, frontend design, security scanning, and more.

**12 companion plugins** across three tiers, installed via `/setup`:

| Tier | Plugins |
|------|---------|
| **Core** (5) | superpowers, frontend-design, claude-md-management, claude-code-setup, pr-review-toolkit |
| **MCP** (2) | context7, github |
| **Phase enhancers** (5) | commit-commands, security-guidance, feature-dev, hookify, skill-creator |

Atlassian (Jira/Confluence) is available as a claude.ai managed integration — connect via `/mcp`.

## Configuration

Optional. Create `~/.claude/skill-config.json` to customize:

```json
{
  "overrides": {
    "brainstorming": { "triggers": ["+prototype", "-design"] },
    "security-scanner": { "enabled": false }
  },
  "custom_skills": [
    {
      "name": "my-conventions",
      "role": "domain",
      "invoke": "Skill(my-conventions)",
      "triggers": ["review", "refactor"],
      "description": "Team coding standards"
    }
  ]
}
```

Trigger syntax: `"+keyword"` adds, `"-keyword"` removes, `"keyword"` replaces all defaults.

## Diagnostics

```
/skill-explain "design a secure frontend component"
```

Shows trigger matches, scoring, role-cap filtering, and the context that would be injected.

| Variable | Effect |
|----------|--------|
| `SKILL_EXPLAIN=1` | Routing explanation with raw scores to stderr |
| `SKILL_VERBOSE=1` | Full output regardless of session depth |

## Prerequisites

- [Claude Code](https://code.claude.com) CLI
- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)

## Uninstalling

```
/plugin uninstall auto-claude-skills@acsm
```
