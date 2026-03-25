# Incident Analysis Critique Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 5 validated findings (2 P1, 3 P2) in the incident-analysis skill where the SKILL.md has internal contradictions, drifted from its spec, or left safety-critical steps implicit.

**Architecture:** All changes are to Markdown prose (SKILL.md, spec.md) and Bash test assertions (test-skill-content.sh, test-postmortem-shape.sh). No runtime code changes. Each task is a self-contained edit + test cycle.

**Tech Stack:** Bash 3.2 test framework (`tests/test-helpers.sh`), Markdown skill files.

---

## File Map

| File | Role | Tasks |
|------|------|-------|
| `skills/incident-analysis/SKILL.md` | Skill definition (source of truth for agent behavior) | 1, 2, 3, 5 |
| `openspec/specs/incident-analysis/spec.md` | Delta spec (contract for code review / regression) | 2, 4 |
| `tests/test-skill-content.sh` | Behavioral contract assertions on SKILL.md content | 1, 2, 3, 5 |
| `tests/test-postmortem-shape.sh` | Postmortem schema regression tests | 4 |

---

### Task 1: Fix Constraint 2 — scope restriction contradicts infrastructure escalation [P1]

**Problem:** Constraint 2 (line 16-18) says all queries MUST be constrained to the specific service or trace ID from Stage 1. But Step 3 infrastructure escalation (line 274-279) requires node-level kubelet/serial/audit checks, and completeness gate Q6 (line 362) asks about systemic risk on other nodes. An agent following Constraint 2 literally will skip the infra queries needed for node-wide incidents.

**Fix:** Narrow Constraint 2 to application-level queries and add an explicit carve-out for infrastructure escalation. The carve-out must be in the constraint itself (not buried in Step 3) so the agent encounters it before it encounters any stage.

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:16-18` (Constraint 2)
- Modify: `tests/test-skill-content.sh` (add assertion for infra carve-out)

- [ ] **Step 1: Write the failing test**

Add to `tests/test-skill-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Scope restriction has infrastructure escalation carve-out
# ---------------------------------------------------------------------------
assert_contains "scope restriction: infra escalation carve-out" "infrastructure escalation" "${SKILL_CONTENT}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-skill-content.sh`
Expected: FAIL on "scope restriction: infra escalation carve-out" — the phrase "infrastructure escalation" does not appear in Constraint 2's text (it appears in Step 3, but the test checks the whole file — verify it actually fails by checking the current text).

Note: The phrase "Infrastructure escalation" already appears at line 274. The test as written would pass on that occurrence. Instead, the test must verify the carve-out lives in the **constraint section**, not just anywhere in the file. Revise:

```bash
# ---------------------------------------------------------------------------
# Scope restriction has infrastructure escalation carve-out
# ---------------------------------------------------------------------------
CONSTRAINT_2_BLOCK=$(sed -n '/### 2\. Scope Restriction/,/### 3\./p' "${SKILL_FILE}")
assert_contains "scope restriction: infra escalation carve-out" "infrastructure escalation" "${CONSTRAINT_2_BLOCK}"
```

Run: `bash tests/test-skill-content.sh`
Expected: FAIL — Constraint 2 block does not currently mention "infrastructure escalation".

- [ ] **Step 3: Fix Constraint 2 in SKILL.md**

Replace lines 16-18 with:

```markdown
### 2. Scope Restriction — No Global Searches During Incidents

During active investigation, all application-level file reads, log queries, and code searches MUST be constrained to the specific service or trace ID identified in Stage 1 (MITIGATE). Global codebase searches (unbounded grep, recursive find) are forbidden. This prevents context window exhaustion and irrelevant noise during time-sensitive debugging.

**Infrastructure escalation exception:** When Step 3 (Single-Service Deep Dive) identifies multi-pod or multi-service failures that indicate a node-level or infrastructure-level root cause, the scope expands to the affected node(s) and their infrastructure signals (kubelet logs, serial console, audit logs, node-level metrics). This escalation is bounded — queries target the specific node(s) implicated by the application-level evidence, not the entire cluster. The completeness gate (Step 8, Q6) may require checking peer nodes for systemic risk; this is also permitted under this exception.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-skill-content.sh`
Expected: All tests PASS including "scope restriction: infra escalation carve-out".

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-skill-content.sh
git commit -m "fix(incident-analysis): add infra escalation carve-out to scope restriction constraint"
```

---

### Task 2: Restore missing safety fields in high-confidence decision record [P1]

**Problem:** The spec (line 233) requires the high-confidence record to include evidence age, veto signals, state fingerprint, and explanation. The SKILL.md template (lines 205-229) is missing all four. Tests only check for broad markers (`CLASSIFY DECISION`, `SIGNALS EVALUATED`) and cannot catch this regression.

**Fix:** Add the four missing fields to the SKILL.md decision record template, and add test assertions for each field. Also update the spec scenario text if needed (the spec already lists them — it's the skill that drifted).

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:205-229` (high-confidence decision record)
- Modify: `tests/test-skill-content.sh` (add assertions for missing fields)

- [ ] **Step 1: Write the failing tests**

Add to `tests/test-skill-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Decision record contains spec-required safety fields
# ---------------------------------------------------------------------------
# Extract the high-confidence decision record template block
HC_RECORD=$(sed -n '/### Decision Record — High Confidence/,/### Decision Record — Medium Confidence/p' "${SKILL_FILE}")
assert_contains "decision record: evidence age field" "Evidence Age" "${HC_RECORD}"
assert_contains "decision record: state fingerprint field" "State Fingerprint" "${HC_RECORD}"
assert_contains "decision record: explanation field" "Explanation" "${HC_RECORD}"
assert_contains "decision record: veto signals field" "VETO" "${HC_RECORD}"
```

- [ ] **Step 2: Run test to verify they fail**

Run: `bash tests/test-skill-content.sh`
Expected: 4 new FAILs — none of these fields exist in the current high-confidence decision record.

- [ ] **Step 3: Update the high-confidence decision record template in SKILL.md**

Replace the template block at lines 205-229 with:

````markdown
```
CLASSIFY DECISION — HIGH CONFIDENCE

Playbook:      <playbook_id> (<playbook_name>)
Confidence:    <confidence>% (margin: <margin>pt over runner-up)
Category:      <category>
Evidence Age:  <seconds since oldest signal query>s (freshness window: <freshness_window_seconds>s)

SIGNALS EVALUATED:
  [detected]            <signal_id> (weight: <w>)
  [detected]            <signal_id> (weight: <w>)
  [not_detected]        <signal_id> (weight: <w>, contradiction: <cw>)
  [unknown_unavailable] <signal_id> (weight: <w>) — excluded from scoring

VETO SIGNALS:
  [not_detected]        <veto_signal_id> — no veto

COVERAGE: <evaluable_weight>/<max_possible> (<coverage>%)

State Fingerprint: <hash or summary of signal states used for EXECUTE recheck>

Explanation:   <one-sentence summary of why this playbook was selected over alternatives>

COMMAND:
  <interpolated command from playbook>

VALIDATION PLAN:
  stabilization_delay: <N>s
  validation_window:   <N>s
  post_conditions:     <list>

Approve to proceed to EXECUTE, or override.
```
````

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-skill-content.sh`
Expected: All tests PASS including the 4 new decision record assertions.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-skill-content.sh
git commit -m "fix(incident-analysis): restore evidence age, veto, fingerprint, explanation in decision record"
```

---

### Task 3: Expand Step 7 synthesis to preserve investigation path material [P2]

**Problem:** Step 7 (line 347-349) tells the agent to synthesize "the timeline and root cause" but the Investigation Path appendix (lines 511-551) expects ruled-out alternatives, hypothesis revisions, and disconfirming evidence. Constraint 4 forbids referencing raw logs after synthesis, so if Step 7 doesn't preserve this material, the agent must either violate the constraint or produce a lossy appendix.

