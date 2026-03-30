# Alert Hygiene: Terraform, Routing & SLO Refinements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add IaC location resolution, routing validation, and SLO coverage cross-referencing to the alert-hygiene skill.

**Architecture:** Extend `compute-clusters.py` with two new fields (`service_key`, `signal_family`), add SLO config enrichment to Stage 1, extend Stage 4 with routing validation and SLO cross-reference, and add IaC search to Stage 5. All GitHub-dependent features are optional enrichment with graceful degradation.

**Tech Stack:** Python 3 (stdlib only), Ruby (stdlib yaml/json), Bash 3.2, `gh` CLI

**Spec:** `docs/superpowers/specs/2026-03-30-alert-hygiene-terraform-routing-slo-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `skills/alert-hygiene/scripts/compute-clusters.py` | Add `extract_service_key()`, `normalize_service_name()`, `classify_signal_family()` functions; emit `service_key` and `signal_family` per cluster |
| `skills/alert-hygiene/SKILL.md` | Stage 1 SLO enrichment instructions, Stage 4 routing validation + SLO cross-reference, Stage 5 IaC search |
| `tests/test-alert-hygiene-scripts.sh` | Tests for new script fields, normalization, signal classification |
| `tests/test-alert-hygiene-skill-content.sh` | Content assertions for new SKILL.md sections |

---

### Task 1: Add `normalize_service_name()` to compute-clusters.py

**Files:**
- Modify: `skills/alert-hygiene/scripts/compute-clusters.py:9` (imports area)
- Modify: `skills/alert-hygiene/scripts/compute-clusters.py:100` (after `check_label_inconsistency`)
- Test: `tests/test-alert-hygiene-scripts.sh`

- [ ] **Step 1: Write the failing test**

Add to `tests/test-alert-hygiene-scripts.sh`, before the `# --- Trigger config ---` line (line 366):

```bash
# --- normalize_service_name ---
NORM_RESULT=$(python3 -c "
import sys; sys.path.insert(0, '${SCRIPTS_DIR}')
from importlib import import_module
cc = import_module('compute-clusters')
cases = [
    ('diet-suggestions-prod', 'diet-suggestions'),
    ('Diet_Suggestions', 'diet-suggestions'),
    ('hcs.gb.staging', 'hcs-gb'),
    ('user-service', 'user-service'),
    ('my-app-pta', 'my-app'),
    ('simple', 'simple'),
]
for inp, expected in cases:
    result = cc.normalize_service_name(inp)
    assert result == expected, f'{inp!r} -> {result!r}, expected {expected!r}'
print('all_passed')
" 2>&1)
assert_equals "normalize_service_name handles all cases" "all_passed" "${NORM_RESULT}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | tail -20`
Expected: FAIL — `normalize_service_name` not defined

- [ ] **Step 3: Write minimal implementation**

Add after `check_label_inconsistency()` function (after line 99 in compute-clusters.py):

```python
def normalize_service_name(name):
    """Normalize service name: lowercase, replace separators, strip env suffixes."""
    if not name:
        return None
    n = name.lower().replace('_', '-').replace('.', '-')
    n = re.sub(r'-(prod|staging|pta)$', '', n)
    return n or None
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | tail -20`
Expected: PASS for `normalize_service_name handles all cases`

- [ ] **Step 5: Commit**

```bash
git add skills/alert-hygiene/scripts/compute-clusters.py tests/test-alert-hygiene-scripts.sh
git commit -m "feat(alert-hygiene): add normalize_service_name to compute-clusters"
```

---

### Task 2: Add `extract_service_key()` to compute-clusters.py

**Files:**
- Modify: `skills/alert-hygiene/scripts/compute-clusters.py` (after `normalize_service_name`)
- Test: `tests/test-alert-hygiene-scripts.sh`

- [ ] **Step 1: Write the failing test**

Add after the normalization test block:

```bash
# --- extract_service_key ---
SKEY_RESULT=$(python3 -c "
import sys; sys.path.insert(0, '${SCRIPTS_DIR}')
from importlib import import_module
cc = import_module('compute-clusters')
cases = [
    # container_name in filter
    ('metric.type=\"custom/m\" AND resource.labels.container_name=\"diet-suggestions-prod\"', '', 'diet-suggestions'),
    # short-form container in PromQL query
    ('', 'rate(http_requests{container=\"hcs-gb\"}[5m]) > 100', 'hcs-gb'),
    # application label in filter
    ('metric.labels.application=\"user-service\"', '', 'user-service'),
    # service label in query
    ('', 'rate(errors{service=\"payment.service.staging\"}[5m]) > 0.01', 'payment-service'),
    # no extractable service
    ('metric.type=\"custom/m\"', 'sum(rate(m[5m])) > 100', None),
    # container_name takes priority over application
    ('resource.labels.container_name=\"foo\" AND metric.labels.application=\"bar\"', '', 'foo'),
]
for filt, query, expected in cases:
    result = cc.extract_service_key(filt, query)
    assert result == expected, f'filter={filt!r}, query={query!r} -> {result!r}, expected {expected!r}'
print('all_passed')
" 2>&1)
assert_equals "extract_service_key handles all cases" "all_passed" "${SKEY_RESULT}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | tail -20`
Expected: FAIL — `extract_service_key` not defined

- [ ] **Step 3: Write minimal implementation**

Add after `normalize_service_name()`:

```python
def extract_service_key(condition_filter, condition_query):
    """Extract deterministic service identity from condition filter/query.

    Priority: container_name > container > application > service > None.
    Returns normalized name or None.
    """
    combined = condition_filter + ' ' + condition_query
    # Priority 1: container_name (full form)
    m = re.search(r'resource\.labels\.container_name\s*=\s*"([^"]+)"', combined)
    if m:
        return normalize_service_name(m.group(1))
    # Priority 2: container (short form, common in PromQL)
    m = re.search(r'container\s*=\s*"([^"]+)"', combined)
    if m:
        return normalize_service_name(m.group(1))
    # Priority 3: application label
    m = re.search(r'(?:metric\.labels\.)?application\s*=\s*"([^"]+)"', combined)
    if m:
        return normalize_service_name(m.group(1))
    # Priority 4: service label
    m = re.search(r'(?:metric\.labels\.)?service\s*=\s*"([^"]+)"', combined)
    if m:
        return normalize_service_name(m.group(1))
    return None
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | tail -20`
Expected: PASS for `extract_service_key handles all cases`

- [ ] **Step 5: Commit**

```bash
git add skills/alert-hygiene/scripts/compute-clusters.py tests/test-alert-hygiene-scripts.sh
git commit -m "feat(alert-hygiene): add extract_service_key to compute-clusters"
```

---

### Task 3: Add `classify_signal_family()` to compute-clusters.py

**Files:**
- Modify: `skills/alert-hygiene/scripts/compute-clusters.py` (after `extract_service_key`)
- Test: `tests/test-alert-hygiene-scripts.sh`

- [ ] **Step 1: Write the failing test**

Add after the service_key test block:

