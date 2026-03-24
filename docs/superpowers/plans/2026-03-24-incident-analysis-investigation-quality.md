# Incident Analysis Investigation Quality Improvements

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the investigation quality gaps exposed by the 2026-03-24 backend-core postmortem — premature root cause declarations, wrong replica counts, unverified recovery times, and missed blast radius.

**Architecture:** Three targeted edits to the core SKILL.md (completeness gate, contradiction check, recovery requirement), one infrastructure routing hint, six new signal definitions in signals.yaml, and a new node-resource-exhaustion playbook.

**Tech Stack:** Markdown (SKILL.md), YAML (signals.yaml, playbook)

**Line number convention:** All SKILL.md line numbers reference the ORIGINAL file before any edits. When implementing, match on **content headings** (e.g., `### Step 5: Formulate Root Cause Hypothesis`), not absolute line numbers, since earlier tasks shift subsequent lines.

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `skills/incident-analysis/SKILL.md` | Modify | Core skill — 4 surgical edits |
| `skills/incident-analysis/signals.yaml` | Modify | Add 6 new signal definitions |
| `skills/incident-analysis/playbooks/node-resource-exhaustion.yaml` | Create | New investigation playbook |
| `skills/incident-analysis/playbooks/infra-failure.yaml` | Modify | Wire new signals into existing playbook |

---

### Task 1: Add contradiction check to INVESTIGATE Step 5

The current Step 5 ("Formulate Root Cause Hypothesis") is a bare heading with no guidance. This is where confirmation bias enters — the investigator picks a hypothesis and moves on without testing it.

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:304`

- [ ] **Step 1: Add content to the empty Step 5 heading**

Replace line 304's bare heading with:

```markdown
### Step 5: Formulate Root Cause Hypothesis

State the hypothesis in one sentence. Then:

1. **Contradiction test:** Identify the strongest piece of evidence that would DISPROVE this hypothesis. Query for it. If found, revise the hypothesis before proceeding.
2. **Symptom coverage:** List every observed symptom. Mark each as "explained" or "unexplained" by the hypothesis. If any symptom is unexplained, either expand the hypothesis or note it as an open question.
3. **Alternative hypotheses:** Name at least one alternative explanation. State why the primary hypothesis is preferred over it, citing specific evidence.
```

- [ ] **Step 2: Verify edit — syntax check**

Run: `bash -n skills/incident-analysis/SKILL.md 2>&1 || true` (markdown won't fail bash -n, but visually confirm no broken formatting)

Read the file at line 304 and confirm the three numbered items are present.

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add contradiction check to INVESTIGATE Step 5"
```

---

### Task 2: Add infrastructure routing hint after Step 3

When multiple pods/services fail simultaneously, the issue is usually at the node or infrastructure level. The current skill has no guidance to "look up" from application logs. Add a conditional hint after the Single-Service Deep Dive.

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:255` (after Step 3 content, before Step 4 heading)

- [ ] **Step 1: Insert the routing hint**

Insert after the Step 3 bullet list (after line 255, before the `### Step 4` heading):

```markdown
**Infrastructure escalation (conditional):** If Step 3 reveals that multiple pods or services are failing simultaneously — especially with `context deadline exceeded`, widespread probe timeouts, or errors localized to a single node — the root cause is likely at the node or infrastructure level, not the application level. Shift investigation to:
- Node resource metrics (memory/CPU allocatable utilization)
- kubelet logs (housekeeping delays, probe failures, eviction events)
- GCE serial console (kernel OOM, balloon driver, memory pressure)
- Audit logs (maintenance-controller, drain events)

If a `node-resource-exhaustion` playbook is available, transition to CLASSIFY for structured scoring.
```

- [ ] **Step 2: Verify edit**

Read lines 253-270 and confirm the hint sits between Step 3 and Step 4.

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add infrastructure escalation hint after INVESTIGATE Step 3"
```

---

### Task 3: Add investigation completeness gate before POSTMORTEM

This is the highest-value change. Currently, INVESTIGATE transitions to POSTMORTEM via Step 8 with no checklist. This is where we declared "gap closed" prematurely.

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:319` (replace the bare Step 8 heading)

- [ ] **Step 1: Replace Step 8 with the completeness gate**

