# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- CAST behavioral eval fixture: new `cast-systemic-factors-coverage` entry in `tests/fixtures/incident-analysis/evals/behavioral.json` invokes `skills/incident-analysis` via `claude -p` against a prompt derived from the 2026-04-08 billing-tab postmortem (a multi-team, multi-controller incident not seen during CAST design). Strict assertion set covers Step 7 items 9–10 and Q12 surface: 2 section headers (`Mental model gaps`, `Systemic factors`), 1 controller-belief shape regex (`believed.*actual`), and 5 CAST category names (Safety Culture, Communication/Coordination, Management of Change, Safety Information System, Environmental Change). Plus 1 reference-pointer assertion (`cast-framing\.md`). Opt-in via `BEHAVIORAL_EVALS=1`, never in the default `tests/run-tests.sh` path — consistent with the v1 runner posture. README under `tests/fixtures/incident-analysis/evals/` lists the new fixture under "Notable scenarios" and notes its independent-from-design provenance. Hindsight-bias absence intentionally not asserted (quoted-phrase replacements would false-positive on legitimate model output that quotes the language being replaced). **Live-run gate is open:** during fixture authoring, two of three `claude -p` runs produced clean Step 7 synthesis matching expected assertions, but the third run interpreted authorship-meta context and used its tool access to revert uncommitted fixture refinements (`git checkout -- behavioral.json` equivalent). Iterative live tuning is unsafe with the current runner, which passes full Edit/Write/Bash tool access to the inner `claude -p` process. Fixture is shipped in its committed strict form; loosening based on observed prose variation (e.g. `Mental[- ]model gaps`, optional whitespace around `Communication/Coordination` slash, `Systems?` plural) is deferred until the runner is hardened (see follow-up notes in the PR — proposed: add `--deny-tool Edit --deny-tool Write` flags to the inner `claude -p` invocation in `tests/run-behavioral-evals.sh`). Capability: `behavioral-evaluation`.
- CAST extensions in `skills/incident-analysis`: Step 7 synthesis gains item 9 **Mental model gaps** (per-controller `<controller> believed <X>; actual was <Y>` lines) and item 10 **Systemic factors** (observation or `N/A — <reason>` across the 5 CAST categories: Safety Culture, Communication/Coordination, Management of Change, Safety Information System, Environmental Change) plus a hindsight-bias self-check (`should have`, `failed to`, `could have easily`, `obviously`, `it was clear that` — replace with evidence-grounded framing). Step 8 completeness gate gains **Q12** — bare `N/A` blocks closure; `not_applicable — <reason>` / `unavailable` / `not_captured` remain valid per the existing Q4-Q12 resolution rule. New reference file `skills/incident-analysis/references/cast-framing.md` (86 lines) with 5-category definitions, mental-model-gap shape + 2 examples, hindsight-bias replacement table, and the "action item ⇒ name the belief" rule. `references/postmortem-template.md` §6 gains a required `**Systemic factors**` sub-block; §7 gains `**Mental model gaps**` + `Hindsight-bias check` paragraph. `references/investigation-schema.md` gains optional `mental_model_gaps` (list) and `systemic_factors` (5-key map) fields under `investigation_summary` — purely additive, no validator enforcement. Step 7 item 1 (Timeline) and item 8 (Evidence links) compressed to fit the 11,500-word SKILL.md guard (now 11,492). `tests/test-incident-analysis-content.sh` gains 32 new assertions covering the additions. Capability: `incident-analysis`.
- LSP nudge hook (`hooks/lsp-nudge.sh`): new `PreToolUse` matcher `Grep` that emits a `hookSpecificOutput.additionalContext` hint when Claude greps for an error string while `context_capabilities.lsp=true`. Pattern matcher (`grep -Ei`) covers language-agnostic error strings: `TypeError`, `SyntaxError`, `Cannot find module|name`, `is not assignable`, `implicit any`, `Property .* does not exist`, `Expected ... got`, `undefined symbol`, `cannot resolve`, `undefined reference to`, etc. Fires alongside the existing `serena-nudge.sh` Grep matcher — both nudges can emit on the same Grep call without interference. Advisory-only; does not deny the Grep. Fail-open on every sub-check (missing jq, missing cache, `lsp=false`, non-Grep tool, non-matching pattern → silent exit 0). Closes the error-hunt drift gap left by the LSP capability awareness release. Capability: `skill-routing`.
- Skill Eval CI Gate: Two-layer defense against skill-routing drift. Deterministic regex-fixture runner `tests/test-regex-fixtures.sh` (bash 3.2 compatible, auto-discovered by `tests/run-tests.sh`) reads `tests/fixtures/routing/<skill>.txt` `MATCH:` / `NO_MATCH:` directives and asserts against compiled triggers in `config/default-triggers.json` using the same lowercase + `[[ =~ ]]` engine as `hooks/skill-activation-hook.sh` — zero LLM cost, fails the default test suite on regex drift. Non-blocking GitHub Actions workflow `.github/workflows/skill-eval.yml` (opt-in via `run-eval` label or `@claude run eval` comment) scores per-skill SKILL.md description trigger accuracy against optional `skills/<name>/evals/evals.json` packs, posts a markdown table per changed skill, flags `<80%` as description-rewrite candidate. Layered hardening against the `issue_comment` secrets-exfil vector on public repos: `author_association` allow-list in the job `if:`, API-based `admin|write|maintain` permission check, fork-PR head refusal before checkout, prompt-injection data-only directive, env-marshalled inputs, SHA-pinned `anthropics/claude-code-action@e58dfa5...`, reaper gated on `steps.eval.outcome == 'success'` so a prompt-injected eval cannot silently wipe prior legitimate warnings. Schema documented at `docs/eval-pack-schema.md`. Ships with `alert-hygiene` demo fixtures only — no backfill for other skills; coverage accrues opportunistically as skills are edited. Capability: `skill-routing`.
- Behavioral eval runner v1 (`tests/run-behavioral-evals.sh`): opt-in shell runner (`BEHAVIORAL_EVALS=1`) that reads `skills/incident-analysis/SKILL.md` verbatim, wraps it in `<skill_guidance>` + `<user_request>` tags around a fixture scenario prompt, invokes `claude -p --output-format json`, and runs each `assertions[].text` as a case-insensitive extended regex against the captured output. Per-run JSON artifact to `tests/artifacts/` (gitignored) with scenario_id, timestamp_utc, model, prompt, raw_output, per-assertion results, overall_passed, and elapsed_seconds. Hermetic self-test `tests/test-run-behavioral-evals.sh` (24 assertions) stubs `claude` via `CLAUDE_BIN` and ships with `tests/run-tests.sh`; real invocation stays opt-in, never in the default CI path. Honest framing README at `tests/fixtures/incident-analysis/evals/README.md` documents the schema-vs-runtime split and three optional additive pack fields (`tags`, `source_artifact`, `skill_version`). Model identifier parsed from either `.model` (mock shape) or `.modelUsage | keys[0]` (real `claude -p` shape). Replaces the previous schema-only pattern that was advertised as "evals" but never invoked the skill. Evaluator-optimizer protocol skill is explicitly parked — see `docs/plans/archive/2026-04-20-evaluator-optimizer-deferred.md`. Capability: `behavioral-evaluation`.
- LSP context capability detection: session-start now sets `context_capabilities.lsp = true` when BOTH conditions hold: (a) an installed plugin under `~/.claude/plugins/cache/` declares `lspServers.<name>.command` in its `plugin.json` (Claude Code's LSP plugin family: `typescript-lsp`, `pyright-lsp`, `gopls-lsp`, `rust-analyzer-lsp`, `jdtls-lsp`, `clangd-lsp`, `csharp-lsp`, `kotlin-lsp`, `lua-lsp`, `php-lsp`, `ruby-lsp`, `swift-lsp`, ...), AND (b) at least one of those declared commands resolves via `command -v` on the session PATH. The two-step requirement prevents false-positive `lsp=true` when a user installed the plugin but not the backing language-server binary (e.g. `typescript-lsp` present without `typescript-language-server` on PATH). When `lsp=true`, session-start emits a guidance line pointing Claude at `mcp__ide__getDiagnostics` alongside the existing Serena hint. When a plugin is present but its binary is missing, a `LSP (partial install)` diagnostic names the plugin and the missing command so the user knows exactly what to install. `unified-context-stack`'s `internal-truth.md` gains a Tier 0 (LSP) above the existing Serena/Grep tiers, and the `testing-and-debug` + `code-review` phase docs surface `lsp=true` as the first branch for compile/type-error questions. `commands/setup.md` lists the `*-lsp` plugin family and explicitly states the plugin + binary prerequisite. Capability: `skill-routing`.
- `skill-config.json` context-capabilities override: `~/.claude/skill-config.json` may include a `context_capabilities` object (e.g., `{"context_capabilities": {"lsp": true}}`) to force-enable detection flags. Augment-only — only upgrades `false → true`; never downgrades. Applies to every capability key, not just `lsp`. Pattern mirrors the existing MCP fallback block; fails open on missing/malformed config.
- Skill-completion PostToolUse hook: `hooks/skill-completion-hook.sh` (new, registered under `PostToolUse` matcher `^Skill$`) advances `.completed` and `.current` in `~/.claude/.skill-composition-state-<token>` whenever a chain-member `Skill` tool returns successfully. Closes the chain-walker blind spot that previously required a follow-up `UserPromptSubmit` trigger match to record in-turn skill completions; `openspec-guard.sh`'s push gate now reflects skills completed mid-turn (e.g., review + verification + ship in one response) without manual state reconciliation. Single jq merge per tool return, chain-order preserved (no `unique_by` dedupe — outer guard blocks duplicates), idempotent on reinvocation. Fail-open on every sub-check (missing jq, missing token, missing/malformed state, errored tool response, non-chain skill, mv failure → silent exit 0). `SKILL_EXPLAIN=1` emits a `[completion]` breadcrumb. Capability: `skill-routing`.
- DESIGN→PLAN contract guard: `hooks/skill-activation-hook.sh` now emits a `DESIGN COMPLETENESS` block in PLAN-phase activation output when the session has an active change with a non-null `design_path`. The block grep-checks the design file for `## Capabilities Affected`, `## Out-of-Scope`, and `## Acceptance Scenarios`, and emits one of three shapes: all-sections-present one-liner, per-section missing-annotations call-to-action, or unreadable-file notice. Advisory-only — does not deny the `Skill(writing-plans)` tool call. Fail-open on every sub-check (missing token, malformed state JSON, missing file, grep errors all degrade silently). `SKILL_EXPLAIN=1` emits a `[design-guard]` breadcrumb with presence flags + multi-change WARN when multiple open changes have `design_path`. Closes the DESIGN→PLAN contract loop (previously declared-but-not-enforced). Capability: `skill-routing`.

### Changed
- OpenSpec canonical specs: migrated all 13 capability specs from the legacy `## ADDED Requirements` shape to the OpenSpec v1.2.0-strict `## Purpose` + `## Requirements` shape. Unblocks `openspec archive` without `--skip-specs` across every capability. Four tracked specs (`adversarial-review`, `hypothesis-loop`, `pdlc-safety`, `skill-routing`) ship in this commit; the other nine remain session-local under the existing `openspec/` gitignore convention and can be force-added if the team decides to track them. Four specs required minor content fixes (adding MUST/SHALL keywords or scenarios) to satisfy strict validation — pre-existing gaps, not migration-induced.

### Fixed
- Composition state `completed` array no longer regresses to empty when the last-invoked signal is a non-chain domain/workflow skill. The chain walker now uses `_current_idx - 1` as a floor (linear composition model: being at anchor N implies predecessors 0..N-1 are done) in addition to the existing `_last_skill_chain_idx` signal. Unblocks chore/tracking commits that previously hit the REVIEW-before-push gate on stale state after a prior SHIP cycle.
- Hypothesis-to-Learning Loop: `write-learn-baseline` SHIP step was declared in composition sequence but had no implementation — LEARN phase silently saw empty `~/.claude/.skill-learn-baselines/`. Added `openspec_state_set_hypotheses`, `openspec_state_mark_archived`, and `openspec_state_write_learn_baseline` helpers. Stop hook now writes baselines as a safety net for any shipped change with hypotheses.
- Hypothesis-to-Learning Loop: `product-discovery` skill now auto-calls state helpers to persist `discovery_path` and structured hypotheses (was a composition hint the LLM could skip, breaking the loop at its source).
- `openspec_state_upsert_change` was hard-overwriting `.changes[$slug]`, silently clobbering `discovery_path` when DESIGN ran after DISCOVER. Converted to a merge that preserves prior values when callers pass empty-string args.
- Jira ticket extraction for learn baselines now filters common technical-standard prefixes (HTTP-2, SHA-256, ISO-8601, CVE-…, etc.) via shape + denylist, so the real ticket wins when it appears after technical prose.

### Added
- Spec-Driven Mode: New `spec-driven` preset with `openspec_first: true` flag — redirects DESIGN/PLAN artifact creation to committed `openspec/changes/<feature>/` folders for multi-user repo visibility
- Spec-Driven Mode: session-start-hook Step 6c rewrites DESIGN PERSIST, DESIGN→PLAN CONTRACT, and CARRY SCENARIOS hint text via jq when preset active
- Spec-Driven Mode: openspec-ship idempotent pre-flight check — validates and syncs existing `openspec/changes/<feature>/` instead of overwriting when upfront change exists
- Spec-Driven Mode: `⚠️ NEW CAPABILITY` warning when openspec-ship or design-debate introduces a capability not yet in `openspec/specs/`
- Spec-Driven Mode: design-debate dual-mode output template (spec-driven + solo)
- Spec-Driven Mode: CLAUDE.md "Spec Persistence Modes" documentation section

### Added
- Hypothesis-to-Learning Loop: Durable hypothesis artifact from DISCOVER through SHIP to LEARN — structured fields (Metric, Baseline, Target, Window) in product-discovery brief, persisted via session state, extracted by openspec-ship, denormalized into learn-baseline JSON, consumed by outcome-review with per-hypothesis validation table
- Hypothesis-to-Learning Loop: `openspec_state_set_discovery_path` helper for targeted discovery_path merge in session state
- Hypothesis-to-Learning Loop: PERSIST DISCOVERY composition hint in DISCOVER phase (matching existing DESIGN pattern)
- Hypothesis-to-Learning Loop: `write-learn-baseline` SHIP composition step — conditional on ship event detection from git state
- Hypothesis-to-Learning Loop: `discovery_path` field in OpenSpec provenance output
- Adversarial Review Lens: Always-on 6-point governance checklist in REVIEW composition — HITL bypass, scope expansion, safety gate weakening, bypass patterns, hook/config changes
- Adversarial Review Lens: `adversarial-reviewer` 4th specialist in agent-team-review with governance lens
- Adversarial Review Lens: 4 adversarial routing scenario fixtures + 10 governance constraint regression assertions

### Changed
- Incident-analysis: Refactored SKILL.md from 12,806 to 11,408 words (~11% reduction) — extracted error taxonomy and deep-dive branches to reference files, compressed behavioral constraints, added stage-transition flowchart
- Incident-analysis: Lowered word count guard from 13,000 to 11,500 with 18 new tests (behavioral navigation-chain verification)

### Added
- SDLC Coverage: 39 routing interaction regression tests across 5 collision groups (code-review, parallel/worktree, debug/incident, cross-phase, negatives)
- SDLC Coverage: `design_path` session state field for tracking design artifacts through the SDLC pipeline
- SDLC Coverage: Intent Truth 5-tier retrieval precedence (OpenSpec active > docs/plans/ live > canonical specs > archived > legacy)
- SDLC Coverage: `docs/plans/archive/` intent archival step in openspec-ship (Step 7b)

### Changed
- Session state: canonical `plan_path`/`spec_path` fields with backward-compatible `sp_plan_path`/`sp_spec_path` legacy aliases
- Intent Truth: `docs/plans/` now takes precedence over `openspec/specs/` for live design intent
- openspec-ship: updated path references from `docs/superpowers/plans/` to canonical `docs/plans/`
- agent-team-review: context gathering now includes acceptance spec and legacy fallback paths
- Activation hook: plan-path warning updated to `docs/plans/`

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
