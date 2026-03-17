# auto-claude-skills

A [Claude Code](https://code.claude.com) plugin that routes skills, workflow guardrails, and optional tool integrations based on prompt intent and SDLC phase.

Instead of remembering which skill to invoke for each task, the plugin classifies your prompt, maps it to the current development phase, and injects the right skills, review flows, and companion-tool hints.

## What It Does

The plugin bundles a small set of skills and routes to many more from companion plugins — covering brainstorming, TDD, debugging, code review, planning, frontend design, security scanning, and more.

- **Prompt routing by intent.** Each prompt is scored against trigger patterns and matched to relevant skills. Prompts that match nothing produce no output — no noise on non-development work.

- **Phase-aware SDLC guidance.** The plugin tracks your position in a structured pipeline and adjusts what it suggests:

  | Phase | What the plugin does |
  |-------|---------------------|
  | DESIGN | Activates brainstorming, explores requirements before coding |
  | PLAN | Structures implementation into discrete tasks with dependency ordering |
  | IMPLEMENT | Enforces TDD, routes to parallel agents for independent work |
  | REVIEW | Triggers multi-perspective code review, processes feedback with rigor |
  | SHIP | Requires verification evidence, generates as-built docs, guides branch completion |
  | DEBUG | Scores highest priority, overrides the current phase with structured root-cause analysis |

- **Guardrails through hooks, not memory.** Phase composition enforces requirements like "write the failing test before implementation" and "show test runner output before claiming done" — computed fresh on every prompt.

- **Optional enrichment from companion tools.** When integrations like Jira, GitHub, Context7, Serena, or GCP Observability are installed, the routing engine injects phase-appropriate context to use them.

## Example Prompts

**"design a secure frontend component"** → DESIGN phase. Activates brainstorming (explore requirements before coding) and design-debate (multi-agent design exploration). With companion plugins, also activates frontend-design (UI patterns). Companion tools query library docs for relevant API constraints.

**"debug this login bug"** → DEBUG phase. Activates systematic-debugging (structured root-cause analysis). TDD is injected as a mandatory parallel — reproduce with a failing test before fixing. If GCP Observability is installed, context hints toward runtime logs.

**"ship this feature"** → SHIP phase. Activates a sequence starting with verification-before-completion (evidence before assertions), then openspec-ship (as-built documentation), through to finishing-a-development-branch (merge/PR/cleanup options).

## How It Works

1. **SessionStart** builds a cached skill registry by merging default triggers, skills discovered from installed plugins, and any user overrides from `~/.claude/skill-config.json`. Also recovers state from interrupted sessions after compaction.
2. **UserPromptSubmit** scores the prompt against trigger patterns — word-boundary matches score higher than substrings, and skill priority, name similarity, and keyword hits all contribute. The engine selects at most 1 process skill, 2 domain skills, and 1 workflow skill.
3. **Phase composition** layers in requirements appropriate to the detected phase: mandatory TDD during implementation, red-flag halts for unverified completion claims, multi-step sequencing during ship.
4. **Guard hooks** run on other lifecycle events — including OpenSpec compliance checks before commands, Serena nudges when Grep could use symbol navigation, context preservation before compaction, agent checkpoint tracking, teammate idle detection, and learning consolidation at session end.

## Install

**Prerequisites:**
- [Claude Code](https://code.claude.com) CLI
- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)

**Minimal install:**

```
/plugin marketplace add damianpapadopoulos/auto-claude-skills-marketplace
/plugin install auto-claude-skills@acsm
```

**Full experience:**

```
/setup
```

`/setup` walks you through installing companion plugins, skills, and MCP integrations. After setup, each session start shows what's active:

```
SessionStart: 24 skills active (12 of 12 plugins). Setup complete
```

The plugin works without every companion integration — it discovers what's installed and routes accordingly. More tools installed means richer context at each phase.

## Optional Integrations

Installed via `/setup` unless noted. The routing engine discovers these automatically and injects phase-appropriate context when they're present.

**Core workflow plugins** — superpowers (brainstorming, TDD, debugging, planning, code review), frontend-design, claude-md-management, claude-code-setup, pr-review-toolkit.

**MCP and context sources** — Context7 (library documentation), GitHub (PR and issue management), Serena (LSP-based symbol navigation), Forgetful Memory (cross-session architectural knowledge), Context Hub CLI (curated doc annotations).

**Phase enhancers** — commit-commands (structured commit/PR workflows), security-guidance (passive write-time guard), feature-dev (parallel exploration agents), hookify (custom behavior rules), skill-creator (skill benchmarking).

**Atlassian managed integration** — Jira and Confluence connect via `/mcp` as a claude.ai managed MCP, not through `/setup`.

## Configuration

Optional. Create `~/.claude/skill-config.json` to customize routing behavior:

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

## What It Is Not

- **Not IDE autocomplete.** It doesn't suggest code inline — it routes to skills and workflows that guide how you work.
- **Not a ticketing or backlog system.** It can pull context from Jira via MCP, but doesn't manage tickets.
- **Not a deployment or observability platform.** It can hint at GCP tools during debugging, but doesn't deploy or monitor.

It orchestrates Claude Code's in-session workflow and points to external tools where relevant.

## Uninstalling

```
/plugin uninstall auto-claude-skills@acsm
```
