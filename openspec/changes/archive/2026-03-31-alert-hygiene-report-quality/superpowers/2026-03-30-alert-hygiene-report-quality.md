# Alert Hygiene Report Quality Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four reproducible report quality gaps: lost config diffs on gate demotion, inflated open-incident hours, non-deterministic inventory health, and dropped silent-policy cleanup.

**Architecture:** Two files change. compute-clusters.py gains per-cluster `total_open_hours` and five inventory-level fields. SKILL.md gains a Proposed Config Diff section in the Investigate template and mandatory render rules for Dead/Orphaned Config, Inventory Health, and Silent Policy Cleanup.

**Tech Stack:** Python 3, Bash test harness (test-helpers.sh assertions)

**Spec:** `docs/superpowers/specs/2026-03-30-alert-hygiene-report-quality-design.md`

---

### Task 1: Add `total_open_hours` per cluster to compute-clusters.py

**Files:**
- Modify: `skills/alert-hygiene/scripts/compute-clusters.py:306-344` (results.append dict)
- Test: `tests/test-alert-hygiene-scripts.sh`

- [ ] **Step 1: Write the failing test**

Append to `tests/test-alert-hygiene-scripts.sh` immediately before the `# --- Scenario: cross-project alerts stay separated ---` line (line 277):

```bash
# Validate total_open_hours per cluster
FLAP_HOURS=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap.get('total_open_hours', 'MISSING'))
" 2>/dev/null)
# 50 incidents x 5 min = 250 min = 4.17 hours
assert_equals "flapping cluster total_open_hours computed" "4.2" "${FLAP_HOURS}"

CHRONIC_HOURS=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
chronic = [c for c in data['clusters'] if 'chronic' in c['policy_name'].lower()][0]
print(chronic.get('total_open_hours', 'MISSING'))
" 2>/dev/null)
# 10 incidents x 5 hours = 50 hours
assert_equals "chronic cluster total_open_hours computed" "50.0" "${CHRONIC_HOURS}"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | grep -E "total_open_hours|FAIL"`
Expected: FAIL — `total_open_hours` field returns `MISSING`

- [ ] **Step 3: Add `total_open_hours` to compute-clusters.py**

In `compute-clusters.py`, in the `results.append({...})` dict (after the `'median_retrigger_sec': med_retrig,` line), add:

```python
            'total_open_hours': round(sum(durations) / 3600, 1) if durations else 0,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | grep -E "total_open_hours|SUMMARY"`
Expected: both total_open_hours assertions PASS

- [ ] **Step 5: Commit**

```bash
git add skills/alert-hygiene/scripts/compute-clusters.py tests/test-alert-hygiene-scripts.sh
git commit -m "feat(alert-hygiene): add total_open_hours per cluster from actual durations"
```

---

### Task 2: Add inventory-level enrichment fields to compute-clusters.py

**Files:**
- Modify: `skills/alert-hygiene/scripts/compute-clusters.py:176-198` (compute_unlabeled_ranking and main output)
- Test: `tests/test-alert-hygiene-scripts.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test-alert-hygiene-scripts.sh` immediately after the existing `assert_equals "unlabeled policy has 10 raw incidents"` block (line 275), before the cross-project scenario:

```bash
# Validate zero_channel_policies — must fail with MISSING before implementation, not silently pass with default []
ZERO_CH_RAW=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
zc = data.get('zero_channel_policies')
print('MISSING' if zc is None else len(zc))
" 2>/dev/null)
assert_equals "zero zero-channel policies in fixture" "0" "${ZERO_CH_RAW}"

# Validate disabled_but_noisy_policies — must fail with MISSING before implementation
DISABLED_NOISY_RAW=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
dn = data.get('disabled_but_noisy_policies')
print('MISSING' if dn is None else len(dn))
" 2>/dev/null)
assert_equals "zero disabled-but-noisy in base fixture" "0" "${DISABLED_NOISY_RAW}"

# Validate silent_policy_count and silent_policy_total
SILENT_COUNT=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(data.get('silent_policy_count', 'MISSING'))
" 2>/dev/null)
assert_equals "zero silent policies (both have incidents)" "0" "${SILENT_COUNT}"

SILENT_TOTAL=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(data.get('silent_policy_total', 'MISSING'))
" 2>/dev/null)
assert_equals "silent_policy_total equals enabled policy count" "2" "${SILENT_TOTAL}"

# Validate condition_type_breakdown
COND_BREAKDOWN=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
bd = data.get('condition_type_breakdown', {})
print(bd.get('conditionThreshold', 'MISSING'))
" 2>/dev/null)
assert_equals "condition_type_breakdown has 2 conditionThreshold" "2" "${COND_BREAKDOWN}"
```

