# auto-claude-skills

A [Claude Code](https://code.claude.com) plugin that automatically activates the right skills at the right time. Instead of remembering which skill to invoke for each task, this plugin matches your prompt to relevant skills and suggests them — so you stay in flow.

## Install

```
/plugin marketplace add damianpapadopoulos/auto-claude-skills-marketplace
/plugin install auto-claude-skills@acsm
/setup
```

The `/setup` command walks you through installing companion plugins, enabling agent teams, and downloading external skills.

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
    "max_suggestions": 3
  },
  "greeting_blocklist": "^(hi|hello|hey|thanks)([[:space:]].*)?$"
}
```

Trigger override syntax: `"+keyword"` adds to defaults, `"-keyword"` removes from defaults, `"keyword"` (no prefix) replaces all defaults.

The `greeting_blocklist` is a regex that suppresses skill activation for greetings and acknowledgements. The default covers ~40 common phrases (hi, hello, thanks, ok, sure, etc.).

## Composition chains

Skills can declare `precedes` and `requires` relationships to form multi-step workflows:

```
brainstorming → writing-plans → executing-plans
verification-before-completion → finishing-a-development-branch
```

When you enter mid-workflow (e.g. "execute the plan"), the plugin shows the full chain with `[DONE?] / [CURRENT] / [NEXT]` markers and a directive to continue to the next step.

## Depth-aware verbosity

The plugin reduces output as your session progresses to save context budget:

| Prompt count | Format |
|-------------|--------|
| 1–5 | Full (phase guide + step-by-step instructions) |
| 6–10 | Compact (skill list + eval line) |
| 11+ | Minimal (skills + eval only) |

Set `SKILL_VERBOSE=1` to force full output regardless of depth.

## Debugging & diagnostics

### `/skill-explain`

Test how the routing engine scores any prompt:

```
/skill-explain "design a secure frontend component"
```

Shows trigger matches, word-boundary vs substring scoring, name-boost detection, role-cap filtering decisions, and the context that would be injected.

### Environment variables

| Variable | Effect |
|----------|--------|
| `SKILL_EXPLAIN=1` | Emit structured routing explanation to stderr |
| `SKILL_DEBUG=1` | Emit raw sorted scores to stderr |
| `SKILL_VERBOSE=1` | Force full-verbosity output regardless of session depth |

## Agent teams

The plugin includes infrastructure for collaborative agent teams (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`):

- **Idle guard** — nudges idle teammates who have unfinished tasks (120s cooldown)
- **Compact hooks** — checkpoints team state before compaction and re-injects it after recovery
- **Bundled skills** — agent-team-execution, agent-team-review, design-debate

Run `/setup` to enable agent teams.

## Prerequisites

- [Claude Code](https://code.claude.com) CLI
- `jq` — required for skill routing. Install with `brew install jq` (macOS) or `apt install jq` (Linux). The plugin warns on startup if jq is missing and falls back to a static registry with reduced functionality.

## Uninstalling

```
/plugin uninstall auto-claude-skills@acsm
```