**Fix:** Expand Step 7's synthesis instruction to explicitly list all categories of information that must be preserved. This keeps Constraint 4 intact (no raw log JSON) while ensuring the synthesis is complete enough for the appendix.

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:347-349` (Step 7)
- Modify: `tests/test-skill-content.sh` (add assertion)

- [ ] **Step 1: Write the failing test**

Add to `tests/test-skill-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Step 7 synthesis preserves investigation path material
# ---------------------------------------------------------------------------
STEP7_BLOCK=$(sed -n '/### Step 7: Context Discipline/,/### Step 8/p' "${SKILL_FILE}")
assert_contains "step 7: preserves ruled-out hypotheses" "ruled-out" "${STEP7_BLOCK}"
assert_contains "step 7: preserves hypothesis revisions" "hypothesis revision" "${STEP7_BLOCK}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-skill-content.sh`
Expected: FAIL — Step 7 block does not currently mention "ruled-out" or "hypothesis revision".

- [ ] **Step 3: Expand Step 7 in SKILL.md**

Replace the Step 7 content (lines 347-349) with:

```markdown
### Step 7: Context Discipline — Synthesize

Write a synthesized summary as an explicit output block. The summary MUST include all of the following (not just timeline and root cause):

1. **Timeline:** Chronological sequence of events with UTC timestamps and evidence sources
2. **Root cause:** The primary hypothesis with supporting evidence
3. **Ruled-out hypotheses:** Each alternative considered, the disconfirming evidence found, and why it was eliminated
4. **Hypothesis revisions:** Where the investigation changed direction, what triggered the revision, and what the previous hypothesis was
5. **Completeness gate answers:** Responses to Step 8 questions (captured here so they survive the context boundary)
6. **Inventory and impact:** Pod/replica counts, distribution, user-facing error counts from Steps 2b/2c

From this point forward, reference ONLY this summary (not raw log JSON). See Constraint 4.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-skill-content.sh`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-skill-content.sh
git commit -m "fix(incident-analysis): expand Step 7 synthesis to preserve investigation path material"
```

---

### Task 4: Fix stale "7 section" reference in spec.md [P2]

**Problem:** `openspec/specs/incident-analysis/spec.md` line 37 says "7 section headers" but SKILL.md implements 8 sections. The postmortem shape tests already enforce 8 sections in SKILL.md and check for absence of "7 section" language — but the spec itself is unchecked.

**Fix:** Update spec.md line 37. Add a test assertion to `test-postmortem-shape.sh` that catches stale section-count language in the spec.

**Files:**
- Modify: `openspec/specs/incident-analysis/spec.md:37`
- Modify: `tests/test-postmortem-shape.sh` (add spec consistency check)

- [ ] **Step 1: Write the failing test**

Add to `tests/test-postmortem-shape.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Test 8: No stale "7 section" language in the spec
# ---------------------------------------------------------------------------
SPEC_FILE="${PROJECT_ROOT}/openspec/specs/incident-analysis/spec.md"
if [ -f "${SPEC_FILE}" ]; then
    SPEC_CONTENT="$(cat "${SPEC_FILE}")"
    if printf '%s' "${SPEC_CONTENT}" | grep -qi "7 section headers\|seven section"; then
        _record_fail "spec: no 7-section language" "found '7 section headers' or 'seven section' in spec.md"
    else
        _record_pass "spec: no 7-section language"
    fi
else
    _record_pass "spec: no 7-section language (spec file not present, skip)"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-postmortem-shape.sh`
Expected: FAIL on "spec: no 7-section language" — spec.md line 37 currently says "7 section headers".

- [ ] **Step 3: Fix spec.md**

In `openspec/specs/incident-analysis/spec.md` line 37, change:

```
Then it uses the built-in schema (7 section headers) and writes to `docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md`
```

to:

```
Then it uses the built-in schema (8 section headers) and writes to `docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md`
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-postmortem-shape.sh`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add openspec/specs/incident-analysis/spec.md tests/test-postmortem-shape.sh
git commit -m "fix(incident-analysis): update spec from 7 to 8 section headers"
```

