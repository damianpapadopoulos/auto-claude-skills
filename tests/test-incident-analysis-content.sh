#!/usr/bin/env bash
# test-incident-analysis-content.sh — Validates incident-analysis skill content
# contains expected diagnostic patterns (Scoutflo adoption).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-incident-analysis-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md"
SIGNALS_FILE="${PROJECT_ROOT}/skills/incident-analysis/signals.yaml"
PLAYBOOK_DIR="${PROJECT_ROOT}/skills/incident-analysis/playbooks"

# ---------------------------------------------------------------------------
# Helper: assert file contains pattern (grep -q wrapper)
# ---------------------------------------------------------------------------
assert_file_contains() {
    local description="$1"
    local pattern="$2"
    local file="$3"

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "pattern '${pattern}' not found in $(basename "${file}")"
    fi
}

# ---------------------------------------------------------------------------
# SKILL.md — Exit code taxonomy
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has exit code taxonomy" "exit code" "${SKILL_FILE}"
assert_file_contains "SKILL.md: exit code 137 OOMKilled" "137" "${SKILL_FILE}"
assert_file_contains "SKILL.md: exit code 139 SIGSEGV" "139" "${SKILL_FILE}"
assert_file_contains "SKILL.md: exit code 143 SIGTERM" "143" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — CrashLoopBackOff triage branch
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has crashloop triage branch" "CrashLoopBackOff triage" "${SKILL_FILE}"
assert_file_contains "SKILL.md: crashloop checks previous container logs" "previous" "${SKILL_FILE}"
assert_file_contains "SKILL.md: crashloop checks termination reason" "[Tt]ermination reason" "${SKILL_FILE}"
assert_file_contains "SKILL.md: crashloop checks rollout history" "rollout history" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Probe/startup-envelope checks
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has probe checks branch" "startup-envelope" "${SKILL_FILE}"
assert_file_contains "SKILL.md: probe checks initialDelaySeconds" "initialDelaySeconds" "${SKILL_FILE}"
assert_file_contains "SKILL.md: probe checks timeoutSeconds" "timeoutSeconds" "${SKILL_FILE}"
assert_file_contains "SKILL.md: probe checks dependency reachability" "[Dd]ependency reachability" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Pod-start failure branch
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has pod-start failure branch" "Pod-start failure" "${SKILL_FILE}"
assert_file_contains "SKILL.md: pod-start mentions ImagePullBackOff" "ImagePullBackOff" "${SKILL_FILE}"
assert_file_contains "SKILL.md: pod-start mentions CreateContainerConfigError" "CreateContainerConfigError" "${SKILL_FILE}"
assert_file_contains "SKILL.md: pod-start mentions imagePullSecrets" "imagePullSecrets" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Capacity/baseline overlay
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has capacity headroom check" "[Cc]apacity headroom" "${SKILL_FILE}"
assert_file_contains "SKILL.md: capacity mentions HPA" "HPA" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Restart gating: triage must precede restart candidacy
# ---------------------------------------------------------------------------
# The CrashLoopBackOff triage branch must appear in INVESTIGATE Step 3
# AND must state that workload-restart is only a candidate after triage.
investigate_section="$(sed -n '/^## Stage 2 — INVESTIGATE/,/^## Stage 3/p' "${SKILL_FILE}")"

# 1. Triage branch exists in INVESTIGATE
crashloop_line="$(echo "${investigate_section}" | grep -n "CrashLoopBackOff triage" | head -1 | cut -d: -f1)"
if [ -n "${crashloop_line}" ] && [ "${crashloop_line}" -gt 0 ] 2>/dev/null; then
    _record_pass "SKILL.md: CrashLoopBackOff triage is in INVESTIGATE stage"
else
    _record_fail "SKILL.md: CrashLoopBackOff triage is in INVESTIGATE stage" "not found in INVESTIGATE section"
fi

