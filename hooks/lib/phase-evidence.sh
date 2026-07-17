#!/bin/bash
# phase-evidence.sh — the ONE "is this chain step done" predicate, shared by
# skill-gate.sh (C1) and openspec-guard.sh (C2) so the two boundaries cannot
# drift. Evidence = append-only invocation record OR branch ledger OR explicit
# attestation (gating milestones excluded by the attest lib's reader lock).
# Fail-open: every leg degrades to "not satisfied"; callers deny only on
# positive violation evidence they establish themselves.
# Spec: openspec/changes/phase-enforcement.

_PHASE_EVID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${_PHASE_EVID_DIR}/phase-attest.sh" ] && . "${_PHASE_EVID_DIR}/phase-attest.sh" 2>/dev/null || true
[ -f "${_PHASE_EVID_DIR}/branch-ledger.sh" ] && . "${_PHASE_EVID_DIR}/branch-ledger.sh" 2>/dev/null || true

# Implementation-slot aliases: one canonical slot (codex #3).
PHASE_IMPL_ALIASES="executing-plans subagent-driven-development agent-team-execution"
# DESIGN-slot aliases: brainstorming and design-debate are the same canonical
# DESIGN slot — evidence for either satisfies a requirement on the other (F4).
PHASE_DESIGN_ALIASES="brainstorming design-debate"
# Every alias group _phase_alias_candidates walks. Add new slot-alias groups
# to this list (both here and in the fallback-registry/default-triggers
# canary list if the group gates a new lib) rather than special-casing below.
_PHASE_ALIAS_GROUPS="PHASE_IMPL_ALIASES PHASE_DESIGN_ALIASES"

# _phase_alias_candidates <step> — prints <step> plus its slot siblings,
# across every alias group in $_PHASE_ALIAS_GROUPS.
_phase_alias_candidates() {
    local step="${1:-}" a group_var group_members is_member
    printf '%s\n' "$step"
    for group_var in $_PHASE_ALIAS_GROUPS; do
        eval "group_members=\"\${${group_var}:-}\""
        is_member=0
        for a in $group_members; do [ "$a" = "$step" ] && is_member=1; done
        if [ "$is_member" -eq 1 ]; then
            for a in $group_members; do [ "$a" != "$step" ] && printf '%s\n' "$a"; done
        fi
    done
}

# phase_step_satisfied <token> <step> <proj_root> -> 0 if any evidence leg
# holds for the step OR an implementation-slot alias of it.
# PROVENANCE (codex #2): the walker-writable .completed is NOT consulted —
# only the completion hook's append-only invocation record, the branch
# ledger, and explicit attestation count.
phase_step_satisfied() {
    local token="${1:-}" step="${2:-}" proot="${3:-}" cand
    [ -z "$step" ] && return 1

    for cand in $(_phase_alias_candidates "$step"); do
        # Leg 1: append-only invocation record (completion-hook writes only)
        if [ -n "$token" ] && command -v jq >/dev/null 2>&1; then
            local rec="${HOME}/.claude/.skill-invocation-evidence-${token}"
            if [ -f "$rec" ] && jq -e --arg s "$cand" 'index($s) != null' "$rec" >/dev/null 2>&1; then
                return 0
            fi
        fi
        # Leg 2: branch ledger (cross-session durable record)
        if command -v branch_ledger_has >/dev/null 2>&1 && branch_ledger_has "$cand" "$proot"; then
            return 0
        fi
        # Leg 3: explicit attestation (reader refuses gating milestones)
        if command -v phase_attested >/dev/null 2>&1 && phase_attested "$token" "$cand"; then
            return 0
        fi
    done
    return 1
}

# phase_gate_log <gate> <decision> <skill> <missing> — telemetry line, fail-open.
phase_gate_log() {
    printf '%s gate=%s decision=%s skill=%s missing=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${1:-?}" "${2:-?}" "${3:-?}" "${4:--}" \
        >> "${HOME}/.claude/.phase-gate-events.log" 2>/dev/null || true
}