```bash
# --- classify_signal_family ---
SIGFAM_RESULT=$(python3 -c "
import sys; sys.path.insert(0, '${SCRIPTS_DIR}')
from importlib import import_module
cc = import_module('compute-clusters')
cases = [
    # error_rate: status match in query
    ('', 'rate(http_requests{status=~\"5..\"}[5m]) > 0.01', 'custom/http_requests', 'error_rate'),
    # error_rate: error in filter
    ('metric.labels.status = starts_with(\"5\")', '', 'prometheus.googleapis.com/http_server_requests_seconds_count/summary', 'error_rate'),
    # latency: duration metric
    ('', 'avg(rate(http_duration_sum[5m])) / avg(rate(http_duration_count[5m])) > 0.5', 'custom/http_duration', 'latency'),
    # latency: latency in metric type
    ('metric.type=\"dbinsights.googleapis.com/perquery/latencies\"', '', 'dbinsights.googleapis.com/perquery/latencies', 'latency'),
    # latency: response_time in metric type
    ('', '', 'prometheus.googleapis.com/http_response_time/gauge', 'latency'),
    # availability: uptime in metric type
    ('', '', 'monitoring.googleapis.com/uptime_check/check_passed', 'availability'),
    # availability: probe in metric type
    ('', '', 'kubernetes.io/container/probe/failure_count', 'availability'),
    # other: queue metric
    ('', '', 'pubsub.googleapis.com/subscription/num_undelivered_messages', 'other'),
    # other: generic custom metric
    ('', 'sum(rate(m[5m])) > 100', 'custom/metric', 'other'),
]
for filt, query, mt, expected in cases:
    result = cc.classify_signal_family(filt, query, mt)
    assert result == expected, f'filter={filt!r}, query={query!r}, mt={mt!r} -> {result!r}, expected {expected!r}'
print('all_passed')
" 2>&1)
assert_equals "classify_signal_family handles all cases" "all_passed" "${SIGFAM_RESULT}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | tail -20`
Expected: FAIL — `classify_signal_family` not defined

- [ ] **Step 3: Write minimal implementation**

Add after `extract_service_key()`:

```python
def classify_signal_family(condition_filter, condition_query, metric_type):
    """Classify alert signal family from condition semantics.

    Priority: query/filter content > metric_type name.
    Returns: error_rate | latency | availability | other.
    """
    combined = (condition_filter + ' ' + condition_query).lower()
    mt_lower = metric_type.lower()
    # Priority 1: error_rate — status match in query/filter
    if re.search(r'(status\s*[=~]+\s*"?5|5xx|error|status\s*>=\s*500)', combined):
        return 'error_rate'
    # Priority 2: latency — percentile/duration/response_time
    if re.search(r'(percentile|latenc|duration|response.time)', combined + ' ' + mt_lower):
        return 'latency'
    # Priority 3: availability — uptime/probe/health
    if re.search(r'(uptime|probe|health)', mt_lower):
        return 'availability'
    # Default
    return 'other'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | tail -20`
Expected: PASS for `classify_signal_family handles all cases`

- [ ] **Step 5: Commit**

```bash
git add skills/alert-hygiene/scripts/compute-clusters.py tests/test-alert-hygiene-scripts.sh
git commit -m "feat(alert-hygiene): add classify_signal_family to compute-clusters"
```

---

### Task 4: Wire `service_key` and `signal_family` into cluster output

**Files:**
- Modify: `skills/alert-hygiene/scripts/compute-clusters.py:250-279` (results.append block)
- Test: `tests/test-alert-hygiene-scripts.sh`

- [ ] **Step 1: Write the failing test**

Add after the signal_family test block. This tests the full pipeline with the existing synthetic fixtures (which already have `condition_filter` and `condition_query` fields):

