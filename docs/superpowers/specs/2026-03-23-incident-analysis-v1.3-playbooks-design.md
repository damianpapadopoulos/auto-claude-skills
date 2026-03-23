# Incident Analysis v1.3: Confidence-Gated Playbooks with Sanitized Evidence and Validation

**Date:** 2026-03-23
**Status:** Draft
**Phase:** DESIGN
**Builds on:** v1.0 (tiered investigation), v1.1 (trace correlation), v1.2 (postmortem permalinks)

## Summary

Extend the existing incident-analysis skill into a confidence-gated mitigation system: MITIGATE -> CLASSIFY -> (HITL or INVESTIGATE loop) -> EXECUTE -> VALIDATE -> POSTMORTEM. Keep the GCP-first investigation core, add GKE and GitHub deployment/workflow context as evidence and parameter sources, and preserve the existing 7-section postmortem shape.

The design is inspired by Google's ProductionAgent approach (executable playbooks with safety checks) and the O'Reilly generic mitigations taxonomy (Rollback, Data Rollback, Degrade, Upsize, Block List, Drain, Quarantine), adapted for the open-tool ecosystem (kubectl, gcloud, gh CLI).

## Core Design Decisions

1. **Hybrid playbook model** (Option C) — core decision logic embedded in the skill, actual playbook definitions in external YAML files. Bundled defaults in `skills/incident-analysis/playbooks/`, repo-local overrides in `playbooks/incident-analysis/`. Resolution by `id`, repo-local replaces bundled.

2. **Confidence-gated routing** (Option C) — autonomous proposal for high confidence, targeted investigation for medium, full deep dive for low. Confidence is a deterministic routing score, not a calibrated probability.

3. **Always-on counterevidence** — both >= 85 and 60-84 paths show supporting AND contradictory signals. The agent never looks overconfident.

4. **Execution boundary** — approval -> fingerprint recheck -> execute -> validate. Approval does not guarantee execution; drift invalidates the command.

5. **Evidence freshness** — if the user has not approved the proposal within `freshness_window_seconds` of evidence collection, the proposal is retracted and the flow returns to CLASSIFY with fresh queries. Stale evidence cannot be acted upon.

## State Machine

```
MITIGATE --> CLASSIFY
                |
                |-- confidence >= 85
                |     (requires ALL of: exactly one playbook selected,
                |      no veto signals, coverage >= 0.70,
                |      all params resolved, pre_conditions passed,
                |      margin over incompatible runner-up >= 15)
                |
                |     Show: command, supporting signals, contradictory signals,
                |           state fingerprint, explanation, coverage, evidence age
                |     --> HITL GATE (await approval)
                |              |
                |          [approval]
                |              |
                |          fingerprint recheck
                |              |
                |          drift? --YES--> back to CLASSIFY (state changed;
                |                          re-score with updated fingerprint)
                |              |
                |             NO
                |              |
                |          EXECUTE (run command / confirm user ran it)
                |              |
                |          VALIDATE
                |              |
                |          Phase 1: Stabilization grace period
                |          (wait stabilization_delay_seconds)
                |          Only hard_stop_conditions are active.
                |              |
                |          hard_stop during grace? --YES--> ESCALATE -> INVESTIGATE
                |              |
                |             NO (grace period expires)
                |              |
                |          Phase 2: Observation window
                |          (sample every sample_interval_seconds
                |           for validation_window_seconds)
                |          Both hard_stop_conditions AND stop_conditions active.
                |          post_conditions evaluated at each sample.
                |              |
                |          hard_stop during observation? --YES--> ESCALATE -> INVESTIGATE
                |          stop_condition during observation? --YES--> ESCALATE -> INVESTIGATE
                |              |
                |             NO (observation window expires)
                |              |
                |          post_conditions met?
                |              |-- YES --> POSTMORTEM
                |              |-- NO  --> ESCALATE -> INVESTIGATE
                |              |-- INCONCLUSIVE --> user choice
                |                   (extend observation / escalate /
                |                    accept as mitigated but unverified)
                |
                |-- confidence 60-84
                |     Show: hypotheses, supporting signals, contradictory signals,
                |           unknown/unavailable signals, suggested follow-up queries
                |     --> targeted read-only follow-up queries
                |     --> back to CLASSIFY (recalculate with new evidence)
                |
                |-- confidence < 60
                      --> INVESTIGATE (existing deep dive, Steps 1-5 only:
                          log queries, signal extraction, deep dive,
                          trace correlation, root cause hypothesis.
                          Steps 6-8 are SKIPPED -- no Flight Plan,
                          no context synthesis, no POSTMORTEM transition.
                          Findings feed back to CLASSIFY.)
                      --> back to CLASSIFY (recalculate with new evidence)
```

