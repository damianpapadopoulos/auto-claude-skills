# Design: Opengrep SAST Adoption

## Architecture

The security-scanner skill resolves a single `$SAST_BIN` variable at Step 1 detection time:

```bash
SAST_BIN="$(command -v opengrep || command -v semgrep || true)"
```

All Step 2 invocations reference `"$SAST_BIN"` instead of a hardcoded `semgrep` binary. The `--config auto`, `--json`, `--severity`, and downstream `jq` pipeline are unchanged because both binaries produce byte-identical JSON for the fields the skill reads (`results[].check_id`, `results[].extra.severity`, `results[].path`, `results[].start.line`, `results[].extra.message`).

The session-start hook (`hooks/session-start-hook.sh:841-846`) gains an `_OPENGREP` boolean detected via `command -v opengrep` and emits it in the `SECURITY_CAPS` line as an additive field positioned after `semgrep=` and before `trivy=`. The downstream consumer at `hooks/session-start-hook.sh:1145` substring-matches `"=false"` and is unaffected by additive fields.

Routing configs gain `opengrep` in the security-scan trigger regex alternation and in the hint/purpose copy. Both `config/default-triggers.json` and `config/fallback-registry.json` are updated identically per the existing `test_fallback_registry_parity` invariant.

## Dependencies

None added. Opengrep is detected at runtime; if absent, the skill silently falls back to semgrep without any user-visible change.

## Decisions & Trade-offs

**Why prefer-detect over hard-swap.** A hard binary swap would force every existing user to install opengrep before the skill works again. Prefer-detect lets opengrep-installed environments benefit immediately while semgrep-installed environments keep working unchanged. The detection cost is one extra `command -v` call per session-start.

**Why not change `--config auto` to `--config p/default`.** Initial speculation suggested opengrep lacked Semgrep's hosted auto-registry. Verified false by reading `cli/src/semgrep/config_resolver.py` and `env.py` in the opengrep repo: opengrep's `semgrep_url` defaults to `https://semgrep.dev` (with a TODO acknowledging the intent to migrate to `opengrep.dev` blocked by failing tests). Both binaries hit the same registry. Keeping `--config auto` preserves rule continuity for existing users.

**Why opengrep first (not semgrep first).** Opengrep returns real values for `extra.fingerprint` and `extra.lines` where semgrep returns `"requires login"`. These fields aren't read by the current jq pipeline but represent strictly more information available to future skill enhancements (e.g., dedup, code-line display in reports). Preferring the binary that produces richer output costs nothing.

**Why keep the `semgrep=` capability label.** The existing `test_security_capabilities_in_output` test asserts `semgrep=` is present in the session-start output. Renaming the field to `sast=` would break the test and any external tooling that grep-parses the line. The chosen approach (additive `opengrep=` field) keeps backwards compatibility.

**Rejected: introducing `--taint-intrafile`.** Opengrep ships free intrafile taint analysis (Pro-tier in Semgrep). Out of scope for this change because (a) the skill is a fast diff-time gate, not a deep audit, and (b) taint analysis produces findings that need human triage, which fits the agent-team-review security specialist better than this skill. Deferred to a follow-up.

**Rejected: parity test fixture in CI.** Could add `tests/test-security-scanner-parity.sh` that runs both binaries against a fixture and asserts identical jq output. Decision: defer to follow-up; hands-on validation in the SHIP session is sufficient evidence for now. Revival trigger: any user-reported divergence between opengrep and semgrep output.
