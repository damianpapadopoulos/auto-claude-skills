# Incident Analysis v1.3: Confidence-Gated Playbooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the incident-analysis skill with confidence-gated generic mitigation playbooks, sanitized evidence capture, and post-execution validation.

**Architecture:** The skill's MITIGATE stage gains a CLASSIFY step that scores bundled YAML playbooks against detected signals, routes through a confidence-gated HITL gate, and feeds into a new VALIDATE stage. External YAML files define playbooks, signals, and compatibility — the skill reads and follows them at runtime. A Bash redaction script sanitizes evidence before persistence.

**Tech Stack:** Bash 3.2 (macOS-compatible), YAML (playbook/signal definitions), jq (test assertions), sed (redaction patterns)

**Design spec:** `docs/superpowers/specs/2026-03-23-incident-analysis-v1.3-playbooks-design.md` (pre-existing, already committed)

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `skills/incident-analysis/signals.yaml` | Central signal registry — canonical IDs, base weights, structured detection params |
| `skills/incident-analysis/compatibility.yaml` | Playbook category compatibility matrix (closed-by-default) |
| `skills/incident-analysis/playbooks/bad-release-rollback.yaml` | Commandable: kubectl rollback |
| `skills/incident-analysis/playbooks/workload-restart.yaml` | Commandable: kubectl rollout restart |
| `skills/incident-analysis/playbooks/traffic-scale-out.yaml` | Commandable: kubectl scale |
| `skills/incident-analysis/playbooks/config-regression.yaml` | Investigation-only |
| `skills/incident-analysis/playbooks/dependency-failure.yaml` | Investigation-only |
| `skills/incident-analysis/playbooks/infra-failure.yaml` | Investigation-only |
| `skills/incident-analysis/scripts/redact-evidence.sh` | Deterministic evidence sanitizer (Bash 3.2, sed) |
| `tests/test-redact-evidence.sh` | Redaction pattern tests (emails, IPs, tokens, JWTs, etc.) |
| `tests/test-playbook-schema.sh` | Playbook YAML structure validation |
| `tests/test-signal-registry.sh` | Signal cross-references, compatibility matrix, collapse rule |
| `tests/test-skill-content.sh` | SKILL.md behavioral contract assertions |
| `tests/test-postmortem-shape.sh` | 7-section postmortem regression (incident-trend-analyzer compat) |
| `tests/test-openspec.sh` | OpenSpec v1.3 change set validation |
| `openspec/changes/2026-03-23-incident-analysis-v1.3/proposal.md` | OpenSpec change set: problem statement + proposed solution |
| `openspec/changes/2026-03-23-incident-analysis-v1.3/design.md` | OpenSpec change set: architecture + decisions |
| `openspec/changes/2026-03-23-incident-analysis-v1.3/tasks.md` | OpenSpec change set: implementation checklist |
| `openspec/changes/2026-03-23-incident-analysis-v1.3/specs/incident-analysis/spec.md` | OpenSpec delta spec for validation |

### Modified files

| File | What changes |
|------|-------------|
| `skills/incident-analysis/SKILL.md` | Add CLASSIFY stage, confidence-gated routing, VALIDATE stage, playbook discovery, decision record formats, evidence bundle instructions |
| `config/default-triggers.json` | Update incident-analysis hint text to mention playbooks, evidence, validation |
| `openspec/specs/incident-analysis/spec.md` | Add v1.3 requirements (playbooks, scoring, evidence, validation) |

---

## Task Dependency Graph

```
Task 1 (signals.yaml) ──┐
Task 2 (compatibility)──┤
Task 3 (redact script)──┼── all independent, can run in parallel
Task 4 (routing) ───────┤
                         │
Task 5 (playbooks) ──────┤── depends on Task 1 (signal IDs must exist)
                         │
Task 6 (SKILL.md) ───────┤── depends on Tasks 1,2,5 (references all of them)
                         │
Task 7 (tests) ──────────┤── depends on Tasks 1-6 (validates everything)
                         │
Task 8 (OpenSpec) ────────┘── depends on Task 6 (spec mirrors skill)
Task 9 (regression) ──────── last: full test suite
```

**Parallelizable group 1:** Tasks 1, 2, 3, 4 (all independent)
**Parallelizable group 2:** Task 5 (after Task 1)
**Sequential:** Tasks 6, 7, 8, 9

---

### Task 1: Create Central Signal Registry

**Files:**
- Create: `skills/incident-analysis/signals.yaml`

