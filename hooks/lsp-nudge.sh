#!/bin/bash
# LSP nudge — hints when Grep is used for error-string hunts while lsp=true
# PreToolUse hook. Bash 3.2 compatible. Exits 0 always (hint only, fail-open).
#
# Complements hooks/serena-nudge.sh:
#   - serena-nudge.sh fires on symbol-like patterns (CamelCase, snake_case, def/class/func/...)
#   - lsp-nudge.sh fires on error-string patterns (TypeError, Cannot find, is not assignable, ...)
# Both can fire on the same Grep call when both conditions are met.
trap 'exit 0' ERR

_INPUT="$(cat)"

# Fast path: only care about Grep (matcher should handle this, but double-check)
_TOOL_NAME=""
if command -v jq >/dev/null 2>&1; then
    _TOOL_NAME="$(printf '%s' "${_INPUT}" | jq -r '.tool_name // empty' 2>/dev/null)" || true
fi
[ "${_TOOL_NAME}" = "Grep" ] || exit 0

# Check lsp availability from cached registry
_CACHE="${HOME}/.claude/.skill-registry-cache.json"
[ -f "${_CACHE}" ] || exit 0
_LSP="$(jq -r '.context_capabilities.lsp // false' "${_CACHE}" 2>/dev/null)" || true
[ "${_LSP}" = "true" ] || exit 0

# Extract the Grep pattern
_PATTERN="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.pattern // empty' 2>/dev/null)" || true
[ -n "${_PATTERN}" ] || exit 0

# Error-hunt regex (case-insensitive). Language-agnostic — covers TS/JS, Python, Go, Rust,
# Java, C/C++, Ruby, PHP diagnostic strings commonly emitted by compilers/runtimes.
# Keep this tight: false positives produce noise; false negatives just miss a nudge.
if printf '%s' "${_PATTERN}" | grep -Eiq '(TypeError|SyntaxError|ReferenceError|ImportError|ModuleNotFoundError|AttributeError|NameError|NullPointerException|ClassCastException|Cannot find (module|name)|is not assignable|implicit any|Property .* does not exist|does not exist on type|Expected [^ ]+ (got|but got)|no matching|undefined symbol|cannot resolve|unresolved (reference|import)|use of undeclared|undefined reference to|not exported from|is not defined|has no attribute)' 2>/dev/null; then
    : # error-hunt pattern — fire the nudge
else
    exit 0
fi

_MSG="LSP is available. Consider mcp__ide__getDiagnostics for authoritative compiler/type errors instead of grepping error strings."
if command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "${_MSG}"
fi
exit 0
