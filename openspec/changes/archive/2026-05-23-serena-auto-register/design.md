# Design: Serena Auto-Register on First Session

## Architecture

**Trigger point:** `hooks/session-start-hook.sh:761-771`. The auto-register block runs immediately before the canonical `context_capabilities` augmentation block. Wrapping the call in `if [ "${_SKILL_TEST_MODE:-0}" != "1" ] || [ "${_SKILL_TEST_AUTOREG:-0}" = "1" ]` keeps the real `claude mcp add` out of the test tmpdir HOMEs that `run_hook` (line 19 of `tests/test-registry.sh`) creates via `_SKILL_TEST_MODE=1`. The integration test sets both flags because its mocked PATH provides equivalent isolation.

**Library:** `hooks/lib/serena-autoregister.sh` exposes one function `serena_maybe_autoregister`. Bash 3.2 compatible. jq NOT required on this path (no JSON parsing — only a `grep -F` over `claude mcp list` output). Function always returns 0 (fail-open invariant). The library is sourced from `$(dirname "$0")/lib/serena-autoregister.sh` so it works regardless of where the hook is invoked from. Sourcing failure (e.g., file missing or unreadable) is swallowed by the `2>/dev/null && ... || true` pattern in the wiring.

**Eligibility checks (5, all must pass):**
1. `_SKILL_TEST_MODE != 1` OR `_SKILL_TEST_AUTOREG = 1` (wiring-level gate).
2. Marker file `${HOME}/.claude/.auto-claude-skills-serena-registered` does NOT exist.
3. `command -v serena` succeeds.
4. `command -v claude` succeeds.
5. `claude mcp list 2>/dev/null | grep -q '^serena: '` returns NO match.

Any failure short-circuits the function (returns 0). Checks 2-4 are O(1); check 5 invokes the `claude` CLI once. The line-prefix grep pattern (`^serena: `) is byte-identical to the existing `SERENA_CONNECTION_CHECK` block at `hooks/session-start-hook.sh:812` so the detection contract stays consistent.

**Action when eligible:**
```bash
claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false
```

The `--scope user` flag writes to the user's global `~/.claude.json` `mcpServers.serena` entry. `--project-from-cwd` lets Serena pick the active project per-session without binding the user-scoped registration to one path. `--open-web-dashboard false` is the **per-MCP-server override** for Serena's `web_dashboard_open_on_launch` config setting — confirmed available in Serena CLI v1.3.0+ (`serena start-mcp-server --help` documents both `--enable-web-dashboard` and `--open-web-dashboard` boolean flags).

**Post-action state:**
- On `claude mcp add` exit 0: write marker `<ISO timestamp>\t<PID>\tregistered`.
- On `claude mcp add` exit non-zero: write marker `<ISO timestamp>\t<PID>\tregister-failed` AND write `${HOME}/.claude/.auto-claude-skills-serena-register-error` containing the captured stderr + exit code. The marker is written even on failure to prevent every-session retries of a deterministically-broken command.
- On already-registered short-circuit (check 5 hit a match): write marker `<ISO timestamp>\t<PID>\talready-registered`.
- `SKILL_EXPLAIN=1` emits one `[serena-autoregister] <status>, marker written` line to stderr in each branch (consistent with `[design-guard]` and other plugin debug breadcrumbs).

## Dependencies

