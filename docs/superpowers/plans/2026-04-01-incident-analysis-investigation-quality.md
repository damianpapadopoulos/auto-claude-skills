# Incident Analysis Investigation Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve investigation quality in the incident-analysis skill: structured timeline extraction, commit-to-log cross-referencing, bounded source analysis expansion, and config-change trigger.

**Architecture:** Four additive text changes to SKILL.md and references/source-analysis.md, plus fixture schema extensions. No new files in the skill directory, no new signals, no structural changes to the stage flow.

**Tech Stack:** Bash 3.2 (tests), Markdown (skill text), JSON (fixtures), jq (test assertions)

**Spec:** `docs/superpowers/specs/2026-04-01-incident-analysis-investigation-quality-design.md`

---

### Task 1: Extend fixture schema and test assertions (Tests first)

**Files:**
- Modify: `tests/test-incident-analysis-output.sh:75-114`
- Modify: `tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json`
- Modify: `tests/fixtures/incident-analysis/README.md:14-29`

- [ ] **Step 1: Add timeline and source analysis assertions to test file**

Insert after the `dom_callers_type` assertion block (after line 113, before `done`):

```bash
    # Timeline completeness (Improvement A)
    timeline_min="$(jq -r '.expected.timeline_events_min // empty' "${fixture_file}")"
    if [ -n "${timeline_min}" ]; then
        if [ "${timeline_min}" -gt 0 ] 2>/dev/null; then
            _record_pass "${fname}: timeline_events_min is positive (${timeline_min})"
        else
            _record_fail "${fname}: timeline_events_min is positive" "got: ${timeline_min}"
        fi
    fi

    timeline_recovery="$(jq -r '.expected.timeline_has_recovery // empty' "${fixture_file}")"
    if [ -n "${timeline_recovery}" ]; then
        case "${timeline_recovery}" in
            true|false)
                _record_pass "${fname}: timeline_has_recovery is boolean (${timeline_recovery})" ;;
            *)
                _record_fail "${fname}: timeline_has_recovery is boolean" "got: ${timeline_recovery}" ;;
        esac
    fi

    # Timeline precision labels (Improvement A)
    precision="$(jq -r '.expected.timeline_precision_labels // empty' "${fixture_file}")"
    if [ -n "${precision}" ]; then
        case "${precision}" in
            true|false)
                _record_pass "${fname}: timeline_precision_labels is boolean (${precision})" ;;
            *)
                _record_fail "${fname}: timeline_precision_labels is boolean" "got: ${precision}" ;;
        esac
    fi

    # Source analysis status (Improvements B, C, D)
    sa_status="$(jq -r '.expected.source_analysis_status // empty' "${fixture_file}")"
    if [ -n "${sa_status}" ]; then
        case "${sa_status}" in
            skipped|reviewed_no_regression|candidate_found|unavailable)
                _record_pass "${fname}: source_analysis_status valid (${sa_status})" ;;
            *)
                _record_fail "${fname}: source_analysis_status valid" \
                  "expected skipped|reviewed_no_regression|candidate_found|unavailable, got: ${sa_status}" ;;
        esac
    fi

    # Analysis basis (Improvement C)
    sa_basis="$(jq -r '.expected.source_analysis_basis // empty' "${fixture_file}")"
    if [ -n "${sa_basis}" ]; then
        case "${sa_basis}" in
            primary_frame|bounded_expansion_same_commit|bounded_expansion_same_package)
                _record_pass "${fname}: source_analysis_basis valid (${sa_basis})" ;;
            *)
                _record_fail "${fname}: source_analysis_basis valid" "got: ${sa_basis}" ;;
        esac
    fi

    # Cross-reference patterns (Improvement B)
    xref="$(jq -r '.expected.cross_reference_patterns // empty' "${fixture_file}")"
    if [ -n "${xref}" ]; then
        case "${xref}" in
            true|false)
                _record_pass "${fname}: cross_reference_patterns is boolean (${xref})" ;;
            *)
                _record_fail "${fname}: cross_reference_patterns is boolean" "got: ${xref}" ;;
        esac
    fi
```

- [ ] **Step 2: Syntax-check the test file**

