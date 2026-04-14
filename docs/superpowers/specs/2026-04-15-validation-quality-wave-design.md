# Validation Quality Wave — Design Spec

**Date:** 2026-04-15
**Status:** Approved
**Scope:** auto-claude-skills plugin — terminal-native validation layer

## Summary

Add a validation layer that closes the gap between "tests pass" and "the feature works as intended in a realistic context," preserving the superpowers-owned workflow backbone.

Three new repo-owned capabilities:

| Capability | Type | Phase | Purpose |
|---|---|---|---|
| `runtime-validation` | Domain skill | REVIEW (primary), SHIP (fallback) | Prove the feature works in a realistic context |
| `implementation-drift-check` | Domain skill | REVIEW + SHIP (auto), IMPLEMENT (explicit) | Detect spec drift, surface assumptions, identify coverage gaps |
| Behavioral eval packs | Artifact layer | Cross-phase reference | Committed example-based behavioral truth |

No CI/CD control. No Computer Use. No superpowers driver changes.

---

## 1. runtime-validation Skill

### 1.1 Identity

```yaml
name: runtime-validation
role: domain
phase: REVIEW
triggers:
  - (validate|validation|e2e|end.to.end|smoke.test|a11y|accessibility|exercise|try.it|does.it.work|interactive.test)
trigger_mode: regex
priority: 15
precedes: []
requires: []
description: >-
  Realistic-context validation: browser E2E, API smoke, CLI checks,
  a11y audits with unified report.
invoke: Skill(auto-claude-skills:runtime-validation)
```

### 1.2 Detection (Step 1)

Run capability detection via Bash to determine project type and available tools:

**Browser path:**
- `command -v npx && npx playwright --version` (preferred)
- Check `package.json` for `cypress` dependency (fallback)
- `command -v axe` or check `@axe-core/cli` in dependencies (a11y overlay)
- Check session-start capability flags for `webapp-testing` companion plugin

**API/Server path:**
- Probe common dev server ports (3000, 5173, 8000, 8080) via `curl -s -o /dev/null -w "%{http_code}" http://localhost:{port}/`
- Check for OpenAPI spec files (`openapi.yaml`, `openapi.json`, `swagger.json`, `swagger.yaml`)

**CLI/Tool path:**
- Check for built binary in `./dist`, `./build`, `./target`, `./bin`
- Check `package.json` `bin` field
- Check `Makefile` targets (`make --dry-run` for common targets)

### 1.3 Scenario Derivation (Step 2)

Three-tier scenario sourcing (highest fidelity first):

1. **Eval packs exist** (`tests/fixtures/evals/*.json`): Read applicable scenarios, filter by `path` field (browser/api/cli)
2. **Intent Truth exists** (OpenSpec specs, plan acceptance criteria): Derive scenarios from spec acceptance scenarios and plan task descriptions
3. **Neither available:** Generate generic smoke checks per detected path:
   - Browser: homepage loads, no console errors, basic a11y pass
   - API: health endpoint returns 200, documented endpoints respond
   - CLI: `--help` exits 0, basic command produces expected output shape

### 1.4 Execution (Step 3)

**Browser path** (when Playwright/Cypress detected):
- If `webapp-testing` companion available: delegate via `Skill(webapp-testing)` with derived scenarios
- If Playwright available directly: run `npx playwright test` on existing test files, or generate and run ad-hoc test scripts for derived scenarios
- If axe-core available: run Playwright axe integration or `npx axe` for a11y baseline (AA contrast, ARIA landmarks, keyboard navigation)
- Capture screenshots to `tests/artifacts/validation/` (gitignored)

**API/Server path** (when dev server detected):
- Health probes: `curl -sf http://localhost:{port}/health`
- Endpoint smoke: For each derived scenario, execute `curl` with expected status code and response shape validation via jq
- If OpenAPI spec available: validate response bodies against schema

**CLI/Tool path** (when binary detected):
- `--help` smoke: verify exit code 0 and non-empty output
- For each derived scenario: run command with test inputs, verify exit code and output patterns
- If fixture files referenced in eval packs: use them as inputs

