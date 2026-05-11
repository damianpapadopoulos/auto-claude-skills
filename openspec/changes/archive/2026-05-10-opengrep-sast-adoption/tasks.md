# Tasks: Opengrep SAST Adoption

## Completed

- [x] 1.1 Validate JSON shape parity hands-on (fixture: Python code-execution-sink finding; both binaries via `--config auto`)
- [x] 1.2 Verify `--config auto` resolves to the same `semgrep.dev/c/auto` registry in opengrep source (`config_resolver.py`, `env.py`)
- [x] 1.3 Verify `.semgrepignore` honored identically by both binaries
- [x] 1.4 Get independent second opinion via `codex:rescue` and incorporate pushback (verified speculation, removed unnecessary scope)
- [x] 2.1 Edit `skills/security-scanner/SKILL.md` — description, `$SAST_BIN` detection, Step 2 invocations, install hints, table label
- [x] 2.2 Edit `hooks/session-start-hook.sh` — add `_OPENGREP` detection and `opengrep=` field in `SECURITY_CAPS`
- [x] 2.3 Edit `config/default-triggers.json` — add `opengrep` to trigger regex; update hint and purpose copy
- [x] 2.4 Edit `config/fallback-registry.json` — same updates (parity)
- [x] 3.1 Run `bash tests/test-security-scanner.sh` — 13/13 passed
- [x] 3.2 Run `bash tests/run-tests.sh` — 44/44 files passed
- [x] 3.3 JSON validity: `jq -e .` on both config files
- [x] 3.4 Bash syntax: `bash -n hooks/session-start-hook.sh`
- [x] 3.5 End-to-end skill command verification with new `$SAST_BIN` pattern
- [x] 4.1 Code review via `pr-review-toolkit:code-reviewer` — no blocking findings