Run: `bash -n tests/test-incident-analysis-output.sh`
Expected: No output (clean syntax)

- [ ] **Step 3: Add new fields to SpiceDB fixture**

Add to the `expected` object in `tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json`:

```json
    "timeline_events_min": 10,
    "timeline_has_recovery": true,
    "timeline_precision_labels": true,
    "source_analysis_status": "skipped",
    "source_analysis_basis": null,
    "cross_reference_patterns": false
```

Rationale: SpiceDB postmortem has 11 timeline entries, recovery signal exists, Step 4b didn't fire (dependency-failure classification, no recent deploy).

- [ ] **Step 4: Update fixture README with new schema fields**

Add the new fields to the example `expected` object in `tests/fixtures/incident-analysis/README.md`, after the existing `signals_detected` line:

```json
    "timeline_events_min": 5,
    "timeline_has_recovery": true,
    "timeline_precision_labels": true,
    "source_analysis_status": "skipped",
    "source_analysis_basis": null,
    "cross_reference_patterns": false
```

- [ ] **Step 5: Run the test suite to verify fixture validation passes**

Run: `bash tests/test-incident-analysis-output.sh`
Expected: All new assertions pass for the SpiceDB fixture (timeline_events_min positive, timeline_has_recovery boolean, timeline_precision_labels boolean, source_analysis_status valid, cross_reference_patterns boolean). `source_analysis_basis` is null so its assertion is skipped.

- [ ] **Step 6: Commit**

```bash
git add tests/test-incident-analysis-output.sh \
  tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json \
  tests/fixtures/incident-analysis/README.md
git commit -m "test(incident-analysis): add timeline and source analysis fixture assertions"
```

---

### Task 2: Add Step 4.5 — Cross-reference commits with log patterns (Improvement B)

**Files:**
- Modify: `skills/incident-analysis/references/source-analysis.md:80-128`

- [ ] **Step 1: Add Step 4.5 after Step 4 (Check Recent Commits)**

Insert between the end of Step 4 (after line 93 "For monorepos: path-filter to service root if mapping is known.") and before Step 5 (line 95 "### Step 5: Emit Structured Output"):

```markdown
### Step 4.5: Cross-Reference with Observed Errors

For each regression candidate from Step 4:
1. State which observed error pattern(s) from INVESTIGATE Step 2 this change could explain.
   Be specific: "removed null check → could produce the NPE in UserController:142 seen in
   logs at 14:18."
2. State which observed patterns it CANNOT explain. E.g., "this change only affects the
   /users endpoint, but errors were also seen on /diet-suggestions."
3. If no candidate explains the dominant error pattern, note: "no commit explains primary
   error pattern" — this weakens the bad-release hypothesis and should be reflected in
   Step 5 hypothesis formation.
```

- [ ] **Step 2: Update Step 5 output to include cross-reference fields**

In the existing Step 5 structured output example (currently lines 97-114), update the `regression_candidates` entry to add cross-reference fields. Replace the current candidate example:

```yaml
  regression_candidates:
    - commit_sha: "def456..."
      date: "2026-03-24T10:30:00Z"
      summary: "removed null check in getUser()"
      files: ["UserController.java"]
```

With:

```yaml
  regression_candidates:
    - commit_sha: "def456..."
      date: "2026-03-24T10:30:00Z"
      summary: "removed null check in getUser()"
      files: ["UserController.java"]
      explains_patterns: ["NPE in UserController:142", "null user in toDto()"]
      cannot_explain_patterns: ["DEADLINE_EXCEEDED on SpiceDB calls"]
```

Add a NEW example after the existing candidate example for the reviewed-but-unexplaining case (candidates exist but none explain the dominant error — Step 4.5b depends on this distinction):

```yaml
source_analysis:
  status: reviewed_no_regression
  deployed_ref: "v2.3.1"
  resolved_commit_sha: "abc123def456..."
  source_files:
    - path: "src/main/java/com/oviva/user/UserController.java"
      line: 142
      code_context: "user.toDto() — no obvious defect at deployed version"
      status: analyzed
  regression_candidates:
    - commit_sha: "def456..."
      date: "2026-03-24T10:30:00Z"
      summary: "removed null check in getUser()"
      files: ["UserController.java"]
      explains_patterns: []
      cannot_explain_patterns: ["DEADLINE_EXCEEDED on SpiceDB calls"]
  cross_reference_note: "no commit explains primary error pattern — bad-release hypothesis weakened"
```

