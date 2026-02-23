#!/bin/bash
# --- Fix invalid plugin manifest keys on session start -----------
# Strips unrecognized keys (category, source, strict) from cached
# plugin.json files so Claude Code's validator doesn't reject them.
# Safe to re-run (idempotent). Runs once per SessionStart.
# -----------------------------------------------------------------
set -uo pipefail

CACHE_DIR="$HOME/.claude/plugins/cache"
[[ ! -d "$CACHE_DIR" ]] && exit 0

find "$CACHE_DIR" -name "plugin.json" -path "*/.claude-plugin/*" 2>/dev/null | while read -r manifest; do
  # Remove invalid keys; jq del() is idempotent
  cleaned=$(jq 'del(.category, .source, .strict)' "$manifest" 2>/dev/null) || continue

  # Only write if something changed
  if [[ "$cleaned" != "$(cat "$manifest")" ]]; then
    printf '%s\n' "$cleaned" > "$manifest"
  fi
done

exit 0
