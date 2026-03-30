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
    "conditions": [{
      "displayName": "metric > 100",
      "type": "conditionThreshold",
      "filter": "metric.type=\"custom/metric\" AND resource.type=\"k8s_container\"",
      "query": "",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 100,
      "evaluationInterval": "60s",
      "duration": "300s",
      "aggregations": []
    }],
    "autoClose": "1800s",
    "notificationChannels": ["projects/test/notificationChannels/1"],
    "combiner": "OR"
  },
  {
    "name": "projects/test/alertPolicies/2",
    "displayName": "Test chronic alert",
    "enabled": true,
    "userLabels": {},
    "conditions": [{
      "displayName": "restarts > 5",
      "type": "conditionThreshold",
      "filter": "metric.type=\"kubernetes.io/container/restart_count\" AND resource.type=\"k8s_container\"",
      "query": "",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 5,
      "evaluationInterval": "60s",
      "duration": "600s",
      "aggregations": []
    }],
    "autoClose": "",
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
CLUSTER_COUNT=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/clusters.json'))['clusters']))" 2>/dev/null)
assert_equals "two clusters produced" "2" "${CLUSTER_COUNT}"

# Validate flapping cluster has correct pattern
FLAP_PATTERN=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['pattern'])
" 2>/dev/null)
assert_equals "flapping alert classified as flapping" "flapping" "${FLAP_PATTERN}"

# Validate chronic cluster has correct pattern
CHRONIC_PATTERN=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
chronic = [c for c in data['clusters'] if 'chronic' in c['policy_name'].lower()][0]
print(chronic['pattern'])
" 2>/dev/null)
assert_equals "chronic alert classified as chronic" "chronic" "${CHRONIC_PATTERN}"

# Validate label inconsistency flagged (staging label on prod resource)
LABEL_FLAG=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print('yes' if flap.get('label_inconsistency') else 'no')
" 2>/dev/null)
assert_equals "label inconsistency flagged" "yes" "${LABEL_FLAG}"

# Validate raw vs deduped counts
RAW_COUNT=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['raw_incidents'])
" 2>/dev/null)
assert_equals "flapping cluster has 50 raw incidents" "50" "${RAW_COUNT}"

# Validate autoClose and evaluationInterval extraction
AUTO_CLOSE=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['auto_close_sec'])
" 2>/dev/null)
assert_equals "flapping cluster auto_close extracted" "1800" "${AUTO_CLOSE}"

EVAL_WINDOW=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['eval_window_sec'])
" 2>/dev/null)
assert_equals "flapping cluster eval_window extracted" "60" "${EVAL_WINDOW}"

CHRONIC_AUTO_CLOSE=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
chronic = [c for c in data['clusters'] if 'chronic' in c['policy_name'].lower()][0]
print(chronic['auto_close_sec'])
" 2>/dev/null)
assert_equals "chronic cluster auto_close is 0 (empty)" "0" "${CHRONIC_AUTO_CLOSE}"

# Validate threshold value extraction
THRESHOLD_VAL=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['threshold_value'])
" 2>/dev/null)
assert_equals "flapping cluster threshold_value extracted" "100" "${THRESHOLD_VAL}"

THRESHOLD_COMP=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['comparison'])
" 2>/dev/null)
assert_equals "flapping cluster comparison extracted" "COMPARISON_GT" "${THRESHOLD_COMP}"

COND_MATCH=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print(flap['condition_match'])
" 2>/dev/null)
assert_equals "flapping cluster condition_match is single" "single" "${COND_MATCH}"

COND_FILTER=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
flap = [c for c in data['clusters'] if 'flapping' in c['policy_name'].lower()][0]
print('yes' if 'custom/metric' in flap.get('condition_filter', '') else 'no')
" 2>/dev/null)
assert_equals "flapping cluster condition_filter contains metric type" "yes" "${COND_FILTER}"

# Validate metric_types_in_inventory
METRIC_TYPES_COUNT=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(len(data['metric_types_in_inventory']))
" 2>/dev/null)
assert_equals "two metric types extracted from inventory" "2" "${METRIC_TYPES_COUNT}"

HAS_CUSTOM=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print('yes' if 'custom/metric' in data['metric_types_in_inventory'] else 'no')
" 2>/dev/null)
assert_equals "metric_types includes custom/metric" "yes" "${HAS_CUSTOM}"

HAS_RESTART=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print('yes' if 'kubernetes.io/container/restart_count' in data['metric_types_in_inventory'] else 'no')
" 2>/dev/null)
assert_equals "metric_types includes restart_count" "yes" "${HAS_RESTART}"

# Validate unlabeled_ranking
UNLABELED_COUNT=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(len(data['unlabeled_ranking']))
" 2>/dev/null)
assert_equals "one unlabeled policy in ranking" "1" "${UNLABELED_COUNT}"

UNLABELED_NAME=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(data['unlabeled_ranking'][0]['policy_name'])
" 2>/dev/null)
assert_equals "unlabeled policy is chronic alert" "Test chronic alert" "${UNLABELED_NAME}"

