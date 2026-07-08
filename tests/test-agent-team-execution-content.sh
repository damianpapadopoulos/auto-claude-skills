#!/usr/bin/env bash
# test-agent-team-execution-content.sh — guards agent-team-execution's load-bearing
# contract: role structure, shared contracts, and the deadlock-prevention / red-flags
# safety sections that keep parallel specialist agents from colliding.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-agent-team-execution-content.sh ==="

SKILL="${PROJECT_ROOT}/skills/agent-team-execution/SKILL.md"
assert_file_exists "agent-team-execution SKILL.md exists" "${SKILL}"
skill="$(cat "${SKILL}" 2>/dev/null)"

assert_contains "frontmatter name field"       "name: agent-team-execution" "${skill}"
assert_contains "mode selection present"       "## Mode Selection"          "${skill}"
assert_contains "roles present"                "## Roles"                   "${skill}"
assert_contains "shared contracts present"     "## Shared Contracts"        "${skill}"
assert_contains "deadlock-prevention present"  "## Deadlock Prevention"     "${skill}"
assert_contains "red flags present"            "## Red Flags"               "${skill}"

print_summary
