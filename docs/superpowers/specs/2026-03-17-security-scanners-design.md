# Security Scanners: Hybrid Deterministic Scanning via Skill + Bash

**Date:** 2026-03-17
**Status:** Draft
**Phase:** DESIGN

## Problem Statement

The current security scanning capabilities are pure-LLM:
- `security-guidance` PreToolUse hook: pattern-matches XSS/injection at write-time
- `security-scanner` skill reference in REVIEW phase: LLM reasoning only, no CLI tools
- `agent-team-review` security reviewer: LLM-only code review perspective

Pure-LLM scanning is slow (minutes), token-expensive (entire codebase in context), and misses:
- AST-level data-flow vulnerabilities (variable passes through 3 files before hitting a sink)
- Known CVEs announced after the model's training cutoff
- IaC misconfigurations in Dockerfiles/Terraform

## Recommended Approach

**Option B: Skill-mediated Bash invocation** — a `security-scanner` SKILL.md that instructs the agent to run Semgrep and Trivy via the Bash tool, parse JSON findings, fix issues, and re-scan to verify.

### Why Not MCP Servers (Option A)

A design debate (3 perspectives, unanimous convergence) rejected MCP because:

1. The agent already has Bash. Wrapping `semgrep scan --json` in an MCP server adds zero capability over running it directly.
2. Prior precedent: the MCP Integration Design (2026-03-03) concluded MCP is only justified for capabilities Bash cannot provide (e.g., interactive browser via Playwright).
3. Token cost: MCP tools consume 1,600-2,400 tokens permanently; a skill costs ~50 tokens when routed, ~500-1,000 on-demand.
4. Installation friction: MCP requires Python 3 + mcp library + server configuration. Skill requires only the CLI tools themselves.
5. Bash gives the agent pipeline control (jq filtering, pagination, scoping to changed files) that MCP locks behind a fixed interface.

### Why Not Hooks (Option C)

Automatic scanning at PreToolUse/PostToolUse was rejected because:
- 95%+ of scans return nothing, wasting tokens on empty results
- Semgrep can exceed the 200ms hook budget
- Conflates "when to scan" (a routing decision) with "how to scan" (execution)

### Why Not Pure-LLM (Option D)

Deterministic scanning is strictly better than LLM-only. AST-based analysis catches data-flow vulnerabilities. CVE databases catch zero-days. The hybrid model (tools find, LLM fixes) is the clear winner.

## Architecture

### Components

**1. `security-scanner/SKILL.md`** — New skill file

Teaches the agent a self-healing scan-fix-verify loop:
- Detect installed tools (`command -v semgrep`, `command -v trivy`)
- Run Semgrep SAST on changed files (scoped via `git diff`)
- Run Trivy dependency/IaC scan on project root
- Parse JSON output, triage by severity
- Fix critical/high findings using normal editing tools
- Re-scan to verify fixes
- Report results as structured table

**2. Session-start capability detection** — Addition to `session-start-hook.sh`

Four `command -v` checks (~1ms total) to detect:
- `semgrep` (SAST)
- `trivy` (dependency/container scanning)
- `bandit` (Python-specific, optional)
- `gitleaks` (secret detection, optional)

Results stored in registry context so the skill can adapt to available tools.

**3. Methodology hint** — Addition to `config/default-triggers.json`

```json
{
  "name": "deterministic-security-scan",
  "triggers": ["(review|security|vulnerabilit|scan|owasp|cve|semgrep|trivy|sast|dast|dependency.audit)"],
  "trigger_mode": "regex",
  "hint": "SECURITY SCAN: If semgrep/trivy are installed, run deterministic scans before LLM review. Invoke Skill(security-scanner).",
  "phases": ["REVIEW"]
}
```

**4. Updated REVIEW phase composition** — Existing entry enhanced

Current (line 871-874 of default-triggers.json):
```json
{
  "use": "security-scanner -> Skill(security-scanner)",
  "when": "always",
  "purpose": "Scan for vulnerabilities, OWASP risks, compliance issues. INVOKE during every review"
}
```

Updated to reference hybrid workflow:
```json
{
  "use": "security-scanner -> Skill(security-scanner)",
  "when": "always",
  "purpose": "Run semgrep/trivy deterministic scans first, then LLM triage. Self-healing loop: scan -> fix -> re-scan -> clean"
}
```

### Data Flow

```
Session Start
  session-start-hook.sh
    -> command -v semgrep/trivy/bandit/gitleaks
    -> emit security_capabilities in registry context

REVIEW Phase
  skill-activation-hook.sh
    -> routes to security-scanner skill (existing trigger)
    -> methodology hint reminds agent to invoke

  Agent loads SKILL.md
    -> Checks security_capabilities
    -> If semgrep: Bash("semgrep scan --json --config auto --severity WARNING .")
    -> If trivy: Bash("trivy fs --format json --severity HIGH,CRITICAL .")
    -> Parse JSON findings
    -> Fix critical/high issues
    -> Re-scan to verify (max 3 iterations)
    -> Report: findings table + what was fixed + what needs human review
```

