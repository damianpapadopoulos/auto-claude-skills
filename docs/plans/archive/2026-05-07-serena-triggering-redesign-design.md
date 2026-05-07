# Serena Triggering Redesign — Design

**Date:** 2026-05-07
**Status:** Approved (scope locked after design debate + Codex consult)
**Driver:** Make auto-claude-skills route to Serena MCP tools more consistently where they actually add value, without fragmenting the hook surface or introducing alarm fatigue.

## Problem

Today the plugin nudges Claude toward Serena (the symbol-aware MCP server: `find_symbol`, `find_referencing_symbols`, `get_symbols_overview`, `rename_symbol`, `get_diagnostics_for_file`) inconsistently:

- `hooks/session-start-hook.sh:1101-1104` emits a one-line "prefer mcp__serena__* over Grep/Read" reminder when `serena=true`. Loaded into **parent context only**.
- `hooks/serena-nudge.sh` is a `PreToolUse` hook on `Grep` that **bails on any regex pattern** and matches CamelCase / snake_case identifiers plus a few keywords.
- `skills/unified-context-stack/tiers/internal-truth.md` describes Tier-0 LSP / Tier-1 Serena / Tier-2 Grep — but the doc only loads when the `unified-context-stack` skill is invoked.
- No `PreToolUse` hook on `Read`, `Glob`, `Edit`, or `Task`.
- Subagents launched via `Task` (`Explore`, `code-explorer`, `feature-dev:*`, `general-purpose`, plugin agents) **do not see the SessionStart banner** — they inherit only their own SKILL.md and the parent's spawn prompt.
- `mcp__serena__get_diagnostics_for_file` exists but the banner says "LSP for diagnostics, Serena for nav," steering Claude away from it.

A four-voice debate (architect / critic / pragmatist + Codex) converged that the highest-leverage interventions are narrow: a Grep regex extension, a banner-line nudge for subagent propagation, and removal of the diagnostics third pole. Broader matchers (Read / Glob / Edit-rename) carry false-positive risk that may undermine all nudges through fatigue, and are parked behind evidence-based revival criteria.

## Capabilities Affected