- [ ] **Step 1: Create signal registry with all signal definitions**

```yaml
# skills/incident-analysis/signals.yaml
# Central signal registry — canonical IDs, base weights, structured detection params.
# Playbooks reference signals by ID only. Definitions, weights, and detection
# logic are owned here.

signals:
  # --- Deploy correlation ---
  error_rate_spike_correlated_with_deploy:
    title: Error spike correlated with recent deployment
    base_weight: 35
    detection:
      method: temporal_correlation
      params:
        max_delta_seconds: 300
        correlation_direction: deploy_then_errors

  recent_deploy_detected:
    title: Recent deployment detected
    base_weight: 15
    detection:
      method: existence
      params:
        source: deploy_metadata
        recency_window_seconds: 3600

  no_prior_error_pattern:
    title: No matching error pattern before deployment
    base_weight: 15
    detection:
      method: absence
      params:
        target: dominant_error_signature
        baseline_window_seconds: 3600

  # --- Resource saturation ---
  cpu_saturation_detected:
    title: CPU utilization exceeding threshold
    base_weight: 25
    detection:
      method: threshold
      params:
        metric: cpu_utilization
        operator: gte
        threshold_percent: 85
        sustained_for_seconds: 300

  memory_pressure_detected:
    title: Memory pressure or OOM events
    base_weight: 25
    detection:
      method: compound
      params:
        any_of:
          - method: event_presence
            event_type: OOMKilled
          - method: threshold
            metric: memory_utilization
            operator: gte
            threshold_percent: 90
            sustained_for_seconds: 300

  traffic_spike_detected:
    title: Abnormal traffic volume increase
    base_weight: 20
    detection:
      method: anomaly
      params:
        metric: request_rate
        anomaly_factor: 2.0
        baseline_window_seconds: 3600

  # --- Infrastructure ---
  errors_localized_to_node:
    title: Errors localized to specific node or zone
    base_weight: 30
    detection:
      method: distribution
      params:
        group_by: node
        distribution_threshold: 0.80
        min_sample_size: 10

  node_not_ready_detected:
    title: Kubernetes node in NotReady state
    base_weight: 30
    detection:
      method: event_presence
      params:
        event_type: NodeNotReady
        include_taints: true

  # --- Workload health ---
  crash_loop_detected:
    title: Pod crash loop backoff
    base_weight: 30
    detection:
      method: event_presence
      params:
        event_type: CrashLoopBackOff
        recency_window_seconds: 1800

  liveness_probe_failures:
    title: Liveness probe failures
    base_weight: 20
    detection:
      method: event_presence
      params:
        event_type: Unhealthy
        probe_type: liveness
        recency_window_seconds: 900

  # --- Config / dependency ---
  config_change_correlated_with_errors:
    title: Config change correlated with error onset
    base_weight: 30
    detection:
      method: temporal_correlation
      params:
        max_delta_seconds: 600
        correlation_direction: config_then_errors

  upstream_dependency_errors:
    title: Upstream dependency returning errors
    base_weight: 25
    detection:
      method: event_presence
      params:
        event_type: dependency_error
        recency_window_seconds: 1800

  # --- Contradiction / veto signals (base_weight: 0) ---
  error_pattern_predates_deploy:
    title: Error pattern existed before deployment
    base_weight: 0
    detection:
      method: temporal_correlation
      params:
        max_delta_seconds: 300
        correlation_direction: errors_then_deploy

  multiple_services_affected_simultaneously:
    title: Multiple services affected at same time
    base_weight: 0
    detection:
      method: distribution
      params:
        group_by: service
        min_correlated_services: 2
        correlation_window_seconds: 300

  resource_saturation_detected:
    title: Resource saturation coexists with other signals
    base_weight: 0
    detection:
      method: compound
      params:
        any_of:
          - signal_ref: cpu_saturation_detected
          - signal_ref: memory_pressure_detected

  crash_loop_coexists_with_saturation:
    title: Crash loops coexist with resource saturation
    base_weight: 0
    detection:
      method: compound
      params:
        all_of:
          - signal_ref: crash_loop_detected
          - any_of:
              - signal_ref: cpu_saturation_detected
              - signal_ref: memory_pressure_detected
```

- [ ] **Step 2: Verify YAML is valid**