### Self-Healing Loop

```
Agent writes code
  -> REVIEW phase activates security-scanner skill
  -> Semgrep finds SQL injection in src/db.py:42
  -> Agent rewrites to parameterized query
  -> Agent re-runs semgrep on src/db.py -> clean
  -> Trivy finds CVE-2024-XXXX in express@4.17.1
  -> Agent bumps to express@4.19.2 in package.json
  -> Agent re-runs trivy -> clean
  -> Report: "2 issues found, 2 fixed, 0 remaining"
```

## Skill Design

### Tool Detection and Graceful Degradation

The skill adapts to what's installed:

| Tools Available | Behavior |
|----------------|----------|
| semgrep + trivy | Full hybrid scan (SAST + dependency) |
| semgrep only | SAST scan, note dependency scanning unavailable |
| trivy only | Dependency scan, note SAST unavailable |
| neither | Fall back to LLM-only review, recommend installation |

### Semgrep Invocation

```bash
# Scoped to changed files (fast inner-loop)
git diff --name-only HEAD | xargs semgrep scan --json --config auto --severity WARNING

# Full project scan (thorough review)
semgrep scan --json --config auto --severity WARNING .
```

Output filtering for large results:
```bash
# Count findings first
semgrep scan --json --config auto . | jq '.results | length'

# Filter by severity
semgrep scan --json --config auto . | jq '[.results[] | select(.extra.severity == "ERROR")]'

# Paginate
semgrep scan --json --config auto . | jq '.results[:20]'
```

### Trivy Invocation

```bash
# Filesystem scan (dependencies + IaC)
trivy fs --format json --severity HIGH,CRITICAL .

# Ignore unfixed vulnerabilities
trivy fs --format json --severity HIGH,CRITICAL --ignore-unfixed .

# Container image scan (when Dockerfile present)
trivy image --format json --severity HIGH,CRITICAL <image-name>
```

### Output Format

The skill instructs the agent to present findings as:

```markdown
## Security Scan Results

### Semgrep (SAST) — 3 findings
| Severity | File | Line | Rule | Message |
|----------|------|------|------|---------|
| ERROR | src/db.py | 42 | python.lang.security.audit.sqli | SQL injection via string concatenation |
| WARNING | src/auth.py | 18 | python.lang.security.audit.crypto-weak | Weak hash algorithm (MD5) |
| WARNING | src/api.py | 95 | javascript.express.security.audit.xss | Unescaped user input in response |

### Trivy (Dependencies) — 1 vulnerability
| Severity | Package | Installed | Fixed | CVE | Title |
|----------|---------|-----------|-------|-----|-------|
| CRITICAL | express | 4.17.1 | 4.19.2 | CVE-2024-XXXX | Prototype pollution |

### Actions Taken
- Fixed SQL injection in src/db.py:42 (parameterized query)
- Upgraded express 4.17.1 -> 4.19.2
- WARNING: MD5 usage in src/auth.py:18 needs human review (business logic dependency)
```

## Trigger Routing

The skill integrates with existing routing via frontmatter:

```yaml
---
name: security-scanner
description: Hybrid deterministic security scanning with Semgrep SAST and Trivy dependency/CVE analysis
role: domain
phase: REVIEW
priority: 25
triggers:
  - "(security|vulnerabilit|scan|owasp|cve|semgrep|trivy|sast|dast|dependency.audit)"
requires: []
precedes: []
---
```

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Semgrep output too large (50KB+ JSON) | Skill instructs: count first, filter by severity, paginate with jq |
| Scan duration on large repos (10-30s) | Scope to changed files via `git diff --name-only`; full scan only on explicit request |
| CLI interface changes | Skills are trivially updatable; no compiled code to rebuild |
| False sense of completeness | Skill report explicitly notes what was NOT scanned and recommends CI/CD integration |
| False positives | Skill instructs agent to check `.semgrepignore`/`.trivyignore` and help configure them |
| Tools not installed | Graceful degradation to LLM-only with install instructions |

## Incremental Upgrade Path

```
Now:        Option B — SKILL.md + capability detection + methodology hint
            Ships in a day, get real usage data.

If needed:  Add lightweight hook for automatic scanning during verification phase only
            (not every file write). Still uses Bash.

Much later: IF tool interface becomes complex (custom rulesets, result caching,
            multi-repo scanning) -> Consider MCP servers then.
```

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `skills/security-scanner/SKILL.md` | Create | Hybrid scan-fix-verify skill |
| `hooks/session-start-hook.sh` | Modify | Add security_capabilities detection |
| `config/default-triggers.json` | Modify | Add methodology hint + update REVIEW composition |
| `config/fallback-registry.json` | Modify | Keep parity with default-triggers.json |
| `tests/test-security-scanner.sh` | Create | Test capability detection + skill routing |

## Decision

Approved by design debate (unanimous, 3/3 high confidence). Option B selected. MCP deferred unless real demand emerges from usage data.
