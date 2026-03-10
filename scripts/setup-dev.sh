#!/bin/bash
# setup-dev.sh — Link the plugin cache to this repo for live development.
#
# After running this once, every new Claude Code session uses hooks,
# config, and skills directly from your working tree — no sync needed.
#
# Usage:  bash scripts/setup-dev.sh          (link)
#         bash scripts/setup-dev.sh --undo   (restore original cache)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_BASE="${HOME}/.claude/plugins/cache"
UNDO=false
[ "${1:-}" = "--undo" ] && UNDO=true

found=0
for marketplace_dir in "${CACHE_BASE}"/*/; do
    [ -d "${marketplace_dir}" ] || continue
    PLUGIN_DIR="${marketplace_dir}auto-claude-skills"
    [ -d "${PLUGIN_DIR}" ] || [ -L "${PLUGIN_DIR}" ] || continue

    for version_entry in "${PLUGIN_DIR}"/*/; do
        [ -d "${version_entry}" ] || [ -L "${version_entry%/}" ] || continue
        version="$(basename "${version_entry%/}")"
        target="${PLUGIN_DIR}/${version}"

        if "${UNDO}"; then
            if [ -L "${target}" ]; then
                backup="${target}.bak"
                if [ -d "${backup}" ]; then
                    rm "${target}"
                    mv "${backup}" "${target}"
                    printf 'Restored: %s\n' "${target}"
                else
                    printf 'No backup found for %s — remove symlink manually\n' "${target}" >&2
                fi
            else
                printf 'Not a symlink, nothing to undo: %s\n' "${target}"
            fi
        else
            if [ -L "${target}" ]; then
                existing="$(readlink "${target}")"
                if [ "${existing}" = "${REPO}" ]; then
                    printf 'Already linked: %s -> %s\n' "${target}" "${REPO}"
                else
                    printf 'Symlink exists but points elsewhere: %s -> %s\n' "${target}" "${existing}" >&2
                fi
            else
                mv "${target}" "${target}.bak"
                ln -s "${REPO}" "${target}"
                printf 'Linked: %s -> %s\n' "${target}" "${REPO}"
            fi
        fi
        found=1
    done
done

if [ "${found}" -eq 0 ]; then
    printf 'No installed auto-claude-skills found in plugin cache.\n' >&2
    printf 'Install the plugin first, then re-run this script.\n' >&2
    exit 1
fi