```bash
# --- service_key and signal_family in cluster output ---
# Create a fixture with PromQL-style conditions that have extractable service keys
cat > "${FIXTURES_DIR}/skey-policies.json" << 'FIXTURE'
[
  {
    "name": "projects/test/alertPolicies/skey1",
    "displayName": "Error rate for diet-suggestions-prod",
    "enabled": true,
    "userLabels": {"squad": "cosmos_alerts"},
    "conditions": [{
      "displayName": "error rate > 1%",
      "type": "conditionPrometheusQueryLanguage",
      "filter": "",
      "query": "rate(http_server_requests_seconds_count{container=\"diet-suggestions-prod\", status=~\"5..\"}[5m]) / rate(http_server_requests_seconds_count{container=\"diet-suggestions-prod\"}[5m]) > 0.01",
      "comparison": "",
      "thresholdValue": null,
      "evaluationInterval": "60s",
      "duration": "300s",
      "aggregations": []
    }],
    "autoClose": "300s",
    "notificationChannels": ["projects/test/notificationChannels/1"],
    "combiner": "OR"
  },
  {
    "name": "projects/test/alertPolicies/skey2",
    "displayName": "Queue backlog alert",
    "enabled": true,
    "userLabels": {},
    "conditions": [{
      "displayName": "backlog > 1000",
      "type": "conditionThreshold",
      "filter": "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\"",
      "query": "",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 1000,
      "evaluationInterval": "60s",
      "duration": "300s",
      "aggregations": []
    }],
    "autoClose": "",
    "notificationChannels": [],
    "combiner": "OR"
  }
]
FIXTURE

python3 -c "
import json
from datetime import datetime, timedelta, timezone
alerts = []
base = datetime(2026, 3, 20, 10, 0, 0, tzinfo=timezone.utc)
for i in range(25):
    open_t = base + timedelta(minutes=i*30)
    close_t = open_t + timedelta(minutes=10)
    alerts.append({
        'name': f'projects/test/alerts/skey1-{i}',
        'state': 'CLOSED',
        'openTime': open_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'closeTime': close_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'policyName': 'projects/test/alertPolicies/skey1',
        'policyDisplayName': 'Error rate for diet-suggestions-prod',
        'policyLabels': {'squad': 'cosmos_alerts'},
        'resourceType': 'k8s_container',
        'resourceProject': 'oviva-k8s-prod',
        'resourceLabels': {'project_id': 'oviva-k8s-prod', 'pod_name': 'pod-1'},
        'metricType': 'prometheus.googleapis.com/http_server_requests_seconds_count/summary',
        'conditionName': 'projects/test/alertPolicies/skey1/conditions/A',
    })
for i in range(5):
    open_t = base + timedelta(hours=i*4)
    close_t = open_t + timedelta(hours=2)
    alerts.append({
        'name': f'projects/test/alerts/skey2-{i}',
        'state': 'CLOSED',
        'openTime': open_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'closeTime': close_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'policyName': 'projects/test/alertPolicies/skey2',
        'policyDisplayName': 'Queue backlog alert',
        'policyLabels': {},
        'resourceType': 'pubsub_subscription',
        'resourceProject': 'oviva-k8s-prod',
        'resourceLabels': {'project_id': 'oviva-k8s-prod', 'subscription': 'my-sub'},
        'metricType': 'pubsub.googleapis.com/subscription/num_undelivered_messages',
        'conditionName': 'projects/test/alertPolicies/skey2/conditions/A',
    })
with open('${FIXTURES_DIR}/skey-alerts.json', 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>&1

python3 "${SCRIPTS_DIR}/compute-clusters.py" \
    --policies "${FIXTURES_DIR}/skey-policies.json" \
    --alerts "${FIXTURES_DIR}/skey-alerts.json" \
    --output "${FIXTURES_DIR}/skey-clusters.json" 2>&1
assert_equals "skey compute-clusters runs" "0" "$?"

# Validate service_key extraction
SKEY_DIET=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/skey-clusters.json'))
c = [c for c in data['clusters'] if 'diet' in c['policy_name'].lower()][0]
print(c.get('service_key', 'MISSING'))
" 2>/dev/null)
assert_equals "diet-suggestions service_key extracted and normalized" "diet-suggestions" "${SKEY_DIET}"

# Validate signal_family for error-rate alert
SIGFAM_DIET=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/skey-clusters.json'))
c = [c for c in data['clusters'] if 'diet' in c['policy_name'].lower()][0]
print(c.get('signal_family', 'MISSING'))
" 2>/dev/null)
assert_equals "diet-suggestions classified as error_rate" "error_rate" "${SIGFAM_DIET}"

# Validate queue alert has null service_key and other signal_family
SKEY_QUEUE=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/skey-clusters.json'))
c = [c for c in data['clusters'] if 'queue' in c['policy_name'].lower()][0]
print(c.get('service_key'))
" 2>/dev/null)
assert_equals "queue alert has null service_key" "None" "${SKEY_QUEUE}"

SIGFAM_QUEUE=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/skey-clusters.json'))
c = [c for c in data['clusters'] if 'queue' in c['policy_name'].lower()][0]
print(c.get('signal_family', 'MISSING'))
" 2>/dev/null)
assert_equals "queue alert classified as other" "other" "${SIGFAM_QUEUE}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | tail -20`
Expected: FAIL — `service_key` and `signal_family` fields missing from cluster output

