# Proposal: Commit-SHA checkpoints in openspec-ship tasks.md

## Why

Nothing in the stack maps commits to planned task boundaries in a durable, reviewable artifact: `hooks/lib/branch-ledger.sh` records only gate milestones, verification verdicts bind to a single SHA, and Superpowers task plans live in gitignored `docs/plans/`. `git log` cannot reconstruct the mapping without a convention. Adopted from the Conductor (gemini-cli-extensions) triage — issue #129, evidence grade Medium, kill criterion pre-registered.

## What Changes

- `skills/openspec-ship/SKILL.md`: the retrospective `tasks.md` template (plan-derived branch only) gains a resolution-note header and optional per-task `[checkpoint: <sha7>]` suffixes, attributed by the SHIP-time model from `git log <merge-base>..HEAD` — stamped only where confidently attributable, bare otherwise. A new step runs the validator and folds its summary line into the ship report.
- New `scripts/checkpoint-validate.sh`: deterministic integrity floor — every stamped SHA must exist on the branch; malformed or foreign stamps fail validation (a stamped lie is worse than no stamp).
- New `tests/test-checkpoint-validate.sh`: red-first scratch-repo coverage.

## Capabilities

- **Modified:** `openspec-ship` (tasks.md artifact contract + one new step)

## Impact

Doc-grade only. No hook, gate, or config involvement; no new commit-message discipline; archives are never retro-stamped. Kill criterion (from issue #129): two consecutive shipped features whose checkpoints nobody reads → remove the stamping step.
