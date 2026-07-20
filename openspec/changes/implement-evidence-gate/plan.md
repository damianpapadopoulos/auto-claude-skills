# IMPLEMENT-evidence Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Close the IMPLEMENT-phase enforcement gap warn-first, reinforce the behavioral first line, and add a deterministic test-delta signal — each proven before any deny lands.

**Architecture:** Three independent units in `openspec/changes/implement-evidence-gate/design.md` (A: IMPLEMENT leg on the push gate, B: `executing-plans` precondition, C: `test_delta` verdict dimension), plus validation tasks (A/B eval for B, backtest for A). The deny-flip for Unit A is explicitly OUT of scope for this plan — it is a follow-up change gated on the backtest.

**Tech Stack:** Bash 3.2 (`/bin/bash`), jq, git; test harness `tests/test-helpers.sh` auto-discovered by `tests/run-tests.sh`; behavioral-eval harness `tests/run-behavioral-evals.sh`; backtest `scripts/phase-gate-backtest.sh`.

## Global Constraints

- Bash 3.2: no associative arrays, no `mapfile`, no unquoted `for x in $(...)` over spaced values. (CLAUDE.md)
- Hooks are fail-open: `trap 'exit 0' ERR`, no `set -e`; guard every sourced lib (`&&`/`|| true`) so a non-zero source can't trip the ERR trap into an exit-0 BYPASS. (CLAUDE.md, [[feedback_err_trap_unguarded_source_hooks]])
- Touch `config/default-triggers.json` AND `config/fallback-registry.json` together (canonical + regenerated). (CLAUDE.md)
- `.completed` MUST NOT satisfy any gate leg. Attestation satisfies IMPLEMENT only; never REVIEW/VERIFY. (spec)
- Warn-first: the IMPLEMENT leg emits advisory + telemetry, NO `permissionDecision:deny`, this plan. (D-3)
- Syntax-check every hook edit with `/bin/bash -n` AND exercise under `/bin/bash`. Run suites with `< /dev/null`. (CLAUDE.md)

---

### Task 1: Unit B — `executing-plans` CURRENT-step precondition (config pair)

**Files:**
- Modify: `config/default-triggers.json` (executing-plans entry, ~line 92)
- Modify: `config/fallback-registry.json` (same entry)
- Modify: `tests/test-registry.sh`

**Interfaces:**
- Produces: a non-empty `precondition` string on the `executing-plans` composition entry in both files; the activation hook already renders `precondition` on the CURRENT step (no hook code).

- [ ] **Step 1: Write the failing test** — add to `tests/test-registry.sh` before its summary:

```bash
# executing-plans carries an IMPLEMENT precondition in BOTH config files
_ep_pre_default="$(jq -r '.composition_chain[]? // .phase_compositions // empty' /dev/null 2>/dev/null; jq -r '(.. | objects | select(.name?=="executing-plans") | .precondition) // empty' "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null | head -1)"
if printf '%s' "${_ep_pre_default}" | grep -qiF "before editing"; then
    _record_pass "executing-plans precondition present in default-triggers.json"
else
    _record_fail "executing-plans precondition present in default-triggers.json" "got: ${_ep_pre_default}"
fi
_ep_pre_fb="$(jq -r '(.. | objects | select(.name?=="executing-plans") | .precondition) // empty' "${PROJECT_ROOT}/config/fallback-registry.json" 2>/dev/null | head -1)"
if [ -n "${_ep_pre_fb}" ] && [ "${_ep_pre_fb}" = "${_ep_pre_default}" ]; then
    _record_pass "executing-plans precondition identical in fallback-registry.json"
else
    _record_fail "executing-plans precondition identical in fallback-registry.json" "default='${_ep_pre_default}' fb='${_ep_pre_fb}'"
fi
```

- [ ] **Step 2: Run to verify it fails**
Run: `bash tests/test-registry.sh < /dev/null`
Expected: FAIL both new assertions (no precondition field yet).

- [ ] **Step 3: Add the precondition to both config files.** In each file's `executing-plans` object, add after the `"description"` line:

