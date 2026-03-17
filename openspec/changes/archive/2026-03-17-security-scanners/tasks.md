# Tasks: Security Scanners

## Completed

- [x] 1.1 Create `skills/security-scanner/SKILL.md` with scan-fix-verify loop for Semgrep, Trivy, Gitleaks
- [x] 2.1 Write failing tests for security_capabilities detection and external skills check removal
- [x] 2.2 Add Step 8f capability detection to `session-start-hook.sh` (command -v semgrep/trivy/bandit/gitleaks)
- [x] 2.3 Emit `Security tools:` line in CONTEXT string (after OpenSpec block)
- [x] 2.4 Remove `security-scanner` from external skills check loop
- [x] 3.1 Write failing tests for methodology hint and REVIEW composition
- [x] 3.2 Add `deterministic-security-scan` methodology hint to `default-triggers.json`
- [x] 3.3 Update REVIEW composition invoke path to `Skill(auto-claude-skills:security-scanner)`
- [x] 4.1 Migrate invoke paths in `test-context.sh` fixtures and assertions
- [x] 4.2 Migrate invoke paths in `test-routing.sh` fixtures and assertions (4 occurrences)
- [x] 4.3 Update `skill-activation-hook.sh` debug output with new invoke path
- [x] 5.1 Replace matteocervelli install instructions with built-in notice and CLI tool setup guidance
- [x] 5.2 Regenerate `fallback-registry.json` and verify parity
- [x] 5.3 Add fallback parity test to `test-security-scanner.sh`
- [x] 6.1 Fix gitleaks `.Match[:50]` secret leak (code review finding, CRITICAL)
- [x] 6.2 Fix `xargs` without `-0` for safe filename handling (code review finding)
- [x] 6.3 Fix `git diff --name-only HEAD` scope to use `merge-base` (code review finding)
- [x] 6.4 Rename duplicate Step 8e to 8f, fix stale checklist and spec references