- `serena-nudge` — `hooks/serena-nudge.sh`. Trigger surface widened (Grep regex coverage).
- `session-start-banner` — `hooks/session-start-hook.sh`. One added line for subagent propagation; one removed mention of `get_diagnostics_for_file`.
- `serena-telemetry` (new) — append-only log + silent observer hooks + follow-through correlator. Lives at `~/.claude/.serena-nudge-telemetry`.
- `behavioral-evaluation` — new fixture `tests/behavioral-evals/serena-grep-matcher.json` (or equivalent in repo's existing eval format) exercising the Grep matcher.

## Out-of-Scope

- **Read matcher** (PreToolUse Read nudge). Parked. The critic's argument that 2000-line Read is often the correct tool stands. Will be revisited only if telemetry shows large-source Reads without follow-through dominate the missed-opportunity log.
- **Glob matcher**. Parked. Glob → Grep → Read is a healthy workflow; nudging at Glob pre-empts narrowing the model already does well.
- **Edit-rename → `rename_symbol` suggestion**. Parked behind a hard gate. `rename_symbol` silently corrupts shadowed/locally-scoped names and the model cannot audit a hook nudge against scope analysis. Revival requires a scope-aware precheck (e.g. confirming single-declaration via `find_declaration` count == 1), which would itself need shell-to-MCP. With the now-relaxed activation-budget constraint this becomes feasible, but is a separate design.
- **Active orchestration** (hooks calling Serena and injecting results). Dead, not parked. Process spawn + MCP handshake at 200-800ms makes synchronous shell-to-MCP unworkable for inline nudge payloads.
- **Hard-route / `denyTool` posture**. Dead. Contradicts the plugin's fail-open principle and would block legitimate Grep/Read on logs, configs, YAML, prose.
- **`hookSpecificOutput.modifiedToolInput` on Task**. Dead. Undocumented surface area, surprises users, and the parent's PreToolUse doesn't reach subagent context anyway.
- **Shared `hooks/lib/serena-heuristic.sh` library**. Premature abstraction at 2 hook scripts; revisit if hook count crosses 4.
- **Editing every plugin's agent SKILL.md**. Replaced by the parent banner-line approach, which propagates through Claude when it controls spawn prompts and reaches every agent type — not just plugin-owned ones.
- **Per-tool nudge fragmentation**. No `read-nudge.sh` / `glob-nudge.sh` / `edit-nudge.sh`. The single `serena-nudge.sh` extension and the silent `serena-observer.sh` are the only new surfaces.

## Approach

### 1. Grep matcher extension (`hooks/serena-nudge.sh`)

Today the script `exit 0`s on any pattern containing regex operators. Extend the existing pattern-detection block to also match:

- Word-boundary symbol patterns: `\bIdentifier\b`, `^Identifier$`
- Dotted / qualified member access: `Foo\.bar`, `Foo::bar`
- Definition-hunt prefixes inside richer regexes (`class `, `def `, `function `, `interface `, `struct `, `func `, `type `) — already handled for plain literals; extend to tolerate surrounding regex anchors and word boundaries.

Keep the existing CamelCase / snake_case fallback. Estimated ~20-25 lines of net change to the existing `case` block. False-positive guards: still suppress when the pattern contains heavy alternation, lookaround, or character classes broader than `[A-Za-z0-9_]`.

Posture: **advisory only**. Same `additionalContext` injection mechanism as today. No `denyTool`, no per-session counter (telemetry layer handles measurement separately).

### 2. SessionStart banner edits (`hooks/session-start-hook.sh:1101-1110`)

Two edits:

- **Add subagent-propagation line** when `serena=true`: *"When spawning subagents via the Task tool for code work, include `Serena available — prefer find_symbol over Grep for symbol lookups` in their prompt."* This delegates propagation to Claude itself — it controls spawn prompts and the instruction reaches every subagent type, plugin-owned or not.
- **Remove pull toward `get_diagnostics_for_file`**. Keep the existing two-pole rule: LSP for compile/type diagnostics, Serena for symbol nav. `lsp-nudge.sh` already covers the file-scoped case.

### 3. Telemetry layer (new)

Three pieces, all small:

**a. Active-matcher logger** (extend `hooks/serena-nudge.sh`): when the Grep nudge fires, append a TSV line to `~/.claude/.serena-nudge-telemetry`:

```
<unix-ts>\t<session-token>\t<turn-id>\tnudge\tgrep_extension\t<pattern-class>
```

`<pattern-class>` is one of `word_boundary|dotted_qualified|definition_prefix|camelcase|snake_case|legacy`. Logging is gated behind `SERENA_TELEMETRY=1` defaulting to `1` (opt-out via env or `~/.claude/skill-config.json`).

**b. Silent observers** (new `hooks/serena-observer.sh`, PreToolUse on `Read|Glob|Edit`): no user-visible nudge. Logs only:

- `Read` on path matching a source extension (`.ts|.tsx|.py|.go|.rs|.java|.kt|.scala|.rb|.cs|.cpp|.c|.h|.swift|.js|.jsx`) AND no `offset|limit` AND `wc -l > 500`. Class: `read_large_source`.
- `Glob` pattern matching `**/*Identifier*` or `**/*.{ext}` with definition-hunt naming. Class: `glob_definition_hunt`.
- `Edit` where `old_string` and `new_string` differ in a single symbol-shaped token AND file is source. Class: `edit_symbol_token`.

These hooks' purpose is to populate the missed-opportunity ledger so the parked-matcher revival criteria become testable.

**c. Follow-through correlator** (new `hooks/serena-followthrough.sh`, PostToolUse on `^mcp__serena__`): when any Serena MCP tool returns successfully, scan the most recent N=20 telemetry lines from this session. For each unmarked nudge or observation within 3 turns, append a follow-up line:

```
<unix-ts>\t<session-token>\t<turn-id>\tfollowup\t<original-class>\t<serena-tool>
```

Computing follow-through % is a downstream join, not done at hook time. A small reporting script (`scripts/serena-telemetry-report.sh`) summarizes the rolling window on demand.

### 4. Behavioral eval fixture

Add a fixture under the existing behavioral-evaluation harness that asserts:

- Given a pattern like `\bUserService\b`, the nudge additionalContext mentions `find_symbol`.
- Given `class Foo<T>` inside a richer regex, the nudge fires.
- Given a markdown / YAML / log path, the nudge does **not** fire (false-positive guard).
- Given a Glob `**/*.test.ts`, the silent observer logs `glob_definition_hunt=false` (not a hunt — enumeration).

Eval format and harness location follow the existing `behavioral-evaluation` capability pattern (per CLAUDE.md and prior project memory `project_behavioral_eval_runner_v1`).

## Acceptance Scenarios

**Scenario 1 — Regex Grep produces nudge.**
GIVEN `serena=true` and the Grep extension is shipped,
WHEN Claude calls `Grep` with pattern `\bUserService\b` against `src/`,
THEN the PreToolUse hook injects `additionalContext` recommending `mcp__serena__find_symbol` or `get_symbols_overview`,
AND a telemetry line `<ts>\t<token>\t<turn>\tnudge\tgrep_extension\tword_boundary` is appended.

**Scenario 2 — Subagent-propagation works without Task hook.**
GIVEN `serena=true`,
WHEN the parent reads the SessionStart banner and subsequently spawns a `code-explorer` subagent for refactor work via the `Task` tool,
THEN Claude includes a one-line Serena reminder in the subagent's spawn prompt,
AND any `Grep` the subagent performs on a symbol-shaped pattern receives the nudge in-band (the PreToolUse hook fires regardless of session origin).

**Scenario 3 — Two-pole diagnostics, no third pole.**
GIVEN `serena=true` and `lsp=true`,
WHEN Claude needs file-scoped diagnostics,
THEN the SessionStart banner mentions only `mcp__ide__getDiagnostics` for diagnostics and `mcp__serena__*` for navigation,
AND `mcp__serena__get_diagnostics_for_file` is not surfaced in routing prose.

**Scenario 4 — Silent telemetry feeds revival criteria.**
GIVEN `serena=true` and the observer hook is shipped,
WHEN Claude reads a 1200-line `.ts` source file with no offset/limit and does not call any Serena tool within 3 turns,
THEN a telemetry line `<ts>\t<token>\t<turn>\tobserve\tread_large_source\t<path>` is appended,
AND no follow-up line is added (no Serena call followed),
AND `scripts/serena-telemetry-report.sh` reflects the missed-opportunity in the rolling window summary.

## Trade-offs Accepted

- **Banner-line propagation depends on Claude's compliance.** If the model ignores the parent's instruction to propagate Serena guidance into spawn prompts, subagents fall back on the in-band Grep nudge alone. Acceptable: in-band coverage is the safety net.
- **Silent observers add ~5-15ms per Read/Glob/Edit** (mostly `wc -l` for Read). Within the relaxed budget. Disabled if `SERENA_TELEMETRY=0`.
- **No active fatigue counter.** If Claude starts ignoring nudges, telemetry's follow-through % surfaces it, and the kill criterion deletes the matcher. We avoid pre-engineering a counter that may never be needed.
- **Telemetry retention is unbounded.** A future cleanup script can rotate the file. For now, append-only is fine — file growth is O(nudges) which is dozens per session at most.

## Decision

Ship the three MVP changes (Grep extension, banner additions, banner cleanup) plus the silent telemetry layer and behavioral eval fixture. Posture: advisory-only on user-visible nudges; passive logging for parked-matcher revival evidence. Re-evaluate Read / Glob / Edit-rename matchers at 14 days post-ship using the rolling-window report.

## Kill / Revival Criteria (post-ship)

| Item | Trigger |
|---|---|
| Grep regex extension | Delete if follow-through % < 40 over 14 days with ≥30 firings. |
| Read matcher (parked) | Revive if `read_large_source` observations without follow-through > 60% over 14 days AND Grep extension follow-through ≥ 40%. |
| Glob matcher (parked) | Revive if `glob_definition_hunt` observations dominate the missed-opportunity log without an intervening Grep step. **Note:** The current `scripts/serena-telemetry-report.sh` aggregates per-class but does not record per-session event ordering. To rigorously evaluate "no intervening Grep" at the 14-day mark, either (a) extend the report to scan raw telemetry per session and detect Glob→Read sequences, or (b) add a sequence-aware view at evaluation time. Tracked as a follow-up — flagged by Codex during PR #25 review. |
| Edit-rename matcher (parked) | Revive only with a scope-aware precheck design — separate proposal, blocked on shell-to-MCP wrapper feasibility study. |
| Telemetry layer itself | Delete if file growth becomes a maintenance burden AND no parked matcher has been revived. |