**Graceful degradation** (per path, independently):

| Condition | Behavior |
|---|---|
| Tool + specs/evals | Derive and run scenarios |
| Tool + no specs | Run generic smoke checks |
| No tool detected | Emit manual validation checklist with specific steps |
| Nothing at all | Skip with note: "no interactive validation tools detected" |

### 1.5 Unified Report (Step 4)

Always terminal-first. Same shape regardless of which paths executed:

```markdown
## Validation Report

### Browser (Playwright) — N scenarios
| Scenario | Source | Result | Evidence |
|----------|--------|--------|----------|

### API (curl @ localhost:PORT) — N scenarios
| Endpoint | Source | Result | Evidence |
|----------|--------|--------|----------|

### CLI (./path/to/binary) — N scenarios
| Command | Source | Result | Evidence |
|---------|--------|--------|----------|

### A11y (axe-core) — N checks
| Check | Severity | Element | Issue |
|-------|----------|---------|-------|

### Coverage Gaps
- [scenarios that couldn't be validated and why]

### Manual Checks Recommended
- [checks requiring human judgment]
```

### 1.6 Fix-Rescan Loop (Step 5, optional)

If browser/a11y failures found during REVIEW: present findings, fix, re-run specific failing scenarios. **Max 3 iterations** (same pattern as `security-scanner`).

### 1.7 Persistence

- Screenshots and binary artifacts → `tests/artifacts/validation/` (gitignored)
- Text report → terminal only; persist to file on explicit user request
- Session marker → `~/.claude/.skill-validation-ran-${TOKEN}` (for SHIP fallback suppression)

---

## 2. implementation-drift-check Skill

### 2.1 Identity

```yaml
name: implementation-drift-check
role: domain
phase: REVIEW
triggers:
  - (drift|reflect|assumption|gap|deviat|on.track|off.track|spec.check|still.on.plan)
trigger_mode: regex
priority: 12
precedes: []
requires: []
description: >-
  Spec drift detection, assumption surfacing, and coverage gap
  identification against Intent Truth.
invoke: Skill(auto-claude-skills:implementation-drift-check)
```

### 2.2 Auto-Co-Selection Guard

Only auto-fires in REVIEW/SHIP when at least one comparison source exists:
- Intent Truth: `openspec/changes/<feature>/` or `openspec/specs/<capability>/spec.md` or `docs/superpowers/specs/*-design.md`
- Plan: `docs/superpowers/plans/*.md` with task list
- Active composition chain with code changes (`git diff` non-empty)

If none exist → does not auto-fire. Can still be explicitly invoked (e.g., "check drift", "am I still on plan") but degrades to assumptions-only mode.

This guard is LLM-evaluated (documented in the SKILL.md instructions), not hook-enforced. The LLM reliably follows these conditions.

### 2.3 Gather Comparison Material (Step 1)

Read in priority order:
1. OpenSpec delta specs (`openspec/changes/<feature>/specs/`)
2. Canonical specs (`openspec/specs/<capability>/spec.md`)
3. Design spec (`docs/superpowers/specs/*-design.md`)
4. Plan task list (`docs/superpowers/plans/*.md`)
5. Eval pack scenarios (`tests/fixtures/evals/*.json`)

### 2.4 Analyze Drift — Full Mode (Step 2)

When comparison material exists, cross-reference `git diff` against gathered material:

**Spec drift:** For each requirement/acceptance scenario in specs, check whether the implementation addresses it.
- Flags: implemented-as-specified, implemented-differently (with evidence), not-implemented, added-without-spec

**Plan drift:** For each plan task, check whether the git diff includes changes to the expected files.
- Flags: completed-as-planned, files-differ, scope-expanded, scope-reduced

**Review-induced drift:** If code review findings were addressed, check whether fixes changed the behavioral contract (not just code quality).
- Flag any scope changes introduced by review feedback

### 2.5 Surface Assumptions and Gaps (Step 3 — always runs)

Runs in both full mode and degraded mode:

- **Assumptions made:** What does the implementation assume about inputs, environment, dependencies, or user behavior that isn't validated by tests?
- **Untested paths:** What code paths in the diff have no test exercise? Cross-reference test files against implementation files.
- **Edge cases identified:** What boundary conditions does the implementation handle that aren't explicitly specified?
- **Eval pack gaps:** If eval packs exist, which scenarios don't have corresponding test coverage?

### 2.6 Report

Terminal-first. Two report shapes depending on mode:

**Full drift mode:**
```markdown
## Implementation Drift Check

### Spec Alignment
| Requirement | Status | Evidence |
|-------------|--------|----------|

### Plan Alignment
| Task | Status | Notes |
|------|--------|-------|

### Review-Induced Changes
- [behavioral contract changes from review feedback]

### Assumptions
- [unvalidated assumptions]

### Untested Paths
- [code paths without test coverage]

### Recommended Actions
- [ ] [actionable items]
```

**Assumptions-only mode** (no comparison material):
```markdown
## Implementation Assumptions & Gaps

### Assumptions
- [unvalidated assumptions]

### Untested Paths
- [code paths without test coverage]

### Recommended Actions
- [ ] [actionable items]
```

### 2.7 Persistence

- Terminal output: always
- When drift or unresolved assumptions found: append concise "Post-Implementation Notes" section to the relevant spec/design document
- Session marker → `~/.claude/.skill-drift-check-ran-${TOKEN}` (for SHIP fallback suppression)

---

## 3. Behavioral Eval Packs

### 3.1 Location

Committed fixtures: `tests/fixtures/evals/*.json`
Generated artifacts: `tests/artifacts/validation/` (gitignored — added to `.gitignore`)

### 3.2 Schema

```json
{
  "id": "auth-login-flow",
  "capability": "auth",
  "source": {
    "spec": "openspec/specs/auth/spec.md",
    "plan": "docs/superpowers/plans/2026-04-10-auth-redesign.md",
    "prototype": null
  },
  "scenarios": [
    {
      "name": "valid-login",
      "description": "User with valid credentials can log in",
      "path": "browser",
      "inputs": {"email": "test@example.com", "password": "valid"},
      "expected": {"result": "redirect", "target": "/dashboard", "status": 302},
      "tags": ["happy-path", "auth"]
    },
    {
      "name": "invalid-password-lockout",
      "description": "5 failed attempts triggers account lockout",
      "path": "api",
      "inputs": {"endpoint": "POST /api/auth/login", "repeat": 5},
      "expected": {"status": 429, "body_contains": "locked"},
      "tags": ["edge-case", "security"]
    }
  ]
}
```

**Required fields:** `id`, `capability`, `scenarios`
**Required per scenario:** `name`, `path` (one of `browser`, `api`, `cli`), `expected`
**Optional:** `source`, `inputs`, `description`, `tags`

### 3.3 Authoring

**This wave: manual only.** Schema + consumption + validation tests + example fixtures for dog-fooding.

**Future wave (deferred):** Auto-scaffolding from specs during PLAN, drift detection when specs change but eval packs don't.

### 3.4 Consumption

- `runtime-validation` reads eval packs as scenario input (highest-fidelity tier)
- `implementation-drift-check` references eval packs when surfacing untested behavior or validation gaps
- Both filter by `path` field to match detected execution paths

---

## 4. Phase Composition Changes

### 4.1 REVIEW Phase

Add two new parallel entries to `phase_compositions.REVIEW.parallel` in `config/default-triggers.json` (after existing security-scanner entry at line ~1183):

```json
{
  "use": "runtime-validation -> Skill(auto-claude-skills:runtime-validation)",
  "when": "validation tools detected (Playwright, dev server, or CLI binary)",
  "purpose": "Realistic-context validation: derive scenarios from specs/evals, execute browser/API/CLI paths, report with evidence"
},
{
  "use": "implementation-drift-check -> Skill(auto-claude-skills:implementation-drift-check)",
  "when": "comparison material exists (specs, plans, or active chain with code changes)",
  "purpose": "Spec drift detection, assumption surfacing, coverage gap identification"
}
```