```json
      "precondition": "PRECONDITION: invoke Skill(superpowers:executing-plans) — or subagent-driven-development / agent-team-execution — BEFORE editing code. Doing the implementation with raw tools first silently skips the IMPLEMENT phase: no evidence is recorded and the push gate will flag (later, deny) the push. If you deliberately skip it, record it: phase_attest executing-plans \"<reason>\".",
```

(Preserve all existing keys; targeted insert, not a rewrite. The string is identical in both files.)

- [ ] **Step 4: Run to verify it passes**
Run: `bash tests/test-registry.sh < /dev/null`
Expected: PASS, including `test_all_triggers_compile` (unchanged triggers).

- [ ] **Step 5: Commit**
```bash
git add config/default-triggers.json config/fallback-registry.json tests/test-registry.sh
git commit -m "feat: executing-plans IMPLEMENT precondition (config pair)"
```

---

### Task 2: Unit C — `test_delta` verdict dimension (writer + reader)

**Files:**
- Modify: `scripts/verify-and-record.sh` (compute + record `test_delta`)
- Modify: `hooks/lib/verdict.sh` (add `verdict_test_delta` reader)
- Create: `tests/test-verdict-test-delta.sh`

**Interfaces:**
- Consumes: `.verify.yml` (declared gate), git diff of the verified range.
- Produces: verdict field `test_delta` ∈ {`covered`,`missing`,`n/a`}; reader `verdict_test_delta <token>` echoes it.

- [ ] **Step 1: Write the failing test** — `tests/test-verdict-test-delta.sh` (hermetic: temp repo + `.verify.yml`, run the script, read the verdict). Full fixture:

```bash
#!/usr/bin/env bash
# test-verdict-test-delta.sh — verify-and-record records test_delta covered|missing|n/a.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-verdict-test-delta.sh ==="

SBOX="$(mktemp -d)"; trap 'rm -rf "${SBOX}"' EXIT
R="${SBOX}/repo"; mkdir -p "${R}/scripts" "${R}/tests" "${R}/docs"
( cd "${R}"; git init -q; git config user.email t@t.t; git config user.name t
  printf 'substrate: local\nchecks:\n  - name: noop\n    run: "true"\n' > .verify.yml
  echo base > scripts/foo.sh; echo base > tests/test-foo.sh; echo base > docs/x.md
  git add -A; git commit -qm base ) >/dev/null 2>&1
export SKILL_SESSION_TOKEN="tdtest-$$"
export HOME_BAK="$HOME"

_run_case() { # $1 = expected test_delta ; edits already staged/committed on top of base
  ( cd "${R}"; git add -A; git commit -qm change >/dev/null 2>&1 )
  SKILL_PROJECT_ROOT="${R}" bash "${PROJECT_ROOT}/scripts/verify-and-record.sh" >/dev/null 2>&1 || true
  # read the verdict the script wrote for our token
  local v="${HOME}/.claude/.skill-project-verified-${SKILL_SESSION_TOKEN}"
  jq -r '.test_delta // "ABSENT"' "$v" 2>/dev/null
}

# Case missing: source changed, no test changed
( cd "${R}"; echo change1 > scripts/foo.sh )
got="$(_run_case)"; [ "$got" = "missing" ] && _record_pass "source w/o test -> missing" || _record_fail "source w/o test -> missing" "got=$got"

# Case covered: source + test changed
( cd "${R}"; echo change2 > scripts/foo.sh; echo change2 > tests/test-foo.sh )
got="$(_run_case)"; [ "$got" = "covered" ] && _record_pass "source + test -> covered" || _record_fail "source + test -> covered" "got=$got"

# Case n/a: docs only
( cd "${R}"; echo change3 > docs/x.md )
got="$(_run_case)"; [ "$got" = "n/a" ] && _record_pass "docs only -> n/a" || _record_fail "docs only -> n/a" "got=$got"

print_summary
```

- [ ] **Step 2: Run to verify it fails**
Run: `bash tests/test-verdict-test-delta.sh < /dev/null`
Expected: FAIL — `test_delta` ABSENT (field not written).

- [ ] **Step 3: Implement in `scripts/verify-and-record.sh`.** After `SHA`/`TOKEN` are established and before the verdict `jq -n`, compute the delta over the last commit range (fallback to merge-base with the mainline when resolvable):

