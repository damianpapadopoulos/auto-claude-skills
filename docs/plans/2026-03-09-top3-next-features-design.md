# Design: Top 3 Next Features

**Date**: 2026-03-09
**Status**: Approved
**Method**: Multi-Agent Debate (architect, critic, pragmatist) — 1 round + synthesis

## Problem Statement

The system has mature routing mechanics (23 skills, 8 plugins, 6 compositions) but is flying blind on outcomes, generating unnecessary context noise, and losing composition state during compaction. What are the three highest-value next investments?

## Recommended Approach (synthesized from debate)

### Feature 1: Silence + False-Positive Defense

**Ship the already-approved fitness review Tier 1 changes + add negative regression tests.**

Rationale: The fitness review (2026-03-03) reached 3/3 consensus on silencing zero-match output and 2/3 on restricting full format. These changes have been approved for 6 days while new features keep adding more output. The system wastes ~4000 tokens/session of pure noise, which contributes to compaction pressure — the root cause of composition fragility (pain point #3) and agent team failures (#8).

Changes:
1. **Silence zero-match output** — emit nothing when 0 skills match (~5 lines)
2. **Full format only on prompt 1** — change threshold from `<= 5` to `<= 1` (~1 line)
3. **Kill YES/NO evaluation ceremony** — remove mandatory visible evaluation (~1 line)
4. **Reduce segment name-boost from +40 to +20** — fixes multi-intent distortion (~1 line)
5. **Drop overflow "Also relevant:" display** — respects role caps (~10 lines)
6. **Add false-positive test suite** — 20-30 negative test cases proving common prompts ("rename this variable", "explain this function", "where is X defined") trigger zero skills. Prove multi-intent prompts route correctly. (~80 lines tests)
7. **Add user escape hatch** — if prompt contains `[no-skills]` or starts with `--`, early-exit without additionalContext (~5 lines)

Effort: ~25 lines production + ~80 lines tests
Files: `skill-activation-hook.sh`, `test-routing.sh`

### Feature 2: Zero-Match Diagnostics

**Log what misses, surface the rate. Defer the PostToolUse feedback loop.**

This is the 20%-effort version of activation telemetry. It tells you *what's failing* before building infrastructure to measure what's working.

Changes:
1. **Log zero-match prompts** — append lowercased prompt to `~/.claude/.skill-zero-match-log` alongside existing counter increment (~5 lines). Rotate at 100 entries.
2. **Surface zero-match rate at session start** — read previous session's counters before reset, append to health message: `| last session: 3/47 prompts unmatched (6%)` (~8 lines). Only report if total prompts > 10.
3. **Extend /skill-explain diagnostics** — read the zero-match log and report top 10 recent unmatched prompts, zero-match rate, and suggested trigger gaps (~30 lines command).

Effort: ~45 lines production + ~40 lines tests
Files: `skill-activation-hook.sh`, `session-start-hook.sh`, `commands/skill-explain.md`, `test-routing.sh`

### Feature 3: Compaction-Resilient Composition State

**Replace text markers with a file-backed state that survives compaction.**

Changes:
1. **Write composition state to file** — on each matched prompt where a composition chain is active, write `~/.claude/.skill-composition-state-{session}` containing chain, current index, and confirmed completions (~10 lines). Uses already-computed `_full_chain`, `_current_idx`, `_LAST_INVOKED_SKILL`.
2. **Read in compact-recovery-hook.sh** — on post-compaction recovery, read the state file and emit a "Composition Recovery" block alongside existing team checkpoint (~8 lines).
3. **Replace [DONE?] with definitive [DONE]** — use persisted `completed` array as ground truth instead of inferring from last-invoked signal (~10 lines in `_walk_composition_chain`).

State file format:
```json
{
  "chain": ["brainstorming", "writing-plans", "executing-plans"],
  "current_index": 1,
  "completed": ["brainstorming"],
  "updated_at": "2026-03-09T14:30:00Z"
}
```

Effort: ~28 lines production + ~40 lines tests
Files: `skill-activation-hook.sh`, `compact-recovery-hook.sh`, `test-context.sh`

## Dissenting Views

- **Architect** ranked PostToolUse activation telemetry as #1. Overruled: both Critic and Pragmatist argued it's premature — measuring a noisy system with ~60% false-positive triggers produces noisy data. Zero-match diagnostics (Feature 2) is the right prerequisite.
- **Architect** ranked git-state phase inference as #2. Overruled: both Critic and Pragmatist argued no evidence that wrong-phase inference is the bottleneck, and git commands in the hot path risk the 50ms budget. Zero-match log data will reveal whether phase mis-inference is actually causing misses.
- **Critic** proposed the escape hatch as a standalone #3. Folded into Feature 1 as a bonus (~5 lines) since it naturally belongs with the noise-reduction work.

## Trade-offs

- **Deferring PostToolUse telemetry** means we don't get per-skill acceptance rates yet. Accepted: zero-match diagnostics covers the 80% case. PostToolUse remains viable as a future step once Feature 1 creates a clean baseline.
- **Deferring git-state phase signal** means we still rely on regex for phase inference. Accepted: Feature 2 data will quantify whether this matters.
- **Adding file-backed composition state** introduces mutable session state (previously avoided by design). Accepted: the existing last-invoked signal and prompt counter already use this pattern. Composition state follows the same session-scoped, fail-open approach.

## Totals

| Feature | Production Lines | Test Lines | Files Touched | Ships Independently |
|---------|-----------------|------------|---------------|-------------------|
| 1. Silence + Defend | ~25 | ~80 | 2 | Yes |
| 2. Zero-Match Diagnostics | ~45 | ~40 | 4 | Yes |
| 3. Composition State | ~28 | ~40 | 3 | Yes |
| **Total** | **~98** | **~160** | **7** | — |

## Decision

Approved. All three features ship independently. Implement in order: Feature 1 first (unblocks cleaner measurement), Feature 2 second (adds visibility), Feature 3 third (fixes the workflow fragility).
