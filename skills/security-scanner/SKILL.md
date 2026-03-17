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

```bash
command -v semgrep && echo "semgrep: available" || echo "semgrep: not installed"
command -v trivy && echo "trivy: available" || echo "trivy: not installed"
command -v gitleaks && echo "gitleaks: available" || echo "gitleaks: not installed"
```

If **neither** semgrep nor trivy is installed, fall back to LLM-only code review and recommend installation:
- Semgrep: `brew install semgrep` or `pip install semgrep`
- Trivy: `brew install trivy`
- Gitleaks: `brew install gitleaks`

## Step 2: Run Semgrep (SAST)

If semgrep is available, scan for code vulnerabilities.

**Fast scan (changed files only — prefer this for inner-loop reviews):**
```bash
git diff --name-only HEAD | xargs semgrep scan --json --config auto --severity WARNING 2>/dev/null | jq '{count: (.results | length), results: [.results[] | {rule: .check_id, severity: .extra.severity, file: .path, line: .start.line, message: .extra.message}]}'
```

**Full project scan (use for thorough reviews or when explicitly asked):**
```bash
semgrep scan --json --config auto --severity WARNING . 2>/dev/null | jq '{count: (.results | length), results: [.results[] | {rule: .check_id, severity: .extra.severity, file: .path, line: .start.line, message: .extra.message}]}'
```

**If output is large (count > 20), filter by severity first:**
```bash
semgrep scan --json --config auto --severity ERROR . 2>/dev/null | jq '.results[:20]'
```

## Step 3: Run Trivy (Dependency/CVE Scanning)

If trivy is available, scan for vulnerable dependencies and IaC misconfigurations.

**Dependency scan:**
```bash
trivy fs --format json --severity HIGH,CRITICAL --ignore-unfixed . 2>/dev/null | jq '{count: (.Results // [] | map(.Vulnerabilities // [] | length) | add // 0), results: [.Results // [] | .[].Vulnerabilities // [] | .[] | {pkg: .PkgName, installed: .InstalledVersion, fixed: .FixedVersion, severity: .Severity, cve: .VulnerabilityID, title: .Title}]}'
```

**If Dockerfile exists, also scan the image config:**
```bash
trivy config --format json --severity HIGH,CRITICAL . 2>/dev/null | jq '.Results // []'
```

## Step 4: Run Gitleaks (Secret Detection)

If gitleaks is available, scan for hardcoded secrets.

```bash
gitleaks detect --source . --no-banner --report-format json 2>/dev/null | jq '{count: (. | length), results: [.[] | {rule: .RuleID, file: .File, line: .StartLine, match: .Match[:50]}]}'
```

## Step 5: Triage and Fix

Present findings as a structured table:

```markdown
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
```

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