Also add a **disabled-but-noisy positive path** fixture. Append a new scenario after the empty-alerts scenario (line 360), before the `normalize_service_name` tests:

```bash
# --- Scenario: disabled noisy policy detected ---
DISABLED_FIXTURES=$(mktemp -d /tmp/ah-disabled-XXXXXX)

cat > "${DISABLED_FIXTURES}/policies.json" << 'FIXTURE'
[
  {
    "name": "projects/test/alertPolicies/active1",
    "displayName": "Active alert",
    "enabled": true,
    "userLabels": {"squad": "prod_alerts"},
    "conditions": [{"displayName": "c1", "type": "conditionThreshold", "filter": "metric.type=\"custom/m\"", "query": "", "comparison": "COMPARISON_GT", "thresholdValue": 100, "evaluationInterval": "60s", "duration": "300s", "aggregations": []}],
    "autoClose": "1800s",
    "notificationChannels": ["projects/test/notificationChannels/1"],
    "combiner": "OR"
  },
  {
    "name": "projects/test/alertPolicies/disabled1",
    "displayName": "Disabled noisy alert",
    "enabled": false,
    "userLabels": {"squad": "stale_alerts"},
    "conditions": [{"displayName": "c2", "type": "conditionPrometheusQueryLanguage", "filter": "", "query": "rate(m[5m]) > 1", "comparison": "", "thresholdValue": null, "evaluationInterval": "60s", "duration": "300s", "aggregations": []}],
    "autoClose": "",
    "notificationChannels": ["projects/test/notificationChannels/1"],
    "combiner": "OR"
  }
]
FIXTURE

python3 -c "
import json
from datetime import datetime, timedelta, timezone
alerts = []
base = datetime(2026, 3, 20, 10, 0, 0, tzinfo=timezone.utc)
# 5 incidents for the disabled policy
for i in range(5):
    open_t = base + timedelta(hours=i*2)
    close_t = open_t + timedelta(minutes=30)
    alerts.append({
        'name': f'projects/test/alerts/disabled-{i}',
        'state': 'CLOSED',
        'openTime': open_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'closeTime': close_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'policyName': 'projects/test/alertPolicies/disabled1',
        'policyDisplayName': 'Disabled noisy alert',
        'policyLabels': {'squad': 'stale_alerts'},
        'resourceType': 'k8s_container',
        'resourceProject': 'test-prod',
        'resourceLabels': {'project_id': 'test-prod', 'pod_name': 'pod-1'},
        'metricType': 'custom/metric',
        'conditionName': '',
    })
with open('${DISABLED_FIXTURES}/alerts.json', 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>&1

python3 "${SCRIPTS_DIR}/compute-clusters.py" \
    --policies "${DISABLED_FIXTURES}/policies.json" \
    --alerts "${DISABLED_FIXTURES}/alerts.json" \
    --output "${DISABLED_FIXTURES}/clusters.json" 2>&1
assert_equals "disabled-noisy compute-clusters runs" "0" "$?"

DISABLED_NOISY_COUNT=$(python3 -c "
import json
data = json.load(open('${DISABLED_FIXTURES}/clusters.json'))
dn = data.get('disabled_but_noisy_policies')
print('MISSING' if dn is None else len(dn))
" 2>/dev/null)
assert_equals "disabled-noisy fixture has 1 disabled noisy policy" "1" "${DISABLED_NOISY_COUNT}"

DISABLED_NOISY_NAME=$(python3 -c "
import json
data = json.load(open('${DISABLED_FIXTURES}/clusters.json'))
dn = data['disabled_but_noisy_policies']
print(dn[0]['policy_name'])
" 2>/dev/null)
assert_equals "disabled noisy policy name correct" "Disabled noisy alert" "${DISABLED_NOISY_NAME}"

DISABLED_NOISY_RAW2=$(python3 -c "
import json
data = json.load(open('${DISABLED_FIXTURES}/clusters.json'))
dn = data['disabled_but_noisy_policies']
print(dn[0]['raw_incidents'])
" 2>/dev/null)
assert_equals "disabled noisy policy has 5 raw incidents" "5" "${DISABLED_NOISY_RAW2}"

# Active policy should appear as silent (no incidents for it)
DISABLED_SILENT=$(python3 -c "
import json
data = json.load(open('${DISABLED_FIXTURES}/clusters.json'))
print(data.get('silent_policy_count', 'MISSING'))
" 2>/dev/null)
assert_equals "active policy with no incidents is silent" "1" "${DISABLED_SILENT}"

rm -rf "${DISABLED_FIXTURES}"
```

