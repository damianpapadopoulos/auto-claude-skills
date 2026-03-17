# README Repositioning Design

## Summary

Rewrite README.md as an end-user-first product page for a Claude Code CLI plugin. Primary audience: GitHub/marketplace visitor evaluating whether to install.

Approach A (product page decision funnel) with Approach C elements (SDLC phase table in "What It Does").

## Structure

10 sections, ordered as a decision funnel — each answers the next question a visitor has:

1. **Intro** (no heading) — title + positioning line + value paragraph
2. **What It Does** — 4 bullets: prompt routing, phase table, guardrails, optional enrichment
3. **Example Prompts** — 3 prompt→phase→behavior examples
4. **How It Works** — 4-step numbered prose covering the plugin's lifecycle hooks
5. **Install** — minimal vs full, prerequisites folded in (no standalone Prerequisites section)
6. **Optional Integrations** — grouped by category (core, MCP, phase enhancers, Atlassian)
7. **Configuration** — one JSON example, trigger syntax
8. **Diagnostics** — `/skill-explain` example, env vars
9. **What It Is Not** — boundary-setting (not autocomplete, not ticketing, not deployment)
10. **Uninstalling** — one-liner

## Section Details

### 1. Intro

No "What It Is" heading — redundant on a README. Two paragraphs:

- First line positions: "A Claude Code plugin that routes skills, workflow guardrails, and optional tool integrations based on prompt intent and SDLC phase."
- Second line sells: "Instead of remembering which skill to invoke for each task, the plugin classifies your prompt, maps it to the current development phase, and injects the right skills, review flows, and companion-tool hints."

### 2. What It Does

Four bullets in user language. Before the phase table, include a brief scope line: "The plugin bundles a small set of skills and routes to many more from companion plugins — covering brainstorming, TDD, debugging, code review, planning, frontend design, security scanning, and more." This replaces the current README's exact counts (which go stale) with a flavor of breadth.

- **Prompt routing by intent.** Scoring against trigger patterns. Prompts that match nothing produce no output — no noise on non-development work. (Present this as a distinct, prominent statement, not buried in a sub-clause.)
- **Phase-aware SDLC guidance.** Table with 6 rows (DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG) describing what the plugin does at each phase. This is the Approach C element.
- **Guardrails through hooks, not memory.** Phase composition enforces TDD-before-implementation, evidence-before-completion. Computed fresh every prompt.
- **Optional enrichment from companion tools.** Routing engine injects phase-appropriate context when integrations are present.

Phase table contents (verified against code):

| Phase | Description |
|-------|-------------|
| DESIGN | Activates brainstorming, explores requirements before coding |
| PLAN | Structures implementation into discrete tasks with dependency ordering |
| IMPLEMENT | Enforces TDD, routes to parallel agents for independent work |
| REVIEW | Triggers multi-perspective code review, processes feedback with rigor |
| SHIP | Requires verification evidence, generates as-built docs, guides branch completion |
| DEBUG | Scores highest priority, overrides the current phase with structured root-cause analysis |

### 3. Example Prompts

Three examples, no raw hook output:

- "design a secure frontend component" → DESIGN. Brainstorming + frontend-design + security-scanner. Companion tools query library docs for API constraints. (Use user-facing language — no "context stack" internal concept.)
- "debug this login bug" → DEBUG. Systematic-debugging + mandatory TDD parallel. GCP Observability hint if installed.
- "ship this feature" → SHIP. Activates a sequence starting with verification-before-completion, then openspec-ship for as-built docs, through to finishing-a-development-branch for merge/PR/cleanup. (Do not claim an exact step count — the full sequence includes additional steps like memory consolidation and commit workflows.)

### 4. How It Works

Four numbered steps covering the plugin's lifecycle hooks. (These simplify seven hooks.json event groups into four conceptual steps — do not claim a 1:1 mapping.)

1. SessionStart → registry build (defaults + plugin discovery + user overrides) + compaction recovery for interrupted sessions
2. UserPromptSubmit → scoring + role-cap selection (1 process, 2 domain, 1 workflow)
3. Phase composition → mandatory requirements per phase (TDD, red-flag halts, sequencing)
4. Guard hooks → including OpenSpec compliance checks (PreToolUse), Serena nudges for code navigation (PreToolUse), context preservation before compaction (PreCompact), agent checkpoint tracking (PostToolUse), teammate idle detection (TeammateIdle), and learning consolidation at session end (Stop). Use "including" to signal this is not exhaustive.

### 5. Install

Prerequisites (Claude Code CLI + jq) are folded into this section — no standalone Prerequisites heading. The current README's separate "Prerequisites" section is merged here.

- Minimal: marketplace add + plugin install (2 commands)
- Full: `/setup`
- Session start example output
- Graceful degradation sentence: works without every integration, richer with more

### 6. Optional Integrations

Four categories (no counts):
- Core workflow plugins
- MCP and context sources
- Phase enhancers
- Atlassian managed integration (via `/mcp`, not `/setup`)

### 7. Configuration

Unchanged from current README. One JSON example with overrides and custom_skills. Trigger syntax line.

### 8. Diagnostics

Unchanged from current README. `/skill-explain` example + SKILL_EXPLAIN/SKILL_VERBOSE env vars.

### 9. What It Is Not

Three "not X" bullets + one summary sentence:
- Not IDE autocomplete
- Not a ticketing/backlog system
- Not a deployment/observability platform
- "It orchestrates Claude Code's in-session workflow and points to external tools where relevant."

### 10. Uninstalling

Single command, unchanged.

## Verification Notes

Claims verified against codebase:

- **Dropped:** "Claude assesses from context" fallthrough claim — zero matches = silent exit, not assessment.
- **Tightened:** PLAN phase says "dependency ordering" not "review gates" (gates are in skill graph, not composition).
- **Tightened:** DEBUG says "scores highest priority, overrides" not "interrupts" (mechanism is scoring dominance, not hard interrupt).
- **Confirmed:** TDD enforcement is real — injected as mandatory parallel with `"when": "always"` in IMPLEMENT composition.
- **Confirmed:** Guardrails are hook-computed, not memory-based — RED FLAGS built fresh every prompt.
- **Confirmed:** Phase-appropriate hints are real — composition-driven, conditional on plugin availability.

## What Changes

- README.md: full rewrite
- No other files change
- No code, interfaces, or types change

## What Does Not Change

- CLAUDE.md (maintainer/architecture reference stays as-is)
- hooks/, config/, skills/, commands/ (no code changes)
- Existing contributor documentation
