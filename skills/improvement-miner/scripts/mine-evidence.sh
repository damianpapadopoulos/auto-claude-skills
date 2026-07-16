#!/bin/bash
# mine-evidence.sh — deterministic evidence collector for the
# improvement-miner skill (Stage 1 LEARN miner).
#
# Modes:
#   fingerprint <class> <id>   print 16-hex fingerprint of class:id
#   bundle                     print JSON evidence bundle on stdout
#   dedup <fp>...              print prior decision per fingerprint
#   select                     stdin: candidate JSON array -> gated selection
#
# FAIL-LOUD BY DESIGN: this is a user-invoked tool, not a fail-open hook.
# Trust boundary lives HERE, not in skill prose: author allowlist, no
# comments, no raw artifact fields, no tests/fixtures/*/evals content.
set -u

MODE="${1:-}"

usage() {
    echo "usage: mine-evidence.sh fingerprint <class> <id> | bundle | dedup <fp>... | select" >&2
    exit 2
}

require() {
    command -v "$1" >/dev/null 2>&1 && return 0
    echo "ERROR: required tool '$1' not found (improvement-miner is fail-loud)" >&2
    exit 3
}

fp_of() { printf '%s:%s' "$1" "$2" | shasum -a 256 | cut -c1-16; }

case "${MODE}" in
    fingerprint)
        require shasum
        [ -n "${2:-}" ] && [ -n "${3:-}" ] || usage
        fp_of "$2" "$3"
        ;;
    bundle|dedup|select)
        require jq; require gh; require shasum
        echo "ERROR: mode '${MODE}' not implemented yet" >&2
        exit 4
        ;;
    *) usage ;;
esac
