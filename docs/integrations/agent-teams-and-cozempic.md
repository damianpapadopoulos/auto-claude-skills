# Agent Teams & Cozempic Integration

**Date**: 2026-02-16
**Status**: Both paths active
**Prerequisites tracking**: See [Activation Checklist](#path-b-activation-checklist) below

## Overview

Two complementary integration paths for multi-agent workflows:

- **Path A** — Cozempic as infrastructure (active now, zero code changes)
- **Path B** — Agent team routing in auto-claude-skills (active, three skills deployed)

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

## Path B: Agent Team Routing (Active)

### What it does

When a plan has 3+ independent tasks, the routing engine suggests team-based execution. Three new skills provide the team workflow:

| Skill | Phase | Role | Purpose |
|-------|-------|------|---------|
| `design-debate` | DESIGN | domain | MAD pattern with architect, critic, pragmatist (opt-in escalation) |
| `agent-team-execution` | IMPLEMENT | workflow | File-disjoint specialist delegation for parallel implementation |
| `agent-team-review` | REVIEW | workflow | Multi-perspective parallel review (security, quality, spec) |

### Skill locations

```
~/.claude/skills/design-debate/SKILL.md
~/.claude/skills/agent-team-execution/SKILL.md
~/.claude/skills/agent-team-review/SKILL.md
```

These are user-installed skills discovered by the registry builder at SessionStart.

### TeammateIdle guard

The `teammate-idle-guard.sh` hook prevents false-positive idle nudges. It checks `~/.claude/tasks/{team}/*.json` for in-progress tasks owned by the idle teammate before nudging.

Wired automatically at SessionStart via `session-start-hook.sh`.

### Activation checklist

- [x] Set `"enabled": true` in default-triggers.json for `agent-team-execution`
- [x] Create `agent-team-execution` skill at `~/.claude/skills/agent-team-execution/SKILL.md`
- [x] Create `agent-team-review` skill at `~/.claude/skills/agent-team-review/SKILL.md`
- [x] Create `design-debate` skill at `~/.claude/skills/design-debate/SKILL.md`
- [x] Add `agent-team-review` and `design-debate` to default-triggers.json
- [x] Add TeammateIdle guard hook (`hooks/teammate-idle-guard.sh`)
- [x] Wire TeammateIdle hook at SessionStart
- [x] Add cozempic auto-install at SessionStart
- [x] Add routing tests for new skills
- [x] Add registry discovery tests
- [x] Update README and setup docs

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
