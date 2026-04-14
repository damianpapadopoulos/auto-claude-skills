# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Wave 1 PDLC Safety Enrichments: `starter-template` domain skill — emits repo-native seed files (SKILL.md skeleton, routing entry, test snippets) when creating new skills
- Wave 1 PDLC Safety Enrichments: `prototype-lab` domain skill — produces 3 thin comparable variants with mandatory Human Validation Plan
- Wave 1 PDLC Safety Enrichments: `agent-safety-review` domain skill — evaluates autonomous agent designs for the lethal trifecta (private data + untrusted input + outbound action)
- Wave 1 PDLC Safety Enrichments: scenario-eval test suite — 12 behavioral scenarios validating routing judgment, safety interception, guardrails, and driver invariants
- Wave 1 PDLC Safety Enrichments: DESIGN phase guidance updated with prototype-lab and agent-safety-review awareness hints

### Added
- Incident-analysis: Constraint 7 Evidence-Only Attribution — bans speculative language in synthesis/YAML, forces evidence-backed claims or 4-state classification
- Incident-analysis: Step 3 application-logic analysis — N+1 call patterns, retry amplification, gRPC connection pinning checks for shared-dependency incidents
- Incident-analysis: Step 5 per-service attribution proof — 4-state model (confirmed-dependent / independent / inconclusive / not-investigated) with cited evidence per service
- Incident-analysis: Step 7 optional service_attribution YAML block for multi-service incidents
- Incident-analysis: Step 8 Q10 completeness gate — multi-service attribution verification
- Incident-analysis: 2 new behavioral eval scenarios (independent failures, incomplete evidence) with machine-verifiable regex assertions
- Incident-analysis: service_attribution output fixture validation with co-occurrence check

### Added
- Incident-analysis: Step 6b Timeline Extraction — structured candidate extraction with time_precision labels and dedupe rules before synthesis
- Incident-analysis: Step 4.5 Cross-Reference — regression candidates annotated with explains_patterns/cannot_explain_patterns linking commits to observed log errors
- Incident-analysis: Step 4.5b Bounded Expansion — same-commit and same-package expansion when primary stack-frame analysis finds no regression candidate
- Incident-analysis: Config-change source analysis trigger using existing config_change_correlated_with_errors signal, plus user override (both require repo-backed git ref)

### Fixed
- Incident-analysis: test assertions now validate `false` and `null` fixture values using `jq has()` instead of `//` operator which treated them as falsy

### Added
- Alert-hygiene: per-cluster `total_open_hours` computed from actual incident durations (fixes 2.7x inflation from `raw * median` estimation)
- Alert-hygiene: five inventory-level enrichment fields in compute-clusters.py — `zero_channel_policies`, `disabled_but_noisy_policies`, `silent_policy_count`, `silent_policy_total`, `condition_type_breakdown`
- Alert-hygiene: Proposed Config Diff section in Investigate template — preserves PR-ready config changes when items are demoted from Do Now due to missing gate requirements
- Alert-hygiene: mandatory report skeleton sections (Dead/Orphaned Config, Inventory Health, Silent Policy Cleanup trigger) reading from deterministic script output instead of ad-hoc LLM computation

### Added
- Alert-hygiene: `service_key` and `signal_family` fields in compute-clusters.py for deterministic service identity and signal classification
- Alert-hygiene Stage 1: optional SLO config enrichment via GitHub API with Ruby stdlib YAML parsing and two-sided normalization contract
- Alert-hygiene Stage 4: routing validation — zero-channel policy detection, unlabeled high-noise policy promotion, label inconsistency promotion to Investigate
- Alert-hygiene Stage 4: SLO coverage cross-reference — migration candidates (no SLO) and redundancy candidates (SLO + noisy threshold alerts)
- Alert-hygiene Stage 5: IaC location resolution via `gh search code` — upgrades Search Required to Likely with repo:path reference
- Two-sided Python/Ruby normalization contract test ensuring service_key and SLO name matching stays aligned

