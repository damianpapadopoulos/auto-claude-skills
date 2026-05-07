#!/usr/bin/env bash
# serena-telemetry-report.sh — Summarise follow-through % per matcher class
# from ~/.claude/.serena-nudge-telemetry over a rolling window (default 14 days).
#
# Usage: bash scripts/serena-telemetry-report.sh [days]
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

awk -F'\t' -v cutoff="${CUTOFF}" '
$1 >= cutoff {
    kind = $4; cls = $5;
    if (kind == "nudge" || kind == "observe") {
        firings[cls]++;
        if (!(cls in seen)) { seen[cls] = 1; order[++ord] = cls; }
    } else if (kind == "followup") {
        followups[cls]++;
    }
}
END {
    if (ord == 0) {
        print "no firings in window";
        exit 0;
    }
    printf "%-25s %8s %10s %12s\n", "class", "firings", "followups", "pct";
    for (i = 1; i <= ord; i++) {
        cls = order[i];
        n = firings[cls];
        f = (cls in followups) ? followups[cls] : 0;
        pct = (n > 0) ? int((f * 100) / n) : 0;
        printf "%-25s %8d %10d %11d%%\n", cls, n, f, pct;
    }
}' "${TELEM}"