- [ ] **Step 3: Write minimal implementation**

In `compute-clusters.py`, in the `main()` function's `results.append()` block (around line 250), add two fields after `'condition_match': cond_match,`:

```python
            'service_key': extract_service_key(
                matched_cond.get('filter', '') if matched_cond else '',
                matched_cond.get('query', '') if matched_cond else '',
            ),
            'signal_family': classify_signal_family(
                matched_cond.get('filter', '') if matched_cond else '',
                matched_cond.get('query', '') if matched_cond else '',
                mt,
            ),
```

This uses the variables already in scope: `matched_cond` (line 200-208) and `mt` (line 183).

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | tail -20`
Expected: PASS for all new service_key and signal_family assertions

- [ ] **Step 5: Also verify existing tests still pass**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1 | grep -E '(PASS|FAIL|Tests)'`
Expected: All existing tests still PASS, new tests PASS, 0 failures

- [ ] **Step 6: Commit**

```bash
git add skills/alert-hygiene/scripts/compute-clusters.py tests/test-alert-hygiene-scripts.sh
git commit -m "feat(alert-hygiene): wire service_key and signal_family into cluster output"
```

---

### Task 5: Add SLO enrichment instructions to SKILL.md Stage 1

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md:99-105` (Stage 1 section)

- [ ] **Step 1: Add SLO enrichment block to Stage 1**

After the existing Stage 1 content (line 105, after "Policies by squad label"), add:

```markdown
#### Optional: SLO Config Enrichment

After pulling policies and incidents, attempt to fetch SLO service definitions from GitHub. This is optional enrichment — the core analysis runs without it.

**Preconditions:** `{github_org}` was provided in Stage 0 AND `gh` CLI is available AND authenticated (`gh auth status` succeeds). If any precondition fails, write fallback artifacts and skip.

**Flow:**

```bash
REPO="${github_org}/monitoring"

# Short-circuit if preconditions not met
if [ -z "${github_org:-}" ]; then
  echo '{"status":"unavailable","reason":"github_org_not_provided","count":0}' \
    > "$WORK_DIR/slo-source-status.json"
  echo '[]' > "$WORK_DIR/slo-services.json"
elif ! command -v gh &>/dev/null || ! gh auth status &>/dev/null 2>&1; then
  echo '{"status":"unavailable","reason":"gh_not_available","count":0}' \
    > "$WORK_DIR/slo-source-status.json"
  echo '[]' > "$WORK_DIR/slo-services.json"
else
  # Step 1: fetch (checked)
  if ! gh api "repos/$REPO/contents/tf/slo-config.yaml" \
       --jq '.content' > "$WORK_DIR/slo-raw-b64.txt" 2>"$WORK_DIR/slo-fetch-err.txt"; then
    echo '{"status":"unavailable","reason":"fetch_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  # Step 2: decode (checked)
  elif ! base64 -d < "$WORK_DIR/slo-raw-b64.txt" > "$WORK_DIR/slo-config.yaml" 2>/dev/null; then
    echo '{"status":"unavailable","reason":"decode_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  # Step 3: extract service names (checked — Ruby stdlib YAML, no PyYAML)
  elif ! ruby -ryaml -rjson -e '
    cfg = YAML.safe_load(File.read(ARGV[0])) || {}
    services = (cfg["services"] || []).map { |s| s["name"] }.compact
      .map { |n| n.downcase.gsub(/[_.]/, "-").gsub(/-(prod|staging|pta)$/, "") }
    File.write(ARGV[1], JSON.generate(services))
    File.write(ARGV[2], JSON.generate({
      status: services.empty? ? "empty" : "ok",
      count: services.length
    }))
  ' "$WORK_DIR/slo-config.yaml" "$WORK_DIR/slo-services.json" \
    "$WORK_DIR/slo-source-status.json" 2>"$WORK_DIR/slo-parse-err.txt"; then
    echo '{"status":"unavailable","reason":"parse_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  fi
  rm -f "$WORK_DIR/slo-raw-b64.txt"
fi
```