- **No new dependencies.** Both `serena` (CLI, detected via `command -v serena`) and `claude` (Claude Code CLI, detected via `command -v claude`) must be present for the feature to fire. The library degrades to a 4-line no-op when either is missing.
- **jq:** NOT required. The library uses only `grep -F` for output parsing.
- **Bash:** 3.2 (macOS default) — no associative arrays, no `[[ ]]`-only constructs.
- **Serena CLI version:** the `--open-web-dashboard` flag requires Serena v1.3.0 or later. Older versions would treat the flag as an unknown argument and may fail registration; the marker would be written anyway and the user would see the error breadcrumb. This is acceptable given Serena v1.3.0 has been the documented minimum for `commands/setup.md` since 2026-05-18 (PR #34).

## Decisions & Trade-offs

**Why first-time-only with a marker file (Option D in brainstorming) over every-session re-check (Option A) or `/setup`-only (Option B):**
- **Option A (every session)** silently fights the user's state. If a user intentionally runs `claude mcp remove serena` (broken venv, debugging, switching projects), the plugin re-adds Serena on the next session. That's the kind of "magic" that erodes trust in a plugin. It also adds a `claude mcp list` grep per session (~50ms) for users who don't need it.
- **Option B (`/setup` only)** is the existing baseline and was the source of the original friction (the maintainer's own `serena_connected=false` happened because they hadn't run `/setup`).
- **Option C (hint, no auto-action)** doesn't meet the "auto-connect" goal; it just relocates the copy-paste burden.
- **Option D (first-time only with marker)** is zero-touch first session and respects user state thereafter. Recovery via `rm ~/.claude/.auto-claude-skills-serena-registered` is documented in `commands/setup.md`. Matches the plugin's broader "additive, opt-in, fail-open" pattern (see how `FORGETFUL_CONNECTION_CHECK` and `SERENA_CONNECTION_CHECK` default to off in the same hook).

**Why `--scope user` over `--scope project` or `--scope local`:**
- `serena` binary on PATH = global resource → user-scope matches the trigger.
- One registration covers every project the user opens; no per-project marker management.
- Project scope would multiply auto-registration side effects across every new repo (every new clone = another `claude mcp add` invocation, another marker file in `<repo>/.auto-claude-skills/`).
- Documented in `commands/setup.md:264` (predates this change) as the recommended pattern.

**Why suppress the dashboard via CLI flag instead of mutating `~/.serena/serena_config.yml`:**
- Per-MCP-server scope respects user state. A user running Serena from other clients (Cursor, Cline, Claude Desktop, agno playground) keeps their existing global dashboard preference.
- The flag lives in `~/.claude.json`'s `mcpServers.serena.args` array — discoverable, editable, and one-line-removable for users who want the tab back.
- Mutating the global config file would be invasive AND wouldn't compose well with the marker's "first time only" semantics (the global config change would persist forever; the marker only encodes "we attempted registration once").

**Why write the marker on failure (not just success):**
- Without the marker on failure, a deterministically-broken `claude mcp add` (e.g., user is logged out of Claude, network unreachable, permissions issue) would retry every session forever.
- Writing the marker AND the error breadcrumb gives `/setup` enough information to surface the prior failure to the user — they can fix the root cause and `rm ~/.claude/.auto-claude-skills-serena-registered` to retry.
- A small loss: transient failures (e.g., a one-time network blip) also get marked. Acceptable trade-off — the recovery is one `rm` command, documented.

**Why a sourceable lib (`hooks/lib/serena-autoregister.sh`) instead of inlining in `session-start-hook.sh`:**
- Unit testability with mocked binaries. Inlining would require running the entire ~1100-line session-start hook per test (slow, sets up unrelated state).
- Matches the existing convention: `hooks/lib/openspec-state.sh` is the same pattern.
- Single responsibility: decide whether to auto-register and do it. Wiring decisions (when/whether to invoke) live in `hooks/session-start-hook.sh`.

**Why a SECOND env var `_SKILL_TEST_AUTOREG` instead of reusing `_SKILL_TEST_MODE`:**
- `_SKILL_TEST_MODE=1` semantically means "we're in tests; skip mutations to source-tree state" (see `hooks/session-start-hook.sh:990`). Auto-register also mutates state (the user's HOME's `~/.claude.json`), so the default skip under `_SKILL_TEST_MODE` is consistent.
- The integration test for auto-register needs the wiring to fire AND needs the source-tree gate to remain active (otherwise the hook would write to the worktree's `config/fallback-registry.json`). A second positive opt-in var (`_SKILL_TEST_AUTOREG=1`) cleanly expresses "I'm a test that has provided full PATH/HOME isolation via mocks; let auto-register run inside the mocked environment."
- Alternatives considered and rejected:
  - Single-var with `_SKILL_TEST_MODE=2` for "tests with mocked binaries" — overloads numeric semantics, less self-documenting.
  - Refactor `_SKILL_TEST_MODE` to be a more granular set of flags — bigger blast radius, touches the whole hook, not justified by this one feature.
