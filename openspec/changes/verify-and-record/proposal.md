# Proposal: deterministic verification-verdict writer

## Why

The project-verification skill's Step 3 has the MODEL author the verdict JSON
(`"failed": [], "gate_gaming_status": "clean"`) into
`~/.claude/.skill-project-verified-<token>` — the artifact the push gate
consumes. Two problems, both observed 2026-07-15 during the gate-status ship:

1. Claude Code's auto-mode permission classifier denies that write as
   self-approval (per-instance — a second write at a new HEAD was denied the
   same day), adding a human prompt to every verification cycle.
2. The provenance is genuinely weak: the values are transcribed by the model,
   not measured by the thing that ran the gate. The skill's own docs disclaim
   the artifact as forgeable.

A pilot (same day, n=1) confirmed a script that runs the gate and writes the
verdict from its own measured exit codes is NOT flagged by the classifier —
it keys on visible command shape.

## What Changes

- `scripts/verify-and-record.sh`: parses `.verify.yml` (the discovery
  ladder's deterministic top rung), runs each declared command with stdin
  nulled, runs `gate-gaming-check.sh`, and writes the verdict JSON from its
  own measured results. Failures, exit-127 (could-not-run), and an unrunnable
  gate-gaming check are recorded honestly; nothing is asserted.
- `skills/project-verification/SKILL.md` Step 3: invoke the script when
  `.verify.yml` exists; otherwise offer to write `.verify.yml` first, or fall
  back to the existing model-authored flow (which may prompt for approval).
- Tests incl. a red fixture proving a failing gate is recorded as
  `failed:[…]`, never laundered to clean.

## Honest framing (not a security boundary)

This improves ergonomics and measured provenance for an HONEST writer. It
does NOT make the artifact trustworthy: the file remains writable by any
shell command, script indirection would pass the classifier for a dishonest
writer too, and external CI remains the only real trust boundary (unchanged
from the skill's existing disclaimer).

## Non-goals

- Discovery beyond `.verify.yml` (manifest/CLAUDE.md rungs stay model-driven
  in the skill).
- Adding the writer to `_GATE_ENFORCE_LIBS`/canary: that list covers
  gate-ENFORCEMENT components whose silent loss fails the gate OPEN. This
  writer's loss fails toward DENY (no fresh verdict → routing governance
  blocks) — more friction, not less enforcement — so it does not belong on
  the canary list (same logic as the deliberate consol-marker.sh exclusion).