# 2. Triage branch references the workload-restart investigation_steps gate
assert_file_contains "SKILL.md: triage references workload-restart investigation_steps" \
    "workload-restart.*investigation_steps" "${SKILL_FILE}"

# 3. workload-restart.yaml has a Restart Decision Gate section
assert_file_contains "workload-restart.yaml: has restart decision gate" \
    "Restart Decision Gate" "${PLAYBOOK_DIR}/workload-restart.yaml"

# 4. The gate explicitly blocks restart for OOMKilled (exit 137)
assert_file_contains "workload-restart.yaml: gate blocks restart for OOMKilled" \
    "137.*OOMKilled" "${PLAYBOOK_DIR}/workload-restart.yaml"

# ---------------------------------------------------------------------------
# Routing — pod-start symptoms reach incident-analysis
# ---------------------------------------------------------------------------
TRIGGERS_FILE="${PROJECT_ROOT}/config/default-triggers.json"
if [ -f "${TRIGGERS_FILE}" ]; then
    assert_file_contains "triggers: ImagePullBackOff routes to incident-analysis" \
        "image.pull" "${TRIGGERS_FILE}"
    assert_file_contains "triggers: CreateContainerConfigError routes to incident-analysis" \
        "create.?container.?config" "${TRIGGERS_FILE}"
fi

# ---------------------------------------------------------------------------
# signals.yaml — New signals present
# ---------------------------------------------------------------------------
assert_file_contains "signals.yaml: has image_pull_failure" "image_pull_failure" "${SIGNALS_FILE}"
assert_file_contains "signals.yaml: has config_error_detected" "config_error_detected" "${SIGNALS_FILE}"
assert_file_contains "signals.yaml: has kubelet_not_running" "kubelet_not_running" "${SIGNALS_FILE}"

# ---------------------------------------------------------------------------
# workload-restart.yaml — Has investigation_steps with crashloop triage
# ---------------------------------------------------------------------------
WR_FILE="${PLAYBOOK_DIR}/workload-restart.yaml"
assert_file_contains "workload-restart.yaml: has investigation_steps" "investigation_steps" "${WR_FILE}"
assert_file_contains "workload-restart.yaml: investigation mentions termination reason" "[Tt]ermination" "${WR_FILE}"
assert_file_contains "workload-restart.yaml: investigation mentions previous logs" "previous" "${WR_FILE}"
assert_file_contains "workload-restart.yaml: investigation mentions exit code" "exit code" "${WR_FILE}"
assert_file_contains "workload-restart.yaml: investigation mentions rollout history" "rollout" "${WR_FILE}"

# ---------------------------------------------------------------------------
# infra-failure.yaml — Node discrimination checks
# ---------------------------------------------------------------------------
IF_FILE="${PLAYBOOK_DIR}/infra-failure.yaml"
assert_file_contains "infra-failure.yaml: mentions node conditions" "[Cc]ondition" "${IF_FILE}"
assert_file_contains "infra-failure.yaml: mentions kubelet logs" "kubelet" "${IF_FILE}"
assert_file_contains "infra-failure.yaml: mentions runtime health" "[Rr]untime" "${IF_FILE}"
assert_file_contains "infra-failure.yaml: mentions connectivity" "[Cc]onnectivity" "${IF_FILE}"
assert_file_contains "infra-failure.yaml: mentions certificate" "[Cc]ertificate" "${IF_FILE}"

# ---------------------------------------------------------------------------
# node-resource-exhaustion.yaml — Enhanced checks
# ---------------------------------------------------------------------------
NRE_FILE="${PLAYBOOK_DIR}/node-resource-exhaustion.yaml"
assert_file_contains "node-resource-exhaustion.yaml: mentions kubelet cert" "[Cc]ertificate" "${NRE_FILE}"
assert_file_contains "node-resource-exhaustion.yaml: mentions runtime health" "[Rr]untime" "${NRE_FILE}"

print_summary
