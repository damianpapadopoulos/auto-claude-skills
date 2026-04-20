#!/usr/bin/env bash
# run-behavioral-evals.sh — Opt-in behavioral eval runner for incident-analysis v1.
# Not in default run-tests.sh; requires BEHAVIORAL_EVALS=1.
# Bash 3.2 compatible.
set -u

usage() {
    cat >&2 <<'EOF'
usage: BEHAVIORAL_EVALS=1 tests/run-behavioral-evals.sh --scenario <id> [--pack <path>]

Environment:
  BEHAVIORAL_EVALS=1      required to run; any other value is a no-op
  CLAUDE_BIN              override 'claude' binary (default: 'claude')
  ARTIFACTS_DIR           override artifact output directory (default: 'tests/artifacts')
  SKILL_PATH              override skill file (default: 'skills/incident-analysis/SKILL.md')

Exit codes:
  0  all assertions passed
  1  at least one assertion failed
  2  guard / schema / precondition failure
EOF
}

if [ "${BEHAVIORAL_EVALS:-0}" != "1" ]; then
    echo "error: BEHAVIORAL_EVALS=1 required to run this runner. See usage:" >&2
    usage
    exit 2
fi

# Argument parsing and subsequent logic added in later tasks.
echo "error: runner body not yet implemented" >&2
exit 2
