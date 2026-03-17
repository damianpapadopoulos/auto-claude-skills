# Security Scanners Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add hybrid deterministic security scanning (Semgrep + Trivy) via a bundled skill that orchestrates CLI tools through Bash, replacing the external grep-based security-scanner placeholder.

**Architecture:** New `skills/security-scanner/SKILL.md` teaches the agent a scan-fix-verify loop using Semgrep (SAST) and Trivy (dependency CVEs) via Bash. Session-start hook detects available tools. REVIEW composition routes to the skill. All changes within auto-claude-skills — no external plugin modifications.

**Tech Stack:** Bash 3.2, jq, SKILL.md (markdown), shell test framework (existing test harness)

**Spec:** `docs/superpowers/specs/2026-03-17-security-scanners-design.md`

---

## Chunk 1: Core Skill and Capability Detection

### Task 1: Create the security-scanner SKILL.md

**Files:**
- Create: `skills/security-scanner/SKILL.md`

- [ ] **Step 1: Create the skill directory and SKILL.md**

```markdown
---
name: security-scanner
description: Run Semgrep SAST and Trivy vulnerability scanning during code review with self-healing fix loop
---

# Security Scanner

Hybrid deterministic scanning: CLI tools find vulnerabilities, you fix them.

## When to Use

During REVIEW phase, after code changes are complete. Also invocable on explicit security requests.

## Step 1: Detect Available Tools

Run these checks via Bash to determine what's available:

\`\`\`bash
command -v semgrep && echo "semgrep: available" || echo "semgrep: not installed"
command -v trivy && echo "trivy: available" || echo "trivy: not installed"
command -v gitleaks && echo "gitleaks: available" || echo "gitleaks: not installed"
\`\`\`

If **neither** semgrep nor trivy is installed, fall back to LLM-only code review and recommend installation:
- Semgrep: `brew install semgrep` or `pip install semgrep`
- Trivy: `brew install trivy`
- Gitleaks: `brew install gitleaks`

## Step 2: Run Semgrep (SAST)

If semgrep is available, scan for code vulnerabilities.

**Fast scan (changed files only — prefer this for inner-loop reviews):**
\`\`\`bash
git diff --name-only HEAD | xargs semgrep scan --json --config auto --severity WARNING 2>/dev/null | jq '{count: (.results | length), results: [.results[] | {rule: .check_id, severity: .extra.severity, file: .path, line: .start.line, message: .extra.message}]}'
\`\`\`

**Full project scan (use for thorough reviews or when explicitly asked):**
\`\`\`bash
semgrep scan --json --config auto --severity WARNING . 2>/dev/null | jq '{count: (.results | length), results: [.results[] | {rule: .check_id, severity: .extra.severity, file: .path, line: .start.line, message: .extra.message}]}'
\`\`\`

**If output is large (count > 20), filter by severity first:**
\`\`\`bash
semgrep scan --json --config auto --severity ERROR . 2>/dev/null | jq '.results[:20]'
\`\`\`

## Step 3: Run Trivy (Dependency/CVE Scanning)

If trivy is available, scan for vulnerable dependencies and IaC misconfigurations.

**Dependency scan:**
\`\`\`bash
trivy fs --format json --severity HIGH,CRITICAL --ignore-unfixed . 2>/dev/null | jq '{count: (.Results // [] | map(.Vulnerabilities // [] | length) | add // 0), results: [.Results // [] | .[].Vulnerabilities // [] | .[] | {pkg: .PkgName, installed: .InstalledVersion, fixed: .FixedVersion, severity: .Severity, cve: .VulnerabilityID, title: .Title}]}'
\`\`\`

**If Dockerfile exists, also scan the image config:**
\`\`\`bash
trivy config --format json --severity HIGH,CRITICAL . 2>/dev/null | jq '.Results // []'
\`\`\`

## Step 4: Run Gitleaks (Secret Detection)

If gitleaks is available, scan for hardcoded secrets.

\`\`\`bash
gitleaks detect --source . --no-banner --report-format json 2>/dev/null | jq '{count: (. | length), results: [.[] | {rule: .RuleID, file: .File, line: .StartLine, match: .Match[:50]}]}'
\`\`\`

## Step 5: Triage and Fix

Present findings as a structured table:

\`\`\`markdown
## Security Scan Results

### Semgrep (SAST) — N findings
| Severity | File | Line | Rule | Message |
|----------|------|------|------|---------|

### Trivy (Dependencies) — N vulnerabilities
| Severity | Package | Installed | Fixed | CVE | Title |
|----------|---------|-----------|-------|-----|-------|

### Gitleaks (Secrets) — N findings
| Rule | File | Line | Match (truncated) |
|------|------|------|-------------------|
\`\`\`

**Fix priority:** CRITICAL > HIGH > ERROR > WARNING

For each fixable finding:
1. Fix the issue using your normal editing tools
2. Re-run the specific scanner on the changed file to verify the fix
3. Move to the next finding

**Max 3 fix-rescan iterations** to prevent infinite loops.

## Step 6: Report

After fixing, present a final summary:
- Total findings by tool and severity
- What was fixed (with file:line references)
- What needs human review (and why — e.g., business logic dependency, false positive candidate)
- What was NOT scanned (tools not installed) with install recommendations

## Ignore Files

If false positives are found, help the user configure:
- `.semgrepignore` for Semgrep exclusions
- `.trivyignore` for Trivy exclusions
- `.gitleaksignore` for Gitleaks exclusions
```

