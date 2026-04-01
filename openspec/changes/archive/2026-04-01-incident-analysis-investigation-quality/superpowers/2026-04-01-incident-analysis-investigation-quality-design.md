# Incident Analysis Investigation Quality Improvements — Design Document

**Date:** 2026-04-01
**Origin:** Comparison with [Google SRE Gemini CLI blog](https://cloud.google.com/blog/topics/developers-practitioners/how-google-sres-use-gemini-cli-to-solve-real-world-outages) (Steps 3-4) and [palladius/gemini-cli-custom-commands](https://github.com/palladius/gemini-cli-custom-commands) postmortem-generator + cloud-build-investigation skills
**Method:** Brainstorming with iterative refinement, validated against SpiceDB postmortem (2026-03-09-ocs-spicedb-latency-cascade.md)

## Problem Statement

Our incident-analysis skill has a strong investigation pipeline (MITIGATE → CLASSIFY →
INVESTIGATE → EXECUTE → VALIDATE → POSTMORTEM) with caller-layer analysis, confidence-gated
playbook scoring, and evidence bundles. Comparing against Google's SRE Gemini CLI workflow
and Palladius's custom skills revealed four gaps in investigation quality — not in the
pipeline structure, but in how evidence is extracted, correlated, and carried into the
postmortem.

### Gaps Identified (validated against SpiceDB incident)

1. **Timeline reconstruction from memory.** Step 7 (Synthesize) asks the LLM to reconstruct
   the timeline from attention over all prior investigation steps. Events get dropped. The
   SpiceDB postmortem has 11 timeline entries; a structured extraction pass would likely
   catch additional events from the dozens of queries executed during investigation.

2. **Code-centric, not log-pattern-aware source analysis.** Step 4b checks recent commits
   for regression indicators but doesn't ask "which observed error pattern could this change
   produce?" The analysis finds suspicious code but doesn't connect it to the specific errors
   seen in production logs.

3. **Source analysis stops at the stack-frame file.** When the stack-frame-mapped file shows
   no regression, Step 4b ends. But the culprit may be in a sibling file changed in the same
   commit or the same package.

4. **Config-change incidents skip source analysis entirely.** Step 4b gates on bad-release
   category only. Repo-backed config changes (Helm charts, application.yaml) that correlate
   with errors have a resolvable git ref but don't trigger code analysis because they're
   classified as config-regression, not bad-release.

### What was evaluated and dropped

- **Action item → issue filing:** Workflow integration concern, not investigation quality.
  Dropped by user decision.
- **Folder-level context passing:** Google's monorepo pattern ("check /path/to/service/")
  doesn't translate — risks context window exhaustion. Bounded expansion (Improvement C)
  captures the same value safely.
- **Broad source analysis gate relaxation:** `infra_signals_clear AND tier1_app_errors_detected`
  fires on nearly every application incident, making Step 4b noisy. Replaced with specific
  config-change trigger (Improvement D).
- **Structured CSV timeline intermediate:** Marginal improvement over current synthesis for
  typical incident scale (~10-15 events).
- **Fix generation in Flight Plan:** Complex incidents need architectural fixes, not patches.
  Our Flight Plan approach (files/logic/outcome) is already appropriate.

---

## Improvement A: Timeline Extraction Step (Step 6b)

**Placement:** New Step 6b in SKILL.md, between Flight Plan (Step 6) and Synthesis (Step 7).

### Specification

```markdown
### Step 6b: Timeline Extraction

Before synthesizing (Step 7), extract candidate timeline events from all evidence
collected during Steps 1-5. This gives Step 7 a structured input rather than
relying on attention-based reconstruction.

For each timestamped event found in collected evidence, extract:
- timestamp_utc: the event timestamp in UTC
- time_precision: "exact" (from log/metric timestamp with second-level or better
  granularity), "minute" (from deploy event, alert firing, or minute-resolution
  metric), or "approximate" (from user report, estimated from context)
- event_kind: one of log_entry | metric_alert | deploy_event | probe_event |
  user_report | recovery_signal
- description: one-sentence description of what happened
- evidence_source: where this was observed (e.g., "SpiceDB gRPC logs", "k8s events")

Dedupe rules:
- If two events describe the same occurrence at different precisions, keep the
  higher-precision entry. E.g., "~14:18 SpiceDB spike" (approximate, user report)
  is superseded by "14:18:23 CheckPermission 4335ms" (exact, gRPC log).
- If log_entry and metric_alert cover the same moment, keep both — they are
  different evidence types for the same event.
- Deploy events from deployment metadata and from audit logs are the same event;
  keep the one with more detail.

Scope: Steps 1-5 evidence only. Exclude Flight Plan items (Step 6) — those are
proposed actions, not observed events.

Sort chronologically. Present the candidate list to Step 7 for curation into
the final timeline.
```

### Step 7 Update

Change the existing Step 7 timeline instruction from:

> 1. **Timeline:** Chronological sequence of events with UTC timestamps and evidence sources

To:

> 1. **Timeline:** Curate the candidate timeline from Step 6b into the final timeline. Remove
>    noise, merge related events, verify chronological ordering. Each entry retains
>    `time_precision` and `evidence_source` from Step 6b. Flag any candidate events removed
>    during curation (and why) so the completeness gate can assess coverage.

### Files Changed

- `skills/incident-analysis/SKILL.md` — Add Step 6b (~120 words), update Step 7 timeline
  instruction (~40 words)

---

## Improvement B: Cross-Reference Commits with Log Patterns (Step 4.5)

**Placement:** New Step 4.5 in `references/source-analysis.md`, after Step 4 (Check Recent
Commits), before Step 5 (Emit Structured Output).

### Specification

```markdown
### Step 4.5: Cross-Reference with Observed Errors

For each regression candidate from Step 4:
1. State which observed error pattern(s) from INVESTIGATE Step 2 this change
   could explain. Be specific: "removed null check → could produce the NPE
   in UserController:142 seen in logs at 14:18."
2. State which observed patterns it CANNOT explain. E.g., "this change only
   affects the /users endpoint, but errors were also seen on /diet-suggestions."
3. If no candidate explains the dominant error pattern, note: "no commit
   explains primary error pattern" — this weakens the bad-release hypothesis
   and should be reflected in Step 5 hypothesis formation.
```

### Output Extension

Add to each `regression_candidates[]` entry in Step 5 structured output:

```yaml
regression_candidates:
  - commit_sha: "def456..."
    date: "2026-03-24T10:30:00Z"
    summary: "removed null check in getUser()"
    files: ["UserController.java"]
    explains_patterns: ["NPE in UserController:142", "null user in toDto()"]
    cannot_explain_patterns: ["DEADLINE_EXCEEDED on SpiceDB calls"]
```

When candidates were reviewed but none explain the dominant error, keep the candidates
(so Step 4.5b can distinguish "no candidates found" from "candidates reviewed and ruled
out") and add the weakening note:

```yaml
regression_candidates:
  - commit_sha: "def456..."
    date: "2026-03-24T10:30:00Z"
    summary: "removed null check in getUser()"
    files: ["UserController.java"]
    explains_patterns: []
    cannot_explain_patterns: ["DEADLINE_EXCEEDED on SpiceDB calls"]
cross_reference_note: "no commit explains primary error pattern — bad-release hypothesis weakened"
```

When Step 4 found no commits at all (empty candidate list before cross-reference):

```yaml
regression_candidates: []
cross_reference_note: null
```

### Files Changed

- `skills/incident-analysis/references/source-analysis.md` — Add Step 4.5 (~80 words),
  update Step 5 output examples (~30 words)

---

## Improvement C: Bounded Expansion Fallback (Step 4.5b)

**Placement:** New Step 4.5b in `references/source-analysis.md`, after Step 4.5, before
Step 5. Conditional — only fires when primary analysis found no regression.

### Design Constraint

The current source-analysis.md is intentionally bounded: 1-2 stack-mapped files, last 3
commits, same service (source-analysis.md lines 54, 82, 142). The expansion MUST use
commit and module proximity, NOT directory recency. "5 most recently modified files in the
service directory" pulls unrelated churn in monorepos and is explicitly rejected.

### Specification

```markdown
### Step 4.5b: Bounded Expansion (conditional)

Gate: source_analysis.status == reviewed_no_regression after Step 4.5, AND
no candidate's explains_patterns includes the dominant error pattern from
INVESTIGATE Step 2. This fires when: (a) regression_candidates is empty,
(b) candidates exist but all have empty explains_patterns, OR (c) candidates
explain secondary symptoms but not the dominant error.

Expand the search using commit and module proximity:

1. **Same-commit siblings:** Other files changed in the same candidate commits
   from Step 4 (i.e., files that were part of the same commit as the analyzed
   file). Max 5 files, excluding lockfiles, generated code, test files, docs.
   If a candidate is found, stop — do not proceed to step 2.
2. **Same-package peers (only if step 1 found no candidate):** Check files in
   the same module/package as the mapped stack frame (e.g., same Java package,
   same Python module, same Go package) that were modified within the 48h
   window. Max 3 files.

For each expanded file, apply Step 4.5 cross-reference: can this change explain
the observed error patterns?

Output: update source_analysis with:
  analysis_basis: "primary_frame" | "bounded_expansion_same_commit" |
                  "bounded_expansion_same_package"

If expansion still yields no candidate, status remains reviewed_no_regression
with analysis_basis: "bounded_expansion_same_package" (indicating expansion
was attempted).
```

### Scope Constraints

- Same service only (unchanged from parent Step 4b)
- Same 48h window (unchanged)
- Read-only (unchanged)
- No blame analysis (unchanged)
- Total expanded file count: max 8 (5 same-commit + 3 same-package)

### Files Changed

- `skills/incident-analysis/references/source-analysis.md` — Add Step 4.5b (~100 words),
  add `analysis_basis` to Step 5 output contract

---

## Improvement D: Config-Change Source Analysis Trigger

**Placement:** Expanded gate condition in SKILL.md Step 4b and
`references/source-analysis.md` Gate Conditions section.

### Design Constraint

Step 4b is defined as code-at-deployed-ref analysis. The gate requires a resolvable deployed
ref (image tag or SHA). This constraint is preserved. The `config_change_correlated_with_errors`
signal already exists in `signals.yaml` (line 243) and is used by the `config-regression`
playbook (`config-regression.yaml`). No new signals are needed.

Config-only incidents (ConfigMap console edit, Secret rotation without git backing) do NOT
have a resolvable ref and therefore do NOT trigger this path. This is intentional — Step 4b
analyzes code/config at a git ref, not runtime state.

### Specification — Automatic Gate

Add an alternate gate condition to Step 4b:

```markdown
**Gate — all required:**
1. Actionable stack frame from Step 2 (skip minified/compiled/generated frames)
2. Resolvable deployed ref (image tag or SHA from Step 2b deployment metadata)
3. Bad-release category: `recent_deploy_detected` signal detected, OR deploy
   within incident window, OR deploy within 4 hours before incident start.
   Config-regression, dependency-failure, and infra-failure do **not** trigger
   this step.

**OR (config-change alternate, all required):**
1. Actionable stack frame from Step 2
2. Resolvable deployed ref (same constraint as above)
3. `config_change_correlated_with_errors` signal detected
4. Config change is repo-backed (has a git ref — e.g., Helm chart in a config
   repo, application.yaml in the service repo). ConfigMap-only or
   console-applied changes without a git ref do NOT trigger this path.

When triggered via the config-change path, the procedure is identical (same
Steps 1-5 in source-analysis.md) but Step 4 (Check Recent Commits) prioritizes
config files (*.yaml, *.properties, *.json, *.toml, *.env) alongside source
files in the commit search.
```

### Specification — User Override

```markdown
**User override:** If the user explicitly requests source analysis (e.g., "check
the changes in the service code", "look at the source"), bypass the category
gate (condition 3 in either path) but NOT the other bounds. Conditions 1-2
remain enforced: actionable stack frame and resolvable deployed ref. The
procedure, scope constraints, token budget, and bounded-evidence rules are
unchanged.
```

### Files Changed

- `skills/incident-analysis/SKILL.md` — Expand Step 4b gate (~75 words), update
  `skip_reason` example from `"not bad-release category"` to
  `"not bad-release or config-change category"`
- `skills/incident-analysis/references/source-analysis.md` — Update Gate Conditions
  section (~30 words), add config-file priority note to Step 4, update header from
  "a bad-release scenario is plausible" (line 3-4) to cover config-change, update
  `skip_reason` enum in skip example (line 17) to include the config-change case

---

## Tests

### Fixture Schema Updates

The current `test-incident-analysis-output.sh` validates fixture schema and optional
`expected` fields. It does NOT execute the skill or validate actual investigation behavior.
The changes below extend the fixture schema to express expectations about timeline and
source analysis, validated structurally against fixture JSON.

**New optional fields in fixture `expected` object:**

```json
{
  "expected": {
    "timeline_events_min": 5,
    "timeline_has_recovery": true,
    "timeline_precision_labels": true,
    "source_analysis_status": "skipped",
    "source_analysis_basis": null,
    "cross_reference_patterns": false
  }
}
```

### Test Assertions

Add to `test-incident-analysis-output.sh`:

```bash
# Timeline completeness (Improvement A)
timeline_min="$(jq -r '.expected.timeline_events_min // empty' "$fixture_file")"
if [ -n "$timeline_min" ]; then
    if [ "$timeline_min" -gt 0 ] 2>/dev/null; then
        _record_pass "${fname}: timeline_events_min is positive ($timeline_min)"
    else
        _record_fail "${fname}: timeline_events_min is positive" "got: $timeline_min"
    fi
fi

timeline_recovery="$(jq -r '.expected.timeline_has_recovery // empty' "$fixture_file")"
if [ -n "$timeline_recovery" ]; then
    case "$timeline_recovery" in
        true|false)
            _record_pass "${fname}: timeline_has_recovery is boolean ($timeline_recovery)" ;;
        *)
            _record_fail "${fname}: timeline_has_recovery is boolean" "got: $timeline_recovery" ;;
    esac
fi

# Timeline precision labels (Improvement A)
precision="$(jq -r '.expected.timeline_precision_labels // empty' "$fixture_file")"
if [ -n "$precision" ]; then
    case "$precision" in
        true|false)
            _record_pass "${fname}: timeline_precision_labels is boolean ($precision)" ;;
        *)
            _record_fail "${fname}: timeline_precision_labels is boolean" "got: $precision" ;;
    esac
fi

# Source analysis status (Improvements B, C, D)
sa_status="$(jq -r '.expected.source_analysis_status // empty' "$fixture_file")"
if [ -n "$sa_status" ]; then
    case "$sa_status" in
        skipped|reviewed_no_regression|candidate_found|unavailable)
            _record_pass "${fname}: source_analysis_status valid ($sa_status)" ;;
        *)
            _record_fail "${fname}: source_analysis_status valid" \
              "expected skipped|reviewed_no_regression|candidate_found|unavailable, got: $sa_status" ;;
    esac
fi

# Analysis basis (Improvement C)
sa_basis="$(jq -r '.expected.source_analysis_basis // empty' "$fixture_file")"
if [ -n "$sa_basis" ]; then
    case "$sa_basis" in
        primary_frame|bounded_expansion_same_commit|bounded_expansion_same_package)
            _record_pass "${fname}: source_analysis_basis valid ($sa_basis)" ;;
        *)
            _record_fail "${fname}: source_analysis_basis valid" "got: $sa_basis" ;;
    esac
fi

# Cross-reference patterns (Improvement B)
xref="$(jq -r '.expected.cross_reference_patterns // empty' "$fixture_file")"
if [ -n "$xref" ]; then
    case "$xref" in
        true|false)
            _record_pass "${fname}: cross_reference_patterns is boolean ($xref)" ;;
        *)
            _record_fail "${fname}: cross_reference_patterns is boolean" "got: $xref" ;;
    esac
fi
```

### SpiceDB Fixture Extension

Update `tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json` to include
the new fields:

```json
{
  "expected": {
    "timeline_events_min": 10,
    "timeline_has_recovery": true,
    "timeline_precision_labels": true,
    "source_analysis_status": "skipped",
    "source_analysis_basis": null,
    "cross_reference_patterns": false
  }
}
```

Rationale:
- `timeline_events_min: 10` — the SpiceDB postmortem has 11 verified entries
- `timeline_has_recovery: true` — recovery signal exists (SpiceDB self-recovered ~16:00)
- `source_analysis_status: skipped` — no recent deploy, dependency-failure classification
- `source_analysis_basis: null` — Step 4b didn't fire
- `cross_reference_patterns: false` — Step 4.5 didn't fire

### README.md Update

Add the new fields to the fixture schema example in
`tests/fixtures/incident-analysis/README.md`.

### Files Changed

- `tests/test-incident-analysis-output.sh` — Add fixture assertions (~40 lines)
- `tests/fixtures/incident-analysis/2026-03-09-ocs-spicedb-cascade.json` — Add new fields
- `tests/fixtures/incident-analysis/README.md` — Update schema example

---

## Summary

| ID | Improvement | File | Change Size |
|----|-------------|------|-------------|
| A | Timeline Extraction (Step 6b) | `SKILL.md` | ~160 words |
| B | Cross-Reference Commits with Logs (Step 4.5) | `references/source-analysis.md` | ~110 words |
| C | Bounded Expansion Fallback (Step 4.5b) | `references/source-analysis.md` | ~100 words |
| D | Config-Change Trigger + User Override | `SKILL.md` + `references/source-analysis.md` | ~105 words |
| T | Fixture schema + SpiceDB fixture + test assertions | tests/ | ~60 lines |

**Total skill text:** ~475 words across 2 files. No new files in the skill directory, no
new signals, no new playbooks, no structural changes to the stage flow.

**Total test changes:** ~60 lines across 3 test/fixture files.

## Guardrails

1. **Step 4b stays repo-backed.** Both the existing bad-release gate and the new
   config-change gate require a resolvable deployed ref. No config-only incidents without
   a git ref.
2. **Expansion uses commit/module proximity, not directory recency.** Step 4.5b explicitly
   rejects "most recently modified files in the service directory."
3. **Tests validate fixture schema, not skill execution.** The test assertions confirm
   fixtures are well-formed and carry the new fields. They do not execute the skill or
   validate investigation behavior — that remains the eval runner's responsibility (future
   PR, gated on real incident fixtures).
4. **User override bypasses category only.** The override relaxes the bad-release/config
   category requirement but preserves actionable-stack-frame, resolvable-ref, scope
   constraints, and token budget.
5. **No new signals or playbooks.** Improvement D uses the existing
   `config_change_correlated_with_errors` signal from `signals.yaml`.

## Shipping Order

Single PR — all four improvements plus tests. The changes are cohesive (all touch source
analysis or postmortem quality within the same skill) and small enough (~475 words + 60 lines)
to review atomically. No cross-PR dependencies.

## Assumptions

1. The `config_change_correlated_with_errors` signal's `temporal_correlation` detection
   method is sufficient to identify repo-backed config changes. If a config change has no
   log evidence (silent config push), this gate will not fire — that is acceptable.
2. Step 6b timeline extraction is behavioral (LLM instruction), not programmatic. Its
   effectiveness depends on the LLM attending to all prior evidence. The dedupe rules and
   structured output format improve this but do not guarantee completeness.
3. The SpiceDB fixture extension uses ground truth from the human-authored postmortem, not
   from running the skill — consistent with the fixture authoring rules in README.md.
4. Step 4.5b fires when no candidate's `explains_patterns` includes the dominant error
   pattern. This covers three cases: no candidates found, candidates with empty
   `explains_patterns`, and candidates that explain secondary symptoms but not the dominant
   error. All three mean "primary analysis didn't find the cause of the main problem."
5. `time_precision` labels survive in the Step 7 synthesis block (investigation metadata)
   but are NOT carried into the final postmortem timeline table. The postmortem is for human
   readers; precision labels are investigation provenance.
