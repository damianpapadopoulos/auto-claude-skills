# auto-claude-skills v4.0: Comprehensive Plugin Orchestration

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to create an implementation plan from this design.

## Problem

auto-claude-skills currently integrates with 5 of the 29+ official marketplace plugins. Seven high-value plugins close real gaps in the development pipeline but have zero routing, discovery, or composition support. Additionally, any plugin installed from community marketplaces is invisible to the routing engine.

## Design Decisions

1. **Superpowers flow is primary** — the skill chain (brainstorm -> plan -> execute -> review -> ship) remains the backbone. New plugins augment by chaining alongside or running in parallel via agent teams.
2. **Comprehensive orchestrator** — auto-claude-skills becomes the single entry point for the entire installed ecosystem.
3. **Auto-discovery + curated manifest hybrid** — auto-scan all plugin directories for basic routing; provide deep integration (phase mapping, composition rules) for curated high-value plugins.
4. **Phase-specific composition rules** — per-phase rules define how plugins compose with superpowers skills (parallel agents, sequential steps, methodology hints).

## Architecture

### Change 1: Plugin Registry in default-triggers.json

Add a `plugins` section mapping every known official marketplace plugin to its capabilities:

```json
{
  "version": "4.0.0",
  "skills": [ "/* existing 21 entries, unchanged */" ],
  "methodology_hints": [ "/* existing, unchanged */" ],

  "plugins": [
    {
      "name": "commit-commands",
      "source": "claude-plugins-official",
      "provides": {
        "commands": ["/commit", "/commit-push-pr", "/clean_gone"],
        "skills": [],
        "agents": [],
        "hooks": []
      },
      "phase_fit": ["SHIP"],
      "description": "Structured commit workflows and branch-to-PR automation"
    },
    {
      "name": "security-guidance",
      "source": "claude-plugins-official",
      "provides": {
        "commands": [],
        "skills": [],
        "agents": [],
        "hooks": ["PreToolUse:security-patterns"]
      },
      "phase_fit": ["*"],
      "description": "Write-time security blocker for XSS, injection, unsafe deserialization"
    },
    {
      "name": "hookify",
      "source": "claude-plugins-official",
      "provides": {
        "commands": ["/hookify", "/hookify:list", "/hookify:configure"],
        "skills": ["writing-rules"],
        "agents": ["conversation-analyzer"],
        "hooks": []
      },
      "phase_fit": ["DESIGN"],
      "description": "Custom rule authoring for Claude behavior guards"
    },
    {
      "name": "feature-dev",
      "source": "claude-plugins-official",
      "provides": {
        "commands": ["/feature-dev"],
        "skills": [],
        "agents": ["code-explorer", "code-architect", "code-reviewer"],
        "hooks": []
      },
      "phase_fit": ["DESIGN", "IMPLEMENT", "REVIEW"],
      "description": "Full feature pipeline with parallel exploration and architecture agents"
    },
    {
      "name": "code-review",
      "source": "claude-plugins-official",
      "provides": {
        "commands": ["/code-review"],
        "skills": [],
        "agents": [],
        "hooks": []
      },
      "phase_fit": ["REVIEW"],
      "description": "5 parallel review agents with confidence scoring, posts to GitHub"
    },
    {
      "name": "code-simplifier",
      "source": "claude-plugins-official",
      "provides": {
        "commands": [],
        "skills": [],
        "agents": ["code-simplifier"],
        "hooks": []
      },
      "phase_fit": ["REVIEW"],
      "description": "Post-review code clarity and simplification pass"
    },
    {
      "name": "skill-creator",
      "source": "claude-plugins-official",
      "provides": {
        "commands": [],
        "skills": ["skill-creator"],
        "agents": ["executor", "grader", "comparator", "analyzer"],
        "hooks": []
      },
      "phase_fit": ["DESIGN"],
      "description": "Skill eval/improvement loop with benchmarking"
    }
  ]
}
```

Each plugin entry declares what it provides (commands, skills, agents, hooks) and which pipeline phases it fits into. The session-start hook marks each `available: true/false` based on installation state.

### Change 2: Phase Composition Rules in default-triggers.json

A `phase_compositions` section defines per-phase orchestration:

```json
{
  "phase_compositions": {
    "DESIGN": {
      "driver": "brainstorming",
      "parallel": [
        {
          "plugin": "feature-dev",
          "use": "agents:code-explorer",
          "when": "installed",
          "purpose": "Parallel codebase exploration while brainstorming clarifies intent"
        }
      ],
      "hints": [
        {
          "plugin": "feature-dev",
          "text": "Consider /feature-dev for agent-parallel feature development",
          "when": "installed"
        },
        {
          "plugin": "skill-creator",
          "text": "Consider Skill(skill-creator) to eval/benchmark skill quality",
          "when": "installed AND prompt matches skill"
        },
        {
          "plugin": "hookify",
          "text": "Consider /hookify to create behavior rules",
          "when": "installed AND prompt matches (prevent|block|guard|rule)"
        }
      ]
    },
    "PLAN": {
      "driver": "writing-plans",
      "parallel": [],
      "hints": []
    },
    "IMPLEMENT": {
      "driver": "executing-plans",
      "parallel": [
        {
          "plugin": "security-guidance",
          "use": "hooks:PreToolUse",
          "when": "installed",
          "purpose": "Passive write-time security guard (always active, no explicit invocation)"
        }
      ],
      "hints": []
    },
    "REVIEW": {
      "driver": "requesting-code-review",
      "parallel": [
        {
          "plugin": "code-review",
          "use": "commands:/code-review",
          "when": "installed AND has_github_remote",
          "purpose": "Run 5 parallel review agents and post findings to GitHub PR"
        },
        {
          "plugin": "code-simplifier",
          "use": "agents:code-simplifier",
          "when": "installed",
          "purpose": "Post-review simplification pass for clarity"
        }
      ],
      "hints": [
        {
          "plugin": "code-review",
          "text": "Consider /code-review for automated multi-agent PR review",
          "when": "installed"
        }
      ]
    },
    "SHIP": {
      "driver": "verification-before-completion",
      "sequence": [
        {
          "plugin": "commit-commands",
          "use": "commands:/commit",
          "when": "installed",
          "purpose": "Execute structured commit after verification passes"
        },
        {
          "step": "finishing-a-development-branch",
          "purpose": "Branch cleanup, merge, or PR creation"
        },
        {
          "plugin": "commit-commands",
          "use": "commands:/commit-push-pr",
          "when": "installed AND user chooses PR option",
          "purpose": "Automated branch-to-PR flow"
        }
      ],
      "hints": [
        {
          "plugin": "commit-commands",
          "text": "Consider /commit-push-pr for automated branch-to-PR workflow",
          "when": "installed"
        }
      ]
    },
    "DEBUG": {
      "driver": "systematic-debugging",
      "parallel": [],
      "hints": []
    }
  }
}
```

**Composition types:**
- `parallel`: dispatch alongside the driver skill for concurrent execution
- `sequence`: ordered steps after the driver completes (SHIP phase)
- `hints`: methodology suggestions the user can opt into

### Change 3: Auto-Discovery in session-start-hook.sh

Extend the session-start hook to:

1. Scan ALL plugin directories under `~/.claude/plugins/cache/*/` (all marketplaces)
2. For each plugin found, check if it exists in the curated `plugins` section
3. If curated: mark `available: true`, copy full metadata into registry cache
4. If unknown: auto-generate a basic entry by scanning:
   - `skills/*/SKILL.md` -> extract skill names
   - `commands/*.md` -> extract command names
   - `agents/*.md` -> extract agent names
   - `hooks/hooks.json` -> detect hook registrations
   - Set `phase_fit: ["*"]` (all phases)
   - No composition rules (basic routing only)
5. Write merged registry to `~/.claude/.skill-registry-cache.json`

### Change 4: Routing Engine Output in skill-activation-hook.sh

After skill selection and phase determination, look up `phase_compositions` for the current phase. Append to the output context:

- `PARALLEL:` lines for available parallel entries
- `SEQUENCE:` lines for available sequence entries (SHIP phase)
- Enhanced methodology hints from the `hints` entries

Output stays under ~40 lines. Only available plugins appear.

**Example REVIEW output:**
```
SKILL ACTIVATION (2 skills | Review + Domain)

Process: requesting-code-review -> Skill(superpowers:requesting-code-review)
  INFORMED BY: security-scanner -> Skill(security-scanner)
  PARALLEL: /code-review -> 5 parallel review agents, posts to GitHub PR [code-review]
  PARALLEL: code-simplifier agent -> post-review clarity pass [code-simplifier]

Evaluate: **Phase: [REVIEW]** | requesting-code-review YES/NO, security-scanner YES/NO
- Consider /code-review for automated multi-agent PR review
```

### Change 5: Fallback Registry Update

Update `config/fallback-registry.json` to include the curated plugins section for graceful degradation when `jq` is unavailable.

## Phase Composition Summary

| Phase | Driver (superpowers) | Parallel/Sequence (plugins) |
|-------|---------------------|-----------------------------|
| DESIGN | brainstorming | feature-dev code-explorer, skill-creator, hookify |
| PLAN | writing-plans | -- |
| IMPLEMENT | executing-plans / subagent-driven-dev | security-guidance (passive hook) |
| REVIEW | requesting-code-review | code-review (5 agents -> GitHub), code-simplifier |
| SHIP | verification-before-completion | /commit -> finishing-branch -> /commit-push-pr |
| DEBUG | systematic-debugging | -- |

## Scope Boundaries

**In scope:**
- Plugin registry and phase composition in default-triggers.json
- Auto-discovery of all installed plugins in session-start-hook.sh
- PARALLEL/SEQUENCE/hint output in skill-activation-hook.sh
- Fallback registry update
- Tests for all new functionality

**Out of scope (future work):**
- Runtime state tracking between prompts (phase hint files)
- Wiring up precedes/requires fields in routing logic
- Trigger quality metrics / feedback loop
- Community marketplace indexing beyond auto-discovery
