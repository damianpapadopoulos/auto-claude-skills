## Why

The plugin nudged Claude toward Serena MCP tools inconsistently. The existing `serena-nudge.sh` fired only on `Grep` and bailed on any regex pattern, missing common symbol-hunt shapes like `\bIdent\b` and `Foo::bar`. Subagents launched via `Task` did not see the SessionStart Serena banner, so their tool selection was guided only by their own SKILL.md. Read on large source files, glob-driven definition hunts, and symbol-rename Edits were entirely uncovered. There was no measurement layer to evaluate whether the parked matchers (Read, Glob, Edit-rename) were worth shipping later — revival decisions would have been pure speculation.

A four-voice design debate (architect, critic, pragmatist, plus an external Codex review) converged on a narrow MVP: extend the Grep matcher's regex coverage, propagate Serena guidance into Task spawn prompts via a single banner-line addition, and add a silent telemetry layer that gathers evidence for the parked matchers without surfacing user-visible nudges.

## What Changes

- `hooks/serena-nudge.sh` Grep classifier extended to handle regex word-boundary, dotted/qualified, and embedded definition-prefix patterns. Suppression rules cover heavy alternation, lookaround, and broad whitespace-bearing character classes. Telemetry append-only TSV write on fire.
- `hooks/serena-observer.sh` (new) — silent PreToolUse on `Read|Glob|Edit`. Logs `read_large_source`, `glob_definition_hunt`, and `edit_symbol_token` candidate observations. Never emits user-visible context.
- `hooks/serena-followthrough.sh` (new) — PostToolUse on `^mcp__serena__`. Correlates Serena MCP calls back to nudges/observations within 3 turns of the same session, idempotent via a `(turn, matcher)` composite key.
- `scripts/serena-telemetry-report.sh` (new) — rolling-window follow-through % per matcher class.
- `hooks/session-start-hook.sh` Serena banner adds a sentence instructing the parent to propagate Serena guidance into Task spawn prompts.
- `tests/fixtures/evals/serena-grep-patterns.json` (new) — behavioral eval fixture covering the broadened matcher.
- 5 new test files in `tests/` covering each new component end-to-end.

## Capabilities

### Modified Capabilities
- `skill-routing` — Serena nudge surface widened, subagent guidance propagates from the parent banner, telemetry layer added for parked-matcher revival evidence.

## Impact

- Affected code: `hooks/serena-nudge.sh`, `hooks/session-start-hook.sh`, `hooks/hooks.json`, plus new `hooks/serena-observer.sh`, `hooks/serena-followthrough.sh`, `scripts/serena-telemetry-report.sh`.
- Affected APIs: none (internal hooks only).
- New side effect: append-only writes to `~/.claude/.serena-nudge-telemetry`. Opt-out via `SERENA_TELEMETRY=0`.
- Dependencies: no new package or binary dependencies. `jq` was already required; remains optional with fallbacks where applicable.
- Subagent UX: spawned agents inherit Serena guidance via the parent's spawn-prompt instruction, plus the broadened Grep nudge fires regardless of session origin.
