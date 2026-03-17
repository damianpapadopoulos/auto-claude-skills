# Design: Security Scanners

## Architecture
The security scanner is a composition-only bundled skill (`skills/security-scanner/SKILL.md`) activated during the REVIEW phase via `default-triggers.json` phase composition. It runs deterministic CLI tools via the agent's Bash tool and parses structured JSON output.

Data flow:
1. Session-start hook detects available tools (`command -v semgrep/trivy/bandit/gitleaks`) at Step 8f
2. Security capabilities emitted as informational context (`Security tools: semgrep=true, ...`)
3. REVIEW phase composition fires `Skill(auto-claude-skills:security-scanner)`
4. SKILL.md instructs agent to run its own `command -v` checks, execute scanners, parse JSON, fix issues, re-scan

## Dependencies
- Semgrep CLI (optional, `brew install semgrep`)
- Trivy CLI (optional, `brew install trivy`)
- Gitleaks CLI (optional, `brew install gitleaks`)
- jq (required by session-start hook, already a project dependency)
- No new Python/MCP/runtime dependencies

## Decisions & Trade-offs

### Option B (Skill+Bash) over Option A (MCP servers)
Design debate with architect, critic, and pragmatist perspectives reached unanimous consensus. MCP wraps `semgrep scan --json` in a Python server to get a JSON schema for a path argument — ceremony without value. Bash gives the agent full pipeline control (jq filtering, pagination, scoped scanning). Token cost: MCP = 1,600-2,400 permanent; Skill = ~50 routed, ~500 on-demand.

### Composition-only routing over trigger scoring
The skill has no frontmatter triggers and is not in the skills array. It activates only via REVIEW composition (`"when": "always"`) reinforced by a methodology hint on security keywords. This prevents it from competing with other domain skills during scoring.

### Self-contained capability detection
The SKILL.md runs its own `command -v` checks at invocation time, independent of session-start detection. Session-start detection is informational for the model, not a routing gate. This makes the skill portable and self-contained.

### Secret output sanitization
Gitleaks output uses `.Description` instead of `.Match[:50]` to prevent partial secret leakage into LLM context. Code review caught this before shipping.
