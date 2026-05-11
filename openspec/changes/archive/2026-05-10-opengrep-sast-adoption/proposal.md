## Why

Semgrep gates several JSON output fields (`extra.fingerprint`, `extra.lines`) behind a Pro/login requirement, returning `"requires login"` instead of real values. Opengrep — an LGPL-2.1 fork of Semgrep v1.100.0 backed by a 10+ AppSec consortium — produces byte-identical JSON for the fields the security-scanner skill consumes, hits the same `--config auto` registry (`semgrep.dev/c/auto`), honors `.semgrepignore` identically, and ships as a single signed binary with no Python dependency. Adopting opengrep as a preferred alternative gives users strictly more output information at zero pipeline cost and future-proofs the skill against further Semgrep license tightening.

## What Changes

The `security-scanner` skill now prefers `opengrep` when present and falls back to `semgrep` otherwise. JSON parsing, registry, and ignore-file behavior are unchanged. The session-start hook reports a new `opengrep=` capability alongside the existing `semgrep=`. Routing config (default-triggers.json and fallback-registry.json) accepts `opengrep` as a trigger keyword and references both binaries in hint and purpose copy.

## Capabilities

### Modified Capabilities
- `security-scanner`: SAST binary detection extended to prefer opengrep over semgrep with identical JSON contract; capability detection emits `opengrep=` field; routing copy and trigger regex include `opengrep`

## Impact

- `skills/security-scanner/SKILL.md` — description, Step 1 detection, Step 2 commands now use a `$SAST_BIN` variable, install hints, table label
- `hooks/session-start-hook.sh` — adds `_OPENGREP=false` capability detection and `opengrep=` field in `SECURITY_CAPS` line
- `config/default-triggers.json` — adds `opengrep` to security-scan trigger regex; updates hint and purpose copy
- `config/fallback-registry.json` — same updates as default-triggers (kept in sync per `test_fallback_registry_parity`)
- No dependency changes
- No new outbound network endpoints (opengrep uses the same `semgrep.dev/c/auto` registry)
- Validated hands-on: byte-identical jq output on a fixture file containing a known Python code-execution-sink finding
