# Incident Analysis Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance the incident-analysis skill with an `/investigate` command, SLO burn rate signal, bounded disambiguation probes, eval runner, and source code analysis stage.

**Architecture:** Selective enhancement of the existing monolithic pipeline. Disambiguation probes add a bounded shortlist to CLASSIFY output and a Step 2b to INVESTIGATE that runs one pre-canned query per runner-up, feeding results back through the existing scorer. No new scoring logic. Source analysis is a named stage with a separate reference file.

**Tech Stack:** Bash 3.2 (macOS), YAML (playbooks/signals), Markdown (SKILL.md/commands), jq + ruby (tests)

**Spec:** `docs/superpowers/specs/2026-03-26-incident-analysis-improvements-design.md`

---

## File Map

### PR 1: `/investigate` command + SLO signal
| Action | File | Responsibility |
|--------|------|---------------|
| Create | `commands/investigate.md` | Entry-point wrapper pre-populating MITIGATE scope |
| Edit | `skills/incident-analysis/signals.yaml` | Add `slo_burn_rate_alert` signal |
| Edit | `tests/test-signal-registry.sh` | Verify new signal is referenced correctly |
| Edit | `tests/test-routing.sh` | SLO burn rate routing test |

### PR 2: Disambiguation probes
| Action | File | Responsibility |
|--------|------|---------------|
| Edit | `skills/incident-analysis/playbooks/dependency-failure.yaml` | Add `queries` + `disambiguation_probe` |
| Edit | `skills/incident-analysis/playbooks/config-regression.yaml` | Add `queries` + `disambiguation_probe` |
| Edit | `skills/incident-analysis/playbooks/infra-failure.yaml` | Add `queries` + `disambiguation_probe` |
| Edit | `tests/test-playbook-schema.sh` | Validate `disambiguation_probe` schema |
| Edit | `tests/test-signal-registry.sh` | Validate `resolves_signals` cross-refs |
| Edit | `skills/incident-analysis/SKILL.md` | CLASSIFY shortlist, Step 2b, scope exception |
| Edit | `tests/test-skill-content.sh` | Behavioral contract tests for new sections |

### PR 3: Fixture schema validator + routing tests
| Action | File | Responsibility |
|--------|------|---------------|
| Edit | `tests/test-routing.sh` | Additional routing accuracy cases |
| Create | `tests/test-incident-analysis-output.sh` | Fixture schema validator (not skill invocation) |
| Create | `tests/fixtures/incident-analysis/README.md` | Fixture authoring guidelines |

### PR 4: SOURCE_ANALYSIS stage
| Action | File | Responsibility |
|--------|------|---------------|
| Create | `skills/incident-analysis/references/source-analysis.md` | Full procedure: GitHub API, SHA resolution, regression heuristic |
| Edit | `skills/incident-analysis/SKILL.md` | Stage header between INVESTIGATE and EXECUTE |
| Edit | `tests/test-skill-content.sh` | Behavioral contract tests for SOURCE_ANALYSIS |

---

## PR 1: `/investigate` command + SLO signal

### Task 1: Add `slo_burn_rate_alert` signal