Validate YAML without PyYAML (not available in this repo's baseline). Use `ruby -e "require 'yaml'; YAML.load_file('skills/incident-analysis/signals.yaml')" && echo "VALID"` (Ruby ships with macOS and includes YAML). Alternatively, rely on the test suite (test-signal-registry.sh) for structural validation.
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/signals.yaml
git commit -m "feat: add central signal registry for incident classification"
```

---

### Task 2: Create Compatibility Matrix

**Files:**
- Create: `skills/incident-analysis/compatibility.yaml`

- [ ] **Step 1: Create compatibility matrix**

```yaml
# skills/incident-analysis/compatibility.yaml
# Playbook category compatibility matrix.
# Default: CLOSED. Any category pair NOT listed in either list is treated
# as UNKNOWN and defaults to INCOMPATIBLE behavior (triggers margin gate
# and contradiction collapse). New playbook categories must be explicitly
# placed in one list or the other.

incompatible_pairs:
  - [bad-release, resource-overload]
  - [bad-release, workload-failure]
  - [resource-overload, infra-failure]
  - [workload-failure, infra-failure]

compatible_pairs:
  - [bad-release, bad-config]
  - [resource-overload, dependency-failure]
```

- [ ] **Step 2: Verify YAML is valid**

Validate YAML: `ruby -e "require 'yaml'; YAML.load_file('skills/incident-analysis/compatibility.yaml')" && echo "VALID"` or rely on test-signal-registry.sh.
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/compatibility.yaml
git commit -m "feat: add playbook category compatibility matrix (closed-by-default)"
```

---

### Task 3: Create Evidence Redaction Script

**Files:**
- Create: `skills/incident-analysis/scripts/redact-evidence.sh`
- Create: `tests/test-redact-evidence.sh`

- [ ] **Step 1: Write the redaction test file**

Create `tests/test-redact-evidence.sh` following project conventions: `set -u`, `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`, `PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"`, source `. "${SCRIPT_DIR}/test-helpers.sh"`, end with `print_summary`. Define test cases as input/expected pairs, pipe input through the redaction script, and assert the output matches. Each pattern gets its own test function.

Test cases to cover:
- Email: `user@example.com` -> `[REDACTED]`
- IPv4: `10.0.0.1`, `192.168.1.100` -> `[REDACTED]`
- IPv6: `fe80::1`, `::ffff:10.0.0.1`, `2001:db8::1` -> `[REDACTED]`
- Bearer tokens: `Bearer eyJhbGciOiJIUzI1NiJ9` -> `Bearer [REDACTED]`
- JWTs: `eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U` -> `[REDACTED]`
- API keys: `X-Api-Key: sk-abc123def456` -> `X-Api-Key: [REDACTED]`
- Cookies: `Cookie: session=abc123; JSESSIONID=xyz789` -> `Cookie: [REDACTED]`
- Secret env vars: `DB_PASSWORD=supersecret123` -> `DB_PASSWORD=[REDACTED]`
- Auth headers: `Authorization: Basic dXNlcjpwYXNz` -> `Authorization: [REDACTED]`
- Non-sensitive text should pass through unchanged

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-redact-evidence.sh`
Expected: FAIL (script does not exist yet)

- [ ] **Step 3: Write the redaction script**

Create `skills/incident-analysis/scripts/redact-evidence.sh` — a Bash 3.2-compatible script that reads stdin and writes sanitized output to stdout. Uses `sed -E` with extended regex. Patterns applied in order:

1. JWTs (3-part base64 dot-separated) -> `[REDACTED]`
2. Bearer tokens -> `Bearer [REDACTED]`
3. Authorization headers -> `Authorization: [REDACTED]`
4. API key headers/params -> key name preserved, value `[REDACTED]`
5. Cookie/session values -> cookie name preserved, value `[REDACTED]`
6. Secret-like env vars (`*_SECRET=`, `*_PASSWORD=`, `*_TOKEN=`, `*_KEY=`) -> name preserved, value `[REDACTED]`
7. Email addresses -> `[REDACTED]`
8. IPv6 addresses -> `[REDACTED]`
9. IPv4 addresses -> `[REDACTED]`

Order matters: JWT before Bearer (JWT is more specific), IPv6 before IPv4 (avoid partial matches).

Make executable: `chmod +x skills/incident-analysis/scripts/redact-evidence.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-redact-evidence.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/scripts/redact-evidence.sh tests/test-redact-evidence.sh
git commit -m "feat: add evidence redaction script with tests"
```

---

### Task 4: Update Routing Configuration

**Files:**
- Modify: `config/default-triggers.json`

- [ ] **Step 1: Update the incident-analysis methodology hint**

In `config/default-triggers.json`, find the methodology hint for `incident-analysis` and update the hint text to mention playbook selection, evidence capture, state fingerprint recheck, and validation:

Old hint text:
```
INCIDENT ANALYSIS: Use Skill(auto-claude-skills:incident-analysis) for structured investigation. Stages: MITIGATE -> INVESTIGATE -> POSTMORTEM. Detect tool tier (MCP > gcloud > guidance). Scope all queries to specific service + environment + narrow time window.
```

New hint text:
```
INCIDENT ANALYSIS: Use Skill(auto-claude-skills:incident-analysis) for structured investigation. Stages: MITIGATE -> CLASSIFY -> (confidence-gated HITL or INVESTIGATE loop) -> EXECUTE -> VALIDATE -> POSTMORTEM. Detect tool tier (MCP > gcloud > guidance). Scope all queries to specific service + environment + narrow time window. Classify incident type against bundled playbooks, capture sanitized evidence, recheck state fingerprint before execution, validate post-mitigation conditions.
```

Also update the skill entry description to match.

Additionally, ensure the GitHub methodology hints in `default-triggers.json` can co-surface with incident-analysis in DEBUG phase. The actual entry is named `github-mcp` (line ~515) and the methodology hint is named `github` (line ~812). Verify the `github` methodology hint's `phases` array includes `"DEBUG"`. If it doesn't, add it. The design spec requires that deploy/regression prompts can co-surface incident-analysis, GKE, and GitHub hints simultaneously. The routing test (Task 7 Step 5) should assert this co-surfacing behavior.

- [ ] **Step 2: Verify JSON is valid**

Run: `python3 -c "import json; json.load(open('config/default-triggers.json'))" && echo "VALID"`
Expected: `VALID`

- [ ] **Step 3: Run existing routing tests to verify no regression**

Run: `bash tests/test-routing.sh`
Expected: All existing tests PASS

- [ ] **Step 4: Regenerate fallback registry**

The fallback registry (`config/fallback-registry.json`) is a checked-in file derived from `default-triggers.json`. Regenerate it by running the session-start hook in a way that writes the fallback:

Run: `CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh < /dev/null 2>/dev/null; echo "done"`

Then verify `config/fallback-registry.json` was updated (check `git diff config/fallback-registry.json`). If the hook does not update the fallback directly, copy from the generated cache or manually regenerate using the same jq pipeline the hook uses.

- [ ] **Step 5: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json
git commit -m "feat: update incident-analysis routing hints for v1.3 playbooks"
```

---

### Task 5: Create Bundled Playbooks (6 files)

**Files:**
- Create: `skills/incident-analysis/playbooks/bad-release-rollback.yaml`
- Create: `skills/incident-analysis/playbooks/workload-restart.yaml`
- Create: `skills/incident-analysis/playbooks/traffic-scale-out.yaml`
- Create: `skills/incident-analysis/playbooks/config-regression.yaml`
- Create: `skills/incident-analysis/playbooks/dependency-failure.yaml`
- Create: `skills/incident-analysis/playbooks/infra-failure.yaml`

**Depends on:** Task 1 (signal IDs must match signals.yaml)

- [ ] **Step 1: Create `bad-release-rollback.yaml`**

Full commandable playbook with:
- `id: bad-release-rollback`, `category: bad-release`, `commandable: true`
- Supporting signals: `error_rate_spike_correlated_with_deploy`, `recent_deploy_detected`, `no_prior_error_pattern`
- Contradicting: `multiple_services_affected_simultaneously`, `resource_saturation_detected`
- Veto: `error_pattern_predates_deploy`
- `contradiction_penalty: 20`
- Local `queries:` block with `kubectl_get_deployment`, `kubectl_rollout_history` (kind: rollout_history), `kubectl_rollout_status` (kind: rollout_status), `kubectl_ready_replicas`, `error_rate_query`, `error_pattern_query`
- Structured conditions (threshold vs threshold_ref, operator, window_seconds)
- State fingerprint: resourceVersion, generation, observedGeneration, pod-template-hash
- Parameters: namespace (prompt), deployment_name (kubectl, bind_to: affected_workload, exactly_one), previous_revision (query, rollout_history, transform: previous)
- Command argv: `["kubectl", "rollout", "undo", ...]`, cas_mode: revalidate_only, dry_run argv
- Timing: freshness 300s, stabilization 120s, validation 300s, sample 30s
- `destructive_action: false`, `requires_pre_execution_evidence: true`
- Explanation text from design spec

Follow the exact schema from the design spec Section 2 (revised).

- [ ] **Step 2: Create `workload-restart.yaml`**

Commandable playbook:
- `id: workload-restart`, `category: workload-failure`, `commandable: true`
- Supporting: `crash_loop_detected`, `liveness_probe_failures`
- Contradicting: `error_rate_spike_correlated_with_deploy` (could be bad release, not workload issue)
- `contradiction_penalty: 15`
- `destructive_action: true`, `requires_pre_execution_evidence: true`
- Command: `kubectl rollout restart deployment/{{deployment_name}} -n {{namespace}}`
- Special: cannot proceed unless pre-restart evidence capture succeeded

- [ ] **Step 3: Create `traffic-scale-out.yaml`**

Commandable playbook:
- `id: traffic-scale-out`, `category: resource-overload`, `commandable: true`
- Supporting: `cpu_saturation_detected`, `memory_pressure_detected`, `traffic_spike_detected`
- Contradicting: `crash_loop_coexists_with_saturation` (heavy penalty — scaling crash-looping pods makes things worse)
- `contradiction_penalty: 30` (heavy)
- Command: `kubectl scale deployment/{{deployment_name}} -n {{namespace}} --replicas={{target_replicas}}`
- Parameters include `current_replicas` (kubectl resolver) and `target_replicas` (computed: current + 3)

- [ ] **Step 4: Create `config-regression.yaml`**

Investigation-only playbook (all mandatory fields required even though `commandable: false`):
- `id: config-regression`, `category: bad-config`, `commandable: false`
- `signals:` with `supporting: [config_change_correlated_with_errors]`, `contradicting: []`, `veto_signals: []`, `contradiction_penalty: 0`
- All timing fields: `freshness_window_seconds: 300`, `stabilization_delay_seconds: 120`, `validation_window_seconds: 300`, `sample_interval_seconds: 30`
- Empty structured conditions: `pre_conditions: []`, `post_conditions: []`, `hard_stop_conditions: []`, `stop_conditions: []`
- `state_fingerprint_fields: []` (empty but present — mandatory for all playbooks)
- Omit: `command`, `queries`, `parameters`, `required_tools`, `explanation`, `destructive_action`, `requires_pre_execution_evidence`

- [ ] **Step 5: Create `dependency-failure.yaml`**

Investigation-only playbook (same mandatory field pattern as config-regression):
- `id: dependency-failure`, `category: dependency-failure`, `commandable: false`
- `signals:` with `supporting: [upstream_dependency_errors]`, `contradicting: []`, `veto_signals: []`, `contradiction_penalty: 0`
- All timing fields, empty conditions, empty `state_fingerprint_fields: []`

- [ ] **Step 6: Create `infra-failure.yaml`**

Investigation-only playbook (same mandatory field pattern):
- `id: infra-failure`, `category: infra-failure`, `commandable: false`
- `signals:` with `supporting: [errors_localized_to_node, node_not_ready_detected]`, `contradicting: []`, `veto_signals: []`, `contradiction_penalty: 0`
- All timing fields, empty conditions, empty `state_fingerprint_fields: []`

- [ ] **Step 7: Verify all YAML files are valid**

Validate all playbook YAML files: `for f in skills/incident-analysis/playbooks/*.yaml; do ruby -e "require 'yaml'; YAML.load_file('$f')" && echo "OK: $f" || echo "FAIL: $f"; done`
Expected: All 6 files show `OK`

- [ ] **Step 8: Commit**

```bash
git add skills/incident-analysis/playbooks/
git commit -m "feat: add 6 bundled playbooks (3 commandable, 3 investigation-only)"
```

---

### Task 6: Update SKILL.md

**Files:**
- Modify: `skills/incident-analysis/SKILL.md`

**Depends on:** Tasks 1, 2, 5 (references signal IDs, playbook schema, compatibility matrix)

This is the largest single change. The existing SKILL.md has 3 stages and 4 behavioral constraints. We add:
- A new CLASSIFY stage between MITIGATE and INVESTIGATE
- A new VALIDATE stage after EXECUTE
- Playbook discovery instructions
- Confidence scoring engine (referencing signals.yaml)
- Decision record formats (high-confidence and medium-confidence)
- Evidence bundle instructions (referencing redact-evidence.sh)
- Modifications to INVESTIGATE re-entry semantics (Steps 1-5 only for reclassification loop)

- [ ] **Step 1: Read current SKILL.md to understand exact insertion points**

Read: `skills/incident-analysis/SKILL.md`
Identify: end of Behavioral Constraints section, Stage 1 MITIGATE Step 5 (HITL gate), Stage 2 transitions

- [ ] **Step 2: Add Behavioral Constraint 5 — Evidence Freshness**

After Constraint 4 (Context Discipline), add:

```markdown
### 5. Evidence Freshness Gate

If the user has not approved a mitigation proposal within the playbook's `freshness_window_seconds` of evidence collection, the proposal is retracted. Return to CLASSIFY with fresh queries. Stale evidence cannot be acted upon.
```

- [ ] **Step 3: Add new new stage — CLASSIFY**

After Stage 1 Step 6 (transition), insert a new section for the CLASSIFY stage. Include:
- Playbook discovery (bundled at `skills/incident-analysis/playbooks/`, repo-local at `playbooks/incident-analysis/`, resolution by id)
- Signal evaluation (tri-state: detected, not_detected, unknown_unavailable)
- Scoring formula (base_score, contradiction_score, evaluable_weight denominator)
- Three-tier eligibility (proposal_eligible, classification_credible, unscored)
- Coverage gate (>= 0.70)
- Winner selection (confidence >= 85, margin >= 15 over incompatible runner-up, no incompatible runner-up = margin passes by default)
- Contradiction collapse (classification_credible candidates, closed-by-default compatibility)
- Confidence-gated routing (>= 85 -> HITL, 60-84 -> targeted follow-up -> reclassify, < 60 -> INVESTIGATE Steps 1-5 only -> reclassify)
- Loop termination (3 iterations without >= 5pt improvement, or user override)
- Decision record formats (embed both high-confidence and medium-confidence templates)

- [ ] **Step 4: Modify Stage 1 MITIGATE — update HITL gate**

The current HITL gate (Stage 1 Step 5) says "If a mutating fix is obvious, present the exact command and HALT." Replace this entirely: "If mitigation is needed, transition to CLASSIFY for structured playbook selection."

**Remove the old direct-command HITL path.** All mutating actions must now go through the playbook framework (classification, evidence capture, fingerprint recheck, VALIDATE). If no playbook matches the incident, the agent must transition to INVESTIGATE or provide manual guidance — it cannot propose a bare command outside the safety contract. This prevents an escape hatch that would bypass v1.3's core safety properties.

- [ ] **Step 5: Modify Stage 2 INVESTIGATE — add re-entry semantics**

Add a note at the top of Stage 2 that when entered from the CLASSIFY < 60 path, only Steps 1-5 run (log queries, signal extraction, deep dive, trace correlation, root cause hypothesis). Steps 6-8 (Flight Plan, context synthesis, POSTMORTEM transition) are SKIPPED. Findings feed back to CLASSIFY.

- [ ] **Step 6: Add new new stage — EXECUTE**

After the HITL gate approval, insert the execution boundary:
1. Fingerprint recheck (compare current state against captured fingerprint)
2. If drift detected -> return to CLASSIFY
3. Execute command (or confirm user ran it externally)
4. Transition to VALIDATE

- [ ] **Step 7: Add new new stage — VALIDATE**

Insert the two-phase validation:
- Phase 1: Stabilization grace period (wait `stabilization_delay_seconds`). Only `hard_stop_conditions` active.
- Phase 2: Observation window (sample every `sample_interval_seconds` for `validation_window_seconds`). Both `hard_stop_conditions` and `stop_conditions` active. `post_conditions` evaluated at each sample.
- Three exit paths: validated_success -> POSTMORTEM, validated_failed -> ESCALATE -> INVESTIGATE, inconclusive -> user choice (extend / escalate / accept as mitigated but unverified)

- [ ] **Step 8: Add evidence bundle instructions**

After the VALIDATE stage, add instructions for:
- Evidence bundle directory structure (`docs/postmortems/evidence/<bundle-id>/`)
- `pre.json` schema (captured before execution)
- `validate.json` schema (captured after validation)
- Redaction rule: all payloads pass through `redact-evidence.sh` before persistence
- Destructive action rule: if `requires_pre_execution_evidence: true`, pre.json must include final log window before command is proposed

- [ ] **Step 9: Modify Stage 3 POSTMORTEM — add mitigation section**

In the postmortem template, add a "Mitigation Applied" section that includes:
- Playbook used (ID)
- Command executed
- Timing (proposed at, approved at, executed at, validated at)
- Verification status (validated_success, validated_failed, unverified)
- Evidence bundle reference (path link)

Keep the existing 7-section structure intact (add mitigation as a subsection of "Resolution and Recovery").

- [ ] **Step 10: Verify SKILL.md is well-formed markdown**

Read through the complete updated file and verify section headers are consistent and cross-references are valid.

- [ ] **Step 11: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat: add CLASSIFY, EXECUTE, VALIDATE stages and playbook framework to SKILL.md"
```

---

### Task 7: Create Test Suites

**Files:**
- Create: `tests/test-skill-content.sh`
- Create: `tests/test-playbook-schema.sh`
- Create: `tests/test-signal-registry.sh`
- Create: `tests/test-postmortem-shape.sh`
- Add routing tests to: `tests/test-routing.sh`

**Depends on:** Tasks 1-6 (validates all created/modified files)

**Convention for ALL test files:** Every test file must follow the project pattern:
```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
# ... test functions ...
print_summary  # REQUIRED at end — without this, failures are silently swallowed
```

- [ ] **Step 1: Create `tests/test-skill-content.sh`**

Source `tests/test-helpers.sh`. Test SKILL.md content assertions using grep:
- Contains confidence bands: `>= 85`, `60-84`, `< 60`
- Contains `contradiction_penalty` and `veto_signals`
- Both decision record formats contain `CONTRADICTORY SIGNALS`
- VALIDATE stage references `stabilization_delay_seconds`
- Fingerprint recheck documented between approval and execution
- `redact-evidence.sh` referenced before persistence
- Three VALIDATE exit paths: `validated_success`, `validated_failed`, `unverified`
- CLASSIFY stage exists
- Loop termination mentioned

- [ ] **Step 2: Create `tests/test-playbook-schema.sh`**

Test all 6 bundled playbook YAML files. Use `ruby -ryaml -rjson -e "puts YAML.load_file(ARGV[0]).to_json" FILE` to convert each YAML to JSON, then pipe through `jq` for field assertions. This avoids the PyYAML dependency while leveraging the existing jq-based test patterns. For each playbook:
- Mandatory fields present: `id`, `title`, `category`, `commandable`, `signals`, timing fields, condition arrays, `state_fingerprint_fields`
- Commandable playbooks also have: `required_tools`, `parameters`, `command` (with `argv` and `cas_mode`), `explanation`, `queries`, `destructive_action`, `requires_pre_execution_evidence`
- Investigation-only playbooks do NOT have: `command`, `parameters`, `required_tools`
- Condition cross-refs: every `query_ref` in conditions resolves to a local `queries:` entry
- Threshold exclusivity: no condition has both `threshold` and `threshold_ref`
- Resolver cardinality: resolvers with `bind_to` have `cardinality: exactly_one`

- [ ] **Step 3: Create `tests/test-signal-registry.sh`**

Validate cross-references:
- Every signal ID referenced in any bundled playbook's `signals.supporting`, `signals.contradicting`, and `signals.veto_signals` exists in `signals.yaml`
- Every category in `compatibility.yaml` (both `incompatible_pairs` and `compatible_pairs`) matches a `category` value in at least one bundled playbook
- SKILL.md mentions the contradiction collapse rule

- [ ] **Step 4: Create `tests/test-postmortem-shape.sh`**

Regression test: verify SKILL.md's built-in postmortem template still contains the 7 required section headers:
1. Summary
2. Impact
3. Timeline
4. Root Cause & Trigger (or Root Cause)
5. Resolution and Recovery (or Resolution)
6. Lessons Learned
7. Action Items

This ensures incident-trend-analyzer's parser still works.

- [ ] **Step 5: Add routing tests for deploy/regression prompts**

In `tests/test-routing.sh`, add test cases that verify:
- Prompt containing "deploy rollback" in DEBUG phase surfaces incident-analysis
- Prompt containing "incident" still surfaces incident-analysis (existing behavior preserved)

- [ ] **Step 6: Run all tests**

Run: `bash tests/run-tests.sh`
Expected: All tests PASS (including new test files, which auto-discover)

- [ ] **Step 7: Create `tests/test-openspec.sh`**

Validate the OpenSpec v1.3 change set. The primary acceptance check should be running the actual openspec validator if available:

```bash
# If openspec CLI is available:
openspec validate 2026-03-23-incident-analysis-v1.3

# If not, fall back to structural checks:
```

Structural fallback checks:
- `openspec/changes/2026-03-23-incident-analysis-v1.3/` directory exists
- Contains `proposal.md` (with `## Why` and `## What Changes` sections — this is the repo's required proposal shape; do NOT use "Problem Statement" / "Proposed Solution" headers), `design.md`, `tasks.md`
- Contains `specs/incident-analysis/spec.md` (delta spec)
- Delta spec contains v1.3 requirement headings (Playbook Discovery, Confidence-Gated Classification, Three-Tier Eligibility, etc.)
- Canonical `openspec/specs/incident-analysis/spec.md` contains v1.3 requirements
- The test should first try `openspec validate` and only fall back to structural checks if the CLI is not installed

- [ ] **Step 8: Commit**

```bash
git add tests/test-skill-content.sh tests/test-playbook-schema.sh tests/test-signal-registry.sh tests/test-postmortem-shape.sh tests/test-openspec.sh tests/test-routing.sh
git commit -m "test: add v1.3 playbook, signal, skill content, postmortem, and openspec tests"
```

---

### Task 8: Create OpenSpec Change Set

**Files:**
- Create: `openspec/changes/2026-03-23-incident-analysis-v1.3/proposal.md`
- Create: `openspec/changes/2026-03-23-incident-analysis-v1.3/design.md`
- Create: `openspec/changes/2026-03-23-incident-analysis-v1.3/tasks.md`
- Create: `openspec/changes/2026-03-23-incident-analysis-v1.3/specs/incident-analysis/spec.md`
- Modify: `openspec/specs/incident-analysis/spec.md`

**Depends on:** Task 6 (spec mirrors skill)

- [ ] **Step 1: Create proposal.md**

Use the repo's required proposal shape (headers `## Why` and `## What Changes`, NOT "Problem Statement" / "Proposed Solution"):
- `## Why`: Current skill has no structured mitigation framework. Investigation stops at root cause hypothesis; no playbook selection, evidence capture, or post-execution validation.
- `## What Changes`: Confidence-gated playbooks with evidence capture and validation. Adds CLASSIFY, EXECUTE, VALIDATE stages; bundled playbooks; signal registry; redaction script; evidence bundles.
- Out of scope: historical calibration, non-kubectl playbooks, evidence-bundle ingestion by trend analyzer.

- [ ] **Step 2: Create design.md**

Reference the design spec at `docs/superpowers/specs/2026-03-23-incident-analysis-v1.3-playbooks-design.md`.
Summarize: architecture (4-stage with CLASSIFY + VALIDATE), dependencies (signals.yaml, compatibility.yaml, playbooks/*.yaml, redact-evidence.sh), key decisions (confidence-gated routing, three-tier eligibility, closed-by-default compatibility).

- [ ] **Step 3: Create delta spec (specs/incident-analysis/spec.md)**

Add v1.3 requirements in BDD Given/When/Then format:
- Requirement: Playbook Discovery and Loading
- Requirement: Confidence-Gated Classification
- Requirement: Three-Tier Eligibility
- Requirement: Contradiction Collapse
- Requirement: State Fingerprint Recheck
- Requirement: Post-Execution Validation (two-phase)
- Requirement: Evidence Sanitization and Persistence
- Requirement: Decision Record Format

Each with 2-4 scenarios covering happy path, edge cases, and safety constraints.

- [ ] **Step 4: Update canonical spec**

Merge the delta spec requirements into `openspec/specs/incident-analysis/spec.md`, preserving existing v1.0-v1.2 requirements.

- [ ] **Step 5: Create tasks.md**

Checklist of completed implementation tasks matching this plan.

- [ ] **Step 6: Commit**

```bash
git add openspec/
git commit -m "feat: add OpenSpec v1.3 change set for incident-analysis playbooks"
```

---

### Task 9: Full Regression and Final Verification

**Depends on:** All previous tasks

- [ ] **Step 1: Run the complete test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests PASS, no regressions

- [ ] **Step 2: Syntax-check all hooks**

Run: `bash -n hooks/skill-activation-hook.sh && bash -n hooks/session-start-hook.sh && echo "VALID"`
Expected: `VALID`

- [ ] **Step 3: Verify no broken cross-references**

Run: `bash tests/test-signal-registry.sh && bash tests/test-playbook-schema.sh && echo "All cross-refs valid"`
Expected: `All cross-refs valid`

- [ ] **Step 4: Commit final state if any fixups were needed**

```bash
git add -A
git commit -m "fix: address regression test findings"
```

(Only if fixups were needed — skip if Task 9 Step 1 passed cleanly.)
