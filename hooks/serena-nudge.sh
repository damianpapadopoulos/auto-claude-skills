#!/bin/bash
# Serena nudge — hints when Grep is used for symbol lookups while serena=true
# PreToolUse hook. Bash 3.2 compatible. Exits 0 always (hint only, fail-open).
trap 'exit 0' ERR

_INPUT="$(cat)"

# Fast path: only care about Grep (matcher should handle this, but double-check)
_TOOL_NAME=""
if command -v jq >/dev/null 2>&1; then
    _TOOL_NAME="$(printf '%s' "${_INPUT}" | jq -r '.tool_name // empty' 2>/dev/null)" || true
fi
[ "${_TOOL_NAME}" = "Grep" ] || exit 0

# Check serena availability from cached registry
_CACHE="${HOME}/.claude/.skill-registry-cache.json"
[ -f "${_CACHE}" ] || exit 0
_SERENA="$(jq -r '.context_capabilities.serena // false' "${_CACHE}" 2>/dev/null)" || true
[ "${_SERENA}" = "true" ] || exit 0

# Check if pattern looks like a symbol lookup
_PATTERN="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.pattern // empty' 2>/dev/null)" || true
[ -n "${_PATTERN}" ] || exit 0

case "${_PATTERN}" in
    *class\ *|*def\ *|*function\ *|*func\ *|*interface\ *|*struct\ *|*import\ *)
        ;; # likely symbol lookup
    *)
        # Check for bare CamelCase or snake_case identifiers (no regex operators)
        if printf '%s' "${_PATTERN}" | grep -qE '^[A-Z][a-zA-Z0-9]+$' 2>/dev/null; then
            : # CamelCase — likely a class/type name
        elif printf '%s' "${_PATTERN}" | grep -qE '^[a-z_][a-z0-9_]+$' 2>/dev/null; then
            : # snake_case — likely a function name
        else
            exit 0 # regex pattern or complex search — not a symbol lookup
        fi
        ;;
esac

_MSG="Serena is available. Consider find_symbol or get_symbols_overview for symbol lookups instead of Grep."
jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
exit 0