```bash
# test_delta (advisory): does a material source change carry a test change?
# docs = docs/**, openspec/**, *.md; test files = tests/*.sh (declared-gate default).
_TD_BASE="$(git -C "$ROOT" rev-parse HEAD~1 2>/dev/null || echo "")"
if [ -n "$_TD_BASE" ]; then
    _TD_FILES="$(git -C "$ROOT" diff --name-only "$_TD_BASE"..HEAD 2>/dev/null)"
else
    _TD_FILES="$(git -C "$ROOT" show --name-only --format= HEAD 2>/dev/null)"
fi
_TD_SRC=0; _TD_TEST=0
while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    case "$_f" in docs/*|openspec/*|*.md) continue ;; esac
    _TD_SRC=1
    case "$_f" in tests/*.sh) _TD_TEST=1 ;; esac
done <<EOF
$_TD_FILES
EOF
if [ "$_TD_SRC" -eq 0 ]; then TEST_DELTA="n/a"
elif [ "$_TD_TEST" -eq 1 ]; then TEST_DELTA="covered"
else TEST_DELTA="missing"; fi
```

Then add to the verdict `jq -n` args: `--arg td "$TEST_DELTA"` and to the object body: `test_delta:$td,`. Add `test_delta` to the closing summary `jq -c` echo.

- [ ] **Step 4: Add the reader to `hooks/lib/verdict.sh`:**

```bash
# verdict_test_delta <token> — echo the recorded test_delta (covered|missing|n/a|"").
verdict_test_delta() {
    local _t="${1:-}" _f
    _f="${HOME}/.claude/.skill-project-verified-${_t}"
    [ -f "$_f" ] || return 1
    jq -r '.test_delta // ""' "$_f" 2>/dev/null
}
```

- [ ] **Step 5: Run to verify it passes**
Run: `bash tests/test-verdict-test-delta.sh < /dev/null`
Expected: PASS all three cases.

- [ ] **Step 6: Commit**
```bash
git add scripts/verify-and-record.sh hooks/lib/verdict.sh tests/test-verdict-test-delta.sh
git commit -m "feat: test_delta advisory dimension in verification verdict"
```

---

### Task 3: Unit A — IMPLEMENT-evidence leg on the push gate (WARN-FIRST)

**Files:**
- Modify: `hooks/openspec-guard.sh` (new leg after the VERIFY check, inside the same `_COMP_STATE` block)
- Create: `tests/test-push-gate-implement-leg.sh`

