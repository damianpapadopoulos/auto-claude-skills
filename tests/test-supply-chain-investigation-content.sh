#!/usr/bin/env bash
# tests/test-supply-chain-investigation-content.sh — Content assertions for the supply-chain-investigation skill
set -u
PASS=0; FAIL=0; ERRORS=""

# Note: grep -qF -- "$needle" prevents needles starting with '--' (e.g., '--format=json') from being interpreted as grep flags
assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected to contain: ${needle}"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected NOT to contain: ${needle}"
  else
    PASS=$((PASS + 1))
  fi
}

test_skill_md_has_frontmatter() {
  echo "--- test_skill_md_has_frontmatter ---"
  local content; content="$(cat skills/supply-chain-investigation/SKILL.md)"
  assert_contains "frontmatter name" "name: supply-chain-investigation" "$content"
  assert_contains "frontmatter description trigger phrase" "Use when investigating" "$content"
}

test_skill_md_documents_workflow_phases() {
  echo "--- test_skill_md_documents_workflow_phases ---"
  local content; content="$(cat skills/supply-chain-investigation/SKILL.md)"
  assert_contains "Step 1 PARSE" "Step 1 — PARSE" "$content"
  assert_contains "Step 2 ORG SCAN" "Step 2 — ORG SCAN" "$content"
  assert_contains "Step 3 PIN AUDIT" "Step 3 — PIN AUDIT" "$content"
  assert_contains "Step 4 CI RISK" "Step 4 — CI RISK" "$content"
  assert_contains "Step 5 LOG FORENSICS" "Step 5 — LOG FORENSICS" "$content"
  assert_contains "Step 6 VERDICT" "Step 6 — VERDICT" "$content"
}

test_skill_md_documents_verdict_scale() {
  echo "--- test_skill_md_documents_verdict_scale ---"
  local content; content="$(cat skills/supply-chain-investigation/SKILL.md)"
  assert_contains "verdict COMPROMISED" "COMPROMISED" "$content"
  assert_contains "verdict AT RISK" "AT RISK" "$content"
  assert_contains "verdict SAFE WITH CAVEATS" "SAFE WITH CAVEATS" "$content"
  assert_contains "verdict SAFE" "SAFE" "$content"
}

test_skill_md_links_ecosystem_patterns() {
  echo "--- test_skill_md_links_ecosystem_patterns ---"
  local content; content="$(cat skills/supply-chain-investigation/SKILL.md)"
  assert_contains "references ecosystem-patterns" "references/ecosystem-patterns.md" "$content"
}

test_skill_md_distinguishes_from_security_scanner() {
  echo "--- test_skill_md_distinguishes_from_security_scanner ---"
  local content; content="$(cat skills/supply-chain-investigation/SKILL.md)"
  assert_contains "discriminates from security-scanner" "security-scanner" "$content"
  assert_contains "routes-routine-cve-elsewhere" "routine CVE" "$content"
}

test_skill_md_no_company_specific_strings() {
  echo "--- test_skill_md_no_company_specific_strings ---"
  local content; content="$(cat skills/supply-chain-investigation/SKILL.md)"
  assert_not_contains "no Oviva reference" "Oviva" "$content"
  assert_not_contains "no oviva-ag reference" "oviva-ag" "$content"
  assert_not_contains "no Aikido reference" "Aikido" "$content"
  assert_not_contains "no Sysdig reference" "Sysdig" "$content"
}

test_ecosystem_patterns_covers_required_ecosystems() {
  echo "--- test_ecosystem_patterns_covers_required_ecosystems ---"
  local content; content="$(cat skills/supply-chain-investigation/references/ecosystem-patterns.md)"
  assert_contains "covers npm" "## npm" "$content"
  assert_contains "covers Maven" "## Maven" "$content"
  assert_contains "covers Gradle" "## Gradle" "$content"
  assert_contains "covers Python" "## Python" "$content"
  assert_contains "covers Go" "## Go" "$content"
}

# Run all tests
test_skill_md_has_frontmatter
test_skill_md_documents_workflow_phases
test_skill_md_documents_verdict_scale
test_skill_md_links_ecosystem_patterns
test_skill_md_distinguishes_from_security_scanner
test_skill_md_no_company_specific_strings
test_ecosystem_patterns_covers_required_ecosystems

echo ""
echo "============================================"
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf "%b\n" "$ERRORS"
  exit 1
fi
exit 0
