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
# SKILL.md — Access Gate (Step 1b)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has access gate step" "Access Gate" "${SKILL_FILE}"
assert_file_contains "SKILL.md: access gate checks gcloud auth" "gcloud auth" "${SKILL_FILE}"
assert_file_contains "SKILL.md: access gate checks kubectl context" "kubectl" "${SKILL_FILE}"
assert_file_contains "SKILL.md: access gate prompts user to fix" "Fix now.*proceed with degraded" "${SKILL_FILE}"
assert_file_contains "SKILL.md: access gate records state for synthesis" "evidence_coverage" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Evidence coverage and gaps (Step 7)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: synthesis includes evidence coverage" "Evidence coverage and gaps" "${SKILL_FILE}"
assert_file_contains "SKILL.md: has evidence_coverage block" "evidence_coverage:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: has gaps block" "gaps:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: coverage levels defined" "complete.*partial.*unavailable" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gap recording rules" "Record a gap for" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Completeness gate references evidence coverage
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: access gate does not block on unfixable gaps" \
    "Do not block.*unfixable" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate references evidence coverage" "evidence_coverage.*block" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate requires gap-aware answers" "what could change the answer" "${SKILL_FILE}"
assert_file_contains "SKILL.md: confident yes impossible with missing domain" \
    "confident.*yes.*not possible.*relevant domain" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Aggregate-first error fingerprinting (Step 3b)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has aggregate fingerprint step" "Aggregate.*[Ff]ingerprint" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions error distribution" "error distribution" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions dominant bucket" "dominant.*bucket" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions sample-biased warning" "sample.biased" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions exemplar reads" "exemplar" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Evidence ledger (Constraint 6)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has evidence ledger constraint" "[Ee]vidence [Ll]edger" "${SKILL_FILE}"
assert_file_contains "SKILL.md: ledger has freshness semantics" "freshness" "${SKILL_FILE}"
assert_file_contains "SKILL.md: ledger excludes EXECUTE recheck" "always re-query" "${SKILL_FILE}"
assert_file_contains "SKILL.md: ledger labels reused evidence" "reused" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Live-triage mode
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has live-triage mode" "[Ll]ive.triage" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage is opt-in" "opt.in\|explicit" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage has non-blocking access" "non.blocking\|[Nn]on-blocking" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage has light inventory" "[Ll]ight inventory" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage defers deep inventory" "[Dd]efer.*deep\|[Dd]eep.*defer" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage preserves safety" "fingerprint recheck\|completeness gate\|safety" "${SKILL_FILE}"
assert_file_contains "SKILL.md: full investigation is default" "[Dd]efault.*[Ff]ull\|[Ff]ull.*[Dd]efault" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Canonical summary schema (Step 7)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: summary has structured block" "investigation_summary:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has scope" "scope:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has dominant_errors" "dominant_errors:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has chosen_hypothesis" "chosen_hypothesis:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has ruled_out" "ruled_out:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has recovery_status" "recovery_status:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: summary schema has open_questions" "open_questions:" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# bad-release-rollback.yaml — Disambiguation probe
# ---------------------------------------------------------------------------
assert_file_contains "bad-release-rollback.yaml: has disambiguation probe" \
    "disambiguation_probe" "${PLAYBOOK_DIR}/bad-release-rollback.yaml"
assert_file_contains "bad-release-rollback.yaml: probe resolves error_pattern_predates_deploy" \
    "error_pattern_predates_deploy" "${PLAYBOOK_DIR}/bad-release-rollback.yaml"

# ---------------------------------------------------------------------------
# node-resource-exhaustion.yaml — Enhanced checks
# ---------------------------------------------------------------------------
NRE_FILE="${PLAYBOOK_DIR}/node-resource-exhaustion.yaml"
assert_file_contains "node-resource-exhaustion.yaml: mentions kubelet cert" "[Cc]ertificate" "${NRE_FILE}"
assert_file_contains "node-resource-exhaustion.yaml: mentions runtime health" "[Rr]untime" "${NRE_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Completeness gate Q10 (multi-service attribution)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: completeness gate has Q10" \
    "| 10 |" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Q10 mentions attribution verification" \
    "attribution\|independently\|error.*match" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — service_attribution in investigation_summary YAML
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: summary schema has service_attribution" \
    "service_attribution:" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Per-Service Attribution Proof in Step 5
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has per-service attribution proof" \
    "Per-Service Attribution Proof\|Per-service attribution" "${SKILL_FILE}"
assert_file_contains "SKILL.md: attribution has four-state model" \
    "confirmed-dependent.*independent.*inconclusive.*not-investigated" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Application-logic analysis in Step 3
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: Step 3 has call pattern analysis" \
    "[Cc]all pattern" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Step 3 mentions N+1 or sequential fan-out" \
    "N+1\|sequential fan.out\|sequential.*permission" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Step 3 mentions gRPC connection analysis" \
    "peer.address\|connection pinning\|gRPC.*caller.*skew" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — No speculative language in routing heuristics
# ---------------------------------------------------------------------------
# The infrastructure escalation paragraph must not use "likely" as a conclusion
investigate_section="$(sed -n '/^## Stage 2 — INVESTIGATE/,/^## EXECUTE/p' "${SKILL_FILE}")"
if echo "${investigate_section}" | grep -q "root cause is likely"; then
    _record_fail "SKILL.md: no speculative 'likely' in infrastructure escalation" \
        "found 'root cause is likely' in INVESTIGATE section"
else
    _record_pass "SKILL.md: no speculative 'likely' in infrastructure escalation"
fi

# ---------------------------------------------------------------------------
# SKILL.md — Evidence-Only Attribution constraint (Constraint 7)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has evidence-only attribution constraint" \
    "Evidence-Only Attribution" "${SKILL_FILE}"
assert_file_contains "SKILL.md: forbids speculative language in synthesis" \
    "likely.*prohibited\|prohibited.*likely\|forbidden.*likely\|likely.*forbidden" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — MCP Result Processing constraint (Constraint 8)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has MCP result processing constraint" \
    "MCP Result Processing" "${SKILL_FILE}"
assert_file_contains "SKILL.md: forbids reading tool-results files" \
    "Never read.*tool-results" "${SKILL_FILE}"
assert_file_contains "SKILL.md: disambiguates from Evidence Ledger" \
    "Evidence Ledger.*Constraint 6" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Intermediary-Layer Investigation Discipline (Constraint 9)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has intermediary-layer constraint" \
    "Intermediary-Layer Investigation" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 9 requires downstream sweep" \
    "query every distinct downstream service" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 9 has scope boundary" \
    "bounded to services explicitly named" "${SKILL_FILE}"

print_summary