**On-disk artifacts (always written, every branch):**
- `slo-services.json` — normalized service name list or `[]`
- `slo-source-status.json` — `{"status": "ok|empty|unavailable", "reason": "...", "count": N}`

**Stage 1 report line addition:** `"{M} services with SLO definitions"` when status is `ok`, `"SLO config: {reason}"` otherwise.
```

- [ ] **Step 2: Verify SKILL.md is still valid markdown**

Run: `wc -l skills/alert-hygiene/SKILL.md`
Expected: line count increased by ~50 lines from current 673

- [ ] **Step 3: Commit**

```bash
git add skills/alert-hygiene/SKILL.md
git commit -m "feat(alert-hygiene): add SLO config enrichment to Stage 1"
```

---

### Task 6: Add routing validation instructions to SKILL.md Stage 4

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md:229-237` (Stage 4 section)

- [ ] **Step 1: Add routing validation subsection to Stage 4**

After the existing Stage 4 coverage gap content (after line 237, after the cross-reference instruction), add:

```markdown
#### Routing Validation

Check for routing and ownership gaps using policy-level and cluster-level data from `$WORK_DIR`.

**Zero-channel policies (policy-level):**
Scan `policies.json` for entries where `notificationChannels` is empty AND `enabled` is true. These fire but notify nobody — invisible failures.
- Policies with `raw_incidents > 10` (cross-reference against `clusters.json`): promote to **Investigate** with action: *"Silent alert — fires but has no notification channels. Add a notification channel or disable."*
- Policies with low/zero incidents: surface in **Systemic Issues > Dead/Orphaned Config** — *"Zero-channel policy: {displayName} — enabled but no notification path."*

**Unlabeled high-noise policies (policy-level):**
The existing `unlabeled_ranking` table stays in Systemic Issues. Additionally, for top entries with `raw_incidents > 10`:
- Promote to **Investigate** with ownership language: *"No squad/team/owner label — ownership is implicit and unauditable. {N} incidents in {days}d have no traceable owner."*
- Do not reference org-specific routing fallback channels. The skill is generic.
- Leave suggested owner as "⚠ assign" — the skill does not infer squad ownership from service names.

**Label inconsistency promotion (cluster-level):**
For clusters where `label_inconsistency` is true AND `raw_incidents > 5`:
- Promote to **Investigate** as a cluster-level finding: *"Label mismatch — staging/test label on a production resource. {N} incidents may be misrouted or ignored."*
- Do NOT merge into the policy-level unlabeled table — entity types stay separate.
```

- [ ] **Step 2: Verify SKILL.md is still valid markdown**

Run: `wc -l skills/alert-hygiene/SKILL.md`
Expected: line count increased by ~25 lines

- [ ] **Step 3: Commit**

```bash
git add skills/alert-hygiene/SKILL.md
git commit -m "feat(alert-hygiene): add routing validation to Stage 4"
```

---

### Task 7: Add SLO coverage cross-reference instructions to SKILL.md Stage 4

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md` (after routing validation section added in Task 6)

- [ ] **Step 1: Add SLO cross-reference subsection**

Add after the routing validation section:

```markdown
#### SLO Coverage Cross-Reference

Only run this section when `$WORK_DIR/slo-source-status.json` has `"status": "ok"`. Read `$WORK_DIR/slo-services.json` (normalized service names) and cross-reference against cluster data.