### State Machine Invariants

1. The >= 85 path to HITL GATE requires ALL of: confidence >= 85 AND exactly one playbook selected AND no veto signals detected AND coverage_ratio >= 0.70 AND all required parameters resolved AND pre_conditions passed AND margin over incompatible runner-up >= 15. If any condition fails, the candidate is presented using the 60-84 investigation summary format (no command block) with the specific failing eligibility condition called out in the SUGGESTED FOLLOW-UP section. The confidence score itself does not change — only the presentation changes.

2. INCONCLUSIVE -> user choice -> "accept as mitigated but unverified" exits to POSTMORTEM with an explicit `verification_status: unverified` flag, distinct from validated success.

3. The 60-84 path never reaches HITL GATE directly. It always loops through targeted investigation back to CLASSIFY until confidence either rises above 85 or drops below 60.

4. **Loop termination:** The CLASSIFY <-> INVESTIGATE loop terminates when any of: (a) confidence reaches >= 85 and eligibility passes, (b) confidence remains < 60 after the abbreviated investigation (Steps 1-5) has produced a root cause hypothesis — the agent presents the hypothesis and asks the user to choose: proceed to POSTMORTEM with current findings, attempt manual mitigation, or continue investigating a different angle, (c) 3 iterations without confidence improvement (defined as: top candidate score did not increase by >= 5 points), in which case the agent presents all gathered evidence and asks the user to choose a path (manual mitigation, continue investigation, or proceed to postmortem with current findings), (d) the user explicitly chooses a path at any iteration.

## Playbook Schema

Each playbook is a YAML file with fully structured, machine-parseable fields.

### Mandatory fields (all playbooks)

- `id`, `title`, `category`, `commandable`
- `signals` (supporting, contradicting, veto_signals, contradiction_penalty)
- `freshness_window_seconds`, `stabilization_delay_seconds`, `validation_window_seconds`, `sample_interval_seconds`
- `pre_conditions`, `post_conditions`, `hard_stop_conditions`, `stop_conditions` (all structured)
- `state_fingerprint_fields`

### Additional mandatory fields when `commandable: true`

- `required_tools`, `parameters`, `command` (argv-based), `explanation`
- `queries` (local query definitions for all referenced `query_ref` values)
- `destructive_action`, `requires_pre_execution_evidence`
- `cas_mode: native | revalidate_only` (fingerprint revalidation is universal; no `none` mode for commandable playbooks)
  - `revalidate_only` — fingerprint recheck before execution; if drift detected, abort and return to CLASSIFY. The command itself has no CAS semantics. This is the default for most kubectl commands.
  - `native` — the command includes a CAS token (e.g., resourceVersion in a JSON patch, etag in an API call) that causes the server to reject the operation if the resource changed. Fingerprint recheck still runs as a belt-and-suspenders check.
  - Fingerprint revalidation is universal for all commandable playbooks. There is no `none` mode — every real mitigation command runs through at minimum `revalidate_only`. The `dry_run` sub-command within a playbook inherits the parent's `cas_mode` but skips the actual execution gate (it is read-only by definition).

When `commandable: false`, execution fields may be omitted and are ignored if present.

### Condition structure

Each condition is a structured object:

```yaml
- id: error_rate_baseline
  query_ref: error_rate_query       # references local queries: block
  operator: lte                     # exists, equals, not_equals, gt, gte, lt, lte
  threshold: 0                      # literal value
  threshold_ref: pre_incident_p95   # OR captured/computed value (mutually exclusive with threshold)
  window_seconds: 300
```

Group semantics (defaults, overridable per-playbook):
- `pre_conditions`: ALL must pass
- `post_conditions`: ALL must pass
- `hard_stop_conditions`: ANY triggers immediate abort
- `stop_conditions`: ANY triggers halt after stabilization delay

### Query definitions

Every `query_ref` used in conditions or resolvers must be defined in the playbook's local `queries:` block. First-class query kinds:
- `kubectl` — generic kubectl command with extract
- `rollout_status` — first-class kind, returns `{ ready: bool, message: string }`
- `rollout_history` — first-class kind, returns `{ revisions: [{ number: int, change_cause: string }] }`
- `log_metric` — log-derived metric from investigation context
- `prompt` — ask user