And update the existing "no regression found" example (currently lines 117-128) for the no-candidates-at-all case (empty list, no cross-reference possible):

```yaml
source_analysis:
  status: reviewed_no_regression
  deployed_ref: "v2.3.1"
  resolved_commit_sha: "abc123def456..."
  source_files:
    - path: "src/main/java/com/oviva/user/UserController.java"
      line: 142
      code_context: "user.toDto() — no obvious defect at deployed version"
      status: analyzed
  regression_candidates: []
  cross_reference_note: null
```

- [ ] **Step 3: Keep Step 5 numbering unchanged**

Step 5 (Emit Structured Output) stays as Step 5. Steps 4.5 and 4.5b are sub-steps of Step 4, not new top-level steps. This matches the spec and avoids unnecessary doc drift.

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/references/source-analysis.md
git commit -m "feat(incident-analysis): add Step 4.5 cross-reference commits with log patterns"
```

---

### Task 3: Add Step 4.5b — Bounded expansion fallback (Improvement C)

**Files:**
- Modify: `skills/incident-analysis/references/source-analysis.md` (after the Step 4.5 added in Task 2)

- [ ] **Step 1: Add Step 4.5b after Step 4.5**

Insert between Step 4.5 (added in Task 2) and Step 5 (Emit Structured Output):

```markdown
### Step 4.5b: Bounded Expansion (conditional)

Gate: `source_analysis.status == reviewed_no_regression` after Step 4.5, AND no candidate's
`explains_patterns` includes the dominant error pattern from INVESTIGATE Step 2. This fires
when: (a) `regression_candidates` is empty, (b) candidates exist but all have empty
`explains_patterns`, OR (c) candidates explain secondary symptoms but not the dominant error.

Expand the search using commit and module proximity:

1. **Same-commit siblings:** Other files changed in the same candidate commits from Step 4
   (i.e., files that were part of the same commit as the analyzed file). Max 5 files,
   excluding lockfiles, generated code, test files, docs. If a candidate is found, stop —
   do not proceed to step 2.
2. **Same-package peers (only if step 1 found no candidate):** Check files in the same
   module/package as the mapped stack frame (e.g., same Java package, same Python module,
   same Go package) that were modified within the 48h window. Max 3 files.

For each expanded file, apply Step 4.5 cross-reference: can this change explain the observed
error patterns?

Output: update `source_analysis` with:
```yaml
  analysis_basis: "primary_frame" | "bounded_expansion_same_commit" | "bounded_expansion_same_package"
```

If expansion still yields no candidate, status remains `reviewed_no_regression` with
`analysis_basis: "bounded_expansion_same_package"` (indicating expansion was attempted).
```

- [ ] **Step 2: Add `analysis_basis` to the Step 5 output examples**

In the Step 5 (Emit Structured Output) examples, add `analysis_basis: "primary_frame"` to both the `candidate_found` and `reviewed_no_regression` examples.

For the `candidate_found` example, add after `status:`:
```yaml
  analysis_basis: "primary_frame"
```

For the `reviewed_no_regression` example, add after `status:`:
```yaml
  analysis_basis: "primary_frame"
```

- [ ] **Step 3: Update Scope Constraints to include expansion bounds**

In the Scope Constraints section (currently line 140), update the "Bounded" bullet:

Replace:
```
- **Bounded:** Max 1-2 top actionable stack frames, 1-2 files, last 3 commits within 48h.
```

With:
```
- **Bounded:** Max 1-2 top actionable stack frames, 1-2 primary files, last 3 commits within
  48h. Bounded expansion (Step 4.5b): max 5 same-commit siblings + 3 same-package peers.
```

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/references/source-analysis.md
git commit -m "feat(incident-analysis): add Step 4.5b bounded expansion fallback"
```

---

