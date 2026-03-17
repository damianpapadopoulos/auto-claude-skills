# README Repositioning Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite README.md as an end-user-first product page that helps GitHub/marketplace visitors decide whether to install.

**Architecture:** Single-file rewrite following the approved spec at `docs/superpowers/specs/2026-03-17-readme-repositioning-design.md`. 10 sections ordered as a decision funnel. All claims verified against codebase.

**Tech Stack:** Markdown only. No code changes.

---

### Task 1: Write the new README

**Files:**
- Modify: `README.md` (full rewrite)
- Reference: `docs/superpowers/specs/2026-03-17-readme-repositioning-design.md` (design spec)
- Reference: `hooks/hooks.json` (verify hook claims)
- Reference: `config/default-triggers.json` (verify phase/trigger claims)
- Reference: `commands/setup.md` (verify install claims)

- [ ] **Step 1: Read the design spec and current README**

Read `docs/superpowers/specs/2026-03-17-readme-repositioning-design.md` for the approved structure and section details.
Read `README.md` for content to preserve (Configuration JSON example, Diagnostics table, install commands, uninstall command).

- [ ] **Step 2: Write sections 1-2 (Intro + What It Does)**

Section 1 — No heading. Two paragraphs:
- Positioning line: "A Claude Code plugin that routes skills, workflow guardrails, and optional tool integrations based on prompt intent and SDLC phase."
- Value line: "Instead of remembering which skill to invoke..."

Section 2 — `## What It Does`. Four bullets:
- Prompt routing by intent. Make the zero-match silent-exit case a prominent, distinct sentence.
- Phase-aware SDLC guidance with 6-row table (DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG). Include scope line before the table: "The plugin bundles a small set of skills and routes to many more from companion plugins — covering brainstorming, TDD, debugging, code review, planning, frontend design, security scanning, and more."
- Guardrails through hooks, not memory.
- Optional enrichment from companion tools.

Phase table contents (verified — copy exactly):

| Phase | What the plugin does |
|-------|---------------------|
| DESIGN | Activates brainstorming, explores requirements before coding |
| PLAN | Structures implementation into discrete tasks with dependency ordering |
| IMPLEMENT | Enforces TDD, routes to parallel agents for independent work |
| REVIEW | Triggers multi-perspective code review, processes feedback with rigor |
| SHIP | Requires verification evidence, generates as-built docs, guides branch completion |
| DEBUG | Scores highest priority, overrides the current phase with structured root-cause analysis |

- [ ] **Step 3: Write section 3 (Example Prompts)**

`## Example Prompts`. Three examples:

1. "design a secure frontend component" → DESIGN phase. Activates brainstorming + frontend-design + security-scanner. Companion tools query library docs for API constraints. (No "context stack" — user-facing language only.)
2. "debug this login bug" → DEBUG phase. Activates systematic-debugging. TDD injected as mandatory parallel — reproduce with a failing test before fixing. If GCP Observability is installed, context hints toward runtime logs.
3. "ship this feature" → SHIP phase. Activates a sequence starting with verification-before-completion, then openspec-ship for as-built docs, through to finishing-a-development-branch for merge/PR/cleanup options. (No exact step count.)

- [ ] **Step 4: Write section 4 (How It Works)**

`## How It Works`. Four numbered steps covering the plugin's lifecycle hooks (not claiming 1:1 mapping to hooks.json event groups):

1. **SessionStart** builds a cached skill registry by merging default triggers, skills discovered from installed plugins, and any user overrides from `~/.claude/skill-config.json`. Also recovers state from interrupted sessions after compaction.
2. **UserPromptSubmit** scores the prompt against trigger patterns — word-boundary matches score higher than substrings, and skill priority, name similarity, and keyword hits all contribute. The engine selects at most 1 process skill, 2 domain skills, and 1 workflow skill.
3. **Phase composition** layers in requirements appropriate to the detected phase: mandatory TDD during implementation, red-flag halts for unverified completion claims, multi-step sequencing during ship.
4. **Guard hooks** run on other lifecycle events — including OpenSpec compliance checks before commands, Serena nudges when Grep could use symbol navigation, context preservation before compaction, agent checkpoint tracking, teammate idle detection, and learning consolidation at session end.

- [ ] **Step 5: Write sections 5-6 (Install + Optional Integrations)**

Section 5 — `## Install`. Prerequisites folded in (no standalone heading):
- Prerequisites: Claude Code CLI + jq (with install commands)
- Minimal install: 2 commands (marketplace add + plugin install)
- Full experience: `/setup`
- Session start example output
- Graceful degradation sentence

Section 6 — `## Optional Integrations`. Intro line + four category paragraphs:
- Core workflow plugins (superpowers, frontend-design, claude-md-management, claude-code-setup, pr-review-toolkit)
- MCP and context sources (Context7, GitHub, Serena, Forgetful Memory, Context Hub CLI)
- Phase enhancers (commit-commands, security-guidance, feature-dev, hookify, skill-creator)
- Atlassian managed integration (via `/mcp`, not `/setup`)

- [ ] **Step 6: Write sections 7-10 (Configuration + Diagnostics + What It Is Not + Uninstalling)**

Section 7 — `## Configuration`. Preserve existing JSON example and trigger syntax line from current README verbatim.

Section 8 — `## Diagnostics`. Preserve existing `/skill-explain` example and env var table from current README verbatim.

Section 9 — `## What It Is Not`. Three bullets + summary:
- Not IDE autocomplete
- Not a ticketing/backlog system
- Not a deployment/observability platform
- Summary: "It orchestrates Claude Code's in-session workflow and points to external tools where relevant."

Section 10 — `## Uninstalling`. Single command, preserved from current README.

- [ ] **Step 7: Final verification pass**

Read the written README end-to-end and verify:
1. Every claim matches the design spec's Verification Notes
2. No internal concepts leak (no "context stack", no "US field separator", no file paths)
3. No brittle counts that will go stale
4. Configuration JSON example matches current README exactly
5. Install commands match current README exactly
6. A new reader can answer in order: what it is, why it helps, how it works, how to install, what's optional, how to debug routing, where its boundaries are

- [ ] **Step 8: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README as end-user product page"
```
