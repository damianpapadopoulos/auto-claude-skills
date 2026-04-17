#!/usr/bin/env bash
# validate-active-openspec-changes.sh
#
# Runs `openspec validate <slug>` against every active (non-archived) change
# under openspec/changes/. Aggregates failures across all active changes and
# exits 1 if any validation fails.
#
# Exits 0 when:
#   - openspec/changes/ does not exist
#   - openspec/changes/ contains only archive/ or is empty
#
# Exits 1 when:
#   - the openspec CLI is not available on PATH
#   - any active change fails `openspec validate`
#
# Designed for CI (GitHub Actions) but also runnable locally. Bash 3.2
# compatible (macOS default).

set -u

CHANGES_DIR="openspec/changes"

# If there's no openspec/changes/ at all, nothing to validate (default-mode
# repo). Exit 0 with a notice.
if [ ! -d "${CHANGES_DIR}" ]; then
    echo "[openspec-validate] No ${CHANGES_DIR}/ directory — nothing to validate."
    exit 0
fi

# Verify openspec CLI availability. A missing CLI is a loud failure: a gate
# that silently passes because its tool is missing is worse than no gate.
if ! command -v openspec >/dev/null 2>&1; then
    echo "[openspec-validate] ERROR: 'openspec' CLI not found on PATH." >&2
    echo "[openspec-validate] Install @fission-ai/openspec before running this script." >&2
    exit 1
fi

# Discover active changes: top-level directories under openspec/changes/
# EXCLUDING archive/. Sort for deterministic output ordering.
ACTIVE_CHANGES=""
for entry in "${CHANGES_DIR}"/*/; do
    [ -d "${entry}" ] || continue
    name="$(basename "${entry}")"
    [ "${name}" = "archive" ] && continue
    ACTIVE_CHANGES="${ACTIVE_CHANGES}${name}
"
done

ACTIVE_CHANGES="$(printf '%s' "${ACTIVE_CHANGES}" | sort)"

if [ -z "${ACTIVE_CHANGES}" ]; then
    echo "[openspec-validate] No active changes under ${CHANGES_DIR}/ (archive excluded) — nothing to validate."
    exit 0
fi

echo "[openspec-validate] Validating active changes:"
printf '  - %s\n' ${ACTIVE_CHANGES}
echo ""

# Validate each change. Do NOT fail-fast — aggregate failures so devs see
# every issue at once in CI logs.
FAILED_CHANGES=""
exit_code=0
while IFS= read -r slug; do
    [ -z "${slug}" ] && continue
    echo "[openspec-validate] --- ${slug} ---"
    if openspec validate "${slug}"; then
        echo "[openspec-validate] PASS: ${slug}"
    else
        echo "[openspec-validate] FAIL: ${slug}"
        FAILED_CHANGES="${FAILED_CHANGES} ${slug}"
        exit_code=1
    fi
    echo ""
done <<EOF
${ACTIVE_CHANGES}
EOF

echo "[openspec-validate] Summary"
echo "==========================="
if [ "${exit_code}" -eq 0 ]; then
    echo "All active changes passed validation."
else
    echo "Failed changes:${FAILED_CHANGES}"
fi

exit "${exit_code}"
