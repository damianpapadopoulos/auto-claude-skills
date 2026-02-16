# Agent Teams & Cozempic Integration

**Date**: 2026-02-16
**Status**: Path A active, Path B deferred
**Prerequisites tracking**: See [Activation Checklist](#path-b-activation-checklist) below

## Overview

Two complementary integration paths for multi-agent workflows:

- **Path A** — Cozempic as infrastructure (active now, zero code changes)
- **Path B** — Agent team routing in auto-claude-skills (deferred, stubs in place)

## Path A: Cozempic Integration

### What it is

[Cozempic](https://github.com/Ruya-AI/cozempic) is a context management tool that prevents session bloat from killing long-running or multi-agent Claude Code sessions. It solves the critical failure mode where context compaction destroys team state (GitHub issue [#23620](https://github.com/anthropics/claude-code/issues/23620)).

### Why it matters now

auto-claude-skills already dispatches Task-based subagents via Superpowers skills (executing-plans, subagent-driven-development, dispatching-parallel-agents). Any session that runs multiple subagents risks context bloat. Cozempic protects these sessions today.

### What cozempic does

Five-layer protection:

1. **Hook-driven checkpointing** — saves team/subagent state at critical moments
2. **Continuous extraction** — tracks subagent spawns, task status, results from JSONL
3. **Tiered pruning** — gentle/standard/aggressive prescriptions with team message protection
4. **Reactive overflow recovery** — kqueue-based file watcher detects sudden bloat spikes
5. **Persistent checkpoints** — `.claude/team-checkpoint.md` survives compaction

### Hook compatibility

Zero conflicts with auto-claude-skills:

| Hook Event | auto-claude-skills | Cozempic | Conflict? |
|-----------|-------------------|----------|-----------|
| `SessionStart` | Registry build (sync) | Guard daemon spawn | None — array append |
| `UserPromptSubmit` | Skill routing | Not used | None |
| `PostToolUse[Task]` | Not used | Checkpoint | None |
| `PostToolUse[TaskCreate\|TaskUpdate]` | Not used | Checkpoint | None |
| `PreCompact` | Not used | Checkpoint | None |
| `Stop` | Not used | Final checkpoint | None |

### Installation

```bash
pip install cozempic
cozempic init
```

This appends hooks to `~/.claude/settings.json` (idempotent, preserves existing hooks). auto-claude-skills hooks in `hooks.json` (plugin-level) are unaffected.

### Verification

After installing both:

```bash
# Verify auto-claude-skills hooks (plugin-level)
cat ~/.claude/plugins/cache/*/auto-claude-skills/*/hooks/hooks.json

# Verify cozempic hooks (settings-level)
jq '.hooks' ~/.claude/settings.json

# Both should show their respective hook registrations without overlap
```

### Runtime behavior

```
SessionStart:
  1. auto-claude-skills: session-start-hook.sh builds registry (sync, ~2s)
  2. cozempic: guard daemon spawns in background

UserPromptSubmit:
  1. auto-claude-skills: skill-activation-hook.sh routes prompt

PostToolUse[Task]:
  1. cozempic: checkpoints subagent state

PreCompact:
  1. cozempic: last-chance checkpoint before compaction

(No ordering dependencies — they operate on different events)
```

---

## Path B: Agent Team Routing (Deferred)

### What it would do

When a plan has 3+ independent tasks, the routing engine could suggest team-based execution instead of sequential subagent dispatch. This means:

- A new process skill (or skill variant) for team-based execution
- Trigger patterns that detect parallelizable work
- Context output that suggests `TeamCreate` + teammate spawning instead of `Task()` subagents

### Why it's deferred

Three prerequisites must be met:

1. **Agent teams exit experimental status** — currently requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
2. **Context compaction bug gets a native fix** — GitHub issue [#23620](https://github.com/anthropics/claude-code/issues/23620) causes lead agents to forget teammates after compaction. No native recovery mechanism exists.
3. **Superpowers updates coordination skills for teams** — the three coordination skills (dispatching-parallel-agents, subagent-driven-development, executing-plans) are marked as orphaned in the latest Superpowers version (e16d611eee14). GitHub issue [obra/superpowers#429](https://github.com/obra/superpowers/issues/429) tracks team support.

### Architecture when activated

```
UserPromptSubmit:
  skill-activation-hook.sh detects plan with independent tasks
  --> suggests "agent-team-execution" skill (role: workflow)
  --> context output includes team formation hints

The skill itself would:
  1. Evaluate plan tasks for independence (no shared files, no sequential deps)
  2. TeamCreate with descriptive team name
  3. Spawn teammates via Task tool with team_name parameter
  4. Use shared TaskCreate/TaskUpdate for coordination
  5. Monitor via TaskList, steer via SendMessage
  6. TeamDelete on completion
```

### What's in place now

**Registry stub** in `config/default-triggers.json`:

```json
{
  "name": "agent-team-execution",
  "role": "workflow",
  "phase": "IMPLEMENT",
  "triggers": ["agent.team", "team.execute", "parallel.team", "swarm"],
  "priority": 16,
  "requires": ["writing-plans"],
  "description": "Team-based parallel execution for plans with independent tasks",
  "enabled": false,
  "_deferred": {
    "reason": "Waiting for agent teams to exit experimental status",
    "tracking": [
      "https://github.com/anthropics/claude-code/issues/23620",
      "https://github.com/obra/superpowers/issues/429"
    ],
    "activate_when": "all three prerequisites met — see docs/integrations/agent-teams-and-cozempic.md"
  }
}
```

This entry is:
- **Discovered** by the registry builder (appears in cache)
- **Disabled** by default (`enabled: false`)
- **Activatable** by user config override: `{"overrides": {"agent-team-execution": {"enabled": true}}}`
- **Self-documenting** via `_deferred` metadata

### Path B activation checklist

When prerequisites are met, activation requires:

- [ ] Set `"enabled": true` in default-triggers.json for `agent-team-execution`
- [ ] Create the skill itself — either as a Superpowers skill (preferred, if [#429](https://github.com/obra/superpowers/issues/429) lands) or as a user skill in `~/.claude/skills/agent-team-execution/SKILL.md`
- [ ] Update `session-start-hook.sh` to discover team-related skills (if Superpowers adds them)
- [ ] Add team-specific triggers to the default set (plan-aware patterns)
- [ ] Add tests in `tests/test-routing.sh` for team skill selection
- [ ] Update README with team execution section
- [ ] Consider adding cozempic as a recommended companion (guards against residual compaction issues)

### Agent teams reference

For implementation, these are the key tools and patterns:

**Tools**: `TeamCreate`, `TeamDelete`, `SendMessage` (message/broadcast/shutdown_request), `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`

**Hooks**: `TeammateIdle` (exit 2 to keep working), `TaskCompleted` (exit 2 to reject)

**Enable**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json env or shell

**Display**: `teammateMode: "auto" | "in-process" | "tmux"` in settings.json

**Known failure modes**:
- Context compaction destroys team awareness (no native recovery)
- `/resume` doesn't restore teammates
- Two teammates editing same file causes overwrites
- Delegate mode bug: teammates spawned after entering delegate mode inherit restrictions
- One team per session, fixed leadership

**File structure**:
```
~/.claude/teams/{team-name}/config.json      # team metadata
~/.claude/teams/{team-name}/inboxes/*.json   # agent mailboxes
~/.claude/tasks/{team-name}/*.json           # shared task list
```
