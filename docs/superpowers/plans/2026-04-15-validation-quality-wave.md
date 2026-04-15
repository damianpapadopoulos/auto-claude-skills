# Validation Quality Wave — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add runtime-validation, implementation-drift-check, and behavioral eval packs to close the gap between "tests pass" and "feature works in realistic context."

**Spec:** `docs/superpowers/specs/2026-04-15-validation-quality-wave-design.md`

**Architecture:** Two new REVIEW-phase domain skills (runtime-validation and implementation-drift-check) with SHIP fallback, backed by committed eval pack fixtures. Two new hook gate types (session-marker and artifact-presence) enable mechanical suppression of composition entries.

**Tech Stack:** Bash 3.2 (hooks), Markdown (SKILL.md), JSON (config/fixtures), jq (registry)

---

### Task 1: Scaffold eval pack infrastructure

**Files:**
- Create: `tests/fixtures/evals/routing-validation.json`
- Create: `tests/test-eval-pack-schema.sh`
- Modify: `.gitignore` (add `tests/artifacts/`)

- [ ] **Step 1: Create the gitignore entry for generated artifacts**

Add `tests/artifacts/` to `.gitignore`:

```
tests/artifacts/
```

Append after the last existing line in `.gitignore`.

- [ ] **Step 2: Create the dog-food eval pack fixture**

Create `tests/fixtures/evals/routing-validation.json`:

```json
{
  "id": "routing-skill-activation",
  "capability": "skill-routing",
  "source": {
    "spec": null,
    "plan": null,
    "prototype": null
  },
  "scenarios": [
    {
      "name": "hook-activates-on-prompt",
      "description": "Skill activation hook produces valid JSON with additionalContext",
      "path": "cli",
      "inputs": {"prompt": "validate the login feature"},
      "expected": {"exit_code": 0, "output_contains": "hookSpecificOutput"},
      "tags": ["smoke", "routing"]
    },
    {
      "name": "review-phase-surfaces-security-scanner",
      "description": "REVIEW phase prompts co-select security-scanner",
      "path": "cli",
      "inputs": {"prompt": "review my code changes"},
      "expected": {"output_contains": "security-scanner"},
      "tags": ["routing", "review"]
    }
  ]
}
```

- [ ] **Step 3: Write the eval pack schema validation test**

Create `tests/test-eval-pack-schema.sh`:

```bash
#!/usr/bin/env bash
# test-eval-pack-schema.sh — Validate eval pack JSON schema
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EVALS_DIR="${PROJECT_ROOT}/tests/fixtures/evals"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-eval-pack-schema.sh ==="

setup_test_env

# ---------------------------------------------------------------------------
# Check that evals directory has at least one file
# ---------------------------------------------------------------------------
# At least one eval pack must exist (Task 1 creates the dog-food fixture)
assert_file_exists "dog-food eval pack exists" "${EVALS_DIR}/routing-validation.json"

# ---------------------------------------------------------------------------
# Validate each eval pack
# ---------------------------------------------------------------------------
for eval_file in "${EVALS_DIR}"/*.json; do
    [ -f "$eval_file" ] || continue
    fname="$(basename "$eval_file")"

    # Valid JSON
    assert_json_valid "${fname}: is valid JSON" "$eval_file"

    # Required top-level fields
    has_id="$(jq -r '.id // empty' "$eval_file")"
    assert_not_empty "${fname}: has 'id' field" "${has_id}"

    has_cap="$(jq -r '.capability // empty' "$eval_file")"
    assert_not_empty "${fname}: has 'capability' field" "${has_cap}"

    scenario_count="$(jq -r '.scenarios | length' "$eval_file")"
    assert_not_empty "${fname}: has at least one scenario" "${scenario_count}"

    # Validate each scenario
    local_i=0
    while [ "$local_i" -lt "$scenario_count" ]; do
        s_name="$(jq -r ".scenarios[${local_i}].name // empty" "$eval_file")"
        assert_not_empty "${fname}[${local_i}]: scenario has 'name'" "${s_name}"

        s_path="$(jq -r ".scenarios[${local_i}].path // empty" "$eval_file")"
        assert_not_empty "${fname}[${local_i}]: scenario has 'path'" "${s_path}"

        # Path must be one of: browser, api, cli
        case "$s_path" in
            browser|api|cli)
                assert_not_empty "${fname}[${local_i}]: path '${s_path}' is valid" "${s_path}" ;;
            *)
                assert_equals "${fname}[${local_i}]: path must be browser|api|cli" "browser|api|cli" "${s_path}" ;;
        esac

        s_expected="$(jq -r ".scenarios[${local_i}].expected // empty" "$eval_file")"
        assert_not_empty "${fname}[${local_i}]: scenario has 'expected'" "${s_expected}"

        local_i=$((local_i + 1))
    done
done

teardown_test_env

echo ""
echo "=== Eval Pack Schema Results ==="
echo "  Total: ${TESTS_RUN}"
echo "  Passed: ${TESTS_PASSED}"
echo "  Failed: ${TESTS_FAILED}"
[ "${TESTS_FAILED}" -eq 0 ] || exit 1
```

- [ ] **Step 4: Run the schema test**