### Parameter resolution

Structured resolvers replace raw shell strings:

```yaml
parameters:
  - name: deployment_name
    resolver:
      kind: kubectl
      resource_kind: deployment
      scope: namespace
      bind_to: affected_workload     # must resolve from investigation context
      cardinality: exactly_one        # >1 match = cannot reach >=85
    required: true
    validation:
      resource_kind: deployment
```

### Command structure

Argv token arrays with parameter substitution, no shell strings:

```yaml
command:
  argv: ["kubectl", "rollout", "undo",
         "deployment/{{deployment_name}}",
         "-n", "{{namespace}}",
         "--to-revision={{previous_revision}}"]
  cas_mode: revalidate_only
  dry_run:
    argv: ["kubectl", "rollout", "undo",
           "deployment/{{deployment_name}}",
           "-n", "{{namespace}}",
           "--to-revision={{previous_revision}}",
           "--dry-run=server"]
```

### V1.3 bundled playbooks

| ID | Category | Commandable | Tool | Special constraints |
|----|----------|-------------|------|---------------------|
| `bad-release-rollback` | bad-release | yes | kubectl | `error_pattern_predates_deploy` is a veto signal |
| `workload-restart` | workload-failure | yes | kubectl | Cannot proceed unless pre-restart evidence capture succeeded (`requires_pre_execution_evidence: true`) |
| `traffic-scale-out` | resource-overload | yes | kubectl | Heavy contradiction penalty if crash loops or rollout failures coexist with saturation |
| `config-regression` | bad-config | no | -- | Investigation-only unless repo-local override supplies full safety contract |
| `dependency-failure` | dependency-failure | no | -- | Investigation-only |
| `infra-failure` | infra-failure | no | -- | Investigation-only |

## Confidence Scoring Engine

### Central signal registry

`skills/incident-analysis/signals.yaml` — canonical definitions with structured detection parameters.

Each signal has:
- `title` — human-readable name
- `base_weight` — contribution to score when detected (0 for contradiction/veto-only signals)
- `detection.method` — one of: `temporal_correlation`, `existence`, `absence`, `threshold`, `event_presence`, `anomaly`, `distribution`, `compound`
- `detection.params` — structured parameters specific to the method (e.g., `max_delta_seconds`, `sustained_for_seconds`, `anomaly_factor`, `distribution_threshold`)

### Tri-state signal evaluation

Every signal evaluates to exactly one of:
- `detected` — evidence found, meets detection params
- `not_detected` — evidence sought, does not meet params
- `unknown_unavailable` — required data source not available

Compound signal propagation (`any_of`):
- `detected` if >= 1 child is detected
- `not_detected` if all children are not_detected
- `unknown_unavailable` if no child is detected AND >= 1 child is unavailable

Only `detected` and `not_detected` contribute to scoring. `unknown_unavailable` signals are excluded from base_score computation, but their weight IS included in `max_possible` for coverage ratio — this is what makes coverage drop when data sources are missing.

### Scoring formula

```
For each candidate playbook:

  1. Veto check (before scoring)
     IF any veto_signal detected -> candidate is disqualified, skip scoring

  2. Coverage gate
     evaluable_weight = sum(base_weight for supporting signals
                            where evaluation was detected or not_detected)
     max_possible     = sum(base_weight for ALL supporting signals)
     coverage_ratio   = evaluable_weight / max_possible
     IF coverage_ratio < 0.70 -> candidate is ineligible for PROPOSAL
     (but still appears in investigation summary with missing data called out)

  3. Score
     base_score          = sum(base_weight for each supporting signal detected)
     contradiction_score = playbook.contradiction_penalty
                           x count(contradicting signals detected)
     -- contradiction_penalty is a single flat value defined per-playbook.
     -- Each detected contradicting signal subtracts this same amount.
     -- Example: penalty=20, 2 contradictions detected -> -40 total.
     raw_score           = base_score - contradiction_score
     confidence          = clamp(0, 100, round(raw_score / max_possible x 100))

  4. Eligibility
     candidate_eligible =
       commandable
       AND no veto_signals detected
       AND coverage_ratio >= 0.70
       AND all required parameters resolved
       AND pre_conditions passed

  5. Winner selection
     proposal_allowed =
       top_candidate.confidence >= 85
       AND top_candidate.confidence - incompatible_runner_up.confidence >= 15
       AND exactly one eligible candidate at top

  6. Contradiction collapse
     IF two or more candidates score >= 60 AND their categories appear
     in the incompatible_pairs list -> all collapse to investigate path
```

