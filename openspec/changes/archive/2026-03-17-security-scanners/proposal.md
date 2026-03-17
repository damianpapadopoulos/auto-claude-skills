# Proposal: Security Scanners

## Problem Statement
The security scanning capabilities in auto-claude-skills were pure-LLM: a write-time pattern matching hook (security-guidance) and an LLM-only review-phase skill reference. This missed AST-level data-flow vulnerabilities, known CVEs announced after the model's training cutoff, and IaC misconfigurations. The external matteocervelli security-scanner was a grep-based wrapper with high false-positive rates.

## Proposed Solution
A hybrid approach: bundled SKILL.md that orchestrates deterministic CLI tools (Semgrep for SAST, Trivy for dependency CVE scanning, Gitleaks for secret detection) via the Bash tool during the REVIEW phase. The agent runs scanners, receives structured JSON findings, fixes critical/high issues, and re-scans to verify. A design debate (3 perspectives, unanimous) selected Skill+Bash over MCP servers for zero additional infrastructure.

## Out of Scope
- MCP server wrappers (deferred unless real demand emerges from usage data)
- STRIDE/threat modeling (future design-phase skill, separate effort)
- Automatic hook-based scanning at PreToolUse/PostToolUse events
- CI/CD integration or production deployment pipelines