Run: `bash tests/test-eval-pack-schema.sh`
Expected: All assertions pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add .gitignore tests/fixtures/evals/routing-validation.json tests/test-eval-pack-schema.sh
git commit -m "feat: add eval pack schema, dog-food fixture, and validation test"
```

---

### Task 2: Write runtime-validation SKILL.md

**Files:**
- Create: `skills/runtime-validation/SKILL.md`

- [ ] **Step 1: Create the skill directory and SKILL.md**

Create `skills/runtime-validation/SKILL.md` with the full skill definition. The content must include:

**Frontmatter:**
```yaml
---
name: runtime-validation
description: Realistic-context validation orchestrator — browser E2E, API smoke, CLI checks, a11y audits with unified report
---
```

**Body sections (all required):**
1. **When to Use** — REVIEW phase, after code changes are complete. Also invocable on explicit validation requests.
2. **Step 1: Detect Available Tools** — Three detection paths (browser, API, CLI) with exact Bash commands from spec section 1.2. Include webapp-testing companion detection via cached skill registry (`jq -r '.skills[] | select(.name == "webapp-testing" and .available == true) | .name' ~/.claude/.skill-registry-cache.json`).
3. **Step 2: Derive Validation Scenarios** — Three-tier sourcing (eval packs → Intent Truth → generic smoke). Include exact file paths to check.
4. **Step 3: Execute Per-Path** — Browser (webapp-testing delegation, Playwright direct, axe-core overlay), API (curl probes), CLI (binary smoke). Ad-hoc scripts go to `mktemp -d`, never the repo. Screenshots go to `tests/artifacts/validation/`.
5. **Step 4: Unified Report** — Full report contract with all table shapes (Browser, API, CLI, A11y, Coverage Gaps, Manual Checks).
6. **Step 5: Fix-Rescan Loop** — Max 3 iterations, same pattern as security-scanner.
7. **Step 6: Session Marker** — After completing, write marker: `touch ~/.claude/.skill-validation-ran-$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)`

Each step must contain exact Bash commands, not descriptions of what to run. Follow the security-scanner pattern: detect → run → triage → fix → report.

- [ ] **Step 2: Verify the SKILL.md has the required content**

Read back the file and confirm it contains:
- All 3 execution paths (browser, API, CLI)
- All 4 graceful degradation tiers
- The unified report contract tables
- The session marker write command
- The fix-rescan loop with max 3 iterations
- The `mktemp -d` ad-hoc script pattern
- The webapp-testing registry check (not session flags)

- [ ] **Step 3: Commit**

```bash
git add skills/runtime-validation/SKILL.md
git commit -m "feat: add runtime-validation skill definition"
```

---

### Task 3: Write implementation-drift-check SKILL.md

**Files:**
- Create: `skills/implementation-drift-check/SKILL.md`

- [ ] **Step 1: Create the skill directory and SKILL.md**

Create `skills/implementation-drift-check/SKILL.md` with the full skill definition. The content must include:

**Frontmatter:**
```yaml
---
name: implementation-drift-check
description: Spec drift detection, assumption surfacing, and coverage gap identification against Intent Truth
---
```

**Body sections (all required):**
1. **When to Use** — REVIEW + SHIP auto-co-selection (when comparison material exists), explicit IMPLEMENT invocation. Include the exact list of comparison sources from spec section 2.2.
2. **Auto-Co-Selection Guard** — Document that the hook enforces artifact-presence gating mechanically. List the 5 glob patterns. Explain that mode selection (full vs. assumptions-only) is LLM-evaluated.
3. **Step 1: Gather Comparison Material** — Read in priority order (5 sources from spec section 2.3). Include exact file paths and Glob patterns.
4. **Step 2: Analyze Drift (Full Mode)** — Three drift dimensions: spec drift (with 4 flags), plan drift (with 4 flags), review-induced drift. Reference `git diff` cross-referencing.
5. **Step 3: Surface Assumptions and Gaps (Always Runs)** — Assumptions, untested paths, edge cases, eval pack gaps. This step runs in both modes.
6. **Step 4: Report** — Two report shapes: full drift mode (6 sections) and assumptions-only mode (3 sections). Include exact table contracts from spec section 2.6.
7. **Step 5: Persistence** — Terminal always. Append "Post-Implementation Notes" to relevant spec when drift found. Write session marker: `touch ~/.claude/.skill-drift-check-ran-$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)`

- [ ] **Step 2: Verify the SKILL.md has the required content**

Read back and confirm:
- Both report modes (full drift + assumptions-only)
- All 5 comparison material sources
- All 3 drift dimensions with their flag sets
- Session marker write command
- The auto-co-selection guard explanation
- The spec persistence pattern

- [ ] **Step 3: Commit**

```bash
git add skills/implementation-drift-check/SKILL.md
git commit -m "feat: add implementation-drift-check skill definition"
```

---

### Task 4: Register both skills in default-triggers.json

**Files:**
- Modify: `config/default-triggers.json` (skills array, ~line 406)

- [ ] **Step 1: Add runtime-validation skill entry**

Insert after the `security-scanner` entry (after line ~406 in `config/default-triggers.json`):

```json
    {
      "name": "runtime-validation",
      "role": "domain",
      "phase": "REVIEW",
      "triggers": [
        "(validate|validation|e2e|end.to.end|smoke.test|a11y|accessibility|exercise|try.it|does.it.work|interactive.test)"
      ],
      "keywords": [],
      "trigger_mode": "regex",
      "priority": 15,
      "precedes": [],
      "requires": [],
      "description": "Realistic-context validation: browser E2E, API smoke, CLI checks, a11y audits with unified report.",
      "invoke": "Skill(auto-claude-skills:runtime-validation)"
    },
