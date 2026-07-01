#!/bin/bash
# coverage-adequacy-check.sh — deterministic test-adequacy tripwire.
# Mirrors gate-gaming-check.sh: advisory, fail-open (exit 0 always). Empty stdout
# means "unverified" (no coverage artifact / unparseable) — the caller treats empty
# as unverified, a normal run prints an explicit clean|suspect.
# Modes (COVERAGE_ADEQUACY_MODE): changed-lines (debug: emit added path\tline) |
# verdict (default: emit clean|suspect + uncovered lines).
set -u

# _changed_lines: unified diff on stdin -> "path<TAB>newline" per added content line.
_changed_lines() {
  awk '
    /^\+\+\+ / { f=$2; sub(/^b\//,"",f); next }
    /^--- /    { next }
    /^@@ /     { match($0, /\+[0-9]+/); ln=substr($0,RSTART+1,RLENGTH-1)+0; next }
    /^\+/      { if (f!="") print f "\t" ln; ln++; next }
    /^-/       { next }
    /^ /       { ln++; next }
  '
}

_mode="${COVERAGE_ADEQUACY_MODE:-verdict}"
_diff="$(cat 2>/dev/null || true)"

if [ "$_mode" = "changed-lines" ]; then
  printf '%s\n' "$_diff" | _changed_lines
  exit 0
fi

# verdict mode filled in Task 3
echo "unverified"
exit 0
