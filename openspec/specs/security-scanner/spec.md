# Security Scanner

## Purpose

Deterministic code-security review via Semgrep (SAST), Trivy (dependencies), and Gitleaks (secrets). Produces JSON-structured findings, degrades gracefully when tools are missing, and drives a self-healing fix-rescan loop during REVIEW.

## Requirements

### Requirement: Hybrid deterministic scanning
The security-scanner skill MUST orchestrate CLI tools (Semgrep, Trivy, Gitleaks) via Bash and parse their structured JSON output for the agent to act on.

#### Scenario: Semgrep SAST scan on changed files
Given semgrep is installed
When the agent invokes the security-scanner skill during REVIEW
Then it runs semgrep with `--json --config auto` on branch-changed files via `git diff --name-only -z`
And presents findings as a structured table with severity, file, line, rule, and message

#### Scenario: Trivy dependency scan
Given trivy is installed
When the agent invokes the security-scanner skill during REVIEW
Then it runs trivy fs with `--format json --severity HIGH,CRITICAL`
And presents vulnerabilities with package name, installed version, fixed version, CVE, and title

#### Scenario: Gitleaks secret detection without leaking secrets
Given gitleaks is installed
When the agent invokes the security-scanner skill
Then it runs gitleaks detect with `--report-format json`
And output includes RuleID, File, StartLine, and Description but NOT the Match content

### Requirement: Graceful degradation
The skill MUST adapt to available tools without failing.

#### Scenario: No tools installed
Given neither semgrep nor trivy nor gitleaks is installed
When the agent invokes the security-scanner skill
Then it falls back to LLM-only review and recommends installation commands

#### Scenario: Partial tools
Given only semgrep is installed (trivy and gitleaks are not)
When the agent invokes the security-scanner skill
Then it runs semgrep scan and notes that dependency and secret scanning are unavailable

### Requirement: Self-healing fix loop
The agent MUST fix critical/high findings and re-scan to verify.

#### Scenario: Fix and verify
Given semgrep finds a SQL injection vulnerability
When the agent fixes the code
Then it re-runs semgrep on the changed file to verify the fix
And reports the fix in the final summary

#### Scenario: Loop cap
Given multiple findings exist
When the agent enters the fix-rescan loop
Then it performs at most 3 iterations to prevent infinite loops

### Requirement: Session-start capability detection
The session-start hook MUST detect and report available security tools.

#### Scenario: Tools detected at session start
Given the session-start hook runs
When semgrep and gitleaks are installed but trivy is not
Then additionalContext includes "Security tools: semgrep=true, trivy=false, bandit=false, gitleaks=true"

### Requirement: REVIEW phase routing
The security-scanner MUST activate via REVIEW composition, not trigger scoring.

#### Scenario: Composition-only activation
Given the REVIEW phase composition in default-triggers.json
When the agent enters REVIEW phase
Then it fires Skill(auto-claude-skills:security-scanner) with "when": "always"

#### Scenario: Methodology hint reinforcement
Given a prompt containing "security scan" during REVIEW phase
When the activation hook processes methodology hints
Then the deterministic-security-scan hint fires with Skill(auto-claude-skills:security-scanner) reference