```

- [ ] **Step 2: Add implementation-drift-check skill entry**

Insert immediately after the runtime-validation entry:

```json
    {
      "name": "implementation-drift-check",
      "role": "domain",
      "phase": "REVIEW",
      "triggers": [
        "(drift|reflect|assumption|gap|deviat|on.track|off.track|spec.check|still.on.plan)"
      ],
      "keywords": [],
      "trigger_mode": "regex",
      "priority": 12,
      "precedes": [],
      "requires": [],
      "description": "Spec drift detection, assumption surfacing, and coverage gap identification against Intent Truth.",
      "invoke": "Skill(auto-claude-skills:implementation-drift-check)"
    },
```

- [ ] **Step 3: Verify JSON is valid**

Run: `jq empty config/default-triggers.json && echo "valid" || echo "BROKEN"`
Expected: `valid`

- [ ] **Step 4: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: register runtime-validation and implementation-drift-check in default-triggers"
```

---

### Task 5: Register both skills, compositions, and hints in fallback-registry.json

**Files:**
- Modify: `config/fallback-registry.json` (skills array, phase_compositions, methodology_hints)

The fallback registry must stay in sync with default-triggers.json. The scenario eval suite (`tests/test-scenario-evals.sh`) installs from `fallback-registry.json`, so the new compositions and hints must be present here too.

- [ ] **Step 1: Add both skill entries to fallback registry**

Insert after the `security-scanner` entry in `config/fallback-registry.json` (skills array, after line ~456). Use the same field values as default-triggers.json, plus add `"available": true, "enabled": true` fields:

```json
    {
      "name": "runtime-validation",
      "role": "domain",
      "phase": "REVIEW",
      "triggers": ["(validate|validation|e2e|end.to.end|smoke.test|a11y|accessibility|exercise|try.it|does.it.work|interactive.test)"],
      "keywords": [],
      "trigger_mode": "regex",
      "priority": 15,
      "precedes": [],
      "requires": [],
      "description": "Realistic-context validation: browser E2E, API smoke, CLI checks, a11y audits with unified report.",
      "invoke": "Skill(auto-claude-skills:runtime-validation)",
      "available": true,
      "enabled": true
    },
    {
      "name": "implementation-drift-check",
      "role": "domain",
      "phase": "REVIEW",
      "triggers": ["(drift|reflect|assumption|gap|deviat|on.track|off.track|spec.check|still.on.plan)"],
      "keywords": [],
      "trigger_mode": "regex",
      "priority": 12,
      "precedes": [],
      "requires": [],
      "description": "Spec drift detection, assumption surfacing, and coverage gap identification against Intent Truth.",
      "invoke": "Skill(auto-claude-skills:implementation-drift-check)",
      "available": true,
      "enabled": true
    },
```

- [ ] **Step 2: Add REVIEW parallel entries to fallback registry**

In `config/fallback-registry.json`, find `phase_compositions.REVIEW.parallel` (line ~1206). After the existing `security-scanner` entry (line ~1229), add the same two entries as Task 6 Step 1:

```json
        {
          "use": "runtime-validation -> Skill(auto-claude-skills:runtime-validation)",
          "when": "validation tools detected (Playwright, dev server, or CLI binary)",
          "purpose": "Realistic-context validation: derive scenarios from specs/evals, execute browser/API/CLI paths, report with evidence"
        },
        {
          "use": "implementation-drift-check -> Skill(auto-claude-skills:implementation-drift-check)",
          "when": "comparison material exists (specs, plans, or active chain with code changes)",
          "purpose": "Spec drift detection, assumption surfacing, coverage gap identification",
          "gate": "artifact-presence",
          "artifacts": [
            "openspec/changes/*/",
            "openspec/specs/*/spec.md",
            "docs/superpowers/specs/*-design.md",
            "docs/superpowers/plans/*.md",
            "tests/fixtures/evals/*.json"
          ]
        }
```

- [ ] **Step 3: Add SHIP fallback entries to fallback registry**

In `config/fallback-registry.json`, find `phase_compositions.SHIP.sequence` (line ~1255). Insert after the first entry (driver) and before `openspec-ship`:

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
        },