Replace the current `### Step 8: Transition to POSTMORTEM` with:

```markdown
### Step 8: Investigation Completeness Gate

Before transitioning to POSTMORTEM, answer each question explicitly in the synthesis output. Any question answered "No" or "Unknown" becomes an **Open Question** in the postmortem — it MUST NOT be papered over with assumptions.

| # | Question | Required evidence |
|---|----------|-------------------|
| 1 | Does the root cause explain ALL observed symptoms? | List each symptom and whether the hypothesis accounts for it |
| 2 | What evidence would disprove this root cause? Did you look for it? | Name the disconfirming evidence sought and what was found |
| 3 | When did the incident start AND end? | Both timestamps from log/metric evidence, not estimation |
| 4 | How many instances/replicas/pods exist? How many were affected? | Verified from metrics or deployment spec, not inferred from log observation |
| 5 | Were other services or components affected? | Checked — list affected or state "checked, none found" |
| 6 | Is this condition systemic (other nodes/instances at similar risk)? | Checked or state "not assessed" |

**Gate rule:** If questions 1-3 have confident answers, proceed to POSTMORTEM. Questions 4-6 may be "not assessed" if investigation time is constrained, but must be flagged as open items. If question 1 or 2 is "No" or "Unknown," return to INVESTIGATE Step 1 with a revised hypothesis.

### Step 9: Transition to POSTMORTEM
```

- [ ] **Step 2: Update INVESTIGATE re-entry paragraph**

Find the re-entry paragraph at the top of Stage 2 (original line 240). It currently reads:

> "only Steps 1-5 run. Steps 6-8 (Flight Plan, context synthesis, POSTMORTEM transition) are SKIPPED."

Replace with:

> "only Steps 1-5 run. Steps 6-9 (Flight Plan, context synthesis, completeness gate, POSTMORTEM transition) are SKIPPED."

- [ ] **Step 3: Verify edit**

Read the INVESTIGATE section and confirm: (a) the re-entry paragraph references Steps 6-9, (b) the completeness gate table renders correctly, (c) Step 9 follows the gate.

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add completeness gate before POSTMORTEM transition"
```

---

### Task 4: Add recovery verification requirement to POSTMORTEM

The current POSTMORTEM Step 3 generates a timeline but doesn't require a verified recovery timestamp. This caused us to write "~3 min" when actual impact was 21 minutes.

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:436-443` (POSTMORTEM Step 3)

- [ ] **Step 1: Add recovery requirement to Step 3**

After the existing bullet list in Step 3 (after line 443, before the "Mitigation Applied" section), insert:

```markdown
**Recovery verification (mandatory):**
- Timeline MUST include a verified recovery timestamp with evidence source (e.g., "first successful DB connection at 13:54:09 per proxy logs")
- If recovery was not verified from evidence, state: "Recovery time not verified — estimated at X based on Y"
- Impact duration = verified recovery time minus incident start time. Do not estimate.
```

- [ ] **Step 2: Verify edit**

Read lines 436-455 (approximate) and confirm the recovery section sits between the bullet list and the "Mitigation Applied" section.

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): require verified recovery timestamp in postmortem"
```

---

### Task 5: Add new signal definitions to signals.yaml

Six new signals for node resource exhaustion detection. These are referenced by the new playbook (Task 7) and enrich the existing `infra-failure` playbook (Task 6).

**Files:**
- Modify: `skills/incident-analysis/signals.yaml` (append after the Infrastructure signals section, before Workload health signals)

- [ ] **Step 1: Add the new signals**

Insert after line 100 (after `node_not_ready_detected`), before the `# Workload health signals` comment:

```yaml
  multi_pod_probe_timeout:
    title: "Multiple pods failing probes with timeout"
    base_weight: 30
    detection:
      method: compound
      params:
        all_of:
          - method: event_presence
            params:
              event_type: Unhealthy
              min_distinct_pods: 3
              correlation_window_seconds: 60
          - method: log_pattern
            params:
              pattern: "context deadline exceeded"
              source: kubelet

  node_memory_overcommit:
    title: "Node non-evictable memory utilization > 85%"
    base_weight: 25
    detection:
      method: threshold
      params:
        metric: "kubernetes.io/node/memory/allocatable_utilization"
        metric_label_filter:
          memory_type: "non-evictable"
        operator: gte
        threshold_percent: 85
        sustained_for_seconds: 300

  kubelet_housekeeping_degraded:
    title: "kubelet housekeeping taking longer than expected"
    base_weight: 20
    detection:
      method: log_pattern
      params:
        pattern: "Housekeeping took longer than expected"
        source: kubelet
        min_occurrences: 3
        recency_window_seconds: 600

  kernel_memory_pressure:
    title: "Kernel memory pressure or balloon failure"
    base_weight: 15
    detection:
      method: compound
      params:
        any_of:
          - method: log_pattern
            params:
              pattern: "Under memory pressure"
              source: serial_console
          - method: log_pattern
            params:
              pattern: "Out of puff"
              source: serial_console

  request_exceeds_actual_usage:
    title: "Memory request significantly below actual usage"
    base_weight: 20
    detection:
      method: ratio
      params:
        numerator_metric: "kubernetes.io/container/memory/used_bytes"
        denominator_metric: "kubernetes.io/container/memory/request_bytes"
        operator: gte
        threshold_ratio: 1.5
        sustained_for_seconds: 3600

  node_metrics_normal:
    title: "Node memory and CPU utilization below 70%"
    base_weight: 0
    detection:
      method: compound
      params:
        all_of:
          - method: threshold
            params:
              metric: "kubernetes.io/node/memory/allocatable_utilization"
              metric_label_filter:
                memory_type: "non-evictable"
              operator: lt
              threshold_percent: 70
              sustained_for_seconds: 300
          - method: threshold
            params:
              metric: "kubernetes.io/node/cpu/allocatable_utilization"
              operator: lt
              threshold_percent: 70
              sustained_for_seconds: 300
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('skills/incident-analysis/signals.yaml'))" && echo "YAML valid"`

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/signals.yaml
git commit -m "feat(incident-analysis): add node resource exhaustion signals"
```

---

### Task 6: Wire new signals into existing infra-failure playbook

The existing `infra-failure.yaml` has only 2 signals and no investigation guidance. Add the new signals and basic investigation steps.

**Files:**
- Modify: `skills/incident-analysis/playbooks/infra-failure.yaml`

- [ ] **Step 1: Update the playbook**

Replace the entire file with:

```yaml
id: infra-failure
title: Infrastructure Failure
category: infra-failure
commandable: false

signals:
  supporting:
    - errors_localized_to_node
    - node_not_ready_detected
    - multi_pod_probe_timeout
    - node_memory_overcommit
    - kubelet_housekeeping_degraded
  contradicting:
    - error_rate_spike_correlated_with_deploy
  veto_signals: []
  contradiction_penalty: 15

investigation_guidance: |
  When this playbook matches, shift investigation from application logs to infrastructure:
  1. Identify the affected node(s) from pod distribution
  2. Query node memory/CPU metrics — check for chronic overcommit (hours, not minutes)
  3. Check kubelet logs for housekeeping delays and probe failures
  4. Check GCE serial console for kernel-level indicators
  5. Assess blast radius: what other pods/services are on the same node?
  6. Check scheduling: are resource requests realistic vs actual usage?

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

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('skills/incident-analysis/playbooks/infra-failure.yaml'))" && echo "YAML valid"`

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/playbooks/infra-failure.yaml
git commit -m "feat(incident-analysis): enrich infra-failure playbook with node exhaustion signals"
```

---

### Task 7: Create node-resource-exhaustion playbook

A dedicated investigation playbook for the specific pattern discovered in the 2026-03-24 incident: chronic node memory overcommit causing system-wide probe failures.

**Files:**
- Create: `skills/incident-analysis/playbooks/node-resource-exhaustion.yaml`

- [ ] **Step 1: Create the playbook**

```yaml
id: node-resource-exhaustion
title: Node Resource Exhaustion (Memory)
category: infra-failure
commandable: false

description: |
  Multiple services on a single k8s node experience simultaneous failures due to
  node-level memory exhaustion. Typically presents as widespread probe timeouts
  (context deadline exceeded), container restarts, and slow kubelet housekeeping.
  Often caused by memory requests significantly below actual usage, allowing the
  scheduler to overcommit the node.