No existing entries change.

### 4.2 SHIP Phase

Add two conditional fallback entries to `phase_compositions.SHIP.sequence`, after `verification-before-completion` and before `openspec-ship`:

```json
{
  "step": "runtime-validation",
  "purpose": "FALLBACK: Run realistic-context validation only if not already run in REVIEW",
  "gate": "session-marker",
  "marker": "validation-ran"
},
{
  "step": "implementation-drift-check",
  "purpose": "FALLBACK: Run drift check only if not already run in REVIEW",
  "gate": "session-marker",
  "marker": "drift-check-ran"
}
```

### 4.3 Session-Marker Gate Mechanism

**New hook predicate** added to `skill-activation-hook.sh` (line ~1182) in the jq composition block:

When processing phase composition entries, if a `gate` field is present with value `"session-marker"`, check:
```bash
[[ -f "${HOME}/.claude/.skill-${marker}-${TOKEN}" ]]
```
If file exists → suppress the entry. If not → emit normally.

**Implementation scope:** The session-marker gate cannot be evaluated inside the existing jq composition block (jq has no filesystem access). Instead, add a post-jq Bash filter: after the jq block emits composition lines (line ~1208), iterate emitted SEQUENCE lines and suppress any whose `marker` value corresponds to an existing session-marker file. This requires the hook to pass marker metadata through the jq output (e.g., `GATED:marker_name:original_line`) and filter in the existing `while IFS= read -r _cline` loop (line ~1211). Approximately 15 lines of Bash added to the existing loop. No new jq logic. No arbitrary expression evaluation. No new external dependencies.

**Marker lifecycle:**
- Written by the skill SKILL.md instruction: "After completing, write marker via Bash"
- Scoped to session token (no cross-session leakage)
- Cleaned up at session end (existing cleanup in session-start-hook.sh)

### 4.4 SHIP Sequence After Changes

1. `verification-before-completion` — proof gate (unchanged)
2. `runtime-validation` — fallback if not run in REVIEW (NEW, gated)
3. `implementation-drift-check` — fallback if not run in REVIEW (NEW, gated)
4. `openspec-ship` — as-built docs (unchanged)
5. Memory consolidation (unchanged)
6. `commit-commands` (unchanged)
7. `finishing-a-development-branch` (unchanged)

---

## 5. Routing & Registry Changes

### 5.1 New Skills Array Entries

Add to `config/default-triggers.json` skills array and `config/fallback-registry.json`:

- `runtime-validation` — as specified in section 1.1
- `implementation-drift-check` — as specified in section 2.1

### 5.2 Methodology Hint Updates

Update existing hints in `config/default-triggers.json`:

- `playwright-mcp` hint: reference `runtime-validation` as the REVIEW orchestration entry point
- `frontend-playwright` hint: reference `runtime-validation` for E2E coverage during REVIEW

### 5.3 Webapp-testing Interop

`webapp-testing` (external plugin, IMPLEMENT phase, priority 12) remains unchanged. `runtime-validation` composes with it when available (checks session-start capability flags), delegates browser-path execution to it, but does not depend on it.

---

## 6. File Manifest

### New Files

| Path | Type | Purpose |
|---|---|---|
| `skills/runtime-validation/SKILL.md` | Skill definition | Browser/API/CLI validation orchestrator |
| `skills/implementation-drift-check/SKILL.md` | Skill definition | Spec drift and assumption analysis |
| `tests/test-validation-skill-content.sh` | Test suite | Content-contract tests for both skills |
| `tests/test-eval-pack-schema.sh` | Test suite | Eval pack JSON schema validation |
| `tests/fixtures/evals/routing-validation.json` | Eval pack | Dog-food example: routing behavior scenarios |
| `tests/fixtures/scenarios/validation-13-ui-with-playwright.json` | Scenario eval | UI change → runtime-validation surfaces |
| `tests/fixtures/scenarios/validation-14-api-smoke.json` | Scenario eval | API change → runtime-validation surfaces |
| `tests/fixtures/scenarios/validation-15-cli-smoke.json` | Scenario eval | CLI change → runtime-validation surfaces |
| `tests/fixtures/scenarios/drift-16-review-with-spec.json` | Scenario eval | REVIEW with spec → drift-check surfaces |
| `tests/fixtures/scenarios/drift-17-no-spec-no-fire.json` | Scenario eval | No comparison material → drift-check silent |
| `tests/fixtures/scenarios/fallback-18-ship-after-review-skip.json` | Scenario eval | SHIP without prior REVIEW → both sidecars fire |