### Compatibility matrix

`skills/incident-analysis/compatibility.yaml` — defines which playbook categories have incompatible mitigations.

```yaml
incompatible_pairs:
  - [bad-release, resource-overload]
  - [bad-release, workload-failure]
  - [resource-overload, infra-failure]
  - [workload-failure, infra-failure]

compatible_pairs:
  - [bad-release, bad-config]
  - [resource-overload, dependency-failure]

# Default: CLOSED. Any category pair NOT listed in either
# incompatible_pairs or compatible_pairs is treated as
# UNKNOWN and defaults to INCOMPATIBLE behavior (triggers
# margin gate and contradiction collapse). New playbook
# categories must be explicitly placed in one list or the
# other. This prevents a newly added category from silently
# bypassing safety checks.
```

Runner-up is the highest-scoring eligible candidate whose category differs from the top candidate. Margin is computed against all runner-ups EXCEPT those in `compatible_pairs`. Any pair not explicitly listed as compatible is treated as incompatible for margin gate and contradiction collapse purposes. This is a closed-by-default safety posture: new playbook categories must be explicitly classified.

### Compact decision records

**High-confidence record (>= 85, proposal):**

```
+-----------------------------------------------------+
| MITIGATION PROPOSAL                                 |
+-----------------------------------------------------+
| Playbook:     bad-release-rollback                  |
| Confidence:   HIGH (92)                             |
| Coverage:     100% (65/65 evaluable)                |
| Margin:       +27 over next candidate               |
| Evidence age: 45s (expires in 255s)                 |
|                                                     |
| SUPPORTING SIGNALS                                  |
| - [35] error spike at 14:31 correlates with deploy  |
|        abc123 at 14:30 (D 60s)                      |
| - [15] deploy abc123 detected via kubectl rollout   |
|        history (2m ago)                              |
| - [15] no matching errors in 1h pre-deploy baseline |
|                                                     |
| CONTRADICTORY SIGNALS                               |
| - none detected                                     |
|                                                     |
| VETO SIGNALS                                        |
| - none detected                                     |
|                                                     |
| UNKNOWN / UNAVAILABLE SIGNALS                       |
| - none -- all data sources available                |
|                                                     |
| STATE FINGERPRINT                                   |
| - resourceVersion: 48291                            |
| - generation: 12                                    |
| - pod-template-hash: 7f9d4b6c8                      |
|                                                     |
| COMMAND                                             |
| kubectl rollout undo deployment/checkout            |
|   -n prod --to-revision=11                          |
|                                                     |
| WHY: Rolling back to revision 11 (last known-good). |
| Error onset within 60s of deploy, no prior error    |
| pattern, clean baseline.                            |
|                                                     |
| VALIDATION PLAN                                     |
| - Stabilization: 120s grace period                  |
| - Then: observe error rate for 300s @ 30s intervals |
| - Hard stops: zero replicas, error rate increase    |
|                                                     |
| [approve] [reject] [investigate further]            |
+-----------------------------------------------------+
| ! Fingerprint will be rechecked before execution    |
+-----------------------------------------------------+
```

**Medium-confidence record (60-84, investigation prompt, no command block):**

```
+-----------------------------------------------------+
| INVESTIGATION SUMMARY                               |
+-----------------------------------------------------+
| Top hypothesis: bad-release (68)                    |
| Runner-up:      resource-overload (54)              |
| Coverage:       82% (53/65 evaluable)               |
| Evidence age:   30s                                 |
|                                                     |
| SUPPORTING SIGNALS (bad-release)                    |
| - [35] error spike at 14:31, deploy at 14:30       |
| - [15] deploy abc123 detected                       |
|                                                     |
| CONTRADICTORY SIGNALS                               |
| - [-20] CPU at 89% -- could be capacity not code   |
|                                                     |
| UNKNOWN / UNAVAILABLE SIGNALS                       |
| - no_prior_error_pattern: pre-deploy baseline not   |
|   yet queried (weight: 15)                          |
|                                                     |
| SUGGESTED FOLLOW-UP (read-only)                     |
| 1. Query pre-deploy error baseline (closes 15pt    |
|    gap, may resolve to >=85)                        |
| 2. Check CPU trend -- sustained or spike-correlated?|
|                                                     |
| [investigate option 1] [investigate option 2]       |
| [investigate both] [choose different path]          |
+-----------------------------------------------------+
```