```

- [ ] **Step 4: Update Playwright hints in fallback registry**

In `config/fallback-registry.json`, update the `playwright-mcp` hint (line ~1488) and `frontend-playwright` hint (line ~1502) to match the updates in Task 7:

`playwright-mcp` hint:
```json
"hint": "PLAYWRIGHT: If Playwright MCP tools are available, use them for visual verification. During REVIEW, use Skill(auto-claude-skills:runtime-validation) as the orchestration entry point for E2E validation."
```

`frontend-playwright` hint:
```json
"hint": "PLAYWRIGHT TESTING: Frontend changes detected. Include Playwright E2E tests covering the changed UI behavior. During REVIEW, use Skill(auto-claude-skills:runtime-validation) for orchestrated E2E and a11y validation."
```

- [ ] **Step 5: Verify JSON is valid**

Run: `jq empty config/fallback-registry.json && echo "valid" || echo "BROKEN"`
Expected: `valid`

- [ ] **Step 6: Commit**

```bash
git add config/fallback-registry.json
git commit -m "feat: register skills, compositions, and hints in fallback-registry"
```

---

### Task 6: Add REVIEW and SHIP phase composition entries

**Files:**
- Modify: `config/default-triggers.json` (phase_compositions section)

- [ ] **Step 1: Add two parallel entries to REVIEW phase composition**

In `config/default-triggers.json`, find the `"REVIEW"` key in `phase_compositions` (line ~1158). In its `"parallel"` array, after the existing `security-scanner` entry, add:

```json
        {
          "use": "runtime-validation -> Skill(auto-claude-skills:runtime-validation)",
          "when": "validation tools detected (Playwright, dev server, or CLI binary)",
          "purpose": "Realistic-context validation: derive scenarios from specs/evals, execute browser/API/CLI paths, report with evidence"
        },
        {
          "use": "implementation-drift-check -> Skill(auto-claude-skills:implementation-drift-check)",
          "when": "comparison material exists (specs, plans, or active chain with code changes)",
          "purpose": "Spec drift detection, assumption surfacing, coverage gap identification",
          "gate": "artifact-presence",
          "artifacts": [
            "openspec/changes/*/",
            "openspec/specs/*/spec.md",
            "docs/superpowers/specs/*-design.md",
            "docs/superpowers/plans/*.md",
            "tests/fixtures/evals/*.json"
          ]
        }
```

- [ ] **Step 2: Add two gated fallback entries to SHIP phase sequence**

In `config/default-triggers.json`, find the `"SHIP"` key in `phase_compositions` (line ~1207). In its `"sequence"` array, insert after the first entry (`verification-before-completion`) and before the `openspec-ship` entry:

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
        },
```

- [ ] **Step 3: Verify JSON is valid**

Run: `jq empty config/default-triggers.json && echo "valid" || echo "BROKEN"`
Expected: `valid`

- [ ] **Step 4: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: add REVIEW parallel and SHIP fallback composition entries for validation wave"
```

---

### Task 7: Update methodology hints

**Files:**
- Modify: `config/default-triggers.json` (methodology_hints section)

- [ ] **Step 1: Update playwright-mcp hint**

Find the `playwright-mcp` methodology hint entry (line ~738). Replace the `hint` field value:

From:
```json
"hint": "PLAYWRIGHT: If Playwright MCP tools are available, use them for visual verification and interactive debugging."
```

To:
```json
"hint": "PLAYWRIGHT: If Playwright MCP tools are available, use them for visual verification. During REVIEW, use Skill(auto-claude-skills:runtime-validation) as the orchestration entry point for E2E validation."
```

- [ ] **Step 2: Update frontend-playwright hint**

Find the `frontend-playwright` methodology hint entry (line ~752). Replace the `hint` field value:

From:
```json
"hint": "PLAYWRIGHT TESTING: Frontend changes detected. Include Playwright E2E tests covering the changed UI behavior. Use the webapp-testing skill."
```

To:
```json
"hint": "PLAYWRIGHT TESTING: Frontend changes detected. Include Playwright E2E tests covering the changed UI behavior. During REVIEW, use Skill(auto-claude-skills:runtime-validation) for orchestrated E2E and a11y validation."
```

- [ ] **Step 3: Verify JSON is valid**

Run: `jq empty config/default-triggers.json && echo "valid" || echo "BROKEN"`
Expected: `valid`

- [ ] **Step 4: Commit**

```bash
git add config/default-triggers.json
git commit -m "feat: update Playwright hints to reference runtime-validation orchestrator"
```

---

### Task 8: Add composition gate predicates to skill-activation-hook.sh

**Files:**
- Modify: `hooks/skill-activation-hook.sh` (line ~1182-1226)

- [ ] **Step 1: Extend jq composition block to emit gate metadata**

In `hooks/skill-activation-hook.sh`, find the jq composition block (line ~1182). The jq must pass gate metadata through its output so Bash can evaluate it. Modify the parallel and sequence branches to emit `GATED:` lines when a `gate` field is present.

Replace the parallel branch (lines 1186-1191):
```
      (.parallel // [] | .[] |
        if .plugin then
          select(.plugin as $p | $avail | any(. == $p)) |
          "LINE:  PARALLEL: \(.use) -> \(.purpose) [\(.plugin)]"
        elif .gate then
          "GATED:\(.gate):\(.marker // ""):\(.artifacts // [] | join(",")):\("  PARALLEL: \(.use) \u2014 \(.purpose)")"
        else
          "LINE:  PARALLEL: \(.use) \u2014 \(.purpose)"
        end),
```

Replace the sequence branch (lines 1193-1198):
```
      (.sequence // [] | .[] |
        if .plugin then
          select(.plugin as $p | $avail | any(. == $p)) |
          "LINE:  SEQUENCE: \(.use // .step) -> \(.purpose) [\(.plugin)]"
        elif .gate then
          "GATED:\(.gate):\(.marker // ""):\(.artifacts // [] | join(",")):\("  SEQUENCE: \(.step) -> \(.purpose)")"
        else
          "LINE:  SEQUENCE: \(.step) -> \(.purpose)"
        end),
