# Serena Subagent Propagation Investigation — Design + Plan

**Date:** 2026-05-07
**Status:** Phase A approved (cross-model baseline + persistence + PR). Phase B (fix decisions) gated on Phase A data.
**Driver:** Empirical finding from 5-iteration Haiku 4.5 baseline (PR #28 fixture): subagent banner propagation broken at 20% pass rate. Plugin is multi-user; we owe users either a fix or a documented limitation.

## Problem

The Serena triggering redesign (PR #25) delegates Serena-guidance propagation to Claude itself: the SessionStart banner instructs the parent context to include `Serena available — prefer find_symbol over Grep` in any Task spawn prompt for code work. PR #28's behavioral fixture validates this empirically; the Haiku 4.5 baseline shows 1/5 pass rate (broken classification).

Two failure modes are possible and not yet distinguished:
1. **Universal failure** — banner instructions are weak across model classes; plugin-level fix needed.
2. **Haiku-specific** — smaller models drop the instruction; larger models honor it; document as a model-class limitation, optional reword for Haiku coverage.

Without cross-model data, any Phase-B fix decision is half-blind.

## Capabilities Affected

- `skill-routing` — potential SessionStart banner reword (Phase B, gated).
- `behavioral-evaluation` — confirms `claude -p --model <alias>` works without runner changes (no extension needed if `CLAUDE_BIN="claude --model <alias>"` succeeds).
- Documentation — fixture README updates, CHANGELOG entry, memory entry update, archive of variance reports.

## Out-of-Scope

- **Phase B implementation work** — banner reword, edit-plugin-owned-agent-SKILL.md, parked-matcher revival. Decision and execution gated on Phase A data.
- **Variance > 10 iterations per model.** 10 is sufficient for stable/flaky/broken classification; 20+ is diminishing returns.
- **Models beyond Haiku/Sonnet/Opus 4.x.** Older or third-party models out of scope.
- **Tool-call introspection in the runner.** The runner asserts on text output only, by design.
- **Sandbox-via-`--disallowedTools` runner extension** — separate concern (per project memory `feedback_inner_claude_p_tool_access`); not blocking this investigation since we run from a dedicated worktree.

## Approach (Phase A)

1. **Persist Haiku-5 baseline** to `docs/plans/archive/2026-05-07-serena-propagation-baseline-haiku-n5.md` (force-add — directory is gitignored).
2. **Run variance 10 each on three models** in the existing worktree at `../auto-claude-skills-evals`:
   - Haiku 4.5 (default; tightens Haiku-5's bands)
   - Sonnet 4.6 (`CLAUDE_BIN="claude --model sonnet"`)
   - Opus 4.7 (`CLAUDE_BIN="claude --model opus"`)
   Each run writes a distinct variance report under `docs/plans/2026-05-07-serena-propagation-baseline-<model>-n10.md`.
3. **Copy all four reports** to live repo `docs/plans/archive/`.
4. **Update memory entry** `project_serena_triggering_redesign.md` with the cross-model finding and what it means for the 14-day decision.
5. **Update fixture README** at `tests/fixtures/serena/README.md` with the actual baseline and result-interpretation table grounded in real data.
6. **CHANGELOG note** under `[Unreleased]` framing this as "investigating subagent propagation reliability across model classes."
7. **Open one PR** with all the above.

## Acceptance Scenarios

- **GIVEN** the runner is invoked with `CLAUDE_BIN="claude --model sonnet"`, **WHEN** Phase A runs Sonnet variance 10, **THEN** the variance report lists `claude-sonnet-4-6` (or its current alias) as the model and produces classification rows for all three assertions.
- **GIVEN** all four reports (Haiku-5, Haiku-10, Sonnet-10, Opus-10), **WHEN** the PR is opened, **THEN** the four reports are present under `docs/plans/archive/` and the memory entry references the cross-model breakdown by classification (stable / flaky / broken per model per assertion).
- **GIVEN** a future session resumes work in this repo on or after 2026-05-21, **WHEN** memory loads, **THEN** the Serena project entry surfaces the empirical propagation finding and the Phase-B decision tree (model-specific vs universal).
- **GIVEN** the assertion 1 (Serena reference) classification across all three models, **WHEN** the result is universal `broken`, **THEN** Phase B begins with banner reword as the cheapest experiment; **OR WHEN** the result is Haiku-specific, **THEN** Phase B documents model-class limitation and optionally reword for Haiku.

## Decision

Execute Phase A. Hold Phase B for the next session/PR informed by Phase A data. No code changes to hooks, scripts, or tests in this PR; Phase A is documentation + measurement only.