**Interfaces:**
- Consumes: `_COMP_STATE`, `_ledger_has`/`_invoc_ok`/`_bridge_has` (in-scope in that block), `phase_attested` (from phase-attest.sh — source-guard it), `_phase_alias_candidates` (phase-evidence.sh, already sourced by the guard's chain block).
- Produces: an advisory in `_STALE_MSG` when IMPLEMENT is in-chain, the diff touches material source, and no IMPLEMENT evidence exists. NO deny in this plan.

- [ ] **Step 1: Write the failing test** — `tests/test-push-gate-implement-leg.sh`. Drives the guard with a synthetic `git push` payload against the real repo state with a seeded composition-state + clean verdict (so REVIEW/VERIFY/routing legs pass and only the IMPLEMENT leg is under test). Mirror the harness in `tests/test-push-gate-ledger.sh` (seed a clean covering verdict; seed `.completed` with review+verify). Assertions:
  - IMPLEMENT in chain, material source in diff, no impl evidence → output contains an IMPLEMENT advisory AND `permissionDecision` is NOT `deny`.
  - After `phase_attest executing-plans "test"` → no IMPLEMENT advisory.
  - Chain without any implementation-slot member → no IMPLEMENT advisory.

(Author against the existing push-gate test harness; reuse its seed helpers verbatim — do not re-invent verdict/ledger seeding.)

- [ ] **Step 2: Run to verify it fails**
Run: `bash tests/test-push-gate-implement-leg.sh < /dev/null`
Expected: FAIL — no IMPLEMENT advisory emitted.

- [ ] **Step 3: Implement the leg** in `hooks/openspec-guard.sh`, immediately AFTER the VERIFY `if [ "${_verif_in_chain}" ... ]` deny block and BEFORE the verify-hardening block:

```bash
            # Check 0 (IMPLEMENT, WARN-FIRST): an implementation-slot skill is in
            # the chain but has no evidence, and the diff touches material source.
            # Accepts attestation (IMPLEMENT is not a gating milestone). Advisory
            # only — no permissionDecision. Deny-flip is a separate change gated on
            # phase-gate-backtest (<10% false-block). .completed does NOT satisfy it.
            _impl_in_chain=false; _impl_ok=false
            for _slot in executing-plans subagent-driven-development agent-team-execution; do
                jq -e --arg s "$_slot" '.chain | index($s)' "${_COMP_STATE}" >/dev/null 2>&1 && _impl_in_chain=true
            done
            if [ "${_impl_in_chain}" = "true" ] && [ "${_gc_is_push}" = "true" ]; then
                for _slot in executing-plans subagent-driven-development agent-team-execution; do
                    _ledger_has "$_slot" && _impl_ok=true
                    [ "${_impl_ok}" = "false" ] && _invoc_ok "$_slot" && _impl_ok=true
                    [ "${_impl_ok}" = "false" ] && _bridge_has "$_slot" && _impl_ok=true
                    if [ "${_impl_ok}" = "false" ] && command -v phase_attested >/dev/null 2>&1; then
                        phase_attested "${_SESSION_TOKEN}" "$_slot" && _impl_ok=true
                    fi
                done
                if [ "${_impl_ok}" = "false" ] && _diff_touches_material_source "${_proot}"; then
                    _STALE_MSG="${_STALE_MSG}${_STALE_MSG:+; }IMPLEMENT: this push edits source but no implementation-slot skill (executing-plans / subagent-driven-development / agent-team-execution) has invocation evidence on this chain. Invoke it, or record a deliberate skip: phase_attest executing-plans \"<reason>\". (advisory; will become a deny after backtest)"
                    command -v phase_gate_log >/dev/null 2>&1 && phase_gate_log "push-implement" "warn" "push" "executing-plans"
                fi
            fi
```

Add the material-source predicate near the other predicates (top of the guard, after libs sourced). Source-guard phase-attest.sh where the guard sources its libs:

```bash
_diff_touches_material_source() {
    local _r="${1:-.}" _base _files _f
    _base="$(git -C "$_r" merge-base HEAD @{upstream} 2>/dev/null || git -C "$_r" rev-parse HEAD~1 2>/dev/null)" || return 1
    _files="$(git -C "$_r" diff --name-only "$_base"..HEAD 2>/dev/null)" || return 1
    while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        case "$_f" in docs/*|openspec/*|*.md) continue ;; *) return 0 ;; esac
    done <<EOF
$_files
EOF
    return 1
}
# source phase-attest for the IMPLEMENT leg's attestation check (guarded)
[ -f "${_PLUGIN_ROOT}/hooks/lib/phase-attest.sh" ] && . "${_PLUGIN_ROOT}/hooks/lib/phase-attest.sh" 2>/dev/null || true
```

- [ ] **Step 4: Syntax + behavior check, then run the test**
Run: `/bin/bash -n hooks/openspec-guard.sh && bash tests/test-push-gate-implement-leg.sh < /dev/null`
Expected: syntax OK; PASS all assertions.

- [ ] **Step 5: Regression — REVIEW/VERIFY still deny, attestation still can't satisfy them**
Run: `bash tests/test-push-gate-failclosed.sh < /dev/null && bash tests/test-push-gate-ledger.sh < /dev/null`
Expected: PASS (the new leg must not weaken existing denies; it appends advisory only).

- [ ] **Step 6: Commit**
```bash
git add hooks/openspec-guard.sh tests/test-push-gate-implement-leg.sh
git commit -m "feat: IMPLEMENT-evidence leg on push gate (warn-first, attestation-accepting)"
```

---

### Task 4: Validation — A/B eval (Unit B) + backtest (Unit A), prove-before-deny

**Files:**
- Create: `tests/fixtures/evals/implement-precondition-ab.json` (control + treatment pack)
- Create: `openspec/changes/implement-evidence-gate/validation-results.md` (recorded evidence)

**Interfaces:** produces the pre-registered evidence that gates (a) precondition adoption and (b) the future deny-flip. No code deny-wiring in this task.

- [ ] **Step 1: Author the A/B eval pack** — control arm = registry WITHOUT the precondition; treatment = WITH it. Pre-registered metric: fraction of implementation-phase prompts where the model invokes an implementation-slot skill BEFORE the first source Write/Edit. ≥5 prompts, pinned judge model+version, safety subset unchanged (no regression). Mirror `tests/fixtures/evals/routing-validation.json` shape; smoke 1 call first ([[reference_behavioral_eval_harness_gotchas]]).

- [ ] **Step 2: Run the A/B** (quota permitting):
Run: `bash tests/run-behavioral-evals.sh tests/fixtures/evals/implement-precondition-ab.json`
Record control vs treatment rates in `validation-results.md`. Decision rule: adopt the precondition only if treatment materially beats control with no safety regression. If quota blocks the run, record BLOCKED + the harness-ready pack, and mark the precondition adoption pending (ship the config behind this evidence, revert if it fails).

- [ ] **Step 3: Backtest the IMPLEMENT leg**
Run: `bash scripts/phase-gate-backtest.sh` (over local transcripts). Human-classify each would-fire as true-catch vs false-block. Record the rate in `validation-results.md`. Pre-registered: deny-flip ships <10% FB; 10–20% narrow; >20% stays advisory. The deny-flip itself is a FOLLOW-UP change, not this plan.

- [ ] **Step 4: Commit the evidence**
```bash
git add tests/fixtures/evals/implement-precondition-ab.json openspec/changes/implement-evidence-gate/validation-results.md
git commit -m "test: A/B eval pack + validation results for implement-evidence gate"
```

---

### Task 5: Docs — CLAUDE.md gotcha + CHANGELOG + full suite

**Files:**
- Modify: `CLAUDE.md` (Gotchas — the IMPLEMENT leg is warn-first + attestation-accepting; deny-flip gated on backtest; PAIRED with the REVIEW/VERIFY legs)
- Modify: `CHANGELOG.md` (`[Unreleased] / ### Added`)

- [ ] **Step 1: CLAUDE.md gotcha** — one paragraph: the push gate now has an IMPLEMENT leg (warn-first) accepting `executing-plans`/`subagent-driven-development`/`agent-team-execution` evidence OR `phase_attest executing-plans`; REVIEW/VERIFY still never accept attestation; deny-flip is gated on `phase-gate-backtest` <10% FB; `test_delta` is an advisory verdict dimension. Regression tests named.

- [ ] **Step 2: CHANGELOG entry** under `## [Unreleased] / ### Added`.

- [ ] **Step 3: Full suite**
Run: `bash tests/run-tests.sh < /dev/null`
Expected: all files pass (new: test-registry additions, test-verdict-test-delta, test-push-gate-implement-leg).

- [ ] **Step 4: Commit**
```bash
git add CLAUDE.md CHANGELOG.md
git commit -m "docs: changelog + CLAUDE.md gotcha for IMPLEMENT-evidence gate"
```

---

## Self-Review

**Spec coverage:** IMPLEMENT leg (Req 1) → Task 3 + backtest Task 4; precondition (Req 2) → Task 1 + A/B Task 4; test_delta (Req 3) → Task 2. All 10 spec scenarios map to an assertion in Tasks 1–3. ✓

**Placeholder scan:** Task 3 step 1 says "mirror the existing harness" rather than inlining the full seed — deliberate (the verdict/ledger seed helpers are long and already exist in `tests/test-push-gate-ledger.sh`; re-inlining risks drift). Every NEW code block is complete. ✓

**Out of scope (explicit):** the Unit-A deny-flip (stays warn-first here; follow-up change gated on Task 4 backtest); deny-wiring `test_delta`; DESIGN/PLAN push-gate legs; a Stop-hook alarm. ✓

**Type/name consistency:** `_diff_touches_material_source`, `_impl_in_chain`, `_impl_ok`, `TEST_DELTA`/`test_delta`, `verdict_test_delta`, precondition string — consistent across tasks. ✓

**Governance:** touches `hooks/` + `config/` and modifies a safety gate → REVIEW MUST run `agent-team-review`. Change strengthens (not weakens) the gate; warn-first + attestation escape bound the blast radius. ✓
