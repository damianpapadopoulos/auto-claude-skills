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

**1. `skills/security-scanner/SKILL.md`** — New bundled plugin skill

Location: `skills/security-scanner/SKILL.md` (bundled in auto-claude-skills plugin).
Invoke path: `Skill(auto-claude-skills:security-scanner)`.

**Migration note:** The existing REVIEW composition references `Skill(security-scanner)` (external user-skill pattern from the `matteocervelli/llms` placeholder). This must be updated to `Skill(auto-claude-skills:security-scanner)` in `default-triggers.json`, `fallback-registry.json`, and all test assertions. The external placeholder at `~/.claude/skills/security-scanner/` can be removed by users after plugin update.

Teaches the agent a self-healing scan-fix-verify loop:
- Detect installed tools at runtime (`command -v semgrep`, `command -v trivy` via Bash)
- Run Semgrep SAST on changed files (scoped via `git diff`)
- Run Trivy dependency/IaC scan on project root
- Parse JSON output, triage by severity
- Fix critical/high findings using normal editing tools
- Re-scan to verify fixes
- Report results as structured table

The SKILL.md runs its own `command -v` checks at invocation time for self-contained detection. The session-start capability detection (below) provides early awareness for routing decisions but is not required by the skill itself.

**2. Session-start capability detection** — Addition to `session-start-hook.sh`

Four `command -v` checks (~1ms total) added **after Step 8d** (context_capabilities detection), following the same pattern. Detects:
- `semgrep` (SAST)
- `trivy` (dependency/container scanning)
- `bandit` (Python-specific, optional)
- `gitleaks` (secret detection, optional)

**Registry placement:** New field `security_capabilities` as a sibling of `context_capabilities` in the `additionalContext` output, using the same boolean pattern:

```json
"security_capabilities": {
  "semgrep": true,
  "trivy": false,
  "bandit": false,
  "gitleaks": true
}
```

Emitted in `additionalContext` string as: `Security tools: semgrep=true, trivy=false, bandit=false, gitleaks=true`

**3. Methodology hint** — Addition to `config/default-triggers.json`

```json
{
  "name": "deterministic-security-scan",
  "triggers": ["(security|vulnerabilit|owasp|cve|semgrep|trivy|sast|dast|dependency.audit)"],
  "trigger_mode": "regex",
  "hint": "SECURITY SCAN: If semgrep/trivy are installed, run deterministic scans before LLM review. Invoke Skill(auto-claude-skills:security-scanner).",
  "phases": ["REVIEW"]
}
```

Note: `review` excluded from triggers to avoid overlap with the existing `pr-review` methodology hint. The REVIEW phase composition already activates the skill independently of hint matching.

**4. Updated REVIEW phase composition** — Invoke path migration

Current:
```json
{
  "use": "security-scanner -> Skill(security-scanner)",
  "when": "always",
  "purpose": "Scan for vulnerabilities, OWASP risks, compliance issues. INVOKE during every review"
}
```

Updated:
```json
{
  "use": "security-scanner -> Skill(auto-claude-skills:security-scanner)",
  "when": "always",
  "purpose": "Run semgrep/trivy deterministic scans first, then LLM triage. Self-healing loop: scan -> fix -> re-scan -> clean"
}
```

### Data Flow

```
Session Start
  session-start-hook.sh (after Step 8d)
    -> command -v semgrep/trivy/bandit/gitleaks
    -> emit security_capabilities in additionalContext (sibling of context_capabilities)
    -> format: "Security tools: semgrep=true, trivy=false, ..."

REVIEW Phase
  skill-activation-hook.sh
    -> REVIEW composition fires Skill(auto-claude-skills:security-scanner)
    -> methodology hint reinforces if security keywords present

  Agent loads SKILL.md
    -> Runs own command -v checks via Bash (self-contained, does not read registry)
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

The skill is activated via **REVIEW phase composition only** (not via trigger scoring). This is consistent with the current architecture where security-scanner is a composition parallel, not a scored domain skill. The SKILL.md has no frontmatter triggers.

The routing path is:
1. Agent enters REVIEW phase
2. REVIEW composition fires `Skill(auto-claude-skills:security-scanner)` as a parallel step
3. Methodology hint `deterministic-security-scan` reinforces on security keywords
4. No trigger scoring — the skill is not in the `skills[]` array of `default-triggers.json`

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
| `skills/security-scanner/SKILL.md` | Create | Hybrid scan-fix-verify skill (bundled, invoke: `Skill(auto-claude-skills:security-scanner)`) |
| `hooks/session-start-hook.sh` | Modify | (1) Add `security_capabilities` detection after Step 8d, same pattern as `context_capabilities`. (2) Remove `security-scanner` from the external missing-skills check (~line 833) since it is now bundled. |
| `config/default-triggers.json` | Modify | (1) Add `deterministic-security-scan` methodology hint, (2) update REVIEW composition invoke path to `Skill(auto-claude-skills:security-scanner)`, (3) update purpose string |
| `config/fallback-registry.json` | Modify | Must be regenerated after `default-triggers.json` changes. Run `session-start-hook.sh` once to auto-regenerate. Implementation step must verify parity (fallback contains `Skill(auto-claude-skills:security-scanner)`, not the stale external path). Include a test assertion for fallback parity. |
| `tests/test-security-scanner.sh` | Create | See Test Strategy below |

### Test Strategy

`tests/test-security-scanner.sh` must cover:

1. **Capability detection**: Mock `command -v` responses, verify `security_capabilities` appears in `additionalContext` output with correct boolean values
2. **Methodology hint firing**: Feed security keywords to `skill-activation-hook.sh`, verify `deterministic-security-scan` hint appears in output
3. **Methodology hint non-firing**: Feed non-security prompts, verify hint does NOT appear (no false positives from removed `review` trigger)
4. **Composition invoke path**: Verify REVIEW phase composition references `Skill(auto-claude-skills:security-scanner)` (not the old external path)

Existing tests to update (significant scope):
- `tests/test-routing.sh`: ~14 references including mock registry entries and assertion patterns — update all `Skill(security-scanner)` to `Skill(auto-claude-skills:security-scanner)`
- `tests/test-context.sh`: ~7 references including mock registry entries and assertion patterns — same invoke path migration

Note: Mock registries embedded in test fixtures also need invoke path updates, not just assertion strings.

### `security_capabilities` routing note

The `security_capabilities` field in `additionalContext` is **informational for the model only**. The activation hook (`skill-activation-hook.sh`) does NOT consume it for routing decisions — the REVIEW composition fires unconditionally (`"when": "always"`). The field helps the model know which tools are available before loading the skill, but is not a routing gate.

## Decision

Approved by design debate (unanimous, 3/3 high confidence). Option B selected. MCP deferred unless real demand emerges from usage data.