**Note:** This signal is intentionally not wired to any playbook. It is a **context signal**
that aids investigation routing and provides investigation context (answering "was an SLO
alert involved?") but does not drive playbook classification. The classifier only evaluates
signals referenced by candidate playbooks — this signal enriches the investigation summary
without influencing scoring. A future playbook (e.g., `slo-burn-rate-response`) could
reference it if a commandable mitigation path is designed.

**Files:**
- Edit: `skills/incident-analysis/signals.yaml`
- Edit: `skills/incident-analysis/SKILL.md`
- Edit: `tests/test-signal-registry.sh`
- Edit: `tests/test-skill-content.sh`

- [ ] **Step 1: Write failing cross-reference test**

Add a test case to `tests/test-signal-registry.sh` that asserts `slo_burn_rate_alert` exists in signals.yaml. Insert before the final `print_summary` call:

```bash
# ---------------------------------------------------------------------------
# slo_burn_rate_alert signal exists
# ---------------------------------------------------------------------------
slo_check="$(printf '%s' "${signal_json}" | jq -r '.signals | has("slo_burn_rate_alert")')"
if [ "${slo_check}" = "true" ]; then
    _record_pass "slo_burn_rate_alert signal exists"
else
    _record_fail "slo_burn_rate_alert signal exists" "not found in signals.yaml"
fi

# slo_burn_rate_alert has required detection fields
slo_method="$(printf '%s' "${signal_json}" | jq -r '.signals.slo_burn_rate_alert.detection.method // empty')"
assert_not_empty "slo_burn_rate_alert has detection method" "${slo_method}"

slo_weight="$(printf '%s' "${signal_json}" | jq -r '.signals.slo_burn_rate_alert.base_weight // empty')"
assert_not_empty "slo_burn_rate_alert has base_weight" "${slo_weight}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-signal-registry.sh`
Expected: FAIL on "slo_burn_rate_alert signal exists"

- [ ] **Step 3: Add signal to signals.yaml**

Append to the end of the signals section in `skills/incident-analysis/signals.yaml` (before any trailing newlines), after the last signal entry:

```yaml

  # ---------------------------------------------------------------------------
  # SLO signals
  # ---------------------------------------------------------------------------

  slo_burn_rate_alert:
    title: "SLO burn rate alert fired"
    base_weight: 30
    detection:
      method: event_presence
      params:
        event_type: AlertFired
        alert_name_pattern: ".*burn.?rate.*"
        recency_window_seconds: 3600
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-signal-registry.sh`
Expected: PASS on all slo_burn_rate_alert assertions

- [ ] **Step 5: Add SKILL.md mention so the signal is surfaced during investigation**

In `skills/incident-analysis/SKILL.md`, in Step 2c: Quantify User-Facing Impact (around
line 100-106), add after the bullet about metrics:

```
- **From alerts (check):** If an SLO burn rate alert fired for this service in the time
  window, note the alert name, burn rate value, and error budget remaining. This provides
  severity context before the deep dive. Check via `list_alert_policies` (Tier 1) or
  `gcloud alpha monitoring policies list` (Tier 2).
```

This ensures the signal is evaluated during MITIGATE and surfaced in the investigation
summary, even though it doesn't drive playbook classification.

- [ ] **Step 6: Add behavioral test for SLO MITIGATE mention**

Add to `tests/test-skill-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SLO burn rate context signal in MITIGATE
# ---------------------------------------------------------------------------
assert_contains "SKILL.md mentions SLO burn rate in MITIGATE" "SLO burn rate alert" "${SKILL_CONTENT}"
```

Run: `bash tests/test-skill-content.sh`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add skills/incident-analysis/signals.yaml skills/incident-analysis/SKILL.md tests/test-signal-registry.sh tests/test-skill-content.sh
git commit -m "feat(incident-analysis): add slo_burn_rate_alert signal with MITIGATE integration"
```

### Task 2: Create `/investigate` command

**Files:**
- Create: `commands/investigate.md`
- Edit: `tests/test-routing.sh`

- [ ] **Step 1: Write failing routing test**

Add a new test function to `tests/test-routing.sh` before the test invocation list at the bottom. Follow the existing `test_incident_analysis_hint_fires` pattern:

```bash
test_investigate_command_routing() {
    echo "-- test: /investigate command exists and references incident-analysis --"

    local cmd_file="${PROJECT_ROOT}/commands/investigate.md"
    assert_file_exists "/investigate command file" "${cmd_file}"

    local content
    content="$(cat "${cmd_file}")"
    assert_contains "references incident-analysis skill" "incident-analysis" "${content}"
    assert_contains "references MITIGATE stage" "MITIGATE" "${content}"
    assert_contains "must not bypass MITIGATE" "Must not bypass MITIGATE" "${content}"
}
```

Add `test_investigate_command_routing` to the test invocation list at the bottom of the file.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | tail -20`
Expected: FAIL on "/investigate command file" (file doesn't exist)

- [ ] **Step 3: Create the command file**

Create `commands/investigate.md`:

```markdown
---
description: Launch a systematic incident investigation
argument-hint: "Service name and symptoms (e.g., 'user-service 500s in hb-prod')"
---

Launch the incident-analysis skill for a systematic, evidence-based investigation of a
production incident.

## What Happens

1. The skill detects available tools (MCP, gcloud CLI, or guidance-only)
2. Establishes scope: service, environment, time window from your input
3. Runs inventory and impact quantification (MITIGATE stage)
4. Classifies the incident against playbooks (CLASSIFY stage)
5. Investigates with targeted queries (INVESTIGATE stage)
6. If remediation is needed, presents playbook with HITL gate (EXECUTE stage)
7. Validates post-mitigation (VALIDATE stage)
8. Generates structured postmortem (POSTMORTEM stage)

## Usage

**With arguments:**
The `$ARGUMENTS` are passed as initial context. Include the service name, environment, and
symptoms.

**Without arguments:**
The skill will ask for incident details interactively.

## Steps

1. Load the `incident-analysis` skill using the Skill tool.
2. Begin at Stage 1 — MITIGATE. Pre-populate scope from `$ARGUMENTS`:
   - Extract service name, environment (hb-prod, dg-prod, etc.), and symptoms
   - Convert any local times to UTC
   - Pass extracted context as MITIGATE Step 2 (Establish Scope) inputs
3. Follow the full investigation pipeline as defined in the skill.

## Important

- All investigation is **read-only** by default
- Remediation actions require **explicit user approval** (HITL gate)
- Must not bypass MITIGATE steps (tool detection, inventory, impact quantification)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-routing.sh 2>&1 | tail -20`
Expected: PASS on all investigate command assertions

- [ ] **Step 5: Commit**

```bash
git add commands/investigate.md tests/test-routing.sh
git commit -m "feat(incident-analysis): add /investigate command entry point"
```

---

## PR 2: Disambiguation Probes

### Task 3: Add disambiguation_probe schema validation to tests

**Files:**
- Edit: `tests/test-playbook-schema.sh`

- [ ] **Step 1: Add disambiguation_probe validation block**

Insert the following after the "Resolver cardinality" block (line 194) and before the closing `done` (line 196) in the main playbook loop in `tests/test-playbook-schema.sh`:

```bash
    # ------------------------------------------------------------------
    # Disambiguation probe validation (optional field)
    # ------------------------------------------------------------------
    has_probe="$(printf '%s' "${json}" | jq 'has("disambiguation_probe")')"

    if [ "${has_probe}" = "true" ]; then
        # query_ref must reference a valid key in queries
        probe_ref="$(printf '%s' "${json}" | jq -r '.disambiguation_probe.query_ref // empty')"
        assert_not_empty "${filename}: disambiguation_probe has query_ref" "${probe_ref}"

        if [ -n "${probe_ref}" ]; then
            has_queries="$(printf '%s' "${json}" | jq 'has("queries")')"
            if [ "${has_queries}" = "true" ]; then
                ref_exists="$(printf '%s' "${json}" | jq --arg ref "${probe_ref}" '.queries | has($ref)')"
                if [ "${ref_exists}" = "true" ]; then
                    _record_pass "${filename}: probe query_ref '${probe_ref}' exists in queries"
                else
                    _record_fail "${filename}: probe query_ref '${probe_ref}' exists in queries" "not found in queries object"
                fi
            else
                _record_fail "${filename}: probe query_ref '${probe_ref}' exists in queries" "playbook has no queries section"
            fi
        fi

        # resolves_signals must be non-empty array
        sig_count="$(printf '%s' "${json}" | jq '.disambiguation_probe.resolves_signals | length' 2>/dev/null)"
        if [ -n "${sig_count}" ] && [ "${sig_count}" -gt 0 ] 2>/dev/null; then
            _record_pass "${filename}: disambiguation_probe.resolves_signals is non-empty (${sig_count})"
        else
            _record_fail "${filename}: disambiguation_probe.resolves_signals is non-empty" "empty or missing"
        fi

        # Probe query must declare max_results (payload cap)
        if [ -n "${probe_ref}" ] && [ "${has_queries}" = "true" ]; then
            max_r="$(printf '%s' "${json}" | jq --arg ref "${probe_ref}" '.queries[$ref].params.max_results // empty')"
            if [ -n "${max_r}" ]; then
                _record_pass "${filename}: probe query '${probe_ref}' has max_results cap"
            else
                _record_fail "${filename}: probe query '${probe_ref}' has max_results cap" "payload cap missing"
            fi
        fi

        # Probe query kind must be read-only (not kubectl apply/patch/delete/scale)
        if [ -n "${probe_ref}" ] && [ "${has_queries}" = "true" ]; then
            probe_kind="$(printf '%s' "${json}" | jq -r --arg ref "${probe_ref}" '.queries[$ref].kind // empty')"
            probe_argv="$(printf '%s' "${json}" | jq -r --arg ref "${probe_ref}" '(.queries[$ref].command_argv // []) | join(" ")' 2>/dev/null)"
            write_cmd=""
            case "${probe_argv}" in
                *"kubectl apply"*|*"kubectl patch"*|*"kubectl delete"*|*"kubectl scale"*) write_cmd="yes" ;;
            esac
            if [ -z "${write_cmd}" ]; then
                _record_pass "${filename}: probe query '${probe_ref}' is read-only"
            else
                _record_fail "${filename}: probe query '${probe_ref}' is read-only" "contains write command: ${probe_argv}"
            fi
        fi

        # Warn if resolves_signals references a signal with distribution or ratio method
        resolve_sigs="$(printf '%s' "${json}" | jq -r '.disambiguation_probe.resolves_signals[]' 2>/dev/null)"
        if [ -n "${resolve_sigs}" ]; then
            IFS_SAVE="$IFS"
            IFS='
'
            for rsig in ${resolve_sigs}; do
                IFS="${IFS_SAVE}"
                sig_method="$(printf '%s' "${signal_json}" | jq -r --arg s "${rsig}" '.signals[$s].detection.method // empty')"
                case "${sig_method}" in
                    distribution|ratio)
                        printf "  WARN: %s: resolves_signals '%s' uses '%s' method (cannot be resolved from single probe)\n" "${filename}" "${rsig}" "${sig_method}"
                        ;;
                esac
            done
            IFS="${IFS_SAVE}"
        fi
    fi
```

Note: this block needs access to `signal_json`. Add these two lines **after** the `yaml_to_json` helper function definition (after line 19, not before it — `yaml_to_json` must be defined first):

```bash
SIGNAL_FILE="${PROJECT_ROOT}/skills/incident-analysis/signals.yaml"
signal_json="$(yaml_to_json "${SIGNAL_FILE}")"
```

- [ ] **Step 2: Run test to verify it passes (no playbooks have probes yet)**

Run: `bash tests/test-playbook-schema.sh`
Expected: PASS — existing playbooks don't have `disambiguation_probe`, so the block is skipped

- [ ] **Step 3: Commit**

```bash
git add tests/test-playbook-schema.sh
git commit -m "test(incident-analysis): add disambiguation_probe schema validation"
```

### Task 4: Add disambiguation_probe to dependency-failure playbook

**Files:**
- Edit: `skills/incident-analysis/playbooks/dependency-failure.yaml`

- [ ] **Step 1: Verify schema test will catch missing fields**

Temporarily add an invalid probe to dependency-failure.yaml to confirm tests catch it:

```yaml
disambiguation_probe:
  query_ref: nonexistent_query
  resolves_signals: []
```

Run: `bash tests/test-playbook-schema.sh`
Expected: FAIL on "probe query_ref 'nonexistent_query' exists in queries" and "resolves_signals is non-empty"

Remove the temporary invalid probe before proceeding.

- [ ] **Step 2: Add queries and disambiguation_probe**

Replace the full content of `skills/incident-analysis/playbooks/dependency-failure.yaml`:

```yaml
id: dependency-failure
title: Dependency Failure
category: dependency-failure
commandable: false

description: >
  Errors caused by upstream dependency failures. The primary service is
  healthy but cannot complete requests because a dependency is down or
  degraded.

signals:
  supporting:
    - upstream_dependency_errors
  contradicting: []
  veto_signals: []
  contradiction_penalty: 0

investigation_steps: |
  1. Identify failing dependency from error messages and traces
  2. Check dependency service health (pods, logs, metrics)
  3. Check Cloud SQL Proxy connections if database-related
  4. Determine if dependency failure is primary or cascading

queries:
  dependency_error_scan:
    kind: log_query
    description: "ERROR logs from known dependencies in same time window"
    params:
      scope: declared_dependencies
      severity: ERROR
      max_results: 10

disambiguation_probe:
  query_ref: dependency_error_scan
  resolves_signals:
    - upstream_dependency_errors

pre_conditions: []
post_conditions: []
hard_stop_conditions: []
stop_conditions: []

freshness_window_seconds: 300
stabilization_delay_seconds: 120
validation_window_seconds: 300
sample_interval_seconds: 30

state_fingerprint_fields: []
```

- [ ] **Step 3: Run tests to verify it passes**

Run: `bash tests/test-playbook-schema.sh && bash tests/test-signal-registry.sh`
Expected: PASS — probe query_ref valid, resolves_signals non-empty, signal exists in signals.yaml

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/playbooks/dependency-failure.yaml
git commit -m "feat(incident-analysis): add disambiguation probe to dependency-failure playbook"
```

### Task 5: Add disambiguation_probe to config-regression playbook

**Files:**
- Edit: `skills/incident-analysis/playbooks/config-regression.yaml`

- [ ] **Step 1: Read current file and add queries + probe**

Replace the full content of `skills/incident-analysis/playbooks/config-regression.yaml`:

```yaml
id: config-regression
title: Configuration Regression
category: bad-config
commandable: false

description: >
  Errors correlated with a configuration change rather than a code deployment.
  Investigate Helm value changes, ConfigMap updates, and Secret rotations.

signals:
  supporting:
    - config_change_correlated_with_errors
  contradicting: []
  veto_signals: []
  contradiction_penalty: 0

investigation_steps: |
  1. Check recent commits to config repo for the affected service
  2. Compare Helm values between current and previous versions
  3. Check ConfigMap and Secret changes in the namespace
  4. Check if Cloud SQL Proxy configuration changed

queries:
  config_change_scan:
    kind: log_query
    description: "Audit log entries for ConfigMap/Secret/HelmRelease changes in same namespace and time window"
    params:
      scope: same_namespace
      log_name: "cloudaudit.googleapis.com%2Factivity"
      max_results: 10

disambiguation_probe:
  query_ref: config_change_scan
  resolves_signals:
    - config_change_correlated_with_errors

pre_conditions: []
post_conditions: []
hard_stop_conditions: []
stop_conditions: []

freshness_window_seconds: 300
stabilization_delay_seconds: 120
validation_window_seconds: 300
sample_interval_seconds: 30

state_fingerprint_fields: []
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-playbook-schema.sh && bash tests/test-signal-registry.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/playbooks/config-regression.yaml
git commit -m "feat(incident-analysis): add disambiguation probe to config-regression playbook"
```

### Task 6: Add disambiguation_probe to infra-failure playbook

**Files:**
- Edit: `skills/incident-analysis/playbooks/infra-failure.yaml`

- [ ] **Step 1: Read current file and add queries + probe**

Replace the full content of `skills/incident-analysis/playbooks/infra-failure.yaml`:

```yaml
id: infra-failure
title: Infrastructure Failure
category: infra-failure
commandable: false

description: >
  General infrastructure-level failure affecting one or more services.
  Includes GKE node issues, network problems, and GCP service disruptions.

signals:
  supporting:
    - node_not_ready_detected
    - errors_localized_to_node
    - multiple_services_affected_simultaneously
  contradicting: []
  veto_signals: []
  contradiction_penalty: 0

investigation_steps: |
  1. Check GKE node status and conditions
  2. Check for GCP service incidents (status.cloud.google.com)
  3. Check network connectivity between services
  4. Determine blast radius — how many services affected?

queries:
  node_status_scan:
    kind: log_query
    description: "Node condition events (NotReady, SchedulingDisabled) in same time window"
    params:
      scope: same_cluster
      event_type: NodeNotReady
      max_results: 10

disambiguation_probe:
  query_ref: node_status_scan
  resolves_signals:
    - node_not_ready_detected

pre_conditions: []
post_conditions: []
hard_stop_conditions: []
stop_conditions: []

freshness_window_seconds: 300
stabilization_delay_seconds: 120
validation_window_seconds: 300
sample_interval_seconds: 30

state_fingerprint_fields: []
```

- [ ] **Step 2: Run tests**

Run: `bash tests/test-playbook-schema.sh && bash tests/test-signal-registry.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/playbooks/infra-failure.yaml
git commit -m "feat(incident-analysis): add disambiguation probe to infra-failure playbook"
```

### Task 7: Add resolves_signals cross-reference validation

**Files:**
- Edit: `tests/test-signal-registry.sh`

- [ ] **Step 1: Write failing test**

Add after the existing playbook signal cross-reference loop in `tests/test-signal-registry.sh`, before the compatibility section:

```bash
# ---------------------------------------------------------------------------
# For every signal in disambiguation_probe.resolves_signals, assert it exists
# ---------------------------------------------------------------------------
for yaml_file in "${PLAYBOOK_DIR}"/*.yaml; do
    filename="$(basename "${yaml_file}")"
    pb_json="$(yaml_to_json "${yaml_file}")"

    has_probe="$(printf '%s' "${pb_json}" | jq 'has("disambiguation_probe")')"
    if [ "${has_probe}" != "true" ]; then
        continue
    fi

    resolve_refs="$(printf '%s' "${pb_json}" | jq -r '.disambiguation_probe.resolves_signals[]' 2>/dev/null)"
    if [ -z "${resolve_refs}" ]; then
        continue
    fi

    IFS_SAVE="$IFS"
    IFS='
'
    for sig_id in ${resolve_refs}; do
        IFS="${IFS_SAVE}"
        found=""
        for key in ${signal_keys}; do
            if [ "${sig_id}" = "${key}" ]; then
                found="yes"
                break
            fi
        done
        if [ -n "${found}" ]; then
            _record_pass "${filename}: resolves_signal '${sig_id}' exists in signals.yaml"
        else
            _record_fail "${filename}: resolves_signal '${sig_id}' exists in signals.yaml" "not found in signals.yaml"
        fi
    done
    IFS="${IFS_SAVE}"
done
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/test-signal-registry.sh`
Expected: PASS — all resolves_signals reference valid signal IDs

- [ ] **Step 3: Commit**

```bash
git add tests/test-signal-registry.sh
git commit -m "test(incident-analysis): add resolves_signals cross-reference validation"
```

### Task 8: Update SKILL.md — CLASSIFY shortlist and medium-confidence output

**Files:**
- Edit: `skills/incident-analysis/SKILL.md`
- Edit: `tests/test-skill-content.sh`

- [ ] **Step 1: Write failing behavioral contract test**

Add to `tests/test-skill-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Disambiguation probe behavioral contracts
# (SKILL_CONTENT is already defined at the top of this test file)
# ---------------------------------------------------------------------------
assert_contains "SKILL.md has SHORTLIST artifact" "SHORTLIST:" "${SKILL_CONTENT}"
assert_contains "SKILL.md has classification_fingerprint" "classification_fingerprint" "${SKILL_CONTENT}"
assert_contains "SKILL.md has disambiguation_round" "disambiguation_round" "${SKILL_CONTENT}"
assert_contains "SKILL.md has pre_probe fingerprint" "pre_probe" "${SKILL_CONTENT}"
assert_contains "SKILL.md has Step 2b" "Step 2b" "${SKILL_CONTENT}"
assert_contains "SKILL.md has Targeted Disambiguation Probes" "Targeted Disambiguation Probes" "${SKILL_CONTENT}"
assert_contains "SKILL.md has scope exception for dependency probes" "declared/known dependencies" "${SKILL_CONTENT}"
assert_contains "SKILL.md has one probe round limit" "one probe round" "${SKILL_CONTENT}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-skill-content.sh`
Expected: FAIL on SHORTLIST, classification_fingerprint, Step 2b, etc.

- [ ] **Step 3: Update CLASSIFY medium-confidence decision record**

In `skills/incident-analysis/SKILL.md`, find the medium-confidence decision record section (around line 246). Replace the `SUGGESTED FOLLOW-UP` block in the medium-confidence template with:

```
SHORTLIST:
  leader:      <playbook_id> (<confidence>%)
  runner-up-1: <playbook_id> (<confidence>%), probe: <query_ref>
  runner-up-2: <playbook_id> (<confidence>%), probe: <query_ref>
  compatibility: [<leader_category>, <runner_category>] = <compatible|incompatible>
  disambiguation_round: pending
  classification_fingerprint: <service>/<time_window>/<pre_probe_signal_state_hash>

Shortlist eligibility: non-vetoed, confidence > 40, evaluable_weight > 0,
has declared disambiguation_probe, max 2 runner-ups.
```

Also update the text around the medium-confidence routing (around line 196-197) to explain that suggested follow-up queries are now the shortlisted probes:

```
**Medium confidence (60-84):**
Present the investigation summary with the medium-confidence decision record (see below).
No command block is shown. The SHORTLIST contains pre-canned disambiguation probes from
runner-up playbooks. Execute one probe per runner-up (read-only, aggregate-first,
max_results <= 10). After probes: existing signal evaluator recomputes affected signal
states, scorer re-ranks unchanged, mark `disambiguation_round: completed`. Normal confidence
routing continues — if still medium after probes, present findings without another probe
round for the same classification fingerprint.
```

- [ ] **Step 4: Add low-confidence shortlist handoff**

In the low-confidence routing section (around line 199-200), update to include the shortlist:

```
**Low confidence (< 60):**
Transition to INVESTIGATE Steps 1-5 only (limited investigation). Include the SHORTLIST
handoff artifact (same format as medium-confidence) so that Step 2b can consume it.
Findings feed back to CLASSIFY for reclassification.
```

- [ ] **Step 5: Add anti-looping rule**

After the Loop Termination section (around line 204), add:

```
### Disambiguation Anti-Looping

- The `classification_fingerprint` is derived from the **pre-probe** evidence snapshot
  (service + time_window + signal_state_hash computed before any probes ran). This fingerprint
  is stable across the probe → rerank cycle.
- At most one probe round per `classification_fingerprint`. After one round, mark
  `disambiguation_round: completed` on the handoff artifact. No second probe round for the
  same fingerprint regardless of confidence level after reranking.
- Probe outcomes are cached per fingerprint. The same probe cannot rerun in the same
  classification cycle unless evidence materially changed (new log queries, new time window).
- A timed-out or failed probe leaves its target signals as `unknown_unavailable`. A
  **timed-out or failed** probe may never strengthen a candidate. A successful probe may flip
  a signal to `detected` or `not_detected`, which feeds into the normal scorer rerank and may
  change the outcome. The existing scorer math and coverage gate are unchanged.
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/test-skill-content.sh`
Expected: PASS on all disambiguation behavioral contracts

- [ ] **Step 7: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-skill-content.sh
git commit -m "feat(incident-analysis): add CLASSIFY shortlist and disambiguation anti-looping"
```

### Task 9: Update SKILL.md — Step 2b and scope exception

**Files:**
- Edit: `skills/incident-analysis/SKILL.md`

- [ ] **Step 1: Add Step 2b to INVESTIGATE**

In `skills/incident-analysis/SKILL.md`, after Step 2: Extract Key Signals (around line 279-281), insert:

```
### Step 2b: Targeted Disambiguation Probes

**Entry condition:** CLASSIFY handoff includes a SHORTLIST with `disambiguation_round: pending`.
If no shortlist is present or `disambiguation_round: completed`, skip to Step 3.

For each runner-up in the shortlist (max 2):

1. Look up the runner-up's playbook and its `disambiguation_probe.query_ref`
2. Execute the referenced query — one read-only query per runner-up
3. Probe collects bounded evidence: aggregate-first (exists, count, distinct group count,
   latest timestamp, top offenders). Hard cap: `max_results <= 10`, at most 1-2 exemplar
   lines in the handoff.
4. The probe result feeds into the existing signal evaluator, which recomputes signal states
   for the IDs listed in `disambiguation_probe.resolves_signals`

**Probe-to-signal contract:** The signal's detection method must be satisfiable from probe
aggregates: `event_presence` (→ exists/count), `threshold` (→ metric value),
`temporal_correlation` (→ timestamps), `log_pattern` (→ match count). Signals with
`distribution` or `ratio` methods remain `unknown_unavailable` even if named in
`resolves_signals`.

After all probes complete:
- Return to CLASSIFY scorer with updated signal states (one rerun only)
- Mark `disambiguation_round: completed` on the handoff artifact
- Continue with normal confidence routing from the updated scores

**Timeout handling:** If a probe times out or fails, the target signals remain
`unknown_unavailable`. The probe may never strengthen a candidate. Falls through to normal
rerank with unchanged scorer math.
```

- [ ] **Step 2: Add scope exception to Behavioral Constraints**

In the scope restriction section (Constraint 2, around line 16-20), add a new paragraph after the infrastructure escalation exception:

```
**Disambiguation probe exception:** During Step 2b, probes for runner-up playbooks may query
outside the primary service scope — but only for declared/known dependencies of the
identified service, in the same time window, with a hard cap of one query per runner-up.
Probes must be declared in the playbook's `disambiguation_probe`, not generated ad-hoc.
This exception is bounded and auditable through the SHORTLIST artifact.
```

- [ ] **Step 3: Run all tests**

Run: `bash tests/run-tests.sh`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add Step 2b disambiguation probes and scope exception"
```

---

## PR 3: Eval Runner + Routing Tests

### Task 10: Add SLO burn rate trigger and routing test

**Files:**
- Edit: `config/default-triggers.json`
- Edit: `config/fallback-registry.json`
- Edit: `tests/test-routing.sh`

The existing incident-analysis triggers don't include SLO/burn-rate language. The production
trigger config, the fallback registry (used when cache is missing), and the test fixture
registry all need updating.

- [ ] **Step 1: Write failing routing test**

Add a new test function to `tests/test-routing.sh`. This test also updates the fixture
registry to include the new trigger pattern:

```bash
test_slo_burn_rate_routes_to_incident_analysis() {
    echo "-- test: SLO burn rate prompts route to incident-analysis --"
    setup_test_env
    install_registry_with_incident_analysis

    # Extend the fixture registry with SLO/burn-rate trigger
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '(.skills[] | select(.name == "incident-analysis") | .triggers) += ["(slo.*(burn|alert|breach|budget)|burn.?rate|error.budget)"]
      | (.skills[] | select(.name == "incident-analysis") | .keywords) += ["SLO burn rate", "error budget"]' \
      "${cache_file}" > "${tmp_file}" && mv "${tmp_file}" "${cache_file}"

    local output context

    output="$(run_hook "SLO burn rate alert fired on checkout-service, error budget depleting fast")"
    context="$(extract_context "${output}")"
    assert_contains "SLO burn rate routes to incident-analysis" "incident-analysis" "${context}"

    output="$(run_hook "burn rate exceeded 2x threshold on payment-service for 10 minutes")"
    context="$(extract_context "${output}")"
    assert_contains "burn rate language routes to incident-analysis" "incident-analysis" "${context}"

    teardown_test_env
}
```

Add `test_slo_burn_rate_routes_to_incident_analysis` to the test invocation list.

- [ ] **Step 2: Run test to verify the pattern works**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "SLO burn rate"`
Expected: PASS (fixture registry is patched inside the test to include the new trigger)

- [ ] **Step 3: Add SLO trigger to production config and fallback registry**

In `config/default-triggers.json`, find the incident-analysis entry's `triggers` array
(around line 411-414) and add a fourth trigger pattern:

```json
"(slo.*(burn|alert|breach|budget)|burn.?rate|error.budget)"
```

Also add to the `keywords` array:
```json
"SLO burn rate",
"error budget"
```

**Also update `config/fallback-registry.json`** with the same trigger and keyword additions.
The runtime falls back to the fallback registry when the cache is missing or invalid
(skill-activation-hook.sh line 59), so burn-rate prompts would miss incident-analysis on
the degraded path without this.

- [ ] **Step 4: Run full routing tests**

Run: `bash tests/test-routing.sh 2>&1 | tail -5`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add tests/test-routing.sh config/default-triggers.json config/fallback-registry.json
git commit -m "feat(incident-analysis): add SLO burn rate routing trigger"
```

### Task 11: Create fixture schema validator and authoring guidelines

**Files:**
- Create: `tests/test-incident-analysis-output.sh`
- Create: `tests/fixtures/incident-analysis/README.md`

- [ ] **Step 1: Create fixture directory and authoring guidelines**

Create `tests/fixtures/incident-analysis/README.md`:

```markdown
# Incident Analysis Test Fixtures

Fixtures for output quality testing of the incident-analysis skill.

## Authoring Rules

1. **Real incidents only.** Every fixture must come from an actual production incident
   postmortem. No synthetic cases authored by the skill developer.
2. **Ground truth is human-authored.** Expected outputs are written by the incident
   responder or postmortem author, not derived from running the skill.
3. **Minimal fixture structure:**

```json
{
  "id": "2026-03-15-checkout-oom",
  "description": "OOMKilled pods on checkout-service after memory limit change",
  "source_postmortem": "docs/postmortems/2026-03-15-checkout-oom.md",
  "input": {
    "service": "checkout-service",
    "environment": "hb-prod",
    "symptoms": "pods OOMKilled, 500 errors on /api/checkout",
    "time_window": "2026-03-15T14:00:00Z/2026-03-15T15:00:00Z"
  },
  "expected": {
    "root_cause_contains": ["OOMKilled", "memory limit"],
    "timeline_has_entries": true,
    "playbook_classification": "node-resource-exhaustion",
    "signals_detected": ["memory_pressure_detected", "crash_loop_detected"]
  }
}
```

4. **One file per incident.** Name: `YYYY-MM-DD-<kebab-summary>.json`
5. **No PII.** Redact service names, IPs, and user data if needed.
```

- [ ] **Step 2: Create fixture schema validator**

**Scope clarification:** This runner validates fixture JSON shape (required fields, input
sub-fields, non-empty expected). It does NOT invoke the skill against fixtures or compare
skill output to expected values — that requires a skill invocation harness which is out of
scope for this PR. The runner ensures fixture authoring discipline so that when an invocation
harness is built, the fixtures are ready to use.

Create `tests/test-incident-analysis-output.sh`:

```bash
#!/usr/bin/env bash
# test-incident-analysis-output.sh — Output quality validation for incident-analysis skill.
# Loads fixture files from tests/fixtures/incident-analysis/ and validates
# expected output fields. Fixtures must come from real incident postmortems.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-incident-analysis-output.sh ==="

FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/incident-analysis"

# ---------------------------------------------------------------------------
# Check fixture directory exists
# ---------------------------------------------------------------------------
if [ ! -d "${FIXTURE_DIR}" ]; then
    echo "  SKIP: No fixture directory at ${FIXTURE_DIR}"
    print_summary
    exit 0
fi

# ---------------------------------------------------------------------------
# Count fixtures (skip README)
# ---------------------------------------------------------------------------
fixture_count=0
for f in "${FIXTURE_DIR}"/*.json; do
    [ -f "${f}" ] || continue
    fixture_count=$((fixture_count + 1))
done

if [ "${fixture_count}" -eq 0 ]; then
    echo "  SKIP: No .json fixtures in ${FIXTURE_DIR}"
    echo "  NOTE: Fixtures must come from real incident postmortems (see README.md)"
    print_summary
    exit 0
fi

echo "  Found ${fixture_count} fixture(s)"

# ---------------------------------------------------------------------------
# Validate fixture schema
# ---------------------------------------------------------------------------
for fixture_file in "${FIXTURE_DIR}"/*.json; do
    [ -f "${fixture_file}" ] || continue
    fname="$(basename "${fixture_file}")"

    # Must be valid JSON
    if jq empty "${fixture_file}" 2>/dev/null; then
        _record_pass "${fname}: valid JSON"
    else
        _record_fail "${fname}: valid JSON" "JSON parse error"
        continue
    fi

    # Required fields
    for field in id description input expected; do
        val="$(jq -r ".${field} // empty" "${fixture_file}")"
        assert_not_empty "${fname}: has ${field}" "${val}"
    done

    # Input sub-fields
    for sub in service environment symptoms; do
        val="$(jq -r ".input.${sub} // empty" "${fixture_file}")"
        assert_not_empty "${fname}: input has ${sub}" "${val}"
    done

    # Expected must have at least one assertion field
    exp_keys="$(jq -r '.expected | keys | length' "${fixture_file}")"
    if [ "${exp_keys}" -gt 0 ] 2>/dev/null; then
        _record_pass "${fname}: expected has assertion fields (${exp_keys})"
    else
        _record_fail "${fname}: expected has assertion fields" "empty expected object"
    fi
done

print_summary
```

- [ ] **Step 3: Make runner executable and verify it runs**

```bash
chmod +x tests/test-incident-analysis-output.sh
bash tests/test-incident-analysis-output.sh
```

Expected: "SKIP: No .json fixtures" (graceful skip, exit 0)

- [ ] **Step 4: Commit**

```bash
git add tests/test-incident-analysis-output.sh tests/fixtures/incident-analysis/README.md
git commit -m "feat(incident-analysis): add eval runner skeleton and fixture guidelines"
```

---

## PR 4: Step 4b Source Analysis (within INVESTIGATE)

**Revised 2026-03-26:** Repositioned from a separate `## SOURCE_ANALYSIS` stage between
INVESTIGATE and EXECUTE to `### Step 4b` within INVESTIGATE, between Step 4 (trace
correlation) and Step 5 (hypothesis formation). See design debate outcome in
`docs/superpowers/plans/2026-03-26-parallel-agents-debate.md` and Oviva PR review for
context on the repositioning decision.

### Task 12: Write failing tests for Step 4b

**Files:**
- Edit: `tests/test-skill-content.sh`

- [ ] **Step 1: Add test assertions**

Add to `tests/test-skill-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Step 4b: Source Analysis — reference file
# ---------------------------------------------------------------------------
ref_file="${PROJECT_ROOT}/skills/incident-analysis/references/source-analysis.md"
assert_file_exists "source-analysis.md reference file" "${ref_file}"

ref_content="$(cat "${ref_file}")"
assert_contains "reference has GitHub API" "GitHub" "${ref_content}"
assert_contains "reference has regression heuristic" "regression" "${ref_content}"
assert_contains "reference has fail-open" "GitHub API unavailable" "${ref_content}"
assert_contains "reference has deployed_ref" "deployed_ref" "${ref_content}"
assert_contains "reference has resolved_commit_sha" "resolved_commit_sha" "${ref_content}"
assert_not_contains "reference does not use deployed_sha" "deployed_sha" "${ref_content}"
assert_contains "reference has structured source_files" "status: analyzed" "${ref_content}"
assert_contains "reference has workload identity" "workload identity" "${ref_content}"

# ---------------------------------------------------------------------------
# Step 4b: Source Analysis — SKILL.md placement
# ---------------------------------------------------------------------------
assert_contains "SKILL.md has Step 4b" "### Step 4b" "${SKILL_CONTENT}"
assert_contains "SKILL.md references source-analysis.md" "references/source-analysis.md" "${SKILL_CONTENT}"
assert_not_contains "SKILL.md has no separate SOURCE_ANALYSIS stage" "## SOURCE_ANALYSIS" "${SKILL_CONTENT}"

# Step 4b must appear before Step 5 (ordering check)
step4b_line="$(grep -n '### Step 4b' "${SKILL_FILE}" | head -1 | cut -d: -f1)"
step5_line="$(grep -n '### Step 5' "${SKILL_FILE}" | head -1 | cut -d: -f1)"

assert_not_empty "SKILL.md has Step 4b line number" "${step4b_line}"
assert_not_empty "SKILL.md has Step 5 line number" "${step5_line}"

if [ -n "${step4b_line}" ] && [ -n "${step5_line}" ] && [ "${step4b_line}" -lt "${step5_line}" ]; then
    _record_pass "Step 4b appears before Step 5"
else
    _record_fail "Step 4b appears before Step 5" "Step 4b line=${step4b_line:-missing}, Step 5 line=${step5_line:-missing}"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-skill-content.sh`
Expected: FAIL on "source-analysis.md reference file" and "SKILL.md has Step 4b"

### Task 13: Create source-analysis.md reference file

**Files:**
- Create: `skills/incident-analysis/references/source-analysis.md`

- [ ] **Step 1: Create the reference file**

Create `skills/incident-analysis/references/source-analysis.md` with the revised procedure:

- Workload identity resolution from trace/log resource labels (not k8s-name-assumptive)
- `deployed_ref` + `resolved_commit_sha` (not `deployed_sha`)
- Structured `source_files` schema with `status` field per file
- Bad-release-only gate (not config-regression or dependency-failure)
- Bounded scope: 1-2 top actionable stack frames, 1-2 files, last 3 commits within 48h
- Actionable-frame gate: skip minified/compiled/generated frames
- Deploy time window: deploy within incident window OR within 4h before start
- Bounded evidence: relevant hunk + context only, never full files or diffs
- Structured output contract with `source_analysis.status` enum
- Fail-open tiering: gh API → git show → guidance

- [ ] **Step 2: Run test to verify reference assertions pass**

Run: `bash tests/test-skill-content.sh`
Expected: Reference file assertions PASS; SKILL.md assertions still FAIL

### Task 14: Add Step 4b to SKILL.md

**Files:**
- Edit: `skills/incident-analysis/SKILL.md`

- [ ] **Step 1: Insert Step 4b**

In `skills/incident-analysis/SKILL.md`, insert after the end of Step 4 (Autonomous Trace
Correlation, after the "Synthesize the causal path only" section, ~line 343) and before
Step 5 (Formulate Root Cause Hypothesis, ~line 345):

~15-20 lines inline covering:
- Conditional trigger (bad-release gate + actionable stack frame + resolvable ref)
- Post-hop workload identity resolution rule
- Pointer to `references/source-analysis.md` for full procedure
- Structured output contract summary
- Fail-open behavior

- [ ] **Step 2: Run test to verify all assertions pass**

Run: `bash tests/test-skill-content.sh`
Expected: All PASS including Step 4b ordering and negative `## SOURCE_ANALYSIS` check

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests PASS

- [ ] **Step 4: SHIP BLOCKER — Real incident fixture gate**

**This PR must not be merged until a real incident fixture exercises the Step 4b path.**
The fixture must:
1. Exist in `tests/fixtures/incident-analysis/` as a `.json` file
2. Have `expected.source_analysis` field with `status` value
3. Come from a real incident where stack traces and deployment info were both available

If no such incident has occurred yet, this PR stays on a branch. The code is complete and
tested but the ship gate is unmet. Add a note to the PR description:

> **Ship gate:** Requires a real incident fixture with source analysis applicability.
> PR remains in draft until the fixture is added and validated.

---

## Self-Review Checklist

1. **Spec coverage:**
   - `/investigate` command → Task 2
   - `slo_burn_rate_alert` signal → Task 1
   - Disambiguation probes (CLASSIFY shortlist, Step 2b, playbook schema, anti-looping, scope exception) → Tasks 3-9
   - Eval runner + routing tests → Tasks 10-11
   - Step 4b source analysis (within INVESTIGATE) → Tasks 12-14
   - K8s signals → DROPPED (already exist), not in plan
   - Hybrid decomposition → DEFERRED, not in plan
   - K8s MCP → DEFERRED, not in plan

2. **Placeholder scan:** No TBD, TODO, or "similar to Task N" found.

3. **Type consistency:** `disambiguation_probe.query_ref`, `resolves_signals`, `classification_fingerprint`, `disambiguation_round` used consistently across SKILL.md, playbook YAML, and test assertions.

4. **Test coverage per PR:**
   - PR 1: signal-registry (signal exists), routing (command file, content)
   - PR 2: playbook-schema (5 assertions per probe), signal-registry (resolves_signals cross-ref), skill-content (6 behavioral contracts)
   - PR 3: routing (SLO burn rate), output runner (fixture schema validation)
   - PR 4: skill-content (Step 4b exists, ordering before Step 5, no separate SOURCE_ANALYSIS stage, reference exists, reference content, output contract fields)