### Task 4: Expand Step 4b gate for config-change trigger + user override (Improvement D)

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:496-514`
- Modify: `skills/incident-analysis/references/source-analysis.md:1-21`

- [ ] **Step 1: Update source-analysis.md header and gate**

Replace lines 1-4 of `references/source-analysis.md`:

```markdown
# Step 4b: Source Analysis — Reference Procedure

Conditional step within INVESTIGATE. Analyzes source code at the deployed version
when actionable stack traces are available and a bad-release scenario is plausible.
```

With:

```markdown
# Step 4b: Source Analysis — Reference Procedure

Conditional step within INVESTIGATE. Analyzes source code at the deployed version
when actionable stack traces are available and a bad-release or repo-backed
config-change scenario is plausible.
```

- [ ] **Step 2: Update source-analysis.md gate conditions**

Replace lines 6-21 (the Gate Conditions section) with:

```markdown
## Gate Conditions

All must be true (bad-release path):
1. **Bad-release gate:** `recent_deploy_detected` signal is detected, OR deploy timestamp
   falls within the incident window or within 4 hours before incident start.
2. **Actionable stack frame:** At least one stack frame from Step 2 resolves to a source file
   (not minified, compiled, or generated code). Skip frames from third-party libraries.
3. **Resolvable deployed ref:** Deployment metadata provides an image tag or SHA that can be
   mapped to a git ref.

OR all must be true (config-change path):
1. **Config-change gate:** `config_change_correlated_with_errors` signal is detected AND
   the config change is repo-backed (has a git ref — e.g., Helm chart in a config repo,
   application.yaml in the service repo). ConfigMap-only or console-applied changes without
   a git ref do NOT trigger this path.
2. **Actionable stack frame:** Same as above.
3. **Resolvable deployed ref:** Same as above.

When triggered via the config-change path, the procedure is identical but Step 4 (Check
Recent Commits) prioritizes config files (*.yaml, *.properties, *.json, *.toml, *.env)
alongside source files in the commit search.

