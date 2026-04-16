#!/usr/bin/env bash
# test-presets.sh — Preset file structure and content validation
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=test-helpers.sh
. "$SCRIPT_DIR/test-helpers.sh"

echo "=== test-presets.sh ==="

# ---------------------------------------------------------------------------
# Preset files exist and are valid JSON
# ---------------------------------------------------------------------------
echo "-- Preset Files --"

for preset in starter standard full; do
    f="$PROJECT_ROOT/config/presets/${preset}.json"
    assert_file_exists "${preset}.json exists" "$f"
    assert_json_valid "${preset}.json is valid JSON" "$f"

    name="$(jq -r '.name' "$f")"
    assert_equals "${preset} name field" "$preset" "$name"
done

# ---------------------------------------------------------------------------
# Starter preset structure
# ---------------------------------------------------------------------------
echo "-- Starter Preset Structure --"

starter="$PROJECT_ROOT/config/presets/starter.json"
default_enabled="$(jq -r '.default_enabled' "$starter")"
assert_equals "starter default_enabled is false" "false" "$default_enabled"

# Verify starter includes core skills
for skill in brainstorming writing-plans systematic-debugging requesting-code-review verification-before-completion finishing-a-development-branch; do
    enabled="$(jq -r ".overrides[\"$skill\"].enabled // \"missing\"" "$starter")"
    assert_equals "starter includes $skill" "true" "$enabled"
done

# Verify starter has exactly 6 overrides
count="$(jq '.overrides | length' "$starter")"
assert_equals "starter has 6 skills" "6" "$count"

# ---------------------------------------------------------------------------
# Standard preset structure
# ---------------------------------------------------------------------------
echo "-- Standard Preset Structure --"

standard="$PROJECT_ROOT/config/presets/standard.json"
default_enabled="$(jq -r '.default_enabled' "$standard")"
assert_equals "standard default_enabled is true" "true" "$default_enabled"

# ---------------------------------------------------------------------------
# Spec-driven preset structure
# ---------------------------------------------------------------------------
echo "-- Spec-Driven Preset Structure --"

spec_driven="$PROJECT_ROOT/config/presets/spec-driven.json"
assert_file_exists "spec-driven.json exists" "$spec_driven"
assert_json_valid "spec-driven.json is valid JSON" "$spec_driven"

name="$(jq -r '.name' "$spec_driven")"
assert_equals "spec-driven name field" "spec-driven" "$name"

openspec_first="$(jq -r '.openspec_first // false' "$spec_driven")"
assert_equals "spec-driven enables openspec_first" "true" "$openspec_first"

default_enabled="$(jq -r '.default_enabled' "$spec_driven")"
assert_equals "spec-driven default_enabled is true" "true" "$default_enabled"

# Description should mention spec-driven / openspec/changes/ for discoverability
description="$(jq -r '.description' "$spec_driven")"
assert_contains "spec-driven description mentions openspec/changes/" "openspec/changes/" "$description"

print_summary
exit $?