## Evidence Sanitization and Persistence

### Redaction helper

`skills/incident-analysis/scripts/redact-evidence.sh` — deterministic Bash 3.2-compatible script using `sed` with extended regex.

Patterns redacted (all replaced with `[REDACTED]`):
- Email addresses
- IPv4 and IPv6 addresses
- Bearer tokens
- JWTs (eyJ.eyJ.sig pattern)
- API keys (X-Api-Key, api_key=, etc.)
- Cookie/session values
- Auth headers (Authorization: ...)
- Secret-like env vars (*_SECRET=, *_PASSWORD=, *_TOKEN=, *_KEY=)

**Rule:** All evidence payloads pass through `redact-evidence.sh` before anything is written to disk. Unsanitized payloads are never hashed and never persisted.

### Evidence bundle structure

```
docs/postmortems/evidence/<bundle-id>/
  +-- pre.json          # written before execution
  +-- validate.json     # written after validation completes
```

Individual files are immutable after write. The bundle directory is append-only (pre.json first, validate.json added later).

Both files contain ONLY:
- Sanitized excerpts (post-redaction)
- Hashes of sanitized payloads
- Timestamps
- Structured metadata (signal evaluations, fingerprint values, confidence score, condition results)

### Destructive action evidence rule

If `destructive_action: true` OR `requires_pre_execution_evidence: true` on the playbook, the `pre.json` bundle MUST include a sanitized final log window and workload-state summary BEFORE the command is even proposed at the HITL gate. If evidence capture fails, the playbook cannot proceed.

### Evidence lifecycle

- Bundles are local by default, not auto-committed
- Individual files immutable after write; directory append-only
- The postmortem references the bundle by ID (path link)
- Evidence-bundle ingestion by incident-trend-analyzer is future work (not v1.3)

## Routing Changes

Update `config/default-triggers.json` incident-analysis hint text to explicitly mention playbook selection, evidence capture, state fingerprint recheck, and validation. Add GitHub deployment/workflow hint co-surfacing in DEBUG phase.

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `skills/incident-analysis/SKILL.md` | Modify | Add CLASSIFY stage, confidence-gated routing, VALIDATE stage, playbook discovery, decision record format, evidence bundle instructions |
| `skills/incident-analysis/signals.yaml` | Create | Central signal registry with structured detection params |
| `skills/incident-analysis/compatibility.yaml` | Create | Playbook category compatibility matrix |
| `skills/incident-analysis/playbooks/bad-release-rollback.yaml` | Create | Commandable: kubectl rollback |
| `skills/incident-analysis/playbooks/workload-restart.yaml` | Create | Commandable: kubectl rollout restart |
| `skills/incident-analysis/playbooks/traffic-scale-out.yaml` | Create | Commandable: kubectl scale |
| `skills/incident-analysis/playbooks/config-regression.yaml` | Create | Investigation-only |
| `skills/incident-analysis/playbooks/dependency-failure.yaml` | Create | Investigation-only |
| `skills/incident-analysis/playbooks/infra-failure.yaml` | Create | Investigation-only |
| `skills/incident-analysis/scripts/redact-evidence.sh` | Create | Deterministic evidence sanitizer |
| `config/default-triggers.json` | Modify | Update incident-analysis hint for playbook/evidence/validation |
| `openspec/specs/incident-analysis/spec.md` | Modify | Add v1.3 change set |
| `openspec/changes/<slug>/proposal.md` | Create | Active OpenSpec change set |
| `openspec/changes/<slug>/design.md` | Create | Active OpenSpec change set |
| `openspec/changes/<slug>/tasks.md` | Create | Active OpenSpec change set |
| `openspec/changes/<slug>/specs/incident-analysis/spec.md` | Create | Delta spec for openspec validate |
| `docs/superpowers/specs/2026-03-23-incident-analysis-v1.3-playbooks-design.md` | Create | This design doc |

## Test Plan