signals:
  supporting:
    - multi_pod_probe_timeout
    - node_memory_overcommit
    - kubelet_housekeeping_degraded
    - kernel_memory_pressure
    - request_exceeds_actual_usage
    - errors_localized_to_node
    - liveness_probe_failures
  contradicting:
    - error_rate_spike_correlated_with_deploy
  veto_signals:
    - node_metrics_normal
  contradiction_penalty: 20

investigation_steps: |
  Structured investigation for node memory exhaustion. Follow in order:

  ## 1. Inventory
  - How many replicas does the deployment have? (metrics, not logs)
  - Which nodes host them? (pod distribution)
  - What are the resource requests, limits, and actual usage per pod?
  - What are the probe configurations (failureThreshold, timeoutSeconds)?

  ## 2. Node Health Timeline
  - Query node non-evictable memory utilization for 6-12 hours before incident
  - Is this chronic (hours of >85%) or acute (sudden spike)?
  - Query kubelet logs for housekeeping delays (expected vs actual)

  ## 3. Trigger Identification
  - Query kubelet logs for probe failures around incident time
  - How many pods failed probes? Were they all on the same node?
  - Check GCE serial console for virtio_balloon failures and kernel memory pressure
  - Check audit logs for maintenance-controller, drain events, deployment events
  - Rule out: rolling deployment, HPA events, manual actions

  ## 4. Blast Radius
  - What other pods/services run on the affected node?
  - Did they also experience failures? (check kubelet probe logs)
  - Do other nodes hosting the same workload have similar overcommit ratios?

  ## 5. Recovery Verification
  - When did affected proxies/containers restart?
  - When were first successful connections re-established?
  - Were pods restarted in-place (same node) or rescheduled?
  - If restarted on same node: how long did restart take? (indicates ongoing pressure)

  ## 6. Scheduling Math
  - Sum all container request_bytes on the affected node
  - Compare to node allocatable_bytes
  - Identify the largest contributors to the (actual - request) gap
  - Check if other nodes have similar overcommit patterns

compatible_with:
  - infra-failure

pre_conditions: []
post_conditions: []
hard_stop_conditions: []
stop_conditions: []

freshness_window_seconds: 600
stabilization_delay_seconds: 120
validation_window_seconds: 300
sample_interval_seconds: 30

state_fingerprint_fields:
  - node_memory_overcommit
  - multi_pod_probe_timeout
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('skills/incident-analysis/playbooks/node-resource-exhaustion.yaml'))" && echo "YAML valid"`

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/playbooks/node-resource-exhaustion.yaml
git commit -m "feat(incident-analysis): add node-resource-exhaustion investigation playbook"
```

---

### Task 8: Verify all changes together

- [ ] **Step 1: Validate all YAML files**

Run:
```bash
for f in skills/incident-analysis/signals.yaml skills/incident-analysis/playbooks/*.yaml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "OK: $f" || echo "FAIL: $f"
done
```

Expected: All OK.

- [ ] **Step 2: Verify signal references in playbooks**

Run:
```bash
# Extract all signal IDs from signals.yaml
python3 -c "
import yaml
with open('skills/incident-analysis/signals.yaml') as f:
    data = yaml.safe_load(f)
defined = set(data['signals'].keys())

# Check all playbooks for undefined signal references
import glob
for pb_path in glob.glob('skills/incident-analysis/playbooks/*.yaml'):
    with open(pb_path) as f:
        pb = yaml.safe_load(f)
    for section in ['supporting', 'contradicting', 'veto_signals']:
        for sig in (pb.get('signals', {}).get(section) or []):
            if sig not in defined:
                print(f'UNDEFINED: {sig} in {pb_path} [{section}]')
print('Signal reference check complete')
"
```

Expected: No UNDEFINED lines. `Signal reference check complete`.

- [ ] **Step 3: Check SKILL.md has correct step numbering**

Read the INVESTIGATE section and confirm steps are numbered 1-9 sequentially (Step 8 is now the completeness gate, Step 9 is the transition).

- [ ] **Step 4: Final commit if any fixups needed**

```bash
git add -A skills/incident-analysis/
git commit -m "fix(incident-analysis): fixup signal references and step numbering"
```

Only run if Step 2 or 3 found issues.
