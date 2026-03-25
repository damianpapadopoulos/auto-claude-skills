#!/usr/bin/env bash
# test-alert-hygiene-scripts.sh — Alert hygiene script unit tests
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-alert-hygiene-scripts.sh ==="

SCRIPTS_DIR="${PROJECT_ROOT}/skills/alert-hygiene/scripts"

# --- pull-policies.py ---
assert_file_exists "pull-policies.py exists" "${SCRIPTS_DIR}/pull-policies.py"

# Syntax check
python3 -c "import py_compile; py_compile.compile('${SCRIPTS_DIR}/pull-policies.py', doraise=True)" 2>/dev/null
assert_equals "pull-policies.py compiles" "0" "$?"

# --- pull-incidents.py ---
assert_file_exists "pull-incidents.py exists" "${SCRIPTS_DIR}/pull-incidents.py"

python3 -c "import py_compile; py_compile.compile('${SCRIPTS_DIR}/pull-incidents.py', doraise=True)" 2>/dev/null
assert_equals "pull-incidents.py compiles" "0" "$?"

# --- compute-clusters.py ---
assert_file_exists "compute-clusters.py exists" "${SCRIPTS_DIR}/compute-clusters.py"

python3 -c "import py_compile; py_compile.compile('${SCRIPTS_DIR}/compute-clusters.py', doraise=True)" 2>/dev/null
assert_equals "compute-clusters.py compiles" "0" "$?"

# --- compute-clusters.py with synthetic data ---
# Create synthetic fixtures
FIXTURES_DIR="$(mktemp -d /tmp/ah-test-XXXXXX)"

cat > "${FIXTURES_DIR}/policies.json" << 'FIXTURE'
[
  {
    "name": "projects/test/alertPolicies/1",
    "displayName": "Test flapping alert",
    "enabled": true,
    "userLabels": {"squad": "staging_alerts"},
    "conditions": [{"conditionPrometheusQueryLanguage": {"query": "metric > 100", "duration": "300s", "evaluationInterval": "60s"}}],
    "alertStrategy": {"autoClose": "1800s"},
    "notificationChannels": ["projects/test/notificationChannels/1"],
    "combiner": "OR"
  },
  {
    "name": "projects/test/alertPolicies/2",
    "displayName": "Test chronic alert",
    "enabled": true,
    "userLabels": {"squad": "prod_alerts"},
    "conditions": [{"conditionPrometheusQueryLanguage": {"query": "restarts > 5", "duration": "600s", "evaluationInterval": "60s"}}],
    "alertStrategy": {},
    "notificationChannels": ["projects/test/notificationChannels/1"],
    "combiner": "OR"
  }
]
FIXTURE

# Generate 50 incidents for policy 1 (flapping: short duration, same resource, rapid retrigger)
# Uses flat extracted format (matching pull-incidents.py extract_alerts() output)
python3 -c "
import json
from datetime import datetime, timedelta, timezone

alerts = []
base = datetime(2026, 3, 20, 10, 0, 0, tzinfo=timezone.utc)
for i in range(50):
    open_t = base + timedelta(minutes=i*15)
    close_t = open_t + timedelta(minutes=5)
    alerts.append({
        'name': f'projects/test/alerts/flap-{i}',
        'state': 'CLOSED',
        'openTime': open_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'closeTime': close_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'policyName': 'projects/test/alertPolicies/1',
        'policyDisplayName': 'Test flapping alert',
        'policyLabels': {'squad': 'staging_alerts'},
        'resourceType': 'k8s_container',
        'resourceProject': 'test-prod',
        'resourceLabels': {'project_id': 'test-prod', 'pod_name': 'pod-1'},
        'metricType': 'custom/metric',
    })
# Add 10 chronic incidents for policy 2 (long duration, distinct resources)
for i in range(10):
    open_t = base + timedelta(hours=i*6)
    close_t = open_t + timedelta(hours=5)
    alerts.append({
        'name': f'projects/test/alerts/chronic-{i}',
        'state': 'CLOSED',
        'openTime': open_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'closeTime': close_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'policyName': 'projects/test/alertPolicies/2',
        'policyDisplayName': 'Test chronic alert',
        'policyLabels': {'squad': 'prod_alerts'},
        'resourceType': 'k8s_container',
        'resourceProject': 'test-prod',
        'resourceLabels': {'project_id': 'test-prod', 'pod_name': f'pod-{i}'},
        'metricType': 'kubernetes.io/container/restart_count',
    })
with open('${FIXTURES_DIR}/alerts.json', 'w') as f:
    json.dump(alerts, f, indent=2)
print(f'Generated {len(alerts)} synthetic alerts')
" 2>&1
assert_equals "synthetic alerts generated" "0" "$?"

# Run compute-clusters.py with fixtures
python3 "${SCRIPTS_DIR}/compute-clusters.py" \
    --policies "${FIXTURES_DIR}/policies.json" \
    --alerts "${FIXTURES_DIR}/alerts.json" \
    --output "${FIXTURES_DIR}/clusters.json" 2>&1
assert_equals "compute-clusters.py runs on synthetic data" "0" "$?"
assert_file_exists "cluster output written" "${FIXTURES_DIR}/clusters.json"

# Validate cluster output structure
CLUSTER_COUNT=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/clusters.json'))))" 2>/dev/null)
assert_equals "two clusters produced" "2" "${CLUSTER_COUNT}"

