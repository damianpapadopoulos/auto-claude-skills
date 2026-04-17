#!/usr/bin/env bash
# migrate-docs-plans-to-openspec.sh
#
# One-shot helper for repos adopting spec-driven mode. Inventories
# docs/plans/*-design.md artifacts (gitignored, session-scoped) and copies
# their content into openspec/changes/<feature>/design.md (committed,
# team-visible).
#
# Usage:
#   bash scripts/migrate-docs-plans-to-openspec.sh --dry-run   # list only
#   bash scripts/migrate-docs-plans-to-openspec.sh --apply     # perform copy
#
# Behavior:
#   - Inventories only *-design.md files (ignores plan.md, spec.md, and other
#     files in docs/plans/).
#   - Derives the feature slug by stripping the YYYY-MM-DD- prefix and the
#     -design.md suffix. E.g., "2026-04-01-auth-refresh-design.md" →
#     "auth-refresh".
#   - Copies to openspec/changes/<slug>/design.md.
#   - NEVER clobbers an existing openspec/changes/<slug>/design.md — if the
#     target already exists (because the feature was already in spec-driven
#     mode), the source file is skipped and a notice is printed.
#   - Preserves the original docs/plans/ file (does not delete or move). This
#     is a migration/copy, not a rename; the gitignored local file stays.
#
# Exit codes:
#   0 — dry-run completed, or apply succeeded (even if some files were skipped)
#   1 — invalid flag, or no --dry-run/--apply specified
#
# Bash 3.2 compatible.

set -u

MODE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) MODE="dry-run" ;;
        --apply)   MODE="apply" ;;
        -h|--help)
            sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
    shift
done

if [ -z "${MODE}" ]; then
    echo "Usage: bash scripts/migrate-docs-plans-to-openspec.sh --dry-run | --apply" >&2
    exit 1
fi

PLANS_DIR="docs/plans"
if [ ! -d "${PLANS_DIR}" ]; then
    echo "[migrate] No docs/plans/ directory — nothing to migrate."
    exit 0
fi

# Inventory *-design.md files. Deterministic sort order.
INVENTORY=""
for f in "${PLANS_DIR}"/*-design.md; do
    [ -f "${f}" ] || continue
    INVENTORY="${INVENTORY}${f}
"
done
INVENTORY="$(printf '%s' "${INVENTORY}" | sort)"

if [ -z "${INVENTORY}" ]; then
    echo "[migrate] No *-design.md files in ${PLANS_DIR}/ — nothing to migrate."
    exit 0
fi

# Derive slug: strip YYYY-MM-DD- prefix and -design.md suffix.
derive_slug() {
    local path="$1"
    local base
    base="$(basename "${path}")"
    # Strip the trailing -design.md
    base="${base%-design.md}"
    # Strip YYYY-MM-DD- prefix (10 chars of date + 1 dash)
    case "${base}" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*)
            base="${base#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"
            ;;
    esac
    printf '%s' "${base}"
}

echo "[migrate] Mode: ${MODE}"
echo "[migrate] Discovered design artifacts:"
copied=0
skipped_exists=0
while IFS= read -r source; do
    [ -z "${source}" ] && continue
    slug="$(derive_slug "${source}")"
    target="openspec/changes/${slug}/design.md"
    echo "  ${source}  →  ${target}  (slug: ${slug})"

    if [ "${MODE}" = "dry-run" ]; then
        continue
    fi

    # Apply mode: copy unless target exists.
    if [ -f "${target}" ]; then
        echo "    SKIP: target already exists (not clobbering)"
        skipped_exists=$((skipped_exists + 1))
        continue
    fi
    mkdir -p "$(dirname "${target}")"
    cp "${source}" "${target}"
    copied=$((copied + 1))
done <<EOF
${INVENTORY}
EOF

echo ""
echo "[migrate] Summary"
echo "================="
if [ "${MODE}" = "dry-run" ]; then
    echo "Dry-run: no files were modified. Re-run with --apply to perform the migration."
else
    echo "Copied: ${copied}"
    echo "Skipped (target exists): ${skipped_exists}"
    echo ""
    echo "Next steps:"
    echo "  1. Review the copied design.md files — they may need proposal.md"
    echo "     and specs/<capability>/spec.md siblings to be fully valid"
    echo "     OpenSpec changes. Run 'openspec validate <slug>' per change."
    echo "  2. git add openspec/changes/ && git commit"
fi
exit 0
