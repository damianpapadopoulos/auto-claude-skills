#!/usr/bin/env bash
# test-model-routing-regex.sh — Calibration guard for the model-routing
# probation fixture's catch-detector regex.
#
# The single assertion in tests/fixtures/model-routing/review-pack.json is the
# load-bearing discriminator for criterion 2 of the model-routing probation
# (docs/observability.md): it decides whether a code review "caught" the planted
# local-masks-exit-code bug. A regex that false-positives inflates a weak
# model's catch rate; one that false-negatives understates the baseline. This
# test pins the discriminator against an adversarial sample of real-catch vs
# missed-the-bug review texts so it cannot rot silently (cf. CLAUDE.md gotcha on
# grepping runtime output). Hermetic — no model calls.
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-model-routing-regex.sh ==="

PACK="${PROJECT_ROOT}/tests/fixtures/model-routing/review-pack.json"
RE="$(jq -r '.[0].assertions[0].text' "${PACK}")"
assert_not_empty "extracted catch-detector regex from pack" "${RE}"

# Classify a review text exactly as the runner does (grep -E -i against .result).
classify() {
    if printf '%s\n' "$1" | grep -E -i -q "${RE}"; then
        echo "CATCH"
    else
        echo "MISS"
    fi
}

# Real catches — MUST classify CATCH. A false negative here understates the
# baseline model and could fail an otherwise-passing probation. Samples include
# markdown formatting (**bold**, `code`) because real model output is markdown,
# and the verbatim phrasing a real Haiku run used (line 1) — an earlier
# proximity-based regex missed it because markdown inflates token distance.
echo "-- real catches (expect CATCH) --"
i=0
while IFS= read -r line; do
    [ -z "${line}" ] && continue
    assert_equals "catch[$i] detected" "CATCH" "$(classify "${line}")"
    i=$((i + 1))
done <<'STRONG'
captures the exit code of the **`local` command itself**, not the exit code of `jq`.
The `local` **builtin** returns 0 on successful assignment, regardless of whether jq failed.
`local parsed=$(jq ...)` **masks** jq's exit status; $? reflects local.
command substitution on one line **discards** the inner command's status
$? holds the status of the local assignment, **not jq**
assigning with local **resets** $? to 0
the exit status is that of the assignment, which always returns success
STRONG

# Missed-the-bug reviews — MUST classify MISS. A false positive here inflates a
# weak model's apparent catch rate and could pass a failing probation. Includes
# adversarial cases that name `local`/exit-status or use risky keywords
# ("instead of") yet never explain the masking.
echo "-- missed-the-bug reviews (expect MISS) --"
i=0
while IFS= read -r line; do
    [ -z "${line}" ] && continue
    assert_equals "miss[$i] rejected" "MISS" "$(classify "${line}")"
    i=$((i + 1))
done <<'WEAK'
declares a `local` variable `parsed`. Later it returns exit code 0 on success.
The function returns proper exit status when the file is fresh.
Consider using `[[ ]]` instead of `[ ]`.
`stat -f %m` is not portable to Linux which uses `stat -c %Y`.
Looks good overall, just add quotes around $cache_path.
The function returns 1 when missing and 0 when fresh.
You should validate the JSON schema, not just that it parses.
Add a comment explaining the max_age_secs parameter.
WEAK

print_summary