```

- [ ] **Step 2: Add gate evaluation in the Bash loop**

In the `while IFS= read -r _cline` loop (line ~1211), add a `GATED:*` case before the existing `LINE:*` case:

```bash
      GATED:*)
        # Parse gate metadata: GATED:type:marker:artifacts:line
        _gate_rest="${_cline#GATED:}"
        _gate_type="${_gate_rest%%:*}"; _gate_rest="${_gate_rest#*:}"
        _gate_marker="${_gate_rest%%:*}"; _gate_rest="${_gate_rest#*:}"
        _gate_artifacts="${_gate_rest%%:*}"; _gate_rest="${_gate_rest#*:}"
        _gate_line="${_gate_rest}"

        _gate_pass=1
        case "$_gate_type" in
          session-marker)
            [[ -f "${HOME}/.claude/.skill-${_gate_marker}-${_SESSION_TOKEN:-default}" ]] && _gate_pass=0
            ;;
          artifact-presence)
            _gate_pass=0
            IFS=',' read -ra _gate_pats <<< "$_gate_artifacts" 2>/dev/null || _gate_pats=()
            for _gpat in "${_gate_pats[@]}"; do
              [[ -z "$_gpat" ]] && continue
              compgen -G "${_PROJECT_ROOT:-.}/${_gpat}" >/dev/null 2>&1 && { _gate_pass=1; break; }
            done
            ;;
        esac

        if [[ "$_gate_pass" -eq 1 ]]; then
          COMPOSITION_LINES="${COMPOSITION_LINES}
${_gate_line}"
        fi
        ;;
```

**Important:** `read -ra` requires Bash 4+. For Bash 3.2 compatibility, replace with:

```bash
          artifact-presence)
            _gate_pass=0
            _saved_IFS="$IFS"; IFS=','
            for _gpat in $_gate_artifacts; do
              IFS="$_saved_IFS"
              [[ -z "$_gpat" ]] && continue
              compgen -G "${_PROJECT_ROOT:-.}/${_gpat}" >/dev/null 2>&1 && { _gate_pass=1; break; }
            done
            IFS="$_saved_IFS"
            ;;
```

- [ ] **Step 3: Set _PROJECT_ROOT variable (overridable for testing)**

Near the top of the hook (after `REGISTRY_CACHE` is defined, line ~58), add:

```bash
_PROJECT_ROOT="${SKILL_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
```

This follows the existing `CLAUDE_PLUGIN_ROOT` pattern: the env var `SKILL_PROJECT_ROOT` allows tests to point the artifact-presence gate at a controlled directory. In production, it falls through to `git rev-parse --show-toplevel`.

- [ ] **Step 4: Verify hook syntax**

Run: `bash -n hooks/skill-activation-hook.sh && echo "valid" || echo "BROKEN"`
Expected: `valid`

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh
git commit -m "feat: add session-marker and artifact-presence gate predicates to composition filter"
```

---

### Task 9: Document session-marker lifecycle (no session-start cleanup needed)

**Files:**
- None (documentation/verification only)

Session markers are scoped to `${SESSION_TOKEN}` (e.g., `.skill-validation-ran-1713200000-12345`). A new session gets a new token, so stale markers from prior sessions are invisible — they will never match the new token's filename. This means:

- **No session-start cleanup is needed.** Deleting all `*-ran-*` files at session start would destroy concurrent sessions' markers, breaking session isolation.
- **Stale markers are harmless.** They are zero-byte files (`touch`) that accumulate slowly and never match active tokens.
- **This follows the existing pattern.** The `prompt-count` cleanup (`rm -f .skill-prompt-count-*`) has the same cross-session issue but is acceptable because prompt counts are statistics, not behavioral gates. Markers affect gating, so they need more care.

- [ ] **Step 1: Verify marker filenames are session-scoped**

Confirm the SKILL.md instructions in Tasks 2 and 3 both use the session-token-scoped pattern:
```bash
touch ~/.claude/.skill-validation-ran-$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)
touch ~/.claude/.skill-drift-check-ran-$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)
```

And the hook gate check (Task 8) uses the same token:
```bash
[[ -f "${HOME}/.claude/.skill-${_gate_marker}-${_SESSION_TOKEN:-default}" ]]
```

- [ ] **Step 2: Verify no stale-marker collision is possible**

Run: `echo "no code changes needed — this task is verification only"`

---

### Task 10: Write routing tests for both new skills

**Files:**
- Modify: `tests/test-routing.sh` (add new test cases at the end, before the summary section)

- [ ] **Step 1: Add install_registry_with_validation() helper**

Add a new registry helper function to `tests/test-routing.sh`, after the existing `install_registry_with_wave1()` function (line ~530). Follow the established pattern — extend the base registry with the new skills via `jq .skills +=`:

```bash
# Helper: install registry extended with validation wave skills
install_registry_with_validation() {
    install_registry
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.skills += [
      {
        "name": "runtime-validation",
        "role": "domain",
        "phase": "REVIEW",
        "triggers": ["(validate|validation|e2e|end.to.end|smoke.test|a11y|accessibility|exercise|try.it|does.it.work|interactive.test)"],
        "trigger_mode": "regex",
        "priority": 15,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(auto-claude-skills:runtime-validation)",
        "available": true,
        "enabled": true
      },
      {
        "name": "implementation-drift-check",
        "role": "domain",
        "phase": "REVIEW",
        "triggers": ["(drift|reflect|assumption|gap|deviat|on.track|off.track|spec.check|still.on.plan)"],
        "trigger_mode": "regex",
        "priority": 12,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(auto-claude-skills:implementation-drift-check)",
        "available": true,
        "enabled": true
      }
    ]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"
}
```

