# Activation-Hook Injection Size Measurement (Phase 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deterministically measure how many tokens trimming the activation-hook "full" verbosity tier would save, then compare against a pre-committed gate to decide whether the expensive Phase 1 model-in-loop experiment is worth building.

**Architecture:** Add an env-gated (`SKILL_LEAN_TIER=1`, default-OFF — zero production impact) lean rendering branch to `_format_output` in the activation hook, alongside the existing "full" branch. A standalone, hermetic measurement script builds the real registry in a temp HOME, runs the hook in full vs lean mode on a fixed 3+-skill depth-1 prompt, and reports the byte/token delta with a gate verdict. No model (`claude -p`) is invoked — this is a deterministic size measurement only.

**Tech Stack:** Bash 3.2, jq. Reuses the `run_hook` / `extract_context` / `_setup_depth_counter` harness patterns already in `tests/test-routing.sh`.

**Pre-committed gate (decided BEFORE running, per PR #43 race-gate discipline):**
- **PROCEED to Phase 1** only if lean saves **≥ 200 tokens** on the full-tier prompt.
- Otherwise **STOP** — record the verdict, do not build the Phase 1 corpus/harness.
- Token estimate = `bytes / 4` (rough, directional — adequate for a go/no-go gate).
- Hard constraint regardless of size: the lean variant MUST retain the `MUST INVOKE` directive, the `Skill(` invocation markers, and the mandatory eval-format line (these carry compliance; only the Step-1/2/3 scaffold + phase-guide table may be cut).

---

## File Structure

- **Modify:** `hooks/skill-activation-hook.sh` — `_format_output()` full-tier branch (lines 969–989): wrap in an `SKILL_LEAN_TIER` env gate; move the `_PHASE_GUIDE` build inside the verbose (else) branch.
- **Modify:** `tests/test-routing.sh` — add `test_lean_tier_env_override` + register it in the run list.
- **Create:** `tests/measure-injection-size.sh` — hermetic measurement runner + gate verdict.
- **Create:** `docs/plans/2026-05-29-injection-size-verdict.md` — recorded numbers + gate decision (written in Task 3 with real output).

---

### Task 1: Env-gated lean rendering branch in `_format_output`

**Files:**
- Modify: `hooks/skill-activation-hook.sh:969-989`
- Test: `tests/test-routing.sh` (new `test_lean_tier_env_override`)

- [ ] **Step 1: Write the failing test**

Add to `tests/test-routing.sh` (after `test_depth_full_format_first_prompt`, ~line 2831):

```bash
test_lean_tier_env_override() {
    setup_test_env
    install_registry

    # Fresh session = prompt 1; "build a secure frontend component" selects 3+ skills => full tier
    _setup_depth_counter
    local full_ctx lean_ctx
    full_ctx="$(extract_context "$(run_hook "build a secure frontend component")")"

    _setup_depth_counter
    lean_ctx="$(extract_context "$(SKILL_LEAN_TIER=1 run_hook "build a secure frontend component")")"

    # Lean drops the verbose scaffold + phase-guide table
    assert_not_contains "lean: no ASSESS PHASE" "ASSESS PHASE" "${lean_ctx}"
    assert_not_contains "lean: no Step 1 label" "Step 1 --" "${lean_ctx}"

    # Lean RETAINS compliance-carrying text
    assert_contains "lean: keeps MUST INVOKE" "MUST INVOKE" "${lean_ctx}"
    assert_contains "lean: keeps Skill( marker" "Skill(" "${lean_ctx}"
    assert_contains "lean: keeps eval Phase line" "**Phase:" "${lean_ctx}"

    # Lean is strictly smaller than full
    local full_len lean_len
    full_len="$(printf '%s' "${full_ctx}" | wc -c | tr -d ' ')"
    lean_len="$(printf '%s' "${lean_ctx}" | wc -c | tr -d ' ')"
    if [[ "${lean_len}" -lt "${full_len}" ]]; then
        _record_pass "lean tier smaller than full (${lean_len} < ${full_len})"
    else
        _record_fail "lean tier smaller than full" "lean=${lean_len} full=${full_len}"
    fi

    teardown_test_env
}
```

`run_hook` already forwards the ambient environment to `bash "${HOOK}"`, so `SKILL_LEAN_TIER=1 run_hook ...` exports the var into the hook process.

- [ ] **Step 2: Register the test and run it to verify it fails**

Find the run-list near the bottom of `tests/test-routing.sh` (where `test_depth_full_format_first_prompt` is invoked) and add a line:

```bash
test_lean_tier_env_override
```

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 lean`
Expected: FAIL — `lean: no ASSESS PHASE` fails because, without the gate, lean mode still renders the full template (ASSESS PHASE present).

- [ ] **Step 3: Implement the env gate in `_format_output`**

Replace the full-tier branch body (`hooks/skill-activation-hook.sh:969-989`). The current branch starts at `elif [[ "$_PROMPT_COUNT" -le 1 ]] && [[ "$TOTAL_COUNT" -ge 3 ]]; then`. New body:

```bash
  elif [[ "$_PROMPT_COUNT" -le 1 ]] && [[ "$TOTAL_COUNT" -ge 3 ]]; then
    # --- full format (3+ skills, prompt 1 only) ---
    if [[ "${SKILL_LEAN_TIER:-0}" == "1" ]]; then
      # Lean variant (Phase 0 measurement / candidate trim): drop the Step 1/2/3
      # scaffold + phase-guide table; KEEP skill lines, MUST INVOKE, eval format.
      OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})