# Validate flapping cluster has correct pattern
FLAP_PATTERN=$(python3 -c "
import json
clusters = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in clusters if 'flapping' in c['policy_name'].lower()][0]
print(flap['pattern'])
" 2>/dev/null)
assert_equals "flapping alert classified as flapping" "flapping" "${FLAP_PATTERN}"

# Validate chronic cluster has correct pattern
CHRONIC_PATTERN=$(python3 -c "
import json
clusters = json.load(open('${FIXTURES_DIR}/clusters.json'))
chronic = [c for c in clusters if 'chronic' in c['policy_name'].lower()][0]
print(chronic['pattern'])
" 2>/dev/null)
assert_equals "chronic alert classified as chronic" "chronic" "${CHRONIC_PATTERN}"

# Validate label inconsistency flagged (staging label on prod resource)
LABEL_FLAG=$(python3 -c "
import json
clusters = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in clusters if 'flapping' in c['policy_name'].lower()][0]
print('yes' if flap.get('label_inconsistency') else 'no')
" 2>/dev/null)
assert_equals "label inconsistency flagged" "yes" "${LABEL_FLAG}"

# Validate raw vs deduped counts
RAW_COUNT=$(python3 -c "
import json
clusters = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in clusters if 'flapping' in c['policy_name'].lower()][0]
print(flap['raw_incidents'])
" 2>/dev/null)
assert_equals "flapping cluster has 50 raw incidents" "50" "${RAW_COUNT}"

# --- Scenario: cross-project alerts stay separated ---
python3 -c "
import json
from datetime import datetime, timedelta, timezone
alerts = []
base = datetime(2026, 3, 20, 10, 0, 0, tzinfo=timezone.utc)
for proj in ['prod-a', 'prod-b']:
    for i in range(10):
        open_t = base + timedelta(hours=i*2)
        close_t = open_t + timedelta(minutes=30)
        alerts.append({
            'name': f'projects/test/alerts/xproj-{proj}-{i}',
            'state': 'CLOSED',
            'openTime': open_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'closeTime': close_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'policyName': 'projects/test/alertPolicies/1',
            'policyDisplayName': 'Test flapping alert',
            'policyLabels': {},
            'resourceType': 'k8s_container',
            'resourceProject': proj,
            'resourceLabels': {'project_id': proj, 'pod_name': 'pod-1'},
            'metricType': 'custom/metric',
            'conditionName': '',
        })
with open('${FIXTURES_DIR}/xproj-alerts.json', 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>&1

python3 "${SCRIPTS_DIR}/compute-clusters.py" \
    --policies "${FIXTURES_DIR}/policies.json" \
    --alerts "${FIXTURES_DIR}/xproj-alerts.json" \
    --output "${FIXTURES_DIR}/xproj-clusters.json" 2>&1

XPROJ_COUNT=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/xproj-clusters.json'))))" 2>/dev/null)
assert_equals "cross-project alerts produce separate clusters" "2" "${XPROJ_COUNT}"

# --- Scenario: same policy/resource/metric, different conditions stay split ---
python3 -c "
import json
from datetime import datetime, timedelta, timezone
alerts = []
base = datetime(2026, 3, 20, 10, 0, 0, tzinfo=timezone.utc)
for cond_name in ['projects/test/alertPolicies/1/conditions/A', 'projects/test/alertPolicies/1/conditions/B']:
    for i in range(8):
        open_t = base + timedelta(hours=i*3)
        close_t = open_t + timedelta(minutes=20)
        alerts.append({
            'name': f'projects/test/alerts/cond-{cond_name[-1]}-{i}',
            'state': 'CLOSED',
            'openTime': open_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'closeTime': close_t.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'policyName': 'projects/test/alertPolicies/1',
            'policyDisplayName': 'Test flapping alert',
            'policyLabels': {'squad': 'staging_alerts'},
            'resourceType': 'k8s_container',
            'resourceProject': 'test-prod',
            'resourceLabels': {'project_id': 'test-prod', 'pod_name': 'pod-1'},
            'metricType': 'custom/metric',
            'conditionName': cond_name,
        })
with open('${FIXTURES_DIR}/multicond-alerts.json', 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>&1

python3 "${SCRIPTS_DIR}/compute-clusters.py" \
    --policies "${FIXTURES_DIR}/policies.json" \
    --alerts "${FIXTURES_DIR}/multicond-alerts.json" \
    --output "${FIXTURES_DIR}/multicond-clusters.json" 2>&1

MULTICOND_COUNT=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/multicond-clusters.json'))))" 2>/dev/null)
assert_equals "different conditions under same policy produce separate clusters" "2" "${MULTICOND_COUNT}"

# --- Scenario: empty alerts input produces empty output ---
echo '[]' > "${FIXTURES_DIR}/empty-alerts.json"
python3 "${SCRIPTS_DIR}/compute-clusters.py" \
    --policies "${FIXTURES_DIR}/policies.json" \
    --alerts "${FIXTURES_DIR}/empty-alerts.json" \
    --output "${FIXTURES_DIR}/empty-clusters.json" 2>&1
EMPTY_COUNT=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/empty-clusters.json'))))" 2>/dev/null)
assert_equals "empty alerts produces zero clusters" "0" "${EMPTY_COUNT}"

# Cleanup
rm -rf "${FIXTURES_DIR}"

print_summary
