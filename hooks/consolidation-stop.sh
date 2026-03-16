#!/bin/bash
# Consolidation stop hook — reminds about memory consolidation when session ends
# Stop hook. Bash 3.2 compatible. Exits 0 always (advisory, fail-open).
trap 'exit 0' ERR

# Check session token
[ -f "${HOME}/.claude/.skill-session-token" ] || exit 0

# Check consolidation marker freshness
_proj_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_proj_hash="$(printf '%s' "${_proj_root}" | shasum | cut -d' ' -f1)"
_consol_marker="${HOME}/.claude/.context-stack-consolidated-${_proj_hash}"

if [ -f "${_consol_marker}" ]; then
    _marker_time="$(stat -f %m "${_consol_marker}" 2>/dev/null || stat -c %Y "${_consol_marker}" 2>/dev/null || echo 0)"
    _last_commit="$(git -C "${_proj_root}" log -1 --format=%ct 2>/dev/null || echo 0)"
    [ "${_marker_time}" -ge "${_last_commit}" ] && exit 0
fi

# Marker is stale or missing — build tier-specific guidance
_CACHE="${HOME}/.claude/.skill-registry-cache.json"
_GUIDANCE="Append findings to docs/learnings.md before ending the session."

if [ -f "${_CACHE}" ] && command -v jq >/dev/null 2>&1; then
    _fm="$(jq -r '.context_capabilities.forgetful_memory // false' "${_CACHE}" 2>/dev/null)" || true
    _chub="$(jq -r '.context_capabilities.context_hub_cli // false' "${_CACHE}" 2>/dev/null)" || true
    if [ "${_fm}" = "true" ]; then
        _GUIDANCE="Use discover_forgetful_tools then execute_forgetful_tool to store architectural learnings from this session."
    elif [ "${_chub}" = "true" ]; then
        _GUIDANCE="Use chub annotate to record API workarounds discovered."
    fi
fi

_MSG="CONSOLIDATION REMINDER: Session ending without memory consolidation. Learnings from this session may be lost. ${_GUIDANCE}"
if command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":$msg}}'
else
    printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"%s"}}\n' "${_MSG}"
fi
exit 0