| Test | File | What it verifies |
|------|------|------------------|
| Routing: deploy/regression prompts in DEBUG | `tests/test-routing.sh` | incident-analysis co-surfaces with GKE and GitHub hints |
| Skill content: confidence bands | `tests/test-skill-content.sh` | SKILL.md contains confidence >= 85, 60-84, < 60 routing |
| Skill content: contradiction penalty | `tests/test-skill-content.sh` | SKILL.md mentions contradiction_penalty and veto_signals |
| Skill content: counterevidence output | `tests/test-skill-content.sh` | Both decision record formats show CONTRADICTORY SIGNALS |
| Skill content: stabilization delay | `tests/test-skill-content.sh` | VALIDATE stage references stabilization_delay_seconds |
| Skill content: state fingerprint recheck | `tests/test-skill-content.sh` | Fingerprint recheck documented between approval and execution |
| Skill content: evidence sanitization | `tests/test-skill-content.sh` | redact-evidence.sh referenced before persistence |
| Skill content: VALIDATE stage | `tests/test-skill-content.sh` | Three exit paths: success, failure, inconclusive |
| Playbook schema validation | `tests/test-playbook-schema.sh` | All bundled YAML files include mandatory safety keys |
| Playbook commandable gates | `tests/test-playbook-schema.sh` | Commandable playbooks have required_tools, parameters, command, explanation |
| Playbook investigation-only gates | `tests/test-playbook-schema.sh` | Non-commandable playbooks omit execution fields |
| Playbook condition cross-refs | `tests/test-playbook-schema.sh` | Every query_ref in conditions resolves to a local queries: entry |
| Playbook threshold exclusivity | `tests/test-playbook-schema.sh` | No condition has both threshold and threshold_ref |
| Playbook resolver cardinality | `tests/test-playbook-schema.sh` | Resolvers with bind_to have cardinality: exactly_one |
| Playbook signal references | `tests/test-signal-registry.sh` | All signal IDs in bundled playbooks exist in signals.yaml |
| Compatibility matrix | `tests/test-signal-registry.sh` | All category IDs in compatibility.yaml match bundled playbook categories |
| Contradiction collapse | `tests/test-signal-registry.sh` | All incompatible_pairs entries reference valid playbook categories; skill content mentions collapse rule |
| Redaction: emails | `tests/test-redact-evidence.sh` | user@example.com -> [REDACTED] |
| Redaction: IPv4/IPv6 | `tests/test-redact-evidence.sh` | 10.0.0.1, fe80::1 -> [REDACTED] |
| Redaction: Bearer tokens | `tests/test-redact-evidence.sh` | Bearer eyJ... -> [REDACTED] |
| Redaction: JWTs | `tests/test-redact-evidence.sh` | eyJ.eyJ.sig -> [REDACTED] |
| Redaction: API keys | `tests/test-redact-evidence.sh` | X-Api-Key: abc -> [REDACTED] |
| Redaction: cookies/sessions | `tests/test-redact-evidence.sh` | Cookie: sid=abc -> [REDACTED] |
| Redaction: secret env vars | `tests/test-redact-evidence.sh` | DB_PASSWORD=xyz -> [REDACTED] |
| Postmortem shape regression | `tests/test-postmortem-shape.sh` | 7 top-level sections unchanged (incident-trend-analyzer compat) |
| OpenSpec validation | `tests/test-openspec.sh` | spec.md v1.3 change set validates |
| Full suite regression | `bash tests/run-tests.sh` | All existing tests pass |

## Assumptions

1. Confidence is a deterministic routing score, not a calibrated probability. Historical calibration telemetry is useful but out of scope for v1.3.
2. Evidence bundles are local by default, sanitized before persistence, and not auto-committed.
3. Existing incident-trend-analyzer remains postmortem-only in v1.3; evidence-bundle ingestion is future work.
4. Bundle files are immutable after write; the bundle directory is append-only until validation completes.
5. State-fingerprint revalidation is universal for all commandable playbooks (`revalidate_only` or `native`). Native CAS is opportunistic and only used where the command family supports it.

## What's NOT in v1.3

- Historical calibration of confidence thresholds (requires outcome telemetry)
- Evidence-bundle ingestion by incident-trend-analyzer
- Non-kubectl playbooks (gcloud, gh CLI, WAF) — repo-local overrides can add these
- Multi-hop trace correlation beyond one hop (existing v1.1 limitation)
- Proactive monitoring or alerting integration
- Auto-commit of evidence bundles

## Evolution Path

```
v1.3  Confidence-gated playbooks, sanitized evidence, VALIDATE stage (this design)
v1.4  Non-kubectl bundled playbooks (gcloud, gh CLI) based on v1.3 real-world usage
v2.0  incident-trend-analyzer with evidence-bundle ingestion
v2.1  Historical confidence calibration from outcome telemetry
v3.0  Backend-agnostic playbooks (Datadog, Splunk, etc.)
```
