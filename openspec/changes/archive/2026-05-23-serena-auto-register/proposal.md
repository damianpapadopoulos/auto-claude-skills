## Why

Users who install `auto-claude-skills` and have `serena` on PATH still see `serena_connected=false` (and often `serena=false`) unless they explicitly invoke `/setup` to register Serena as an MCP server. The plugin's session-start hook detects Serena's binary correctly but does nothing about an absent MCP registration. The friction is real: even the maintainer's own session at the time of this proposal showed `serena=true, serena_connected=false`, and most users will not realize `/setup` is the prerequisite for the plugin's Serena-aware skill routing to take effect.

A 2-question brainstorming pass selected `command -v serena` as the trigger and `--scope user` as the registration scope (binary on PATH = global resource). The implementation surfaced a second issue: Serena defaults to opening a browser tab to its web dashboard every time the MCP server starts (i.e., every Claude Code session). For a feature whose stated goal is *zero-touch onboarding*, spamming the user's browser on first session would be the opposite of the intended UX. Resolved by passing Serena's `--open-web-dashboard false` CLI flag in the registration command (per-MCP-server scope; user's global `~/.serena/serena_config.yml` is never modified).

## What Changes

- **First-time Serena MCP auto-registration** — `hooks/lib/serena-autoregister.sh` (new sourceable library) is invoked from `hooks/session-start-hook.sh` immediately before the existing `context_capabilities` augmentation block. The library runs `claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false` when `serena` is on PATH, `claude` CLI is on PATH, the marker file does not exist, and `claude mcp list` does not already contain a `serena:` entry.

- **Dashboard auto-open suppression** — the `--open-web-dashboard false` flag is baked into the registered command so Serena does NOT open a browser tab on each Claude Code session start. The dashboard itself remains enabled and reachable at `http://localhost:24282/dashboard/` for users who want it.

- **Idempotency marker** — successful or failed registration writes a TSV marker at `~/.claude/.auto-claude-skills-serena-registered` (`<ISO timestamp>\t<PID>\t<status>`), preventing re-runs across sessions. Failure paths additionally write stderr to `~/.claude/.auto-claude-skills-serena-register-error` for `/setup` to surface.

- **Test-mode isolation** — the session-start invocation is gated on `_SKILL_TEST_MODE != 1` so the real `claude mcp add` does not pollute test tmpdir HOMEs. The integration test sets `_SKILL_TEST_AUTOREG=1` to opt back in (it provides full PATH/HOME isolation via mocks).

- **`/setup` docs update** — `commands/setup.md` gains a "Auto-registration and recovery" subsection documenting the marker, recovery via marker deletion, the error-breadcrumb inspection path, and how users who *want* the browser tab back can edit `~/.claude.json`.

## Capabilities

### Modified Capabilities

- `skill-routing`: adds the first-time Serena MCP auto-registration requirement plus its fail-open invariants and test-mode isolation gate.

## Impact

- **Code:** `hooks/lib/serena-autoregister.sh` (+71 lines, new file), `hooks/session-start-hook.sh` (+15 lines for the source+call block wrapped in the `_SKILL_TEST_MODE` gate), `tests/test-serena-autoregister.sh` (+233 lines, new file — 7 unit tests with mocked `serena`/`claude` binaries), `tests/test-registry.sh` (+58 lines, 1 integration test with mocked binaries and 3 assertions including the dashboard-flag regression guard).
- **Docs:** `commands/setup.md` (+18 lines, recovery subsection), `CHANGELOG.md` (+1 line under `[Unreleased]` → `### Added`).
- **Config:** none. No changes to `config/default-triggers.json` or `config/fallback-registry.json` — this is a routing-hook behavior change, not a trigger-block addition.
- **Dependencies:** none new. Bash 3.2 (macOS-compat) and the `serena` + `claude` CLIs (both detected via `command -v`). jq is NOT required on this path.
- **Runtime:** session-start gains 4 cheap checks in the steady state (3× `command -v`, 1× stat on marker file). When auto-registration actually fires (once per user, ever), latency is dominated by `claude mcp add` (~200-500ms one-time cost).
- **User state mutated:** `~/.claude.json` (one new `mcpServers.serena` entry, only on first run when eligible). The plugin does NOT modify `~/.serena/serena_config.yml`.
- **Push gate:** untouched. Composition state remains authoritative for SHIP enforcement.
- **Marker file side-effects:** new files in `~/.claude/`: `.auto-claude-skills-serena-registered` (always, on first run with `serena` + `claude` on PATH), `.auto-claude-skills-serena-register-error` (only on `claude mcp add` failure).
