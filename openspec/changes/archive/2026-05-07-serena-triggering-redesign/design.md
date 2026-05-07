# Design: Serena Triggering Redesign

## Architecture

Three layers:

1. **Active matcher** — `hooks/serena-nudge.sh` (PreToolUse on `Grep`) emits `additionalContext` recommending Serena symbol tools when the pattern classifies into one of: `definition_prefix`, `camelcase`, `snake_case`, `word_boundary`, `dotted_qualified`. On fire, also writes a TSV line to `~/.claude/.serena-nudge-telemetry`.

2. **Silent observers** — `hooks/serena-observer.sh` (PreToolUse on `Read|Glob|Edit`) classifies parked-matcher candidates without emitting any user-visible output. Recorded classes: `read_large_source`, `glob_definition_hunt`, `edit_symbol_token`. Purpose: gather evidence for revival criteria.

3. **Follow-through correlator** — `hooks/serena-followthrough.sh` (PostToolUse on `^mcp__serena__`) appends `followup` records when a Serena MCP tool runs within 3 turns of an unmarked nudge or observation in the same session. Idempotent via a `(turn, matcher)` composite key.

The reporting script `scripts/serena-telemetry-report.sh` joins these record types into per-class follow-through %.

The SessionStart banner change instructs the parent to propagate Serena guidance into Task spawn prompts. Subagents inherit guidance through Claude's compliance with that instruction; in-band Grep nudges cover the rest because PreToolUse hooks fire regardless of session origin.

## Dependencies

- `jq` — already required by other hooks. Optional fallbacks present where existing pattern uses them.
- `awk` — POSIX awk available on macOS by default.
- `wc` — standard.
- No new packages, binaries, or external services.

## Decisions & Trade-offs

**Posture: advisory-only, not hard-route.** The critic's argument that 2000-line Read is sometimes the *correct* tool stands. Hard-routing would block legitimate Read/Grep on logs, configs, prose. Trade-off: relies on Claude's compliance.

**Subagent strategy: parent-banner instruction, not Task hook.** `hookSpecificOutput.modifiedToolInput` on Task is undocumented surface and surprises users. The parent's PreToolUse output doesn't reach subagent context anyway. Banner instruction delegates propagation to Claude, which controls spawn prompts and reaches every agent type — plugin-owned or not. Trade-off: depends on Claude following the instruction; Grep nudge is the safety net.

**Silent observers, not active nudges, for parked matchers.** Read on a large source file is often the right call. Glob → Grep → Read is a healthy workflow. Edit-rename via `rename_symbol` corrupts shadowed names. Active nudges on these would create alarm fatigue. Silent observers gather evidence for revival without risking user-visible noise.

**Telemetry shipped together with active matcher.** Without telemetry, revival criteria cannot be evaluated. The pragmatist worried "telemetry without consumer is theatre"; the reporting script + revival criteria in the design doc are the consumer. Pre-committed kill criterion: delete the regex extension if `<40%` follow-through over 14 days with `≥30` firings.

**Two-pole diagnostics retained.** Surfacing `mcp__serena__get_diagnostics_for_file` would create a third route the model has to disambiguate at activation. `lsp-nudge.sh` already routes file-scoped diagnostics. Trade-off: users with `serena=true` and `lsp=false` lose a marginally better path; they keep the existing Tier-2 fallback.

**No shared `hooks/lib/serena-heuristic.sh` library.** Premature abstraction at 2 hook scripts. Reuse-vs-rewrite check: each hook has a different shape (active nudge vs silent observer). Revisit if hook count crosses 4.

**No active orchestration.** Hooks emit text only; they never call Serena MCP and inject results. Process spawn + MCP handshake at 200-800ms is incompatible with the original 50ms activation budget; even with budget relaxed, a stale or mistaken inline result is worse than no result.

## Rejected Alternatives

- **Hard-route on clear cases** (block Grep, require Serena). Rejected: contradicts plugin's fail-open posture; would block legitimate non-symbol grep on logs/configs.
- **`hookSpecificOutput.modifiedToolInput` on Task** (mutate spawn prompt at hook time). Rejected: undocumented surface, surprises users.
- **Edit each plugin's agent SKILL.md to mention Serena.** Rejected: cascades to every plugin; doesn't reach built-in or third-party agents.
- **Read matcher with active nudge.** Parked behind revival gate (≥60% large-source-Read miss rate AND Grep extension follow-through ≥40%).
- **Glob matcher with active nudge.** Parked behind revival gate (Glob → Read sequences without intervening Grep dominate the missed-opportunity log).
- **Edit-rename → `rename_symbol` suggestion with active nudge.** Parked. Requires scope-aware precheck (single-declaration verification) which would itself need shell-to-MCP. Re-design when feasibility study completes.
- **Telemetry without kill criterion.** Rejected as theatre per critic; replaced with explicit revival/kill thresholds documented in the design.

## Implementation Notes (synced at ship time)

- The `_SEEN` deduplication key in `serena-followthrough.sh` uses tab as the field separator (matcher names cannot contain tabs by TSV invariant) rather than `|`, eliminating any future ambiguity if a class name ever contained `|`.
- `serena-followthrough.sh` filters the telemetry file by session token *before* `tail -200`, so concurrent sessions writing to the same file cannot evict our session's nudges from the lookup window. A regression test pre-loads 250 lines of cross-session noise and asserts that the local nudge still correlates.
