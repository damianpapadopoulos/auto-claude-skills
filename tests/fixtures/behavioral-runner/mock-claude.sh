#!/usr/bin/env bash
# mock-claude.sh — Stub 'claude' binary for hermetic eval runner tests.
# Reads the mock response from MOCK_RESPONSE_FILE and emits a JSON envelope
# shaped like 'claude -p --output-format json'.
set -u

if [ -z "${MOCK_RESPONSE_FILE:-}" ] || [ ! -f "${MOCK_RESPONSE_FILE}" ]; then
    echo "mock-claude: MOCK_RESPONSE_FILE unset or missing" >&2
    exit 1
fi

response_text="$(cat "${MOCK_RESPONSE_FILE}")"
jq -n \
    --arg result "${response_text}" \
    --arg model "mock-claude-v1" \
    '{type: "result", result: $result, model: $model, num_turns: 1}'