**Service grouping:** Group clusters by `service_key` from `clusters.json`. Skip clusters where `service_key` is `null`. Only consider clusters with `signal_family` in (`error_rate`, `latency`, `availability`) — exclude `other`.

**SLO migration candidates:**
For each service_key with `total_raw_incidents > 20` across user-facing clusters AND NOT in `slo-services.json`:
- Surface in **Coverage Gaps** table: *"SLO review candidate — {service_key} has {N} noisy user-facing threshold alerts ({families}), no SLO definition."*

**SLO review candidates (redundancy check):**
For each service_key that IS in `slo-services.json` AND has noisy user-facing threshold alerts:
- Surface as **Needs Decision** item: *"Service {service_key} has an SLO definition and also {N} noisy user-facing threshold alerts; review for redundancy or intentional overlap."*
- Do not claim same-signal overlap — `slo-services.json` carries service names only, not signal coverage metadata.

**Matching rules:** Both `service_key` and SLO service names are normalized (lowercase, env suffixes stripped, separators unified). Only exact-match after normalization. Unmatched service_keys are excluded, not fuzzy-guessed.
```

- [ ] **Step 2: Verify SKILL.md is still valid markdown**

Run: `wc -l skills/alert-hygiene/SKILL.md`
Expected: line count increased by ~20 lines

- [ ] **Step 3: Commit**

```bash
git add skills/alert-hygiene/SKILL.md
git commit -m "feat(alert-hygiene): add SLO coverage cross-reference to Stage 4"
```

---

### Task 8: Add IaC location resolution instructions to SKILL.md Stage 5

**Files:**
- Modify: `skills/alert-hygiene/SKILL.md:238-239` (Stage 5 section, before report production)

- [ ] **Step 1: Add IaC search subsection to Stage 5**

Add to Stage 5, before the report skeleton, as part of the Do Now gate evaluation:

```markdown
#### IaC Location Resolution via GitHub Search

During Do Now gate evaluation, attempt to upgrade IaC Location tier for candidates using `gh search code`. This is optional enrichment — if it adds nothing, the report is identical to the version without it.

**Preconditions:** `{github_org}` was provided AND `gh` is available AND authenticated (`gh auth status`). If any fail, skip entirely.

**When to search:** Only for items that pass all other Do Now gate requirements (config diff, named owner, outcome DoD, measured/structural evidence, rollback signal) but have IaC Location of Search Required or Unknown.

**Rate limit:** `gh search code` allows 10 requests/minute. Cap at top 10 candidates by raw incident count. Remaining items keep their existing IaC Location tier.

**Search strategy per item:**

```bash
# Primary: policy ID (most unique token)
gh search code --owner "$github_org" "alertPolicies/{policy_id}" \
  --extension tf --json path,repository --limit 5 \
  > "$WORK_DIR/iac-search-${policy_id}.json" 2>/dev/null

# Secondary (if primary returns 0 results): identifying fragment
# Use the PromQL fragment, condition filter string, or label key
# already captured in Stage 3 for the Search Required spec
gh search code --owner "$github_org" "{identifying_fragment}" \
  --extension tf --json path,repository --limit 5 \
  > "$WORK_DIR/iac-search-${policy_id}.json" 2>/dev/null
```

Do not search by `display_name` — too generic and noisy.

