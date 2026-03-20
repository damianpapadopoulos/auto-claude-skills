# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Bundled `incident-analysis` skill with tiered GCP log investigation (MCP > gcloud > guidance) and structured postmortem generation
- 3-stage investigation state machine: MITIGATE → INVESTIGATE → POSTMORTEM with 4 behavioral guardrails (HITL gate, scope restriction, temp-file LQL pattern, context discipline)
- Observability Truth tier in unified-context-stack testing-and-debug phase
- Session-start `observability_capabilities` detection (gcloud availability)
- Postmortem permalinks in `incident-analysis` skill (v1.2): trace IDs as clickable Cloud Console links, commit hashes as clickable GitHub links
- One-hop trace correlation in `incident-analysis` skill (v1.1): autonomous Service A → Service B correlation, evidence-gated, Tier 1 MCP only
- Updated `gcp-observability` routing hint with incident/postmortem/outage triggers
- README rewritten as end-user product page with decision-funnel structure, SDLC phase table, example prompts, and boundary-setting section
- Bundled `security-scanner` skill with hybrid Semgrep/Trivy/Gitleaks scanning via Bash
- Session-start `security_capabilities` detection (Step 8f: semgrep, trivy, bandit, gitleaks)
- `deterministic-security-scan` methodology hint (REVIEW phase, security keywords)
- Setup guidance for CLI tool installation and first-run configuration

### Changed
- REVIEW composition invoke path migrated to `Skill(auto-claude-skills:security-scanner)`
- security-scanner removed from external skills check (now bundled)
- setup.md: matteocervelli install replaced with built-in notice + CLI tool setup

### Fixed
- Gitleaks output sanitized to prevent partial secret leakage into LLM context (uses Description instead of Match)
- Fast scan uses null-delimited xargs for safe filename handling
- Fast scan scope uses git merge-base for branch-level changes

## [3.9.2] - 2026-03-17

### Added
- MCP detection fallback: session-start hook reads ~/.claude.json for serena/forgetful/context7 MCP servers
- Forgetful curated plugin entry in default-triggers.json with all-phase coverage
- Forgetful session-start usage hint (parallel to existing Serena hint)
- Serena PreToolUse nudge guard (hints when Grep used for symbol lookups)
- Historical Truth step in Implementation phase (workaround check)
- Historical Truth step in Code Review phase (convention check)
- Memory consolidation enforcement in openspec-guard (commit-time warning)
- Delta spec sync check in openspec-guard (warns on unsynced archived deltas)
- Consolidation-stop.sh Stop hook with tier-specific guidance at session end

### Fixed
- Serena tool name: cross_reference corrected to find_referencing_symbols across all phase/tier docs
- Forgetful tool names: memory-search/memory-save/memory-explore corrected to actual MCP tool pattern
- openspec-guard refactored to accumulator pattern for multi-warning PreToolUse output
- printf fallback in openspec-guard escapes newlines for valid JSON

### Changed
- Design phase document for unified-context-stack (Intent Truth + Historical Truth before brainstorming)
- Phase-aware RED FLAGS for DESIGN, PLAN, IMPLEMENT, and REVIEW phases
- Phase-enforcement methodology hint for DESIGN/PLAN phases
- REVIEW 3-step sequence (requesting → agent-team → receiving code review)
- IMPLEMENT sequence entries for worktree and finishing-branch requirements
- Required role (`role: "required"`) for cap-bypassing skills
- Composition parallel entries for TDD (IMPLEMENT/DEBUG) and security-scanner (REVIEW)
- SDLC chain bridging: end-to-end 7-step composition chain (DESIGN → SHIP)
- IMPLEMENT stickiness rule for explicit continuation language

### Changed
- Narrowed DESIGN phase activation hint from generic 4-tier to Intent Truth + Historical Truth
- Narrowed brainstorming triggers to boundary-safe generic verbs
- Narrowed design-debate triggers to tradeoff/comparison language only
- Narrowed agent-team-execution triggers to team-specific language
- Reclassified using-git-worktrees to required role (trigger-gated)
- Reclassified agent-team-review to required role (condition-gated)
- Updated requesting-code-review description to reflect subagent dispatch
- Updated executing-plans description to include worktree and finishing requirements
- Relaxed hook budget from 50ms to <200ms

### Fixed
- Composition state guard against _current_idx=-1 corruption
- IMPLEMENT stickiness restricted to continuation language (respects HARD-GATE)
- Guard stickiness injection against disabled/missing executing-plans
- Zero-match log prompt truncation (200 chars) and byte-size rotation (50KB)
- TDD fallback grep replaced with boolean flag (perf)
- Fallback registry parity with production config
- Test fixture parity for requesting-code-review priority