- [ ] **Step 2: Add isolated runtime-validation routing test**

Add a new test function to `tests/test-routing.sh` before the summary section. Follow the established pattern (`setup_test_env` → `install_registry_with_validation` → run → `teardown_test_env`):

```bash
# ---------------------------------------------------------------------------
# runtime-validation routing (isolated)
# ---------------------------------------------------------------------------
test_runtime_validation_routing() {
    echo "-- runtime-validation routing --"

    setup_test_env
    install_registry_with_validation

    echo "  trigger: 'validate the feature end to end'"
    local output context
    output="$(run_hook "I want to validate the feature works end to end")"
    context="$(extract_context "$output")"
    assert_contains "runtime-validation surfaces on validate prompt" "runtime-validation" "$context"
    assert_not_contains "runtime-validation is not process driver" "Process: runtime-validation" "$context"

    echo "  negative: 'fix this crash'"
    output="$(run_hook "fix this crash in the auth module")"
    context="$(extract_context "$output")"
    assert_not_contains "runtime-validation not in debug" "runtime-validation" "$context"

    teardown_test_env
}
test_runtime_validation_routing
```

- [ ] **Step 3: Add isolated implementation-drift-check routing test**

Add immediately after:

```bash
# ---------------------------------------------------------------------------
# implementation-drift-check routing (isolated)
# ---------------------------------------------------------------------------
test_drift_check_routing() {
    echo "-- implementation-drift-check routing --"

    setup_test_env
    install_registry_with_validation

    echo "  trigger: 'check drift against the spec'"
    local output context
    output="$(run_hook "check drift against the spec")"
    context="$(extract_context "$output")"
    assert_contains "drift-check surfaces on explicit" "implementation-drift-check" "$context"
    assert_not_contains "drift-check is not process driver" "Process: implementation-drift-check" "$context"

    echo "  trigger: 'am I still on plan'"
    output="$(run_hook "am I still on plan")"
    context="$(extract_context "$output")"
    assert_contains "drift-check surfaces on plan check" "implementation-drift-check" "$context"

    teardown_test_env
}
test_drift_check_routing
```

- [ ] **Step 4: Add isolated artifact-presence gate test**

Add a test that verifies the gate suppresses composition entries when no artifacts exist. Uses a v4 registry with phase_compositions and a temp project root with no spec/plan files:

```bash
# ---------------------------------------------------------------------------
# artifact-presence gate suppression (isolated)
# ---------------------------------------------------------------------------
test_artifact_presence_gate() {
    echo "-- artifact-presence gate --"

    setup_test_env
    install_registry_with_validation

    # Patch registry to add phase_compositions.REVIEW with the gated entry
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.phase_compositions.REVIEW = {
      "driver": "requesting-code-review",
      "parallel": [
        {
          "use": "implementation-drift-check -> Skill(auto-claude-skills:implementation-drift-check)",
          "when": "comparison material exists",
          "purpose": "Spec drift detection",
          "gate": "artifact-presence",
          "artifacts": [
            "openspec/changes/*/",
            "openspec/specs/*/spec.md",
            "docs/superpowers/specs/*-design.md",
            "docs/superpowers/plans/*.md",
            "tests/fixtures/evals/*.json"
          ]
        }
      ]
    }' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"

    # Create a clean temp directory with no spec/plan/eval artifacts.
    # Point the hook at it via SKILL_PROJECT_ROOT (the env var override
    # added in Task 8 Step 3). This is the key: without this override,
    # _PROJECT_ROOT resolves to the real repo root which has artifacts.
    local artifact_free_root
    artifact_free_root="$(mktemp -d "${TMPDIR:-/tmp}/acs-gate-test.XXXXXXXX")"

    echo "  gate should suppress drift-check in artifact-free project"
    local output context
    output="$(SKILL_PROJECT_ROOT="${artifact_free_root}" run_hook "review my code changes")"
    context="$(extract_context "$output")"
    # With SKILL_PROJECT_ROOT pointing to a clean temp dir, the gate's
    # compgen -G checks find no matching artifacts → entry suppressed
    assert_not_contains "drift-check suppressed by gate" "implementation-drift-check" "$context"

    rm -rf "${artifact_free_root}"
    teardown_test_env
}
test_artifact_presence_gate
```

This test works because `SKILL_PROJECT_ROOT` overrides `_PROJECT_ROOT` in the hook (Task 8 Step 3), pointing the artifact-presence gate at a clean temp directory with no `openspec/`, `docs/superpowers/`, or `tests/fixtures/evals/` files. The gate's `compgen -G` checks fail, suppressing the entry. The real repo's artifacts are invisible to this test.

- [ ] **Step 5: Run routing tests**

Run: `bash tests/test-routing.sh`
Expected: All tests pass including new ones. Zero failures.

- [ ] **Step 6: Commit**

```bash
git add tests/test-routing.sh
git commit -m "test: add isolated routing and gate tests for validation wave skills"
```

---

### Task 11: Write scenario eval fixtures

**Files:**
- Create: `tests/fixtures/scenarios/validation-13-ui-with-playwright.json`
- Create: `tests/fixtures/scenarios/validation-14-api-smoke.json`
- Create: `tests/fixtures/scenarios/validation-15-cli-smoke.json`
- Create: `tests/fixtures/scenarios/drift-16-review-with-spec.json`
- Create: `tests/fixtures/scenarios/drift-17-trigger-exclusion.json`
- Create: `tests/fixtures/scenarios/fallback-18-ship-after-review-skip.json`