Also add a test for zero-channel detection using the existing `skey2` fixture (which has `notificationChannels: []`). Append after the existing `assert_equals "queue alert classified as other"` block (line 570), before the `rm -rf`:

```bash
# Validate zero_channel_policies from skey fixture (skey2 has no channels)
SKEY_ZERO_CH=$(python3 -c "
import json
data = json.load(open('${SKEY_FIXTURES}/clusters.json'))
zc = data.get('zero_channel_policies', [])
print(len(zc))
" 2>/dev/null)
assert_equals "skey fixture has 1 zero-channel policy" "1" "${SKEY_ZERO_CH}"

SKEY_ZERO_CH_NAME=$(python3 -c "
import json
data = json.load(open('${SKEY_FIXTURES}/clusters.json'))
zc = data.get('zero_channel_policies', [])
print(zc[0]['policy_name'] if zc else 'MISSING')
" 2>/dev/null)
assert_equals "zero-channel policy is Queue backlog alert" "Queue backlog alert" "${SKEY_ZERO_CH_NAME}"

SKEY_ZERO_CH_RAW=$(python3 -c "
import json
data = json.load(open('${SKEY_FIXTURES}/clusters.json'))
zc = data.get('zero_channel_policies', [])
print(zc[0].get('raw_incidents', 'MISSING') if zc else 'MISSING')
" 2>/dev/null)
assert_equals "zero-channel policy raw_incidents populated" "5" "${SKEY_ZERO_CH_RAW}"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | grep -E "zero-channel|silent|condition_type|disabled|FAIL"`
Expected: FAIL — all new fields return `MISSING` or wrong counts

- [ ] **Step 3: Implement inventory-level fields in compute-clusters.py**

The `compute_unlabeled_ranking` function already builds a `policy_raw` dict mapping policy full names to raw incident counts. The new fields need the same mapping. Refactor: extract `policy_raw` computation into `main()` so it's available for both `compute_unlabeled_ranking` and the new fields.

In `main()`, after `results.sort(...)` (line 346), replace the current output block with:

