#!/usr/bin/env bash
# serena-glob-sequence-check.sh — Sequence-aware analysis of
# glob_definition_hunt observations. Classifies each observation as one of:
#   - followed_up: a Serena MCP tool was called within 3 turns of the same
#     session (already correlated by hooks/serena-followthrough.sh).
#   - intervening_grep: a Grep nudge fired within 3 turns of the same
#     session, suggesting the user proceeded into the symbol-search workflow
#     manually instead of using Serena.
#   - revival_signal: neither — the user globbed and proceeded to do
#     something that did not register as either a Serena call or a Grep
#     nudge. This is the evidence that supports reviving the parked Glob
#     active matcher.
#
# Used at the 14-day revival evaluation point (see docs/plans/archive/
# 2026-05-07-serena-triggering-redesign-design.md Kill / Revival Criteria
# table). Address the gap noted by Codex during PR #25 review.
#
# Usage: bash scripts/serena-glob-sequence-check.sh [days]
set -u

DAYS="${1:-14}"
TELEM="${HOME}/.claude/.serena-nudge-telemetry"

if [ ! -s "${TELEM}" ]; then
    echo "no telemetry recorded yet at ${TELEM}"
    exit 0
fi

NOW="$(date +%s)"
WINDOW=$((DAYS * 86400))
CUTOFF=$((NOW - WINDOW))

# Awk implements the lookahead by buffering pending globs per session and
# updating their state as later events arrive. Bash 3.2 compatible — awk
# associative arrays are fine; the script uses no bash arrays.
awk -F'\t' -v cutoff="${CUTOFF}" '
$1 < cutoff { next }
{
    tok = $2; turn = $3 + 0; kind = $4; cls = $5;
    if (kind == "observe" && cls == "glob_definition_hunt") {
        glob_total++;
        glob_session[glob_total] = tok;
        glob_turn[glob_total] = turn;
        glob_followed[glob_total] = 0;
        glob_intervened[glob_total] = 0;
    }
    # Update earlier globs in the same session that are still in their window.
    for (i = 1; i <= glob_total; i++) {
        if (glob_session[i] != tok) continue;
        d = turn - glob_turn[i];
        if (d <= 0 || d > 3) continue;
        if (kind == "followup" && cls == "glob_definition_hunt") {
            glob_followed[i] = 1;
        } else if (kind == "nudge") {
            glob_intervened[i] = 1;
        }
    }
}
END {
    if (glob_total == 0) {
        print "no glob_definition_hunt observations in window";
        exit 0;
    }
    followed = 0; intervened = 0; revival = 0;
    for (i = 1; i <= glob_total; i++) {
        if (glob_followed[i])      { followed++ }
        else if (glob_intervened[i]) { intervened++ }
        else                         { revival++ }
    }
    print "Glob definition-hunt sequence analysis (last " '"$DAYS"' " days)";
    printf "Total observations:                       %d\n", glob_total;
    printf "  Serena followup (good — Glob → Serena): %d\n", followed;
    printf "  Intervening Grep (Glob → Grep workflow): %d\n", intervened;
    printf "  No follow-up, no Grep (revival signal): %d\n", revival;
}
' "${TELEM}"