- [ ] **Step 1: Create validation-13 fixture**

Create `tests/fixtures/scenarios/validation-13-ui-with-playwright.json`:

```json
{
  "name": "validation-13-ui-with-playwright",
  "prompt": "I need to validate the login page works with playwright e2e tests",
  "expected_skills": ["runtime-validation"],
  "expected_phase": "REVIEW",
  "must_not_match": ["Process: runtime-validation"]
}
```

- [ ] **Step 2: Create validation-14 fixture**

Create `tests/fixtures/scenarios/validation-14-api-smoke.json`:

```json
{
  "name": "validation-14-api-smoke",
  "prompt": "validate the API endpoints with smoke tests",
  "expected_skills": ["runtime-validation"],
  "expected_phase": "REVIEW",
  "must_not_match": ["Process: runtime-validation"]
}
```

- [ ] **Step 3: Create validation-15 fixture**

Create `tests/fixtures/scenarios/validation-15-cli-smoke.json`:

```json
{
  "name": "validation-15-cli-smoke",
  "prompt": "does the CLI tool work? try it with a smoke test",
  "expected_skills": ["runtime-validation"],
  "expected_phase": "REVIEW",
  "must_not_match": ["Process: runtime-validation"]
}
```

- [ ] **Step 4: Create drift-16 fixture**

Create `tests/fixtures/scenarios/drift-16-review-with-spec.json`:

```json
{
  "name": "drift-16-review-with-spec",
  "prompt": "check drift against the spec before we ship",
  "expected_skills": ["implementation-drift-check"],
  "expected_phase": "REVIEW",
  "must_not_match": ["Process: implementation-drift-check"]
}
```

- [ ] **Step 5: Create drift-17 fixture**

**Design note:** The artifact-presence gate is a coarse repo-level filter (suppresses drift-check in repos with NO design artifacts). In repos like auto-claude-skills that always have specs/plans, drift-check WILL appear in composition lines when the REVIEW phase is active. This fixture tests that drift-check does NOT appear as a *selected skill* when the prompt contains no drift-related trigger words — trigger exclusion, not artifact-presence gating. The artifact-presence gate is tested in isolation in Task 10's dedicated gate test (see `test_artifact_presence_gate`).

Create `tests/fixtures/scenarios/drift-17-trigger-exclusion.json`:

```json
{
  "name": "drift-17-trigger-exclusion",
  "prompt": "review my code changes and check for bugs",
  "expected_skills": ["requesting-code-review"],
  "expected_phase": "REVIEW",
  "must_not_match": ["Domain: implementation-drift-check"]
}
```

Note: `must_not_match` checks `"Domain: implementation-drift-check"` (the skill activation line), not just `"implementation-drift-check"` (which could match composition parallel hints). This ensures the skill was not selected by the scoring engine, while allowing it to appear in composition context.

- [ ] **Step 6: Create fallback-18 fixture**

Create `tests/fixtures/scenarios/fallback-18-ship-after-review-skip.json`:

```json
{
  "name": "fallback-18-ship-after-review-skip",
  "prompt": "ship it, merge to main and push",
  "expected_skills": ["verification-before-completion"],
  "expected_phase": "SHIP",
  "expected_in_composition": ["runtime-validation", "implementation-drift-check"],
  "must_not_match": []
}
```

Note: `expected_in_composition` uses the existing scenario runner feature (test-scenario-evals.sh line 88-97) to verify both sidecars appear in the SHIP composition chain as fallback entries.

- [ ] **Step 7: Run scenario evals**

Run: `bash tests/test-scenario-evals.sh`
Expected: All 18 scenarios pass (12 existing + 6 new). Zero failures.

- [ ] **Step 8: Commit**

```bash
git add tests/fixtures/scenarios/validation-13-ui-with-playwright.json \
        tests/fixtures/scenarios/validation-14-api-smoke.json \
        tests/fixtures/scenarios/validation-15-cli-smoke.json \
        tests/fixtures/scenarios/drift-16-review-with-spec.json \
        tests/fixtures/scenarios/drift-17-trigger-exclusion.json \
        tests/fixtures/scenarios/fallback-18-ship-after-review-skip.json
git commit -m "test: add scenario eval fixtures for validation and drift-check routing"
```

---

### Task 12: Write content-contract tests for both skills

**Files:**
- Create: `tests/test-validation-skill-content.sh`

- [ ] **Step 1: Write the content-contract test suite**

Create `tests/test-validation-skill-content.sh`:

```bash
#!/usr/bin/env bash
# test-validation-skill-content.sh — Content-contract assertions for
# runtime-validation and implementation-drift-check skills.
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-validation-skill-content.sh ==="

setup_test_env

# ---------------------------------------------------------------------------
# runtime-validation content assertions
# ---------------------------------------------------------------------------
RV_SKILL="${PROJECT_ROOT}/skills/runtime-validation/SKILL.md"
RV_CONTENT="$(cat "${RV_SKILL}")"

# Frontmatter
assert_contains "rv: has name frontmatter" "name: runtime-validation" "$RV_CONTENT"

# Three execution paths
assert_contains "rv: browser path documented" "Browser" "$RV_CONTENT"
assert_contains "rv: API path documented" "API" "$RV_CONTENT"
assert_contains "rv: CLI path documented" "CLI" "$RV_CONTENT"

# Playwright detection
assert_contains "rv: playwright detection" "playwright" "$RV_CONTENT"

# axe-core / a11y
assert_contains "rv: a11y checks documented" "axe" "$RV_CONTENT"

# Graceful degradation
assert_contains "rv: graceful degradation documented" "no interactive validation tools" "$RV_CONTENT"

# Report contract
assert_contains "rv: unified report heading" "Validation Report" "$RV_CONTENT"
assert_contains "rv: coverage gaps section" "Coverage Gaps" "$RV_CONTENT"
assert_contains "rv: manual checks section" "Manual Checks" "$RV_CONTENT"

# Fix-rescan loop
assert_contains "rv: fix-rescan loop" "Max 3" "$RV_CONTENT"

# Session marker
assert_contains "rv: session marker" "validation-ran" "$RV_CONTENT"

# Ad-hoc script temp location
assert_contains "rv: mktemp for ad-hoc scripts" "mktemp" "$RV_CONTENT"

# Webapp-testing registry check
assert_contains "rv: registry-based webapp-testing check" "skill-registry-cache" "$RV_CONTENT"

# Eval pack consumption
assert_contains "rv: eval pack consumption" "fixtures/evals" "$RV_CONTENT"

# ---------------------------------------------------------------------------
# implementation-drift-check content assertions
# ---------------------------------------------------------------------------
DC_SKILL="${PROJECT_ROOT}/skills/implementation-drift-check/SKILL.md"
DC_CONTENT="$(cat "${DC_SKILL}")"

# Frontmatter
assert_contains "dc: has name frontmatter" "name: implementation-drift-check" "$DC_CONTENT"

# Two report modes
assert_contains "dc: full drift mode" "Implementation Drift Check" "$DC_CONTENT"
assert_contains "dc: assumptions-only mode" "Assumptions & Gaps" "$DC_CONTENT"

# Comparison sources
assert_contains "dc: openspec changes source" "openspec/changes" "$DC_CONTENT"
assert_contains "dc: canonical spec source" "openspec/specs" "$DC_CONTENT"
assert_contains "dc: design spec source" "superpowers/specs" "$DC_CONTENT"
assert_contains "dc: plan source" "superpowers/plans" "$DC_CONTENT"
assert_contains "dc: eval pack source" "fixtures/evals" "$DC_CONTENT"

# Drift dimensions
assert_contains "dc: spec drift" "Spec Alignment" "$DC_CONTENT"
assert_contains "dc: plan drift" "Plan Alignment" "$DC_CONTENT"
assert_contains "dc: review-induced drift" "Review-Induced" "$DC_CONTENT"

# Flags
assert_contains "dc: implemented-as-specified flag" "implemented-as-specified" "$DC_CONTENT"
assert_contains "dc: added-without-spec flag" "added-without-spec" "$DC_CONTENT"

# Session marker
assert_contains "dc: session marker" "drift-check-ran" "$DC_CONTENT"

# Auto-co-selection guard explanation
assert_contains "dc: artifact-presence gate" "artifact-presence" "$DC_CONTENT"

# Persistence
assert_contains "dc: post-implementation notes" "Post-Implementation Notes" "$DC_CONTENT"

teardown_test_env

echo ""
echo "=== Validation Skill Content Results ==="
echo "  Total: ${TESTS_RUN}"
echo "  Passed: ${TESTS_PASSED}"
echo "  Failed: ${TESTS_FAILED}"
[ "${TESTS_FAILED}" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run the content tests**

Run: `bash tests/test-validation-skill-content.sh`
Expected: All assertions pass. Exit 0.

- [ ] **Step 3: Commit**

```bash
git add tests/test-validation-skill-content.sh
git commit -m "test: add content-contract tests for runtime-validation and implementation-drift-check"
```

---

### Task 13: Run full test suite and fix any regressions

**Files:**
- None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All test suites pass. Zero failures across routing, registry, context, scenario evals, skill content, eval pack schema, and all existing tests.

- [ ] **Step 2: Run scenario evals specifically**

Run: `bash tests/test-scenario-evals.sh`
Expected: All 18 scenarios pass (12 existing + 6 new).

- [ ] **Step 3: Run routing tests specifically**

Run: `bash tests/test-routing.sh`
Expected: All routing tests pass including new runtime-validation and drift-check tests.

- [ ] **Step 4: Verify hook syntax for both hooks**

Run: `bash -n hooks/skill-activation-hook.sh && bash -n hooks/session-start-hook.sh && echo "all valid"`
Expected: `all valid`

- [ ] **Step 5: Debug-run the activation hook with explain mode**

Run: `echo '{"prompt":"validate the feature with playwright e2e tests"}' | SKILL_EXPLAIN=1 CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/skill-activation-hook.sh 2>&1`
Expected: Output shows `runtime-validation` scored and selected. Stderr shows explain trace with scoring breakdown.

- [ ] **Step 6: Fix any failures found in steps 1-5**

If any test fails, diagnose the root cause, fix, and re-run. Do not proceed until all tests pass.

- [ ] **Step 7: Commit any fixes (if needed)**

```bash
git add -A
git commit -m "fix: address test regressions from validation wave integration"
```

Only commit if there were actual fixes. Skip if all tests passed on first run.