```python
    results.sort(key=lambda x: -x['raw_incidents'])
    metric_types = extract_metric_types(policies)

    # Build policy-level raw counts for inventory enrichment
    policy_raw = defaultdict(int)
    for c in results:
        pfn = c.get('policy_full_name', '')
        policy_raw[pfn] += c.get('raw_incidents', 0)

    unlabeled = compute_unlabeled_ranking(policies, results)

    # Inventory-level enrichment
    enabled_policies = [p for p in policies if p.get('enabled', True)]
    cluster_policy_ids = set(c.get('policy_full_name', '') for c in results)

    zero_channel = [
        {
            'policy_name': p['displayName'],
            'policy_id': p['name'],
            'enabled': True,
            'raw_incidents': policy_raw.get(p['name'], 0),
            'squad': p.get('userLabels', {}).get('squad', '-'),
        }
        for p in enabled_policies
        if len(p.get('notificationChannels', [])) == 0
    ]

    disabled_but_noisy = [
        {
            'policy_name': p['displayName'],
            'policy_id': p['name'],
            'raw_incidents': policy_raw.get(p['name'], 0),
            'squad': p.get('userLabels', {}).get('squad', '-'),
        }
        for p in policies
        if not p.get('enabled', True) and policy_raw.get(p['name'], 0) > 0
    ]

    silent_ids = set(p['name'] for p in enabled_policies) - cluster_policy_ids
    cond_types = Counter(
        c.get('type', 'unknown') for p in policies for c in p.get('conditions', [])
    )

    output = {
        'clusters': results,
        'metric_types_in_inventory': metric_types,
        'unlabeled_ranking': unlabeled,
        'zero_channel_policies': zero_channel,
        'disabled_but_noisy_policies': disabled_but_noisy,
        'silent_policy_count': len(silent_ids),
        'silent_policy_total': len(enabled_policies),
        'condition_type_breakdown': dict(cond_types),
    }
    with open(args.output, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"Computed {len(results)} clusters from {len(alerts)} incidents across {len(policies)} policies")
```

- [ ] **Step 4: Run the full test suite**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | tail -5`
Expected: all assertions PASS including new ones

- [ ] **Step 5: Commit**

```bash
git add skills/alert-hygiene/scripts/compute-clusters.py tests/test-alert-hygiene-scripts.sh
git commit -m "feat(alert-hygiene): add inventory-level enrichment to compute-clusters output"
```

---

### Task 3: Add Proposed Config Diff to SKILL.md Investigate template

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md:602-628` (Investigate Per-Item Template)

- [ ] **Step 1: Replace the Investigate Per-Item Template**

In `skills/alert-hygiene/SKILL.md`, replace the template block (lines 602-628) with:

````markdown
### Investigate Per-Item Template

```
### {N}. {investigation_title} [{High|Medium} / Stage 1]

**Policy ID:** projects/{project}/alertPolicies/{id}
**Target Owner:** {team}
**Scope:** {projects affected}
**Notification Reach:** {N} channels
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/{id}?project={project}) · [Search IaC](https://github.com/search?q=org%3A{github_org}+{id}&type=code)

**Situation:** {what is happening — 1-2 sentences}
**Impact:** {why it matters — incident counts, team effect}

#### Proposed Config Diff (pending gate resolution)
> Include this section ONLY when evidence basis is `measured` or `structural` AND a specific
> config diff is derivable. Omit entirely for heuristic-only items.

| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| {param}   | {value} | {value}  | {why this value was chosen} |

**Evidence Basis:** {measured|structural} — {detail}
**Gate Blocker:** {which Do Now gate requirement is missing}
**To Upgrade:** {resolve blocker} → promotes to Do Now

**Hypothesis:** {explicit, testable hypothesis}

**Stage 1 DoD (Discovery — this ticket):**
- {specific diagnostic steps}
- **Closes when:** hypothesis confirmed/refuted AND follow-up action documented as a separate item
- **Timebox:** {N} days

**Stage 2 (Execution — spawned follow-up):**
- **If confirmed:** {specific action with its own numeric outcome DoD}
- **If refuted:** {alternative action or close with rationale}
```
````

- [ ] **Step 2: Verify SKILL.md content test still passes**

Run: `bash tests/test-alert-hygiene-skill-content.sh 2>&1 | tail -5`
Expected: PASS (the content tests check for section headings, not template verbatim text)

- [ ] **Step 3: Commit**

```bash
git add skills/alert-hygiene/SKILL.md
git commit -m "feat(alert-hygiene): add Proposed Config Diff to Investigate template"
```

---

