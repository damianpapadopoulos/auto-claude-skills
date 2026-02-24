# Cozempic Compaction Integration Design

**Date:** 2026-02-24
**Status:** Approved
**Scope:** Hook changes only (no cozempic Python changes)

## Problem

Claude Code auto-compacts sessions when context approaches the window limit. Compaction summarizes the conversation, destroying raw JSONL messages including team state (TeamCreate, SendMessage, TaskCreate). The current PreCompact hook only runs `cozempic checkpoint` — it saves team state but doesn't prune the session, so Claude still compacts a bloated JSONL.

## Goal

Make cozempic auto-fire a full treat (prune) whenever compaction fires — both auto and manual (`/compact`). This is a layered defense:

1. **Layer 1 (proactive):** Guard daemon prunes at 50MB threshold (already exists)
2. **Layer 2 (pre-compact):** PreCompact hook runs `cozempic treat` before Claude summarizes — NEW
3. **Layer 3 (post-compact recovery):** SessionStart/compact hook re-injects critical state — NEW

## Design

### 1. PreCompact hook: checkpoint + treat

**Current:**
```json
{
  "hooks": [{ "type": "command", "command": "cozempic-wrapper.sh checkpoint" }]
}
```

**New:**
```json
{
  "hooks": [{ "type": "command", "command": "pre-compact-hook.sh" }]
}
```

No matcher — fires on both `auto` and `manual` compaction.

`pre-compact-hook.sh`:
1. Runs `cozempic checkpoint` (save team state)
2. Runs `cozempic treat current -rx standard --execute` (prune JSONL in-place)
3. Logs the event (JSONL size, timestamp) to `~/.claude/.compact-events.log` for future adaptive calibration

The treat runs in-place (no reload). Claude will still compact, but the JSONL is now smaller, so the summary is higher quality.

### 2. SessionStart/compact hook: post-compaction recovery

New hook entry with matcher `"compact"`:

`compact-recovery-hook.sh`:
1. If `.claude/team-checkpoint.md` exists, outputs its contents to stdout (injected into Claude's context)
2. Outputs a brief reminder of active session state
3. Logs the post-compaction file size for calibration

### 3. Files changed

| File | Change |
|------|--------|
| `hooks/hooks.json` | PreCompact command → `pre-compact-hook.sh`; add SessionStart/compact entry |
| `hooks/pre-compact-hook.sh` | New script: checkpoint + treat + log |
| `hooks/compact-recovery-hook.sh` | New script: re-inject team state + skill registry |

### What stays the same

- Guard daemon (SessionStart) — proactive pruning layer
- PostToolUse checkpoints on Task/TaskCreate/TaskUpdate
- Stop hook checkpoint
- cozempic-wrapper.sh
- TeammateIdle guard

## Future: Adaptive Calibration (Phase C)

When ready, add to cozempic Python:
- `pre-compact-hook.sh` already logs JSONL size at compaction time
- Guard reads `~/.claude/.compact-events.log` on startup
- Adjusts hard threshold to `median(logged_sizes) * 0.8` (prune before Claude would compact)
- Over time, compaction never fires because guard pre-empts it

## Behavior on treat failure

If `cozempic treat` fails (not installed, permission error, etc.), the hook exits 0 silently (consistent with cozempic-wrapper.sh behavior). Compaction proceeds normally. This is fail-open by design.