---

### Task 5: Operationalize evidence persistence in EXECUTE and VALIDATE flows [P2]

**Problem:** The Evidence Bundle section (lines 443-464) describes what `pre.json` and `validate.json` should contain and labels when they should be captured, but the actual EXECUTE and VALIDATE stage steps never say "write pre.json" or "write validate.json". In a prompt-driven workflow, the agent follows numbered steps and will skip persistence entirely.

**Fix:** Add explicit evidence-writing steps to EXECUTE (between fingerprint recheck and command execution) and VALIDATE (in each exit path). Reference the Evidence Bundle section for format.

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:386-402` (EXECUTE stage) and `skills/incident-analysis/SKILL.md:425-441` (VALIDATE exit paths)
- Modify: `tests/test-skill-content.sh` (add assertions)

- [ ] **Step 1: Write the failing tests**

Add to `tests/test-skill-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Evidence persistence is operationalized in EXECUTE and VALIDATE
# ---------------------------------------------------------------------------
EXECUTE_BLOCK=$(sed -n '/## EXECUTE/,/## VALIDATE/p' "${SKILL_FILE}")
assert_contains "EXECUTE: write pre.json step" "pre.json" "${EXECUTE_BLOCK}"

VALIDATE_BLOCK=$(sed -n '/## VALIDATE/,/## Evidence Bundle/p' "${SKILL_FILE}")
assert_contains "VALIDATE: write validate.json step" "validate.json" "${VALIDATE_BLOCK}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-skill-content.sh`
Expected: FAIL on both — the EXECUTE block doesn't mention `pre.json` and the VALIDATE block doesn't mention `validate.json`.

Note: Verify the `sed` ranges extract the right blocks. EXECUTE starts at "## EXECUTE" and ends before "## VALIDATE". VALIDATE starts at "## VALIDATE" and ends before "## Evidence Bundle".

- [ ] **Step 3: Add Step 1.5 to EXECUTE in SKILL.md**

After EXECUTE Step 1 (Fingerprint Recheck, ending around line 392) and before Step 2 (Execute Command), insert:

```markdown
### Step 1b: Persist Pre-Execution Evidence

Write the evidence bundle's `pre.json` to `docs/postmortems/evidence/<bundle-id>/pre.json`. Contents: signal states from CLASSIFY, fingerprint snapshot from Step 1, and the final log window (last N entries matching the playbook's signals). All payloads MUST pass through `redact-evidence.sh` before writing. See Evidence Bundle for format and redaction details.

If the playbook specifies `requires_pre_execution_evidence: true`, this step is mandatory — do not proceed to Step 2 without writing `pre.json`.
```

- [ ] **Step 4: Add validate.json writing to each VALIDATE exit path**

In each of the three VALIDATE exit paths, add an evidence persistence line:

**Validated — Success** (after "Record `verification_status: verified`"):
```
- Write `validate.json` to the evidence bundle with validation sample results, post_condition evaluations, and timing data. All payloads MUST pass through `redact-evidence.sh`.
```

**Validated — Failed (ESCALATE)** (after "Record `verification_status: failed`"):
```
- Write `validate.json` to the evidence bundle with the failure evidence, stop_condition trigger details, and timing data. All payloads MUST pass through `redact-evidence.sh`.
```

**Inconclusive** (after presenting options, before the list):
```
- Regardless of which option the user chooses, write `validate.json` to the evidence bundle with the partial results and timing data. All payloads MUST pass through `redact-evidence.sh`.
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/test-skill-content.sh`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-skill-content.sh
git commit -m "fix(incident-analysis): operationalize evidence persistence in EXECUTE and VALIDATE flows"
```

---

## Execution Order

Tasks are independent and can be executed in any order or in parallel. Each task touches different sections of SKILL.md with no overlap. Recommended order for a single agent: 1 → 2 → 3 → 4 → 5 (P1s first).

## Final Verification

After all tasks complete:

```bash
bash tests/run-tests.sh
```

All test suites must pass. Then a single squash or per-task commit strategy depending on preference.
