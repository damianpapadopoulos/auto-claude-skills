## ADDED Requirements

### Requirement: Serena First-Time MCP Auto-Registration

The session-start hook (`hooks/session-start-hook.sh`) MUST source `hooks/lib/serena-autoregister.sh` and invoke `serena_maybe_autoregister` immediately before the existing `context_capabilities` augmentation block. The library function MUST be fail-open (return 0 in every branch) and MUST be idempotent via a marker file at `${HOME}/.claude/.auto-claude-skills-serena-registered`. When all eligibility checks pass, the function MUST execute exactly:

```
claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false
```

The `--open-web-dashboard false` flag MUST be present in the registered command so Serena does NOT open a browser tab on each Claude Code session start. The plugin MUST NOT modify the user's global `~/.serena/serena_config.yml` — all dashboard-suppression behavior MUST be expressed at the per-MCP-server scope via the CLI flag.

#### Scenario: Fresh user with Serena installed and no MCP registration

- **GIVEN** `command -v serena` returns a path
- **AND** `command -v claude` returns a path
- **AND** `claude mcp list` does NOT contain a line beginning `serena: `
- **AND** `${HOME}/.claude/.auto-claude-skills-serena-registered` does NOT exist
- **WHEN** the user starts a Claude Code session in any project (outside `_SKILL_TEST_MODE=1`, OR with `_SKILL_TEST_AUTOREG=1` set)
- **THEN** `hooks/lib/serena-autoregister.sh::serena_maybe_autoregister` MUST run `claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false`
- **AND** the marker file MUST be written with a `<ISO timestamp>\t<PID>\tregistered` TSV line
- **AND** no browser tab MUST open for the Serena dashboard
- **AND** `~/.serena/serena_config.yml` MUST NOT be modified

#### Scenario: Marker file already exists

- **GIVEN** `${HOME}/.claude/.auto-claude-skills-serena-registered` exists (from a prior session)
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST return 0 immediately without invoking `claude mcp list` or `claude mcp add`

#### Scenario: Serena already registered in claude mcp list

- **GIVEN** `claude mcp list` contains a line matching `^serena: `
- **AND** the marker file does NOT exist
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST NOT invoke `claude mcp add` (idempotent — registration already present)
- **AND** the marker file MUST be written with status `already-registered`

#### Scenario: Serena binary not on PATH

- **GIVEN** `command -v serena` fails
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST return 0 immediately without invoking `claude mcp list` or `claude mcp add`
- **AND** the marker file MUST NOT be written

#### Scenario: Claude CLI not on PATH

- **GIVEN** `command -v serena` succeeds
- **AND** `command -v claude` fails
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST return 0 immediately without invoking any further commands
- **AND** the marker file MUST NOT be written

#### Scenario: claude mcp add exits non-zero

- **GIVEN** all eligibility checks pass
- **WHEN** `claude mcp add ...` exits with a non-zero status
- **THEN** the marker file MUST be written with status `register-failed` (to prevent every-session retries of a deterministically broken command)
- **AND** `${HOME}/.claude/.auto-claude-skills-serena-register-error` MUST be written with the captured stderr and exit code
- **AND** the function MUST still return 0 (fail-open invariant)

#### Scenario: SKILL_EXPLAIN breadcrumbs

- **GIVEN** `SKILL_EXPLAIN=1` is set in the environment
- **WHEN** `serena_maybe_autoregister` takes any code path other than the early marker-exists return
- **THEN** the function MUST emit exactly one line to stderr matching `^\[serena-autoregister\] (registered|already-registered|register-failed)` followed by a status message

#### Scenario: Test-mode default isolation

- **GIVEN** the session-start hook is invoked with `_SKILL_TEST_MODE=1` set
- **AND** `_SKILL_TEST_AUTOREG` is NOT set (or set to `0`)
- **WHEN** the hook reaches the auto-register wiring block
- **THEN** `serena_maybe_autoregister` MUST NOT be invoked
- **AND** no `claude mcp add` MUST execute
- **AND** no marker file MUST be written

#### Scenario: Test-mode opt-in via _SKILL_TEST_AUTOREG

- **GIVEN** `_SKILL_TEST_MODE=1` and `_SKILL_TEST_AUTOREG=1` are both set
- **WHEN** the hook reaches the auto-register wiring block
- **THEN** `serena_maybe_autoregister` MUST be invoked (per the standard eligibility checks)

### Requirement: Serena Auto-Register Library Bash Compatibility

`hooks/lib/serena-autoregister.sh` MUST be compatible with Bash 3.2 (macOS default `/bin/bash`). It MUST NOT use associative arrays, `[[` -only constructs without `[`-equivalents, or any features introduced in Bash 4+. It MUST NOT depend on `jq` — the library's parsing of `claude mcp list` output MUST use only `grep -F` / `grep -q` patterns.

#### Scenario: jq is unavailable

- **GIVEN** the host environment has no `jq` binary on PATH
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST proceed through all branches without invoking `jq`
- **AND** MUST return 0
