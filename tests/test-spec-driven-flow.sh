#!/usr/bin/env bash
# test-spec-driven-flow.sh — End-to-end verification of spec-driven mode
# 1. Preset file has openspec_first: true
# 2. Session-start with spec-driven preset mutates DESIGN/PLAN hints
# 3. Session-start without preset leaves hints pointing at docs/plans/
# 4. openspec-ship SKILL.md has pre-flight check content
# 5. design-debate SKILL.md has both mode outputs
#
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-spec-driven-flow.sh ==="

# ---------------------------------------------------------------------------
# Phase 1: Preset file has the flag
# ---------------------------------------------------------------------------
echo "-- Phase 1: preset file --"
preset_file="${PROJECT_ROOT}/config/presets/spec-driven.json"
assert_file_exists "spec-driven preset exists" "$preset_file"
flag="$(jq -r '.openspec_first // false' "$preset_file")"
assert_equals "openspec_first is true" "true" "$flag"

# ---------------------------------------------------------------------------
# Phase 2: Session-start with spec-driven preset mutates hints
# ---------------------------------------------------------------------------
echo "-- Phase 2: session-start mutates hints --"
setup_test_env
mkdir -p "${HOME}/.claude"
printf '{"preset":"spec-driven"}' > "${HOME}/.claude/skill-config.json"

CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    bash "${HOOK}" >/dev/null 2>&1

cache_file="${HOME}/.claude/.skill-registry-cache.json"
assert_file_exists "cache file exists" "$cache_file"

design_hints="$(jq -r '.phase_compositions.DESIGN.hints[].text // empty' "$cache_file" | tr '\n' ' ')"
assert_contains "DESIGN hints mention openspec/changes/" "openspec/changes/" "$design_hints"
assert_contains "DESIGN hints mention specs/<capability-slug>/spec.md" "specs/<capability-slug>/spec.md" "$design_hints"

plan_hints="$(jq -r '.phase_compositions.PLAN.hints[].text // empty' "$cache_file" | tr '\n' ' ')"
assert_contains "PLAN hints mention openspec/changes/" "openspec/changes/" "$plan_hints"

teardown_test_env

# ---------------------------------------------------------------------------
# Phase 3: Session-start without preset preserves docs/plans/ hints
# ---------------------------------------------------------------------------
echo "-- Phase 3: no preset preserves defaults --"
setup_test_env
# No skill-config.json → no preset → no mutation
CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    bash "${HOOK}" >/dev/null 2>&1

cache_file="${HOME}/.claude/.skill-registry-cache.json"
design_hints="$(jq -r '.phase_compositions.DESIGN.hints[].text // empty' "$cache_file" | tr '\n' ' ')"
assert_contains "DESIGN hints mention docs/plans/ in default mode" "docs/plans/YYYY-MM-DD-<slug>-design.md" "$design_hints"
teardown_test_env

# ---------------------------------------------------------------------------
# Phase 4: openspec-ship has idempotent pre-flight check content
# ---------------------------------------------------------------------------
echo "-- Phase 4: openspec-ship content --"
ship_content="$(cat "${PROJECT_ROOT}/skills/openspec-ship/SKILL.md")"
assert_contains "pre-flight check documented" "Pre-flight check" "$ship_content"
assert_contains "spec-driven mode path documented" "change folder already exists" "$ship_content"
assert_contains "new-capability warning documented" "NEW CAPABILITY" "$ship_content"

# ---------------------------------------------------------------------------
# Phase 5: design-debate has dual-mode output template
# ---------------------------------------------------------------------------
echo "-- Phase 5: design-debate content --"
debate_content="$(cat "${PROJECT_ROOT}/skills/design-debate/SKILL.md")"
assert_contains "design-debate: spec-driven section" "Spec-driven mode" "$debate_content"
assert_contains "design-debate: solo section" "Solo mode" "$debate_content"

print_summary
exit $?
