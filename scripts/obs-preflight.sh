#!/usr/bin/env bash
# obs-preflight.sh — On-demand observability environment check
# Called by incident-analysis, alert-hygiene, and /investigate before data pulls.
# Outputs JSON to stdout. Exits 0 always (fail-open).
# Bash 3.2 compatible.

trap 'printf "{\"gcloud\":\"error\",\"kubectl\":\"error\",\"observability_mcp\":\"error\",\"summary\":\"preflight errored — proceeding without checks\"}\n"; exit 0' ERR

# --- gcloud ---
_GCLOUD="missing"
if command -v gcloud >/dev/null 2>&1; then
    if gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | grep -q '@'; then
        _GCLOUD="ready"
    else
        _GCLOUD="unauthenticated"
    fi
fi

# --- kubectl ---
_KUBECTL="missing"
if command -v kubectl >/dev/null 2>&1; then
    if kubectl cluster-info --request-timeout=3s >/dev/null 2>&1; then
        _KUBECTL="ready"
    else
        _KUBECTL="unreachable"
    fi
fi

# --- observability MCP ---
_OBS_MCP="unavailable"
if [ -f "${HOME}/.claude.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq -e '.mcpServers["gcp-observability"] // .mcpServers["observability"]' "${HOME}/.claude.json" >/dev/null 2>&1 && _OBS_MCP="configured"
    else
        grep -q '"gcp-observability"\|"observability"' "${HOME}/.claude.json" 2>/dev/null && _OBS_MCP="configured"
    fi
fi

# --- Build summary ---
_ISSUES=""
case "${_GCLOUD}" in
    missing)         _ISSUES="gcloud not installed" ;;
    unauthenticated) _ISSUES="gcloud not authenticated — run: gcloud auth login" ;;
esac
case "${_KUBECTL}" in
    missing)     [ -n "${_ISSUES}" ] && _ISSUES="${_ISSUES}; "; _ISSUES="${_ISSUES}kubectl not installed" ;;
    unreachable) [ -n "${_ISSUES}" ] && _ISSUES="${_ISSUES}; "; _ISSUES="${_ISSUES}kubectl unreachable — check cluster context" ;;
esac
case "${_OBS_MCP}" in
    unavailable) [ -n "${_ISSUES}" ] && _ISSUES="${_ISSUES}; "; _ISSUES="${_ISSUES}observability MCP not configured — run /setup for Tier 1" ;;
esac

_SUMMARY="all checks passed"
[ -n "${_ISSUES}" ] && _SUMMARY="${_ISSUES}"

# --- Output JSON ---
if command -v jq >/dev/null 2>&1; then
    jq -n \
        --arg g "${_GCLOUD}" \
        --arg k "${_KUBECTL}" \
        --arg m "${_OBS_MCP}" \
        --arg s "${_SUMMARY}" \
        '{gcloud:$g, kubectl:$k, observability_mcp:$m, summary:$s}'
else
    printf '{"gcloud":"%s","kubectl":"%s","observability_mcp":"%s","summary":"%s"}\n' \
        "${_GCLOUD}" "${_KUBECTL}" "${_OBS_MCP}" "${_SUMMARY}"
fi
exit 0