### Added
- On-demand observability preflight script (`scripts/obs-preflight.sh`) — checks gcloud auth, kubectl connectivity, and observability MCP configuration with JSON output and fail-open behavior
- Preflight wired into incident-analysis Step 1, alert-hygiene Tier Detection, and /investigate command as first step before tier selection
- REVIEW-before-SHIP guard in openspec-guard.sh (Check 4) — warns on git commit/push when requesting-code-review is in composition chain but not completed
- CLAUDE.md rules: "proceed means continue" (infer next step from context) and "no full-file rewrites" (use targeted edits, preserve existing data)

### Changed
- Alert-hygiene report restructured from confidence-band grouping (High/Medium/Needs Analyst) to action-class structure (Do Now / Investigate / Needs Decision) with strict Do Now gating, two-stage investigation DoDs, Decision Summary table, Verification Scorecard, and Systemic Issues consolidation

### Added
- Bounded disambiguation probes for incident-analysis CLASSIFY: SHORTLIST artifact, targeted disambiguation probes section, one-round anti-looping with pre-probe fingerprint
- Playbook `disambiguation_probe` schema on dependency-failure, config-regression, and infra-failure playbooks
- Step 4b source analysis within INVESTIGATE: bad-release gated code analysis at deployed ref, post-hop workload resolution, structured output contract
- `/investigate` command entry point pre-populating MITIGATE scope inputs
- `slo_burn_rate_alert` context signal with MITIGATE Step 2c integration
- SLO burn rate routing trigger in default-triggers.json and fallback-registry.json
- Fixture schema validator (test-incident-analysis-output.sh) with real-incident-only authoring guidelines
- 15 new test assertions for disambiguation probes and Step 4b behavioral contracts
- Remediation verification for incident-analysis: Step 2b inventory now captures scheduling constraints (affinity, topologySpreadConstraints, taints/tolerations) with tiered retrieval (kubectl > GitOps > unverified flag)
- "Current State" field in postmortem action items — forces verification of existing config before recommending changes, with functional equivalence guidance (topologySpreadConstraints ≈ podAntiAffinity)

### Fixed
- Incident-analysis Constraint 2 scope restriction now has infrastructure escalation exception for node-level investigation
- High-confidence decision record restored missing safety fields: Evidence Age, VETO SIGNALS, State Fingerprint, Explanation
- Step 7 synthesis expanded to preserve ruled-out hypotheses and revision history for Investigation Path appendix
- OpenSpec spec.md corrected from "7 section headers" to "8 section headers"
- EXECUTE and VALIDATE stages now have explicit evidence persistence steps (pre.json, validate.json)

### Added
- DISCOVER phase: `product-discovery` skill with tiered Atlassian MCP detection (Jira/Confluence context → discovery brief → transition to DESIGN)
- LEARN phase: `outcome-review` skill with tiered PostHog MCP detection (analytics queries → outcome report → gated Jira follow-up creation)
- Two-tier DISCOVER trigger patterns (strong + weak signals) with high-threshold scoring for disambiguation against DESIGN
- PostHog MCP server detection in session-start hook (follows Serena/Forgetful pattern)
- PostHog plugin entry with 6 MCP tools (query-run, get-experiment, list-experiments, get-feature-flag, list-feature-flags, create-annotation)
- DISCOVER and LEARN phase_guide, phase_compositions, red flags, and labels in routing engine
- SHIP composition LEARN reminder hint
- posthog-metrics methodology hint (plugin-gated, LEARN/SHIP/DEBUG phases)
- 12 new routing/registry/context tests for DISCOVER and LEARN phases
- Regex compilation validation test for all trigger patterns (Bash 3.2 POSIX ERE)
- Bundled `incident-trend-analyzer` skill (v2.0): on-demand postmortem trend analysis with recurrence grouping, trigger categorization, MTTR/MTTD metrics, tiered eligibility, confidence-aware extraction, and terminal-first output with optional persistence

### Changed
- Atlassian plugin phase_fit extended to include DISCOVER and LEARN; mcp_tools extended with createJiraIssue and addCommentToJiraIssue
- atlassian-jira methodology hint phases extended to include DISCOVER; triggers extended with discover/triage/prioriti
- No-registry fallback message updated to include DISCOVER and LEARN phases
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
- Fallback registry parity: added `security-scanner` to `default-triggers.json` with `phase: REVIEW` (composition-only, resolves 2 pre-existing test-registry.sh failures)
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
