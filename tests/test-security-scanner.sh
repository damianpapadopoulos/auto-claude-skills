#!/usr/bin/env bash
# tests/test-security-scanner.sh — Tests for security scanner integration
set -u
PASS=0; FAIL=0; ERRORS=""

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected to contain: ${needle}\n    got: $(printf '%s' "$haystack" | head -c 200)"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected NOT to contain: ${needle}"
  else
    PASS=$((PASS + 1))
  fi
}

# ── Test: security_capabilities appears in session-start output ──
test_security_capabilities_in_output() {
  echo "--- test_security_capabilities_in_output ---"
  local output
  output="$(bash hooks/session-start-hook.sh 2>/dev/null)" || true
  assert_contains "session-start emits security tools" "Security tools:" "$output"
  assert_contains "session-start emits semgrep capability" "semgrep=" "$output"
  assert_contains "session-start emits trivy capability" "trivy=" "$output"
}

# ── Test: security-scanner removed from missing external skills ──
test_security_scanner_not_in_external_check() {
  echo "--- test_security_scanner_not_in_external_check ---"
  local hook_source
  hook_source="$(cat hooks/session-start-hook.sh)"
  assert_not_contains "security-scanner not in external skills loop" \
    "doc-coauthoring webapp-testing security-scanner" "$hook_source"
}

# ══════════════════════════════════════════════════════════════════
# Run tests
# ══════════════════════════════════════════════════════════════════
test_security_capabilities_in_output
test_security_scanner_not_in_external_check

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ -n "$ERRORS" ]; then
  printf '%b\n' "$ERRORS"
  exit 1
fi
exit 0
