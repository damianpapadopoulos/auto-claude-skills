#!/usr/bin/env bash
# verdict.sh — read + interpret the owned verification verdict artifact
# (~/.claude/.skill-project-verified-<token>) and routing-diff scope. Separates
# STATUS (a gating Skill returned) from VERDICT (it actually passed). Bash 3.2.
# All functions fail-open: on any error they return "no usable verdict / no
# scope" so the push gate falls back to the status layer (never a false-block).

verdict_artifact_path() {
    local token="${1:-}"
    [ -z "$token" ] && return 1
    printf '%s' "${HOME}/.claude/.skill-project-verified-${token}"
}

_verdict_sha() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -r '.sha // empty' "$f" 2>/dev/null
}

# verdict_sha_is_head <token> <proj_root> — 0 iff artifact .sha == HEAD exactly.
verdict_sha_is_head() {
    local token="${1:-}" proot="${2:-}" sha head
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || return 1
    [ -n "$head" ] && [ "$sha" = "$head" ]
}

# verdict_covers_head <token> <proj_root> — 0 iff .sha == HEAD or is an ancestor
# of HEAD on the branch. This is the branch-scoping the token-scoped artifact
# lacks: an unrelated (cross-branch) or missing sha never covers HEAD.
verdict_covers_head() {
    local token="${1:-}" proot="${2:-}" sha head
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || return 1
    [ -z "$head" ] && return 1
    [ "$sha" = "$head" ] && return 0
    git -C "${proot:-.}" merge-base --is-ancestor "$sha" "$head" 2>/dev/null
}

# verdict_resolve_token <session_token> <proj_root> — pick the token whose verdict
# is authoritative for the CURRENT push. The verdict is bound to the COMMIT (sha),
# NOT the session: the project-verification SKILL has no stdin payload and can only
# derive its token from the shared singleton, while this hook resolves payload-first
# (issue #51). Concurrent sessions clobber the singleton (last-writer-wins) so the two
# tokens diverge and a token-scoped read would never find the verdict — a live deadlock.
#
# To stay byte-identical when the session's own verdict is usable, this returns
# <session_token> whenever ITS artifact covers HEAD. ONLY otherwise (the divergence
# case) does it scan sibling ~/.claude/.skill-project-verified-* artifacts and return
# the first one bound to the same HEAD, preferring a FAILURE at HEAD (deny-bias /
# anti-gate-gaming) over a clean one. If nothing covers HEAD, returns <session_token>
# unchanged (absent/stale semantics preserved). sha==HEAD remains the sole authority —
# no forgery surface is added (token-scoping was session-isolation, never a security
# property). Fail-open: echoes <session_token> on any error.
verdict_resolve_token() {
    local session_token="${1:-}" proot="${2:-}" head f base tok best_clean=""
    # 1. Session token's own verdict covers HEAD (equal OR ancestor) -> use it. This is
    #    byte-identical to prior single-token behavior, including ancestor acceptance.
    if [ -n "$session_token" ] && verdict_covers_head "$session_token" "$proot"; then
        printf '%s' "$session_token"; return 0
    fi
    # 2. Cross-token bridge: consult sibling artifacts, but ONLY those bound to the EXACT
    #    HEAD. A foreign session's verdict is authoritative for THIS push solely when
    #    measured at this precise commit — the forgery-resistant binding (ancestor
    #    acceptance stays scoped to the session's own token, step 1). A grep -F prefilter
    #    on the HEAD sha bounds the jq/git forks to the few files naming HEAD (usually
    #    0-2), so the scan cost does not grow with an un-GC'd artifact dir. A failure at
    #    HEAD outranks a clean one (deny-bias / anti-gate-gaming).
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || head=""
    [ -z "$head" ] && { printf '%s' "$session_token"; return 0; }
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        base="${f##*/}"                                   # fork-free basename (bash 3.2; no BSD -- ambiguity)
        tok="${base#.skill-project-verified-}"
        [ -z "$tok" ] && continue
        [ "$tok" = "$session_token" ] && continue
        verdict_sha_is_head "$tok" "$proot" || continue   # jq-confirm exact HEAD (grep can match other fields)
        if verdict_has_test_failure "$tok"; then printf '%s' "$tok"; return 0; fi
        [ -z "$best_clean" ] && verdict_is_clean "$tok" && best_clean="$tok"
    done <<EOF
$(grep -lF "$head" "${HOME}/.claude/.skill-project-verified-"* 2>/dev/null)
EOF
    [ -n "$best_clean" ] && { printf '%s' "$best_clean"; return 0; }
    printf '%s' "$session_token"
}

# verdict_has_test_failure <token> — 0 iff present+parseable AND .failed non-empty.
# Positive-evidence only: a missing/malformed artifact returns 1 (no failure),
# so verify-hardening never denies for absence.
verdict_has_test_failure() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e '((.failed // []) | length) > 0' "$f" >/dev/null 2>&1
}

# verdict_is_clean <token> — 0 iff present+parseable AND fully clean (same
# predicate deploy-gate uses for local verification of record).
verdict_is_clean() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e '((.failed // []) | length == 0)
       and ((.could_not_verify // []) | length == 0)
       and ((.gate_gaming_status // "") == "clean")' "$f" >/dev/null 2>&1
}

# verdict_failing_gates <token> — prints comma-joined .failed command names.
verdict_failing_gates() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 0
    [ -f "$f" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '((.failed // []) | join(", "))' "$f" 2>/dev/null || true
}

# is_routing_repo <proj_root> — 0 iff this looks like a skill-routing plugin repo
# (has config/default-triggers.json). Scopes the routing-governance gate.
is_routing_repo() {
    local proot="${1:-}"
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$proot" ] && [ -f "${proot}/config/default-triggers.json" ]
}

# _routing_base <proj_root> — best-available mainline merge-base for HEAD.
_routing_base() {
    local proot="${1:-.}" ref b
    for ref in origin/HEAD '@{upstream}' origin/main main origin/master master; do
        b="$(git -C "$proot" merge-base HEAD "$ref" 2>/dev/null)" && [ -n "$b" ] && { printf '%s' "$b"; return 0; }
    done
    return 1
}

# verdict_routing_delta <token> <proj_root> — 0 iff routing paths changed between
# the verdict's sha and HEAD (i.e., routing work POST-DATES the verdict, so the
# clean verdict does not cover it). Used by the routing gate to decide whether an
# ancestor-clean verdict is still authoritative. Fail-open: sha unknown/unreadable
# => 1 (no detectable delta => don't manufacture a false-block).
verdict_routing_delta() {
    local token="${1:-}" proot="${2:-}" sha head names
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || return 1
    names="$(git -C "${proot:-.}" diff --name-only "$sha" "$head" 2>/dev/null)" || return 1
    printf '%s\n' "$names" | grep -Eq '^(skills|config|hooks)/'
}

# diff_touches_routing <proj_root> — 0 iff the branch diff (base..HEAD) touches a
# routing path. Fail-open: unresolvable base => 1 (no gate).
diff_touches_routing() {
    local proot="${1:-}" head base names
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$proot" ] && return 1
    head="$(git -C "$proot" rev-parse HEAD 2>/dev/null)" || return 1
    base="$(_routing_base "$proot")" || return 1
    names="$(git -C "$proot" diff --name-only "$base" "$head" 2>/dev/null)" || return 1
    printf '%s\n' "$names" | grep -Eq '^(skills|config|hooks)/'
}