### Task 4: Update SKILL.md report skeleton for mandatory inventory sections

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md:731-744` (Dead/Orphaned Config, Inventory Health)

- [ ] **Step 1: Replace Dead/Orphaned Config section**

In `skills/alert-hygiene/SKILL.md`, replace lines 731-733:

```markdown
### Dead/Orphaned Config
- Zero-channel policies (no notification path)
- Disabled-but-still-noisy policies
```

with:

```markdown
### Dead/Orphaned Config
Read from compute-clusters output — do not compute ad-hoc.

**Zero-channel policies:** Read `zero_channel_policies` array. If non-empty, render table:

| Policy | Policy ID | Raw ({days}d) | Squad |
|--------|-----------|---------------|-------|

If empty: *"No zero-channel policies found."*

**Disabled-but-still-noisy:** Read `disabled_but_noisy_policies` array. If non-empty, render table with same columns. If empty: *"No disabled-but-noisy policies."*
```

- [ ] **Step 2: Replace Inventory Health section**

In `skills/alert-hygiene/SKILL.md`, replace lines 741-744:

```markdown
### Inventory Health
- Silent policy ratio (zero incidents in analysis window)
- Condition type breakdown (PromQL vs conditionThreshold vs MQL)
- Enabled/disabled counts
```

with:

```markdown
### Inventory Health
Read from compute-clusters output — do not compute ad-hoc.

- **Silent policy ratio:** `silent_policy_count` / `silent_policy_total` from compute-clusters output
- **Condition type breakdown:** render `condition_type_breakdown` dict from compute-clusters output
- **Enabled/disabled counts:** from Stage 1 policy pull (no change)
```

- [ ] **Step 3: Add Silent Policy Cleanup trigger to Needs Decision guidance**

After the existing `### Needs Decision Rules` section in SKILL.md, add:

```markdown
### Mandatory Needs Decision Triggers

The following Needs Decision items are mandatory when their trigger condition is met:

- **Silent Policy Cleanup:** If `silent_policy_total > 0` and `silent_policy_count / silent_policy_total > 0.5` (more than half of enabled policies had zero incidents in the analysis window), include a "Silent Policy Cleanup" Needs Decision item with exact counts from compute-clusters output.
```

- [ ] **Step 4: Add content test assertions for new SKILL.md sections**

Append to `tests/test-alert-hygiene-skill-content.sh` before the `print_summary` line:

```bash
# --- Report quality improvements (v4) ---

# Investigate template: Proposed Config Diff
assert_contains "investigate proposed config diff" "Proposed Config Diff" "${SKILL_CONTENT}"
assert_contains "investigate gate blocker field" "Gate Blocker:" "${SKILL_CONTENT}"

# Dead/Orphaned Config reads from script output
assert_contains "dead orphaned reads zero_channel_policies" "zero_channel_policies" "${SKILL_CONTENT}"
assert_contains "dead orphaned reads disabled_but_noisy" "disabled_but_noisy_policies" "${SKILL_CONTENT}"

# Inventory Health reads from script output
assert_contains "inventory health reads silent_policy_count" "silent_policy_count" "${SKILL_CONTENT}"
assert_contains "inventory health reads silent_policy_total" "silent_policy_total" "${SKILL_CONTENT}"
assert_contains "inventory health reads condition_type_breakdown" "condition_type_breakdown" "${SKILL_CONTENT}"

# Mandatory Needs Decision trigger
assert_contains "mandatory needs decision triggers section" "Mandatory Needs Decision Triggers" "${SKILL_CONTENT}"
assert_contains "silent policy cleanup trigger" "Silent Policy Cleanup" "${SKILL_CONTENT}"
```

- [ ] **Step 5: Run SKILL.md content tests — expect new assertions to pass**

Run: `bash tests/test-alert-hygiene-skill-content.sh 2>&1 | tail -5`
Expected: all assertions PASS (including new ones — the SKILL.md changes from Steps 1-3 should satisfy them)

- [ ] **Step 6: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`
Expected: all test files pass

- [ ] **Step 7: Commit**

```bash
git add skills/alert-hygiene/SKILL.md tests/test-alert-hygiene-skill-content.sh
git commit -m "feat(alert-hygiene): mandatory report sections from deterministic script output"
```
