#!/usr/bin/env bash
# test-memory-validate.sh — scripts/memory-validate.sh: structural ERRORs (exit 1),
# staleness WARNs (exit 0). Hermetic: builds a throwaway git repo + memory fixtures.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
VALIDATE="${PROJECT_ROOT}/scripts/memory-validate.sh"

echo "=== test-memory-validate.sh ==="

# --- hermetic sandbox: a repo-root with two committed files, and a memory dir ---
SBOX="$(mktemp -d)"
trap 'rm -rf "${SBOX}"' EXIT
REPO="${SBOX}/repo"; MEM="${SBOX}/memory"
mkdir -p "${REPO}/hooks" "${MEM}"
( cd "${REPO}"
  git init -q
  git config user.email t@t.t; git config user.name t
  mkdir -p hooks
  echo x > hooks/openspec-guard.sh
  echo x > config.json
  git add -A && git commit -qm init ) >/dev/null 2>&1

# helper: write a memory file
_mem() { printf '%s\n' "$2" > "${MEM}/$1"; }

# valid MEMORY.md index referencing every fixture we create with a valid type
_mem MEMORY.md "# Memory Index
- [Good](good.md) — ok"

# Fixture A: missing metadata.type -> ERROR
_mem bad_type.md "---
name: bad
metadata:
  foo: bar
---
body"
# ensure index has an entry so ONLY the type defect fires
printf '%s\n' "- [Bad](bad_type.md) — x" >> "${MEM}/MEMORY.md"

# Fixture B: valid type
_mem good.md "---
name: good
metadata:
  type: feedback
---
body"

out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 1 ] && printf '%s' "${out}" | grep -qF "bad_type.md"; then
    _record_pass "missing metadata.type -> ERROR exit 1"
else
    _record_fail "missing metadata.type -> ERROR exit 1" "rc=${rc} out=${out}"
fi

print_summary