### Modified Files

| Path | Change |
|---|---|
| `config/default-triggers.json` | Add 2 skill entries, 2 REVIEW parallel entries, 2 SHIP sequence entries with gate, update 2 hints |
| `config/fallback-registry.json` | Add 2 skill entries matching default-triggers |
| `hooks/skill-activation-hook.sh` | Add session-marker gate predicate (~10 lines in jq composition block) |
| `.gitignore` | Add `tests/artifacts/` |
| `tests/run-tests.sh` | Include new test suites |

---

## 7. Test Plan

### Routing Tests (in `tests/test-routing.sh`)
- `runtime-validation` surfaces on "validate the feature" during REVIEW
- `runtime-validation` does not fire on "fix this bug" (DEBUG phase)
- `implementation-drift-check` surfaces on "check drift" during IMPLEMENT (explicit)
- `implementation-drift-check` surfaces in REVIEW when composition chain is active
- Neither skill displaces existing process drivers

### Composition Tests (in `tests/test-context.sh`)
- REVIEW parallel includes both new sidecars
- SHIP sequence includes gated fallback entries
- No superpowers driver displacement

### Content-Contract Tests (new `tests/test-validation-skill-content.sh`)
- `runtime-validation` SKILL.md documents all 3 execution paths and graceful degradation
- `implementation-drift-check` SKILL.md documents full-mode and assumptions-only mode
- Both skills document their report contracts

### Eval Pack Schema Tests (new `tests/test-eval-pack-schema.sh`)
- Each file in `tests/fixtures/evals/` is valid JSON
- Required fields: `id`, `capability`, `scenarios`
- Each scenario has: `name`, `path`, `expected`
- `path` values constrained to: `browser`, `api`, `cli`

### Scenario Evals (new fixtures in `tests/fixtures/scenarios/`)
- `validation-13-ui-with-playwright.json` — UI change with Playwright → runtime-validation
- `validation-14-api-smoke.json` — API endpoint change → runtime-validation
- `validation-15-cli-smoke.json` — CLI tool change → runtime-validation
- `drift-16-review-with-spec.json` — REVIEW with spec context → drift-check
- `drift-17-no-spec-no-fire.json` — No comparison material → drift-check silent
- `fallback-18-ship-after-review-skip.json` — SHIP without prior REVIEW → both sidecars fire

### Regression Guards
- All existing scenario evals continue to pass
- No superpowers driver displacement
- No CI/CD behavior introduced
- No Computer Use dependency
- Existing security-scanner, pr-review-toolkit, unified-context-stack routing unchanged

---

## 8. Constraints & Assumptions

- Superpowers continues to own all process drivers. This wave adds domain sidecars only.
- `runtime-validation` is orchestration-only — composes with tools, not a testing framework.
- Playwright is preferred browser path; Cypress is fallback. `webapp-testing` is optional companion, not hard dependency.
- Reports are terminal-first. Committed eval goldens (`tests/fixtures/evals/`) and generated artifacts (`tests/artifacts/validation/`, gitignored) are strictly separated.
- Eval pack authoring is manual in this wave. Schema + consumption + validation only.
- The session-marker gate is the only new hook predicate. No arbitrary expression evaluation.
- Bash 3.2 compatibility for all hook changes. SKILL.md files have no Bash constraint.
- Deployment automation, headless agents, Figma MCP, Computer Use, and temporal knowledge graphs are out of scope.
- Outcome-to-rediscovery loop closure is deferred to a future wave.