UNLABELED_RAW=$(python3 -c "
import json
data = json.load(open('${FIXTURES_DIR}/clusters.json'))
print(data['unlabeled_ranking'][0]['total_raw'])
" 2>/dev/null)
assert_equals "unlabeled policy has 10 raw incidents" "10" "${UNLABELED_RAW}"

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

XPROJ_COUNT=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/xproj-clusters.json'))['clusters']))" 2>/dev/null)
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

MULTICOND_COUNT=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/multicond-clusters.json'))['clusters']))" 2>/dev/null)
assert_equals "different conditions under same policy produce separate clusters" "2" "${MULTICOND_COUNT}"

# --- Scenario: empty alerts input produces empty output ---
echo '[]' > "${FIXTURES_DIR}/empty-alerts.json"
python3 "${SCRIPTS_DIR}/compute-clusters.py" \
    --policies "${FIXTURES_DIR}/policies.json" \
    --alerts "${FIXTURES_DIR}/empty-alerts.json" \
    --output "${FIXTURES_DIR}/empty-clusters.json" 2>&1
EMPTY_COUNT=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/empty-clusters.json'))['clusters']))" 2>/dev/null)
assert_equals "empty alerts produces zero clusters" "0" "${EMPTY_COUNT}"

# metric types still populated from policies even with zero alerts
EMPTY_METRICS=$(python3 -c "import json; print(len(json.load(open('${FIXTURES_DIR}/empty-clusters.json'))['metric_types_in_inventory']))" 2>/dev/null)
assert_equals "empty alerts still extracts metric types from policies" "2" "${EMPTY_METRICS}"

# Cleanup
rm -rf "${FIXTURES_DIR}"

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

# --- service_key and signal_family in cluster output ---
SKEY_FIXTURES=$(mktemp -d /tmp/ah-skey-XXXXXX)

cat > "${SKEY_FIXTURES}/policies.json" << 'FIXTURE'
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
with open('${SKEY_FIXTURES}/alerts.json', 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>&1

python3 "${SCRIPTS_DIR}/compute-clusters.py" \
    --policies "${SKEY_FIXTURES}/policies.json" \
    --alerts "${SKEY_FIXTURES}/alerts.json" \
    --output "${SKEY_FIXTURES}/clusters.json" 2>&1
assert_equals "skey compute-clusters runs" "0" "$?"

SKEY_DIET=$(python3 -c "
import json
data = json.load(open('${SKEY_FIXTURES}/clusters.json'))
c = [c for c in data['clusters'] if 'diet' in c['policy_name'].lower()][0]
print(c.get('service_key', 'MISSING'))
" 2>/dev/null)
assert_equals "diet-suggestions service_key extracted and normalized" "diet-suggestions" "${SKEY_DIET}"

SIGFAM_DIET=$(python3 -c "
import json
data = json.load(open('${SKEY_FIXTURES}/clusters.json'))
c = [c for c in data['clusters'] if 'diet' in c['policy_name'].lower()][0]
print(c.get('signal_family', 'MISSING'))
" 2>/dev/null)
assert_equals "diet-suggestions classified as error_rate" "error_rate" "${SIGFAM_DIET}"

SKEY_QUEUE=$(python3 -c "
import json
data = json.load(open('${SKEY_FIXTURES}/clusters.json'))
c = [c for c in data['clusters'] if 'queue' in c['policy_name'].lower()][0]
print(c.get('service_key'))
" 2>/dev/null)
assert_equals "queue alert has null service_key" "None" "${SKEY_QUEUE}"

SIGFAM_QUEUE=$(python3 -c "
import json
data = json.load(open('${SKEY_FIXTURES}/clusters.json'))
c = [c for c in data['clusters'] if 'queue' in c['policy_name'].lower()][0]
print(c.get('signal_family', 'MISSING'))
" 2>/dev/null)
assert_equals "queue alert classified as other" "other" "${SIGFAM_QUEUE}"

rm -rf "${SKEY_FIXTURES}"

# --- Two-sided normalization contract: Python == Ruby ---
NORM_CONTRACT=$(python3 -c "
import sys, subprocess, json
sys.path.insert(0, '${SCRIPTS_DIR}')
from importlib import import_module
cc = import_module('compute-clusters')

cases = [
    'diet-suggestions-prod',
    'Diet_Suggestions',
    'hcs.gb.staging',
    'user-service',
    'my-app-pta',
    'simple',
    'Foo.Bar_Baz-prod',
]

# Python side
py_results = [cc.normalize_service_name(c) for c in cases]

# Ruby side (same normalization rules)
ruby_code = 'require \"json\"; cases = JSON.parse(ARGV[0]); results = cases.map { |n| n.downcase.gsub(/[_.]/, \"-\").gsub(/-(prod|staging|pta)\$/, \"\") }; puts JSON.generate(results)'
ruby_out = subprocess.check_output(
    ['ruby', '-e', ruby_code, json.dumps(cases)],
    text=True
).strip()
rb_results = json.loads(ruby_out)

mismatches = []
for c, py, rb in zip(cases, py_results, rb_results):
    if py != rb:
        mismatches.append(f'{c}: py={py!r} rb={rb!r}')

if mismatches:
    print('MISMATCH: ' + '; '.join(mismatches))
else:
    print('contract_holds')
" 2>&1)
assert_equals "Python/Ruby normalization contract holds" "contract_holds" "${NORM_CONTRACT}"

# --- Trigger config ---
TRIGGERS_FILE="${PROJECT_ROOT}/config/default-triggers.json"
TRIGGER_ENTRY=$(python3 -c "
import json
with open('${TRIGGERS_FILE}') as f:
    data = json.load(f)
matches = [s for s in data['skills'] if s['name'] == 'alert-hygiene']
print(len(matches))
" 2>/dev/null)
assert_equals "alert-hygiene trigger exists" "1" "${TRIGGER_ENTRY}"

print_summary