${SKILL_LINES}${COMPOSITION_CHAIN}${COMPOSITION_LINES}
You MUST print a brief evaluation for each skill above:
  **Phase: [PHASE]** | ${EVAL_SKILLS}
Process skills marked MUST INVOKE are mandatory — invoke them. Domain/workflow skills marked YES/NO are optional.${DOMAIN_HINT}${COMPOSITION_DIRECTIVE}"
    else
      # Build phase guide from registry (falls back to a minimal default)
      _PHASE_GUIDE="$(printf '%s' "$REGISTRY" | jq -r '
        .phase_guide // empty | to_entries | sort_by(.key) |
        .[] | "  " + .key + (" " * ((10 - (.key | length)) | if . < 0 then 0 else . end)) + " -> " + .value
      ' 2>/dev/null)"
      [[ -z "$_PHASE_GUIDE" ]] && _PHASE_GUIDE="  (no phase guide available — assess intent from context)"

      OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})

Step 1 -- ASSESS PHASE. Check conversation context:
${_PHASE_GUIDE}

Step 2 -- EVALUATE skills against your phase assessment.${SKILL_LINES}${COMPOSITION_CHAIN}${COMPOSITION_LINES}
You MUST print a brief evaluation for each skill above. Format:
  **Phase: [PHASE]** | ${EVAL_SKILLS}
Process skills marked MUST INVOKE are mandatory — invoke them. Domain/workflow skills marked YES/NO are optional.
This line is MANDATORY -- do not skip it.

Step 3 -- INVOKE the process skill. Do not skip to a later phase.${DOMAIN_HINT}${COMPOSITION_DIRECTIVE}"
    fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | tail -5`
Expected: full suite PASS (including the 5 new `lean:` assertions). Confirm no existing depth-tier test regressed (`test_depth_full_format_first_prompt` still passes — default path unchanged).

Also syntax-check: `bash -n hooks/skill-activation-hook.sh` → no output (clean).

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: env-gated lean injection tier for size measurement (Phase 0)"
```

---

### Task 2: Hermetic measurement script + gate

**Files:**
- Create: `tests/measure-injection-size.sh`

- [ ] **Step 1: Write the measurement script**

Create `tests/measure-injection-size.sh`:

```bash
#!/usr/bin/env bash
# Phase 0: measure the token savings of the lean injection tier vs the full tier.
# Deterministic — no model invocation. Builds the real registry from repo config
# in a temp HOME so it does not touch the user's ~/.claude.
set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
SESSION_START="${PROJECT_ROOT}/hooks/session-start-hook.sh"
PROMPT="${1:-build a secure frontend component and review it for security}"
GATE_TOKENS=200   # pre-committed: proceed to Phase 1 only if savings >= this

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "${TMP_HOME}"' EXIT
mkdir -p "${TMP_HOME}/.claude"

# Build the real registry from repo config into the temp HOME.
HOME="${TMP_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    bash "${SESSION_START}" >/dev/null 2>&1 || true

run() {  # $1 = extra env assignment ("" or "SKILL_LEAN_TIER=1")
    local extra="$1"
    rm -f "${TMP_HOME}/.claude/.skill-prompt-count-"* "${TMP_HOME}/.claude/.skill-session-token" 2>/dev/null
    jq -n --arg p "${PROMPT}" '{"prompt":$p}' | \
        env HOME="${TMP_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ${extra} \
        bash "${HOOK}" 2>/dev/null | \
        jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

FULL="$(run "")"
LEAN="$(run "SKILL_LEAN_TIER=1")"

full_b="$(printf '%s' "${FULL}" | wc -c | tr -d ' ')"
lean_b="$(printf '%s' "${LEAN}" | wc -c | tr -d ' ')"
delta_b=$(( full_b - lean_b ))
full_t=$(( full_b / 4 )); lean_t=$(( lean_b / 4 )); delta_t=$(( delta_b / 4 ))
pct=0; [[ "${full_b}" -gt 0 ]] && pct=$(( delta_b * 100 / full_b ))

echo "Prompt:        ${PROMPT}"
echo "Full tier:     ${full_b} bytes (~${full_t} tokens)"
echo "Lean tier:     ${lean_b} bytes (~${lean_t} tokens)"
echo "Savings:       ${delta_b} bytes (~${delta_t} tokens, ${pct}%)"
echo "Gate (>=${GATE_TOKENS} tokens): $([[ "${delta_t}" -ge "${GATE_TOKENS}" ]] && echo "PROCEED to Phase 1" || echo "STOP — not worth Phase 1")"

# Sanity: fail loudly if the full tier never rendered (registry build failed)
if [[ "${full_b}" -lt 50 ]]; then
    echo "WARN: full tier output suspiciously small — registry may not have built; verdict unreliable." >&2
    exit 3
fi
```

