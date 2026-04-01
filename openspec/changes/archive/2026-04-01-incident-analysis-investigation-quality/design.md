# Design: Incident Analysis Investigation Quality

## Architecture
Four additive text changes within the existing MITIGATE → CLASSIFY → INVESTIGATE → EXECUTE →
VALIDATE → POSTMORTEM pipeline. No structural changes to the stage flow.

- **Step 6b (SKILL.md):** Inserted between Flight Plan (Step 6) and Synthesis (Step 7).
  Extracts candidate events with timestamp_utc, time_precision, event_kind, description,
  evidence_source. Step 7 curates rather than reconstructs.
- **Steps 4.5/4.5b (source-analysis.md):** Sub-steps within Step 4b, between Check Recent
  Commits (Step 4) and Emit Structured Output (Step 5). 4.5 cross-references, 4.5b expands.
- **Gate expansion (both files):** Alternate config-change path added to Step 4b gate using
  existing config_change_correlated_with_errors signal. User override bypasses category only.

## Dependencies
No new dependencies. Uses existing signals.yaml signal, existing jq in tests.

## Decisions & Trade-offs

### Commit/module proximity over directory recency (Step 4.5b)
Expansion searches same-commit siblings then same-package peers, NOT most-recently-modified
files in the service directory. Directory recency pulls unrelated churn in monorepos.

### Three distinct output shapes (Step 4.5)
candidate_found, reviewed-but-unexplaining (candidates kept with empty explains_patterns),
and no-candidates (empty list). Step 4.5b gate depends on this distinction.

### time_precision in synthesis only
Precision labels survive in Step 7 synthesis (investigation metadata) but are NOT carried
into the final postmortem timeline table. The postmortem is for human readers.

### Config-change gate stays repo-backed
Both paths require resolvable deployed ref. ConfigMap-only or console-applied changes
without a git ref do not trigger Step 4b. This prevents blurring code analysis with
runtime-config investigation.