- [ ] **Step 2: Verify the skill file renders correctly**

Run: `bash -n skills/security-scanner/SKILL.md 2>&1; echo "Markdown file, no bash syntax to check — OK"`
Expected: Confirmation (markdown files don't need syntax checks, just verify the file exists)

Run: `head -5 skills/security-scanner/SKILL.md`
Expected: Frontmatter with `name: security-scanner`

- [ ] **Step 3: Commit**

```bash
git add skills/security-scanner/SKILL.md
git commit -m "feat: add hybrid security-scanner skill with Semgrep/Trivy/Gitleaks support"
```

---

### Task 2: Add security_capabilities detection to session-start-hook.sh

**Files:**
- Modify: `hooks/session-start-hook.sh:664` (after CONTEXT_CAPS finalization, before Step 9)
- Modify: `hooks/session-start-hook.sh:897-904` (CONTEXT string, after OpenSpec capabilities block)
- Modify: `hooks/session-start-hook.sh:833` (remove from external skills check)

- [ ] **Step 1: Write the failing test for capability detection**

Add to `tests/test-security-scanner.sh` (new file):

```bash
#!/usr/bin/env bash
# tests/test-security-scanner.sh — Tests for security scanner integration
set -u
PASS=0; FAIL=0; ERRORS=""

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected to contain: ${needle}\n    got: $(printf '%s' "$haystack" | head -c 200)"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected NOT to contain: ${needle}"
  else
    PASS=$((PASS + 1))
  fi
}

# ── Test: security_capabilities appears in session-start output ──
test_security_capabilities_in_output() {
  echo "--- test_security_capabilities_in_output ---"
  local output
  output="$(bash hooks/session-start-hook.sh 2>/dev/null)" || true
  assert_contains "session-start emits security tools" "Security tools:" "$output"
  assert_contains "session-start emits semgrep capability" "semgrep=" "$output"
  assert_contains "session-start emits trivy capability" "trivy=" "$output"
}

# ── Test: security-scanner removed from missing external skills ──
test_security_scanner_not_in_external_check() {
  echo "--- test_security_scanner_not_in_external_check ---"
  local hook_source
  hook_source="$(cat hooks/session-start-hook.sh)"
  assert_not_contains "security-scanner not in external skills loop" \
    "doc-coauthoring webapp-testing security-scanner" "$hook_source"
}

test_security_capabilities_in_output
test_security_scanner_not_in_external_check

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ -n "$ERRORS" ]; then
  printf '%b\n' "$ERRORS"
  exit 1
fi
exit 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-security-scanner.sh`
Expected: FAIL — "Security tools:" not found in session-start output, and external skills loop still contains security-scanner

- [ ] **Step 3: Add security_capabilities detection after CONTEXT_CAPS finalization**

In `hooks/session-start-hook.sh`, after line 664 (the `CONTEXT_CAPS` finalization block that ends with the unified-context-stack plugin override), add before the `# Step 9+10` comment at line 666:

```bash
# ── Step 8e: Detect security scanner capabilities ──────────────────
_SEMGREP=false; _TRIVY=false; _BANDIT=false; _GITLEAKS=false
command -v semgrep  >/dev/null 2>&1 && _SEMGREP=true
command -v trivy    >/dev/null 2>&1 && _TRIVY=true
command -v bandit   >/dev/null 2>&1 && _BANDIT=true
command -v gitleaks >/dev/null 2>&1 && _GITLEAKS=true
SECURITY_CAPS="semgrep=${_SEMGREP}, trivy=${_TRIVY}, bandit=${_BANDIT}, gitleaks=${_GITLEAKS}"
```

- [ ] **Step 4: Emit security_capabilities in CONTEXT string**

The `additionalContext` is built as the bash variable `CONTEXT` via string concatenation (lines 874-934), NOT via jq. It is emitted at line 936 via `jq -Rs .`.

Insert after the OpenSpec capabilities block (after line 904, where `${_OPENSPEC_LINE}` is appended):

```bash
# Append security scanner capabilities
CONTEXT="${CONTEXT}
Security tools: ${SECURITY_CAPS}"
```

This follows the exact same pattern as the Serena hint (line 887), Forgetful hint (line 893), and OpenSpec line (line 902).

- [ ] **Step 5: Remove security-scanner from external skills check**

At line 833, change:
```bash
for _skill in doc-coauthoring webapp-testing security-scanner; do
```
to:
```bash
for _skill in doc-coauthoring webapp-testing; do
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/test-security-scanner.sh`
Expected: PASS — both tests green

- [ ] **Step 7: Run existing tests to verify no regressions**

Run: `bash tests/run-tests.sh`
Expected: All existing tests pass (the external skills check change may affect count assertions — fix if needed)

- [ ] **Step 8: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-security-scanner.sh
git commit -m "feat: add security_capabilities detection to session-start hook"
```

---

## Chunk 2: Registry Changes and Invoke Path Migration

### Task 3: Add methodology hint and update REVIEW composition

**Files:**
- Modify: `config/default-triggers.json:378-555` (methodology_hints array)
- Modify: `config/default-triggers.json:870-874` (REVIEW composition)

- [ ] **Step 1: Write failing test for methodology hint**

Append to `tests/test-security-scanner.sh`:

```bash
# ── Test: methodology hint exists in registry with correct triggers ──
test_methodology_hint_in_registry() {
  echo "--- test_methodology_hint_in_registry ---"
  local registry
  registry="$(cat config/default-triggers.json)"
  assert_contains "registry has deterministic-security-scan hint" \
    "deterministic-security-scan" "$registry"
  assert_contains "hint triggers include security keyword" \
    "security|vulnerabilit" "$registry"
  assert_not_contains "hint triggers exclude plain review" \
    '"(review|security' "$registry"
}

# ── Test: methodology hint is phase-scoped to REVIEW only ──
test_methodology_hint_phase_scoped() {
  echo "--- test_methodology_hint_phase_scoped ---"
  local hint_block
  # Extract the hint entry and verify phase scoping
  hint_block="$(jq '.methodology_hints[] | select(.name == "deterministic-security-scan")' config/default-triggers.json 2>/dev/null)" || true
  assert_contains "hint is phase-scoped to REVIEW" '"REVIEW"' "$hint_block"
  assert_contains "hint references bundled skill" "auto-claude-skills:security-scanner" "$hint_block"
}

# ── Test: REVIEW composition has updated invoke path ──
test_review_composition_invoke_path() {
  echo "--- test_review_composition_invoke_path ---"
  local registry
  registry="$(cat config/default-triggers.json)"
  assert_contains "REVIEW composition uses bundled invoke path" \
    "Skill(auto-claude-skills:security-scanner)" "$registry"
  assert_not_contains "REVIEW composition has no stale external path" \
    '"Skill(security-scanner)"' "$registry"
}

test_methodology_hint_in_registry
test_methodology_hint_phase_scoped
test_review_composition_invoke_path
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-security-scanner.sh`
Expected: FAIL — "deterministic-security-scan" not found in registry, REVIEW composition still has old invoke path

- [ ] **Step 3: Add deterministic-security-scan methodology hint**

In `config/default-triggers.json`, add to the `methodology_hints` array (before the closing `]` of the array, around line 555):

```json
{
  "name": "deterministic-security-scan",
  "triggers": ["(security|vulnerabilit|owasp|cve|semgrep|trivy|sast|dast|dependency.audit)"],
  "trigger_mode": "regex",
  "hint": "SECURITY SCAN: If semgrep/trivy are installed, run deterministic scans before LLM review. Invoke Skill(auto-claude-skills:security-scanner).",
  "phases": ["REVIEW"]
}
```

- [ ] **Step 4: Update REVIEW composition invoke path**

At lines 870-874 of `config/default-triggers.json`, change:
```json
{
  "use": "security-scanner -> Skill(security-scanner)",
  "when": "always",
  "purpose": "Scan for vulnerabilities, OWASP risks, compliance issues. INVOKE during every review"
}
```
to:
```json
{
  "use": "security-scanner -> Skill(auto-claude-skills:security-scanner)",
  "when": "always",
  "purpose": "Run semgrep/trivy deterministic scans first, then LLM triage. Self-healing loop: scan -> fix -> re-scan -> clean"
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-security-scanner.sh`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add config/default-triggers.json tests/test-security-scanner.sh
git commit -m "feat: add security-scan methodology hint and update REVIEW composition"
```

---

### Task 4: Migrate invoke paths across tests and hooks

**Files:**
- Modify: `tests/test-context.sh:95-105,800-835` (invoke path in fixture + assertions)
- Modify: `tests/test-routing.sh:180-191,490-499,1016-1020,1034,1289-1297,1431-1438` (invoke paths in fixtures + assertions)
- Modify: `hooks/skill-activation-hook.sh:1270` (debug output)

- [ ] **Step 1: Update test-context.sh invoke paths**

In `tests/test-context.sh`:

At lines 95-105 (registry fixture), change `"invoke": "Skill(superpowers:security-scanner)"` to `"invoke": "Skill(auto-claude-skills:security-scanner)"`.

At lines 820-826 (assertion), change `Skill(security-scanner)` references to `Skill(auto-claude-skills:security-scanner)`.

- [ ] **Step 2: Update test-routing.sh invoke paths**

In `tests/test-routing.sh`, update ALL registry fixtures and assertions:

- Lines 180-191: Change invoke to `Skill(auto-claude-skills:security-scanner)`
- Lines 490-499: Same
- Lines 1289-1297: Change `"invoke": "Skill(security-scanner)"` to `"invoke": "Skill(auto-claude-skills:security-scanner)"`
- Lines 1431-1438: Same
- Lines 1016-1020: Update assertion if it checks the invoke path

- [ ] **Step 3: Update skill-activation-hook.sh debug output**

At line 1270, change `Skill(security-scanner)` to `Skill(auto-claude-skills:security-scanner)` in the debug/explain comment.

- [ ] **Step 4: Run all tests to verify no regressions**

Run: `bash tests/run-tests.sh`
Expected: All tests pass with updated invoke paths

- [ ] **Step 5: Commit**

```bash
git add tests/test-context.sh tests/test-routing.sh hooks/skill-activation-hook.sh
git commit -m "refactor: migrate security-scanner invoke path to auto-claude-skills:security-scanner"
```

---

## Chunk 3: Cleanup and Verification

### Task 5: Update setup.md and regenerate fallback registry

**Files:**
- Modify: `commands/setup.md:87-93` (remove matteocervelli recommendation)
- Modify: `config/fallback-registry.json` (regenerate for parity)

- [ ] **Step 1: Update setup.md**

At lines 87-93 of `commands/setup.md`, replace the matteocervelli security-scanner section with:

```markdown
### 4. security-scanner (built-in)

The `security-scanner` skill is now bundled with auto-claude-skills. No external installation needed.

If you have the old matteocervelli version at `~/.claude/skills/security-scanner/`, you can remove it:
```bash
rm -rf ~/.claude/skills/security-scanner
```

For best results, install the CLI tools the skill orchestrates:
```bash
brew install semgrep   # SAST — code vulnerability scanning
brew install trivy     # Dependency CVE scanning
brew install gitleaks  # Secret detection
```
```

- [ ] **Step 2: Regenerate fallback-registry.json**

Run: `bash hooks/session-start-hook.sh >/dev/null 2>&1`

Then verify parity:
Run: `grep -c 'auto-claude-skills:security-scanner' config/fallback-registry.json`
Expected: At least 1 match (the REVIEW composition entry)

Run: `grep -c 'Skill(security-scanner)' config/fallback-registry.json`
Expected: 0 (old path should be gone)

- [ ] **Step 3: Add fallback parity test**

Append to `tests/test-security-scanner.sh`:

```bash
# ── Test: fallback registry has updated invoke path ──
test_fallback_registry_parity() {
  echo "--- test_fallback_registry_parity ---"
  local fallback
  fallback="$(cat config/fallback-registry.json)"
  assert_contains "fallback has new invoke path" "auto-claude-skills:security-scanner" "$fallback"
  assert_not_contains "fallback has no stale invoke path" '"Skill(security-scanner)"' "$fallback"
}

test_fallback_registry_parity
```

- [ ] **Step 4: Run all tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add commands/setup.md config/fallback-registry.json tests/test-security-scanner.sh
git commit -m "chore: update setup.md for bundled security-scanner, regenerate fallback registry"
```

---

### Task 6: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (routing, registry, context, security-scanner)

- [ ] **Step 2: Syntax-check all modified hooks**

Run: `bash -n hooks/session-start-hook.sh && bash -n hooks/skill-activation-hook.sh && echo "All hooks syntax-clean"`
Expected: "All hooks syntax-clean"

- [ ] **Step 3: Verify the skill is discoverable**

Run: `ls skills/security-scanner/SKILL.md && echo "Skill file exists"`
Expected: "Skill file exists"

- [ ] **Step 4: Verify capability detection works**

Run: `bash hooks/session-start-hook.sh 2>/dev/null | grep -o 'Security tools:[^"]*'`
Expected: `Security tools: semgrep=true, trivy=...` (values depend on what's installed)

- [ ] **Step 5: Verify methodology hint routing**

Run: `SKILL_EXPLAIN=1 echo '{"prompt":"run security scan"}' | bash hooks/skill-activation-hook.sh 2>&1 | grep -i "deterministic\|security"`
Expected: Shows the deterministic-security-scan hint being matched

---

## Summary

| Task | Files | Description |
|------|-------|-------------|
| 1 | `skills/security-scanner/SKILL.md` | Core skill with scan-fix-verify loop |
| 2 | `hooks/session-start-hook.sh`, `tests/test-security-scanner.sh` | Capability detection + remove external check |
| 3 | `config/default-triggers.json`, `tests/test-security-scanner.sh` | Methodology hint + REVIEW composition update |
| 4 | `tests/test-context.sh`, `tests/test-routing.sh`, `hooks/skill-activation-hook.sh` | Invoke path migration |
| 5 | `commands/setup.md`, `config/fallback-registry.json`, `tests/test-security-scanner.sh` | Cleanup + fallback parity |
| 6 | — | Final verification sweep |

**Total files created:** 2 (`skills/security-scanner/SKILL.md`, `tests/test-security-scanner.sh`)
**Total files modified:** 7 (`session-start-hook.sh`, `skill-activation-hook.sh`, `default-triggers.json`, `fallback-registry.json`, `test-context.sh`, `test-routing.sh`, `setup.md`)
**Estimated commits:** 5