**User override:** If the user explicitly requests source analysis (e.g., "check the changes
in the service code"), bypass the category gate (condition 1 in either path) but NOT the
other bounds. Conditions 2-3 remain enforced. The procedure, scope constraints, token budget,
and bounded-evidence rules are unchanged.

If no gate is met and no user override, skip with structured output:
```yaml
source_analysis:
  status: skipped
  skip_reason: "no actionable stack frame" | "deployed ref unresolvable" | "not bad-release or config-change category"
```
```

- [ ] **Step 3: Update SKILL.md Step 4b gate**

Replace lines 500-505 in SKILL.md:

```markdown
**Gate — all required:**
1. Actionable stack frame from Step 2 (skip minified/compiled/generated frames)
2. Resolvable deployed ref (image tag or SHA from Step 2b deployment metadata)
3. Bad-release category: `recent_deploy_detected` signal detected, OR deploy within incident window, OR deploy within 4 hours before incident start. Config-regression, dependency-failure, and infra-failure do **not** trigger this step.

**If any condition is not met:** Set `source_analysis.status: skipped` with `skip_reason` and proceed to Step 5.
```

With:

```markdown
**Gate — all required (bad-release path):**
1. Actionable stack frame from Step 2 (skip minified/compiled/generated frames)
2. Resolvable deployed ref (image tag or SHA from Step 2b deployment metadata)
3. Bad-release category: `recent_deploy_detected` signal detected, OR deploy within incident window, OR deploy within 4 hours before incident start.

**OR all required (config-change path):**
1. Actionable stack frame from Step 2
2. Resolvable deployed ref
3. `config_change_correlated_with_errors` signal detected AND config change is repo-backed (has a git ref). ConfigMap-only or console-applied changes do not trigger this path.

**User override:** If the user explicitly requests source analysis, bypass the category gate (condition 3) but NOT conditions 1-2 or the procedure bounds.

**If no gate is met:** Set `source_analysis.status: skipped` with `skip_reason` and proceed to Step 5.
```

- [ ] **Step 4: Update SKILL.md Step 4b procedure line**

In SKILL.md line 514, update the procedure summary to include the new sub-steps. Replace:

```
5. Emit structured output: `source_analysis.status` (`reviewed_no_regression` | `candidate_found` | `skipped` | `unavailable`), `source_files[]`, `regression_candidates[]`
```

With:

```
4.5. Cross-reference candidates with observed log patterns (`explains_patterns[]`, `cannot_explain_patterns[]`)
4.5b. If no candidate explains dominant error: bounded expansion (same-commit siblings, then same-package peers)
5. Emit structured output: `source_analysis.status`, `source_files[]`, `regression_candidates[]`, `analysis_basis`
```

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md skills/incident-analysis/references/source-analysis.md
git commit -m "feat(incident-analysis): add config-change source analysis trigger and user override"
```

---

### Task 5: Add Step 6b — Timeline extraction (Improvement A)

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:546-566`

- [ ] **Step 1: Add Step 6b after Step 6 (Flight Plan)**

Insert between Step 6 (Flight Plan, ending at line 553) and Step 7 (Context Discipline — Synthesize, starting at line 555). Add:

```markdown
### Step 6b: Timeline Extraction

Before synthesizing (Step 7), extract candidate timeline events from all evidence collected during Steps 1-5. This gives Step 7 a structured input rather than relying on attention-based reconstruction.

For each timestamped event found in collected evidence, extract:
- **timestamp_utc:** the event timestamp in UTC
- **time_precision:** `exact` (from log/metric timestamp with second-level or better granularity), `minute` (from deploy event, alert firing, or minute-resolution metric), or `approximate` (from user report, estimated from context)
- **event_kind:** one of `log_entry` | `metric_alert` | `deploy_event` | `probe_event` | `user_report` | `recovery_signal`
- **description:** one-sentence description of what happened
- **evidence_source:** where this was observed (e.g., "SpiceDB gRPC logs", "k8s events")

**Dedupe rules:**
- If two events describe the same occurrence at different precisions, keep the higher-precision entry. E.g., "~14:18 SpiceDB spike" (approximate, user report) is superseded by "14:18:23 CheckPermission 4335ms" (exact, gRPC log).
- If `log_entry` and `metric_alert` cover the same moment, keep both — they are different evidence types for the same event.
- Deploy events from deployment metadata and from audit logs are the same event; keep the one with more detail.

**Scope:** Steps 1-5 evidence only. Exclude Flight Plan items (Step 6) — those are proposed actions, not observed events.

Sort chronologically. Present the candidate list to Step 7 for curation into the final timeline.
```

- [ ] **Step 2: Update Step 7 timeline instruction**

In Step 7 (Context Discipline — Synthesize), replace the timeline instruction (line 559):

```markdown
1. **Timeline:** Chronological sequence of events with UTC timestamps and evidence sources
```

With:

```markdown
1. **Timeline:** Curate the candidate timeline from Step 6b into the final timeline. Remove noise, merge related events, verify chronological ordering. Each entry retains `time_precision` and `evidence_source` from Step 6b. Flag any candidate events removed during curation (and why) so the completeness gate can assess coverage.
```

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add Step 6b timeline extraction with precision labels"
```

---

### Task 6: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Syntax-check SKILL.md references**

Run: `bash -n skills/incident-analysis/scripts/redact-evidence.sh`
Expected: No output (clean syntax — verifies the only bash file in the skill directory)

- [ ] **Step 2: Run incident-analysis output tests**

Run: `bash tests/test-incident-analysis-output.sh`
Expected: All assertions pass including the new timeline and source analysis fields.

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All test suites pass.

- [ ] **Step 4: Verify no broken markdown references**

Run: `grep -n 'source-analysis.md' skills/incident-analysis/SKILL.md`
Expected: Reference to `references/source-analysis.md` is present and unchanged.

Run: `grep -c '### Step' skills/incident-analysis/references/source-analysis.md`
Expected: 7 step headers (1, 2, 3, 4, 4.5, 4.5b, 5).

- [ ] **Step 5: Verify step numbering consistency between SKILL.md and source-analysis.md**

SKILL.md Step 4b procedure summary should list steps 1-5 with sub-steps 4.5 and 4.5b matching source-analysis.md. Verify with:

Run: `grep -A 12 'Procedure.*Follow' skills/incident-analysis/SKILL.md | head -14`
Expected: Steps 1 through 5 listed, with 4.5 (cross-reference) and 4.5b (bounded expansion) between 4 and 5.