- [ ] **Step 2: Make executable and run it**

Run:
```bash
chmod +x tests/measure-injection-size.sh
bash tests/measure-injection-size.sh
```
Expected: prints Full/Lean byte+token counts, savings, and a PROCEED/STOP verdict. Capture this output verbatim for Task 3. (If it prints the registry WARN and exits 3, debug the session-start build before recording a verdict.)

- [ ] **Step 3: Commit**

```bash
git add tests/measure-injection-size.sh
git commit -m "test: add deterministic injection-size measurement script (Phase 0)"
```

---

### Task 3: Record the verdict

**Files:**
- Create: `docs/plans/2026-05-29-injection-size-verdict.md`

- [ ] **Step 1: Write the verdict doc with the REAL captured numbers**

Create `docs/plans/2026-05-29-injection-size-verdict.md`. Paste the actual `measure-injection-size.sh` output and fill the decision. Template (replace bracketed values with measured output — no placeholders left):

```markdown
# Injection-Size Measurement — Verdict (Phase 0)

**Date:** 2026-05-29
**Method:** `tests/measure-injection-size.sh` — deterministic byte/token diff of full vs lean activation-hook injection on a depth-1, 3+-skill prompt. No model invoked.

## Measured

- Prompt: `[prompt used]`
- Full tier: `[N]` bytes (~`[N/4]` tokens)
- Lean tier: `[N]` bytes (~`[N/4]` tokens)
- Savings: `[N]` bytes (~`[N/4]` tokens, `[pct]%`)

## Gate

Pre-committed threshold: proceed to Phase 1 only if savings ≥ 200 tokens.

**Verdict:** `[PROCEED | STOP]`

## Decision

`[If STOP: Phase 1 (model-in-loop A/B) is NOT built. The lean tier remains an env-gated
(SKILL_LEAN_TIER, default-OFF) measurement artifact. Savings of ~[N] tokens fire only on
the first prompt of a session with 3+ skills — too small to justify a ~2-day, multi-million-token
behavioral experiment, consistent with the debate's effect-size finding.]`

`[If PROCEED: Phase 1 is justified. Next step: build the injection-aware behavioral harness
(pipe prompt -> activation hook -> additionalContext -> claude -p) + cross-phase tool_call corpus.]`

## Notes

- Token estimate is bytes/4 (directional).
- The dominant trimmable chunk is the 8-row phase-guide table + Step-1/2/3 scaffold; skill-line
  content varies with routing, so absolute savings vary by prompt.
```

- [ ] **Step 2: Commit**

```bash
git add -f docs/plans/2026-05-29-injection-size-verdict.md
git commit -m "docs: record injection-size measurement verdict (Phase 0)"
```

(`docs/plans/` is gitignored — `git add -f` is required, per project convention.)

---

## Self-Review

- **Spec coverage:** Plan covers the approved Phase 0 scope — instrumentation (Task 1 lean branch + Task 2 byte/token measurement), the deterministic proxy assertions (Task 1 test: retains MUST INVOKE/Skill/eval, drops scaffold), the pre-committed gate (Task 2 + Task 3), and the recorded verdict (Task 3). Phase 1 is explicitly out of scope and gated.
- **No production behavior change:** the lean branch is `SKILL_LEAN_TIER`-gated, default-OFF; the default rendering path is byte-identical to current (verified by `test_depth_full_format_first_prompt` still passing in Task 1 Step 4).
- **Placeholder scan:** verdict-doc brackets are intentionally filled with real captured output in Task 3 Step 1 — not shipped as placeholders.
- **Type/name consistency:** `SKILL_LEAN_TIER`, `measure-injection-size.sh`, `test_lean_tier_env_override`, gate=200 tokens used consistently across tasks.
```