**Result interpretation:**
- **1+ plausible results:** Upgrade to IaC Location = **Likely**. Include top `repo:path` in the finding. Add note: *"Search match at {repo}:{path} — verify before applying."*
- **0 results after both tokens:** **Preserve original tier.** Search Required stays Search Required. Unknown stays Unknown. A failed search must NOT upgrade Unknown to Search Required — that would incorrectly make a Do-Now-ineligible item eligible.
- **Confirmed is not achievable from search alone** — would require opening the file and verifying match context.
```

- [ ] **Step 2: Verify SKILL.md is still valid markdown**

Run: `wc -l skills/alert-hygiene/SKILL.md`
Expected: line count increased by ~35 lines

- [ ] **Step 3: Commit**

```bash
git add skills/alert-hygiene/SKILL.md
git commit -m "feat(alert-hygiene): add IaC location resolution to Stage 5"
```

---

### Task 9: Add SKILL.md content tests for new sections

**Files:**
- Modify: `tests/test-alert-hygiene-skill-content.sh`

- [ ] **Step 1: Read current skill content test file**

Run: `cat tests/test-alert-hygiene-skill-content.sh` to understand existing pattern.

- [ ] **Step 2: Add content assertions for new sections**

Add before `print_summary` at the end of the file:

```bash
# --- New sections from terraform/routing/SLO refinements ---
SKILL_CONTENT=$(cat "${PROJECT_ROOT}/skills/alert-hygiene/SKILL.md")

# SLO enrichment in Stage 1
assert_contains "SKILL.md has SLO enrichment section" \
    "SLO Config Enrichment" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions slo-services.json artifact" \
    "slo-services.json" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions slo-source-status.json artifact" \
    "slo-source-status.json" "${SKILL_CONTENT}"
assert_contains "SKILL.md SLO uses Ruby not PyYAML" \
    "ruby -ryaml -rjson" "${SKILL_CONTENT}"

# Routing validation in Stage 4
assert_contains "SKILL.md has routing validation section" \
    "Routing Validation" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions zero-channel policies" \
    "Zero-channel policies" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions unlabeled high-noise" \
    "ownership is implicit and unauditable" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions label inconsistency promotion" \
    "Label inconsistency promotion" "${SKILL_CONTENT}"

# SLO cross-reference in Stage 4
assert_contains "SKILL.md has SLO cross-reference section" \
    "SLO Coverage Cross-Reference" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions SLO migration candidates" \
    "SLO migration candidate" "${SKILL_CONTENT}"
assert_contains "SKILL.md gates SLO xref on signal_family" \
    "signal_family" "${SKILL_CONTENT}"
assert_contains "SKILL.md excludes other from SLO xref" \
    "exclude" "${SKILL_CONTENT}"

# IaC location resolution in Stage 5
assert_contains "SKILL.md has IaC search section" \
    "IaC Location Resolution" "${SKILL_CONTENT}"
assert_contains "SKILL.md preserves original tier on no results" \
    "Preserve original tier" "${SKILL_CONTENT}"
assert_contains "SKILL.md says Confirmed not achievable from search" \
    "Confirmed is not achievable from search alone" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions gh auth status precondition" \
    "gh auth status" "${SKILL_CONTENT}"
```

- [ ] **Step 3: Run content tests**

Run: `bash tests/test-alert-hygiene-skill-content.sh 2>&1 | tail -20`
Expected: All new assertions PASS (the SKILL.md edits from Tasks 5-8 must be in place)

- [ ] **Step 4: Commit**

```bash
git add tests/test-alert-hygiene-skill-content.sh
git commit -m "test(alert-hygiene): add content assertions for new SKILL.md sections"
```

---

### Task 10: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Run all alert-hygiene tests**

Run: `bash tests/test-alert-hygiene-scripts.sh 2>&1`
Expected: All tests PASS, 0 failures

- [ ] **Step 2: Run skill content tests**

Run: `bash tests/test-alert-hygiene-skill-content.sh 2>&1`
Expected: All tests PASS, 0 failures

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1`
Expected: All test files pass, no regressions

- [ ] **Step 4: Syntax check compute-clusters.py**

Run: `python3 -c "import py_compile; py_compile.compile('skills/alert-hygiene/scripts/compute-clusters.py', doraise=True)"`
Expected: No errors

- [ ] **Step 5: Verify SKILL.md line count is reasonable**

Run: `wc -l skills/alert-hygiene/SKILL.md`
Expected: ~800 lines (was 673, added ~130 lines across Tasks 5-8)
