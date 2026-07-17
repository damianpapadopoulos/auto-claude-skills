# Phase-Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deterministic non-skippable SDLC phase transitions: a PreToolUse `^Skill$` sequencing gate + outbound DESIGN/PLAN evidence (backtest-gated), with an explicit logged skip-attestation escape that never satisfies REVIEW/VERIFY.

**Architecture:** Two deny boundaries share one evidence predicate (**append-only invocation record ∪ branch ledger ∪ attestation — NEVER the walker-writable `.completed`**): `hooks/skill-gate.sh` (new PreToolUse `^Skill$`) denies out-of-order chain-member invocations with implementation-slot aliasing; `hooks/openspec-guard.sh` gains a DESIGN/PLAN leg next to its global REVIEW/VERIFY gate (warn = telemetry-only; deny only via config after the replay backtest clears it). Spec: `openspec/changes/phase-enforcement/` incl. the 2026-07-16 sparring amendments.

**Tech Stack:** Bash 3.2 (`/bin/bash`), jq (evidence legs are jq-dependent — no jq ⇒ gates fall open, matching the push gate), repo test harness (`tests/test-helpers.sh`).

## Global Constraints

- Bash 3.2: no associative arrays; NEVER quote operands inside `$(( ))`; validate numerics with `[[ "$V" =~ ^[0-9]+$ ]]` before arithmetic.
- Fail-open on ERROR everywhere: any infrastructure failure → exit 0, no output. DENY requires positive, readable violation evidence (this is the deliberate inversion of the push gate's fail-closed posture — documented in design.md Trade-offs).
- Deny output shape (exact, reuse from openspec-guard.sh): `jq -n --arg msg "$MSG" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'`.
- Chain state uses BARE skill names (`brainstorming`, not `superpowers:brainstorming`); normalize invoked names with `${raw##*:}` (completion-hook rule).
- Gating milestones `requesting-code-review` and `verification-before-completion` MUST NOT be attestable — enforced in BOTH the attest writer and every evidence reader (two independent locks).
- Session-token resolution is payload-first via `resolve_session_token_from_transcript`; singleton fallback (issue #51).
- jq program strings use `\u`-escapes for control chars, never raw bytes; verify with `LC_ALL=C grep -c $'\x1f' <file>` = 0 after editing.
- New hook files need the exec bit (hooks.json invokes directly) and a `[ -x ]` test assert.
- Routing files `config/default-triggers.json` and `config/fallback-registry.json` change TOGETHER (canonical-source memory).
- Tests run `/bin/bash <suite> < /dev/null`; full suite `bash tests/run-tests.sh < /dev/null`.
- Commits: `<type>: <description>` + Co-Authored-By trailer.

---

### Task 1: Attestation lib (`hooks/lib/phase-attest.sh`)

**Files:**
- Create: `hooks/lib/phase-attest.sh`
- Test: `tests/test-skill-gate.sh` (new — created here, extended by later tasks)

**Interfaces:**
- Produces: `phase_attest <step> <reason>` (writes/merges `~/.claude/.skill-phase-attest-<token>`; refuses gating milestones with exit 1 + stderr; resolves token itself: payload-less callers use the singleton). `phase_attested <token> <step>` → exit 0 iff step attested AND step is not a gating milestone (reader-side lock). `PHASE_ATTEST_GATING_EXCLUDE` — space-separated exclusion list constant. Attest file shape: `{"<step>": {"reason": "...", "ts": "<utc>"}}`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test-skill-gate.sh`:

```bash
#!/usr/bin/env bash
# test-skill-gate.sh — phase-enforcement suite (attest lib, evidence lib,
# skill-gate, guard C2 leg). Spec: openspec/changes/phase-enforcement/specs/pdlc-safety/spec.md
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-skill-gate.sh ==="

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/psg-home-XXXXXX)"
mkdir -p "$HOME/.claude"
trap 'rm -rf "$HOME"; export HOME="$_OLDHOME"' EXIT

TOKEN="session-psg-test"
printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
ATTEST_LIB="${PROJECT_ROOT}/hooks/lib/phase-attest.sh"
ATTEST_FILE="$HOME/.claude/.skill-phase-attest-${TOKEN}"

# --- attest: writes reason + ts, merges, refuses gating milestones ---
rm -f "$ATTEST_FILE"
/bin/bash -c ". '${ATTEST_LIB}' && phase_attest product-discovery 'bugfix - covered by brief'" 2>/dev/null
assert_file_exists "attest writes file" "$ATTEST_FILE"
assert_contains "attest records reason" "covered by brief" "$(cat "$ATTEST_FILE")"
/bin/bash -c ". '${ATTEST_LIB}' && phase_attest openspec-ship 'doc-only session'" 2>/dev/null
assert_contains "attest merges second step" "openspec-ship" "$(cat "$ATTEST_FILE")"
assert_contains "attest keeps first step" "product-discovery" "$(cat "$ATTEST_FILE")"

_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attest requesting-code-review 'nope'" 2>/dev/null || _rc=$?
assert_equals "attest refuses requesting-code-review (exit 1)" "1" "$_rc"
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attest verification-before-completion 'nope'" 2>/dev/null || _rc=$?
assert_equals "attest refuses verification-before-completion (exit 1)" "1" "$_rc"
assert_not_contains "gating milestones absent from attest file" "requesting-code-review" "$(cat "$ATTEST_FILE")"

# --- attested reader: true for written step, false for absent, false for gating even if forged ---
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attested '${TOKEN}' product-discovery" || _rc=$?
assert_equals "attested: recorded step -> 0" "0" "$_rc"
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attested '${TOKEN}' brainstorming" || _rc=$?
assert_equals "attested: absent step -> 1" "1" "$_rc"
# Forge a gating-milestone entry by direct file write (Scenario 3, reader-side lock)
jq '. + {"requesting-code-review":{"reason":"forged","ts":"x"}}' "$ATTEST_FILE" > "$ATTEST_FILE.t" && mv "$ATTEST_FILE.t" "$ATTEST_FILE"
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attested '${TOKEN}' requesting-code-review" || _rc=$?
assert_equals "attested: forged gating milestone -> 1 (reader lock)" "1" "$_rc"

print_summary
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd .claude/worktrees/phase-enforcement && /bin/bash tests/test-skill-gate.sh < /dev/null`
Expected: FAIL (lib does not exist).

- [ ] **Step 3: Implement the lib**

Create `hooks/lib/phase-attest.sh`:

```bash
#!/bin/bash
# phase-attest.sh — explicit skip-attestation for composition-chain steps.
# phase_attest <step> <reason> records a logged, review-surfaced skip in
# ~/.claude/.skill-phase-attest-<token>. Gating milestones are NEVER
# attestable: the writer refuses them here AND every reader re-checks
# (two independent locks, like the max_iterations role-allowlist).
# Spec: openspec/changes/phase-enforcement (Scenario 2, 3).

PHASE_ATTEST_GATING_EXCLUDE="requesting-code-review verification-before-completion"

# _phase_attest_token: singleton read (attest is invoked from the model's
# Bash turn, which has no hook payload; the singleton was re-stamped by the
# activation hook this prompt — issue #51 narrowing applies).
_phase_attest_token() {
    cat "${HOME}/.claude/.skill-session-token" 2>/dev/null
}

phase_attest() {
    local step="${1:-}" reason="${2:-}"
    [ -z "$step" ] && { echo "[phase-attest] usage: phase_attest <step> <reason>" >&2; return 1; }
    [ -z "$reason" ] && { echo "[phase-attest] a reason is required — attestation is an auditable decision" >&2; return 1; }
    local ex
    for ex in $PHASE_ATTEST_GATING_EXCLUDE; do
        if [ "$step" = "$ex" ]; then
            echo "[phase-attest] REFUSED: '$step' is a gating milestone and cannot be attested away (invoke the real skill)" >&2
            return 1
        fi
    done
    command -v jq >/dev/null 2>&1 || { echo "[phase-attest] jq required" >&2; return 1; }
    local token; token="$(_phase_attest_token)"
    [ -z "$token" ] && { echo "[phase-attest] no session token" >&2; return 1; }
    local f="${HOME}/.claude/.skill-phase-attest-${token}" tmp
    local base="{}"
    [ -f "$f" ] && jq empty "$f" >/dev/null 2>&1 && base="$(cat "$f")"
    tmp="$(printf '%s' "$base" | jq --arg s "$step" --arg r "$reason" \
        '. + {($s): {reason: $r, ts: (now | todate)}}' 2>/dev/null)" || return 1
    [ -z "$tmp" ] && return 1
    printf '%s\n' "$tmp" > "${f}.tmp.$$" 2>/dev/null && mv "${f}.tmp.$$" "$f" 2>/dev/null || return 1
    printf '%s gate=attest decision=recorded step=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$step" \
        >> "${HOME}/.claude/.phase-gate-events.log" 2>/dev/null || true
    echo "[phase-attest] recorded skip of '$step' — visible at REVIEW" >&2
    return 0
}

# phase_attested <token> <step> — 0 iff attested AND not a gating milestone.
phase_attested() {
    local token="${1:-}" step="${2:-}" ex
    [ -z "$token" ] || [ -z "$step" ] && return 1
    for ex in $PHASE_ATTEST_GATING_EXCLUDE; do
        [ "$step" = "$ex" ] && return 1
    done
    command -v jq >/dev/null 2>&1 || return 1
    local f="${HOME}/.claude/.skill-phase-attest-${token}"
    [ -f "$f" ] || return 1
    jq -e --arg s "$step" 'has($s)' "$f" >/dev/null 2>&1
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/bin/bash -n hooks/lib/phase-attest.sh && /bin/bash tests/test-skill-gate.sh < /dev/null`
Expected: PASS (all asserts).

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/phase-attest.sh tests/test-skill-gate.sh
git commit -m "feat: skip-attestation lib — logged, gating-milestones excluded (two locks)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Evidence predicate lib + completion-hook provenance split

**Files:**
- Create: `hooks/lib/phase-evidence.sh`
- Modify: `hooks/skill-completion-hook.sh` (append-only invocation record + all-step ledger recording)
- Modify: `hooks/session-start-hook.sh` (state-prune patterns + `_GATE_ENFORCE_LIBS`)
- Test: `tests/test-skill-gate.sh` (append before `print_summary`)

**Interfaces:**
- Consumes: `phase_attested` (Task 1), `branch_ledger_has <milestone> <proj_root>` + `branch_ledger_record <milestone> <proj_root>` (existing `hooks/lib/branch-ledger.sh`).
- Produces: `phase_step_satisfied <token> <step> <proj_root>` → 0 iff step (or an implementation-slot alias of it) is in the **invocation record** `~/.claude/.skill-invocation-evidence-<token>` (JSON array of bare names, written ONLY by the completion hook on successful Skill returns) OR `branch_ledger_has` OR `phase_attested`. **`.completed` is deliberately NOT an evidence source** — the walker back-fills it on trigger matches (codex #2). `PHASE_IMPL_ALIASES="executing-plans subagent-driven-development agent-team-execution"` — one canonical slot (codex #3). `phase_gate_log <gate> <decision> <skill> <missing>` appends one line to `~/.claude/.phase-gate-events.log`.

- [ ] **Step 1: Append failing tests**

Append to `tests/test-skill-gate.sh` before `print_summary`:

```bash
# --- evidence predicate: invocation-record / ledger / attested / NEVER .completed ---
EVID_LIB="${PROJECT_ROOT}/hooks/lib/phase-evidence.sh"
COMP_FILE="$HOME/.claude/.skill-composition-state-${TOKEN}"
INVOC_FILE="$HOME/.claude/.skill-invocation-evidence-${TOKEN}"
printf '{"chain":["brainstorming","writing-plans","subagent-driven-development","requesting-code-review","verification-before-completion","openspec-ship","finishing-a-development-branch"],"completed":["brainstorming","writing-plans"],"current_index":1}\n' > "$COMP_FILE"
printf '["brainstorming"]\n' > "$INVOC_FILE"

_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' brainstorming ''" || _rc=$?
assert_equals "evidence: invocation-record step -> 0" "0" "$_rc"
# THE CODEX-#2 PIN: writing-plans is in .completed (walker back-fill) but NOT
# in the invocation record -> NOT satisfied. Walker anchoring is not evidence.
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' writing-plans ''" || _rc=$?
assert_equals "evidence: walker-backfilled .completed does NOT satisfy -> 1" "1" "$_rc"
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' product-discovery ''" || _rc=$?
assert_equals "evidence: attested step -> 0" "0" "$_rc"
# forged gating attestation must NOT satisfy (Scenario 3 via shared predicate)
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' requesting-code-review ''" || _rc=$?
assert_equals "evidence: forged gating attest does not satisfy -> 1" "1" "$_rc"
# implementation-slot alias: evidence for SDD satisfies executing-plans (codex #3)
printf '["brainstorming","subagent-driven-development"]\n' > "$INVOC_FILE"
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' executing-plans ''" || _rc=$?
assert_equals "evidence: impl-slot alias satisfies sibling -> 0" "0" "$_rc"
# malformed invocation record: leg degrades, attested leg still works
printf 'NOT JSON' > "$INVOC_FILE"
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' product-discovery ''" || _rc=$?
assert_equals "evidence: malformed record, attested leg still works -> 0" "0" "$_rc"
printf '["brainstorming"]\n' > "$INVOC_FILE"

# --- completion hook: writes invocation record + all-step ledger ---
COMPLETION_HOOK="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"
_CH_REPO="$(mktemp -d /tmp/psg-ch-XXXXXX)"
( cd "$_CH_REPO" && git init -q && git commit -q --allow-empty -m init )
_ch_payload() {  # $1=skill $2=is_error
    printf '{"transcript_path":"","tool_response":{"is_error":%s},"tool_input":{"skill":"%s"},"cwd":"%s"}' "$2" "$1" "$_CH_REPO"
}
rm -f "$INVOC_FILE"
_ch_payload superpowers:writing-plans false | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$COMPLETION_HOOK" >/dev/null 2>&1
assert_contains "completion hook appends bare name to invocation record" "writing-plans" "$(cat "$INVOC_FILE" 2>/dev/null)"
_ch_payload superpowers:openspec-ship true | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$COMPLETION_HOOK" >/dev/null 2>&1
assert_not_contains "errored Skill return NOT recorded" "openspec-ship" "$(cat "$INVOC_FILE" 2>/dev/null)"
rm -rf "$_CH_REPO"
printf '["brainstorming"]\n' > "$INVOC_FILE"
```

- [ ] **Step 2: Run to verify the new asserts fail**

Expected: evidence asserts FAIL (lib missing); Task-1 asserts still pass.

- [ ] **Step 3: Implement the lib**

Create `hooks/lib/phase-evidence.sh`:

```bash
#!/bin/bash
# phase-evidence.sh — the ONE "is this chain step done" predicate, shared by
# skill-gate.sh (C1) and openspec-guard.sh (C2) so the two boundaries cannot
# drift. Evidence = composition .completed (invocation record) OR branch
# ledger OR explicit attestation (gating milestones excluded by the attest
# lib's reader lock). Fail-open: every leg degrades to "not satisfied";
# callers deny only on positive violation evidence they establish themselves.
# Spec: openspec/changes/phase-enforcement.

_PHASE_EVID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${_PHASE_EVID_DIR}/phase-attest.sh" ] && . "${_PHASE_EVID_DIR}/phase-attest.sh" 2>/dev/null || true
[ -f "${_PHASE_EVID_DIR}/branch-ledger.sh" ] && . "${_PHASE_EVID_DIR}/branch-ledger.sh" 2>/dev/null || true

# Implementation-slot aliases: one canonical slot (codex #3).
PHASE_IMPL_ALIASES="executing-plans subagent-driven-development agent-team-execution"

# _phase_alias_candidates <step> — prints <step> plus its slot siblings.
_phase_alias_candidates() {
    local step="${1:-}" a is_impl=0
    printf '%s\n' "$step"
    for a in $PHASE_IMPL_ALIASES; do [ "$a" = "$step" ] && is_impl=1; done
    if [ "$is_impl" -eq 1 ]; then
        for a in $PHASE_IMPL_ALIASES; do [ "$a" != "$step" ] && printf '%s\n' "$a"; done
    fi
}

# phase_step_satisfied <token> <step> <proj_root> -> 0 if any evidence leg
# holds for the step OR an implementation-slot alias of it.
# PROVENANCE (codex #2): the walker-writable .completed is NOT consulted —
# only the completion hook's append-only invocation record, the branch
# ledger, and explicit attestation count.
phase_step_satisfied() {
    local token="${1:-}" step="${2:-}" proot="${3:-}" cand
    [ -z "$step" ] && return 1

    for cand in $(_phase_alias_candidates "$step"); do
        # Leg 1: append-only invocation record (completion-hook writes only)
        if [ -n "$token" ] && command -v jq >/dev/null 2>&1; then
            local rec="${HOME}/.claude/.skill-invocation-evidence-${token}"
            if [ -f "$rec" ] && jq -e --arg s "$cand" 'index($s) != null' "$rec" >/dev/null 2>&1; then
                return 0
            fi
        fi
        # Leg 2: branch ledger (cross-session durable record)
        if command -v branch_ledger_has >/dev/null 2>&1 && branch_ledger_has "$cand" "$proot"; then
            return 0
        fi
        # Leg 3: explicit attestation (reader refuses gating milestones)
        if command -v phase_attested >/dev/null 2>&1 && phase_attested "$token" "$cand"; then
            return 0
        fi
    done
    return 1
}

# phase_gate_log <gate> <decision> <skill> <missing> — telemetry line, fail-open.
phase_gate_log() {
    printf '%s gate=%s decision=%s skill=%s missing=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${1:-?}" "${2:-?}" "${3:-?}" "${4:--}" \
        >> "${HOME}/.claude/.phase-gate-events.log" 2>/dev/null || true
}
```

- [ ] **Step 3b: Extend the completion hook (provenance writer)**

In `hooks/skill-completion-hook.sh`, immediately AFTER the existing `.completed` merge write succeeds (the `mv "${_STATE}.tmp.$$"` line, ~line 67) and BEFORE the review-embedding ledger section, add:

```bash
# --- Append-only invocation record (phase-enforcement provenance split).
# The gates trust THIS file, never the walker-writable .completed: a
# successful Skill return is the only writer path (codex #2).
_INVOC="${HOME}/.claude/.skill-invocation-evidence-${_SESSION_TOKEN}"
_IBASE="[]"
[ -f "${_INVOC}" ] && jq empty "${_INVOC}" >/dev/null 2>&1 && _IBASE="$(cat "${_INVOC}")"
_ITMP="$(printf '%s' "${_IBASE}" | jq --arg s "${_BARE}" 'if index($s) == null then . + [$s] else . end' 2>/dev/null)" || _ITMP=""
if [ -n "${_ITMP}" ]; then
    printf '%s\n' "${_ITMP}" > "${_INVOC}.tmp.$$" 2>/dev/null && \
        mv "${_INVOC}.tmp.$$" "${_INVOC}" 2>/dev/null || rm -f "${_INVOC}.tmp.$$" 2>/dev/null || true
fi
```

And in the ledger section (read it first — it currently records gating milestones + review-embedding credits): additionally record EVERY chain-member return durably (codex #4, re-anchor erasure):

```bash
# Durable per-branch record for ALL chain-step returns (not just gating
# milestones) — re-anchors reset session state but must not erase evidence.
command -v branch_ledger_record >/dev/null 2>&1 && \
    branch_ledger_record "${_BARE}" "" 2>/dev/null || true
```

NOTE: read the existing ledger call's arguments first (`branch_ledger_record <milestone> <proj_root>` — how does the hook derive proj_root today? Reuse its existing derivation verbatim; if it has none for the gating record, mirror that exact call shape). Also note the invocation record write must be OUTSIDE the "is chain member" jq condition? NO — keep it INSIDE the successful-return path but WITHOUT requiring chain membership: move it BEFORE the chain-membership merge if the hook exits early for non-chain skills (read lines 44-55: the hook proceeds for any `_BARE`; the jq merge is a no-op for non-members — the invocation record SHOULD record all successful skill returns, chain member or not, so a later chain re-anchor can still find pre-anchor evidence).

- [ ] **Step 3c: Update the state-prune + canary lists**

`hooks/session-start-hook.sh`: (a) add `-o -name '.skill-invocation-evidence-*'` and `-o -name '.skill-phase-attest-*'` to the stale-state prune find (with matching `! -name "...-${_SESSION_TOKEN}"` exclusions for both — the `*-state-<token>` exclusion does NOT match these names; same trap as the compact-pending marker, PR #118); (b) PAIRED CLAUDE.md rule: new gate-ENFORCEMENT components join `_GATE_ENFORCE_LIBS` — add `phase-evidence.sh` and `phase-attest.sh` (source-probed libs, existing pattern) and `skill-gate.sh` (parse-checked script, the openspec-guard.sh pattern — verify how the list distinguishes libs from scripts before editing). This extends both the push-gate canary and the plugin-drift canary automatically. Add a `tests/test-push-gate-canary.sh`-style assertion only if that suite enumerates the list generically — read it first; if it hardcodes five names, extend its expected set.

- [ ] **Step 4: Run tests to verify they pass**

Run: `/bin/bash -n hooks/lib/phase-evidence.sh && /bin/bash tests/test-skill-gate.sh < /dev/null`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/phase-evidence.sh tests/test-skill-gate.sh
git commit -m "feat: shared phase-evidence predicate (completed OR ledger OR attested)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Skill-sequencing gate (`hooks/skill-gate.sh` + registration)

**Files:**
- Create: `hooks/skill-gate.sh` (executable)
- Modify: `hooks/hooks.json` (PreToolUse array — new `^Skill$` matcher entry)
- Test: `tests/test-skill-gate.sh` (append)

**Interfaces:**
- Consumes: `phase_step_satisfied`, `phase_gate_log` (Task 2); `resolve_session_token_from_transcript` (existing `hooks/lib/session-token.sh`).
- Produces: PreToolUse deny JSON (exact guard shape) on out-of-order chain invocation; silence otherwise. Mode from `~/.claude/skill-config.json` `.phase_enforcement.skill_sequencing` (`deny|warn|off`); default `deny` only when `<proj_root>/.claude-plugin/plugin.json` name is `auto-claude-skills` (dogfood identity, codex #8), else `warn`.

- [ ] **Step 1: Append failing tests**

Append before `print_summary` (uses the COMP_FILE seeded in Task 2's block):

```bash
# --- skill-gate: sequencing matrix (Scenarios 1 and 4) ---
GATE_HOOK="${PROJECT_ROOT}/hooks/skill-gate.sh"
_gate() {  # $1 = skill name to invoke; prints hook stdout
    printf '{"tool_name":"Skill","tool_input":{"skill":"%s"},"transcript_path":""}' "$1" \
        | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${PROJECT_ROOT}" /bin/bash "$GATE_HOOK" 2>/dev/null
}
assert_equals "gate hook is executable" "yes" "$([ -x "$GATE_HOOK" ] && echo yes || echo no)"

# chain: brainstorming[evidence] -> writing-plans -> subagent-driven-development -> ...
# Evidence lives in INVOC_FILE (the append-only record) — NEVER seeded via .completed.
printf '["brainstorming"]\n' > "$INVOC_FILE"
_out="$(_gate superpowers:subagent-driven-development)"
assert_contains "deny: SDD before writing-plans" '"permissionDecision":"deny"' "$_out"
assert_contains "deny names the missing step" "writing-plans" "$_out"
assert_contains "deny offers attestation remedy" "phase_attest" "$_out"

# THE CODEX-#2 PIN (gate-level): walker back-fill in .completed alone must NOT unblock.
jq '.completed = ["brainstorming","writing-plans"]' "$COMP_FILE" > "$COMP_FILE.t" && mv "$COMP_FILE.t" "$COMP_FILE"
_out="$(_gate superpowers:subagent-driven-development)"
assert_contains "deny: walker-backfilled .completed is not invocation evidence" '"permissionDecision":"deny"' "$_out"

# THE CODEX-#3 PIN: sibling implementation skill cannot bypass the slot.
_out="$(_gate auto-claude-skills:agent-team-execution)"
assert_contains "deny: impl-slot sibling also gated (alias mapping)" "writing-plans" "$_out"

_out="$(_gate superpowers:writing-plans)"
assert_equals "allow: invoking the first unfinished step itself" "" "$_out"

_out="$(_gate superpowers:brainstorming)"
assert_equals "allow: re-invoking an evidenced step" "" "$_out"

_out="$(_gate superpowers:systematic-debugging)"
assert_equals "allow: non-chain skill (DEBUG detour)" "" "$_out"

# real evidence satisfies: writing-plans in the invocation record -> SDD allowed
printf '["brainstorming","writing-plans"]\n' > "$INVOC_FILE"
_out="$(_gate superpowers:subagent-driven-development)"
assert_equals "allow: after predecessor invocation evidence exists" "" "$_out"

# attestation satisfies: openspec-ship attested earlier (Task 1) -> finishing allowed
# (requesting-code-review + verification-before-completion must block first though)
_out="$(_gate superpowers:finishing-a-development-branch)"
assert_contains "deny: finishing blocked by unfinished gating milestone" "requesting-code-review" "$_out"
printf '["brainstorming","writing-plans","subagent-driven-development","requesting-code-review","verification-before-completion"]\n' > "$INVOC_FILE"
_out="$(_gate superpowers:finishing-a-development-branch)"
assert_equals "allow: finishing with gating evidenced + openspec-ship attested" "" "$_out"

# Scenario 4: no chain / malformed state / gate error -> allow, exit 0
rm -f "$COMP_FILE"
_out="$(_gate superpowers:finishing-a-development-branch)"
assert_equals "allow: no composition state" "" "$_out"
printf 'NOT JSON' > "$COMP_FILE"
_out="$(_gate superpowers:finishing-a-development-branch)"
assert_equals "allow: malformed composition state" "" "$_out"
_rc=0; printf 'NOT EVEN JSON PAYLOAD' | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$GATE_HOOK" >/dev/null 2>&1 || _rc=$?
assert_equals "fail-open: malformed hook payload exits 0" "0" "$_rc"

# warn mode: config flips deny to systemMessage-only
printf '{"chain":["brainstorming","writing-plans","subagent-driven-development"],"completed":[],"current_index":0}\n' > "$COMP_FILE"
printf '{"phase_enforcement":{"skill_sequencing":"warn"}}\n' > "$HOME/.claude/skill-config.json"
_out="$(_gate superpowers:subagent-driven-development)"
assert_not_contains "warn mode: no permissionDecision" "permissionDecision" "$_out"
assert_contains "warn mode: still surfaces the gap" "writing-plans" "$_out"
rm -f "$HOME/.claude/skill-config.json"
# events log got deny + allow lines
assert_contains "telemetry log written" "gate=skill-seq" "$(cat "$HOME/.claude/.phase-gate-events.log" 2>/dev/null)"
```

- [ ] **Step 2: Run to verify the new asserts fail**

Expected: gate asserts FAIL (hook missing); Tasks 1-2 asserts still pass.

- [ ] **Step 3: Implement the gate**

Create `hooks/skill-gate.sh` (chmod +x):

```bash
#!/bin/bash
# skill-gate.sh — PreToolUse ^Skill$ sequencing gate (phase-enforcement C1).
# Denies invoking a composition-chain member while a required predecessor
# lacks evidence (invocation record OR branch ledger OR attestation —
# NEVER the walker-writable .completed, codex #2). Deny only on
# positive violation evidence; ANY infrastructure failure allows (exit 0,
# no output) — the deliberate inversion of the push gate's fail-closed
# posture (design.md Trade-offs). Human ! commands never reach this hook.
# Spec: openspec/changes/phase-enforcement (Scenarios 1, 2, 4).

trap 'exit 0' ERR

INPUT=""
if [ ! -t 0 ]; then INPUT="$(cat 2>/dev/null)" || INPUT=""; fi
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

_F="$(printf '%s' "$INPUT" | jq -r '[(.tool_input.skill // .tool_input.name // ""), (.transcript_path // "")] | join("\u001f")' 2>/dev/null)" || _F=""
_RAW_SKILL="${_F%%$'\x1f'*}"
_TRANSCRIPT="${_F#*$'\x1f'}"
[ -z "$_RAW_SKILL" ] && exit 0
_SKILL="${_RAW_SKILL##*:}"

# Token: payload-first (issue #51), singleton fallback.
_SESSION_TOKEN=""
if [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_session_token_from_transcript >/dev/null 2>&1 && \
        _SESSION_TOKEN="$(resolve_session_token_from_transcript "${_TRANSCRIPT}")"
fi
[ -z "$_SESSION_TOKEN" ] && [ -f "${HOME}/.claude/.skill-session-token" ] && \
    _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
[ -z "$_SESSION_TOKEN" ] && exit 0

_COMP="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
[ -f "$_COMP" ] || exit 0
jq empty "$_COMP" >/dev/null 2>&1 || exit 0

# Invoked skill's chain index. Implementation-slot aliasing (codex #3): if
# the bare name is not a literal member but IS an implementation-slot skill
# and the chain contains a sibling, use the sibling's index — invoking
# agent-team-execution when the chain rendered executing-plans must not
# bypass sequencing. Requires phase-evidence.sh (sourced below) for
# _phase_alias_candidates; source it BEFORE membership resolution.
[ -f "${PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" ] || exit 0
# shellcheck source=lib/phase-evidence.sh
. "${PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" 2>/dev/null || true
command -v phase_step_satisfied >/dev/null 2>&1 || exit 0

_IDX=-1
for _cand in $(_phase_alias_candidates "$_SKILL"); do
    _CI="$(jq -r --arg s "$_cand" '(.chain // []) | index($s) // -1' "$_COMP" 2>/dev/null)" || exit 0
    [[ "$_CI" =~ ^[0-9]+$ ]] && [ "$_CI" -ge 0 ] && { _IDX="$_CI"; break; }
done
[[ "$_IDX" =~ ^-?[0-9]+$ ]] || exit 0
[ "$_IDX" -le 0 ] && exit 0

_PROJ_ROOT="${SKILL_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# First unsatisfied strict predecessor -> violation.
_MISSING=""
_j=0
while [ "$_j" -lt "$_IDX" ]; do
    _STEP="$(jq -r --argjson i "$_j" '(.chain // [])[$i] // empty' "$_COMP" 2>/dev/null)" || exit 0
    [ -z "$_STEP" ] && break
    if ! phase_step_satisfied "$_SESSION_TOKEN" "$_STEP" "$_PROJ_ROOT"; then
        _MISSING="$_STEP"
        break
    fi
    _j=$(( _j + 1 ))
done
if [ -z "$_MISSING" ]; then
    phase_gate_log "skill-seq" "allow" "$_SKILL" "-"
    exit 0
fi

# Mode: deny | warn | off. Default: deny ONLY in the plugin's own source repo
# (identity via plugin manifest name, codex #8 — a generic
# config/default-triggers.json path would false-deny unrelated external
# repos that happen to ship that file); warn everywhere else.
_MODE=""
[ -f "${HOME}/.claude/skill-config.json" ] && \
    _MODE="$(jq -r '.phase_enforcement.skill_sequencing // empty' "${HOME}/.claude/skill-config.json" 2>/dev/null)" || _MODE=""
if [ -z "$_MODE" ]; then
    _REPO_ID="$(jq -r '.name // empty' "${_PROJ_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)" || _REPO_ID=""
    if [ "$_REPO_ID" = "auto-claude-skills" ]; then _MODE="deny"; else _MODE="warn"; fi
fi
[ "$_MODE" = "off" ] && exit 0

_MSG="PHASE GATE — Step '${_MISSING}' has no invocation evidence, but Skill(${_RAW_SKILL}) comes after it in the composition chain. Do now (one of): (1) invoke the missing step: Skill(${_MISSING}); (2) record an explicit, review-surfaced skip: source \"\$CLAUDE_PLUGIN_ROOT/hooks/lib/phase-attest.sh\" && phase_attest ${_MISSING} \"<reason>\"; (3) human bypass: run the action yourself with the ! prefix. Gating milestones (requesting-code-review, verification-before-completion) accept only real invocations."
if [ "$_MODE" = "warn" ]; then
    phase_gate_log "skill-seq" "warn" "$_SKILL" "$_MISSING"
    jq -n --arg msg "PHASE GATE (advisory): $_MSG" '{"systemMessage":$msg}'
    exit 0
fi
phase_gate_log "skill-seq" "deny" "$_SKILL" "$_MISSING"
jq -n --arg msg "$_MSG" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
exit 0
```

- [ ] **Step 4: Register in hooks.json**

Append to the `PreToolUse` array in `hooks/hooks.json` (targeted edit, after the Bash/openspec-guard entry):

```json
      {
        "matcher": "^Skill$",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/skill-gate.sh",
            "timeout": 5
          }
        ]
      }
```

- [ ] **Step 5: Run tests, checks, commit**

```bash
chmod +x hooks/skill-gate.sh
/bin/bash -n hooks/skill-gate.sh && jq empty hooks/hooks.json
LC_ALL=C grep -c $'\x1f' hooks/skill-gate.sh   # expect 0
/bin/bash tests/test-skill-gate.sh < /dev/null
git add hooks/skill-gate.sh hooks/hooks.json tests/test-skill-gate.sh
git commit -m "feat: PreToolUse Skill-sequencing gate — deny out-of-order chain invocations

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Outbound DESIGN/PLAN leg in openspec-guard (C2, warn-until-backtest)

**Files:**
- Modify: `hooks/openspec-guard.sh` (immediately after the global fail-closed REVIEW/VERIFY block, ~line 268)
- Test: `tests/test-skill-gate.sh` (append) + verify no regression in `tests/test-push-gate-failclosed.sh`

**Interfaces:**
- Consumes: `phase_step_satisfied` (Task 2); existing guard locals `_PUSHGATE_SKIP`, `_LEDGER_OK`, `_COMP_STATE`, `_proot`, `_GATE_ACTION`, `_SESSION_TOKEN` (verify exact local names at the insertion point while implementing — the guard resolves its own token earlier; reuse ITS variable, do not re-resolve).
- Produces: on chain-covered pushes (composition chain non-empty for this session OR branch ledger has any chain record), missing `brainstorming`/`writing-plans` evidence → systemMessage WARN by default; DENY only when `~/.claude/skill-config.json` `.phase_enforcement.outbound == "deny"` (flipped by Task 5's backtest, never hardcoded).

- [ ] **Step 1: Append failing tests**

Append before `print_summary`:

```bash
# --- C2: outbound DESIGN/PLAN leg (warn default = telemetry-only; deny only via config) ---
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
_push() {  # runs guard against a git push command payload
    printf '{"tool_name":"Bash","tool_input":{"command":"git push"},"transcript_path":""}' \
        | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$GUARD" 2>/dev/null
}
# Seed: chain active, REVIEW+VERIFY satisfied, DESIGN+PLAN missing.
# (Run inside a throwaway git repo so branch-ledger keys don't touch the real repo.)
_C2_REPO="$(mktemp -d /tmp/psg-repo-XXXXXX)"
( cd "$_C2_REPO" && git init -q && git commit -q --allow-empty -m init )
printf '{"chain":["brainstorming","writing-plans","requesting-code-review","verification-before-completion"],"completed":["requesting-code-review","verification-before-completion"],"current_index":0}\n' > "$COMP_FILE"
: > "$HOME/.claude/.phase-gate-events.log"
_out="$(cd "$_C2_REPO" && _push)"
assert_not_contains "C2 default: no deny for missing DESIGN/PLAN" '"permissionDecision":"deny"' "$_out"
assert_not_contains "C2 default: warn emits NO stdout JSON (one-object contract)" "brainstorming" "$_out"
assert_contains "C2 default: warn logged to events" "gate=outbound decision=warn" "$(cat "$HOME/.claude/.phase-gate-events.log" 2>/dev/null)"
printf '{"phase_enforcement":{"outbound":"deny"}}\n' > "$HOME/.claude/skill-config.json"
_out="$(cd "$_C2_REPO" && _push)"
assert_contains "C2 deny mode: denies without DESIGN evidence" '"permissionDecision":"deny"' "$_out"
# REAL evidence flips it (invocation record, NOT .completed — codex #2)
printf '["brainstorming","writing-plans","requesting-code-review","verification-before-completion"]\n' > "$INVOC_FILE"
_out="$(cd "$_C2_REPO" && _push)"
assert_not_contains "C2 deny mode: allows with DESIGN+PLAN invocation evidence" "brainstorming" "$_out"
rm -f "$HOME/.claude/skill-config.json"

# codex #6: ledger-covered branch with NO comp state still gets the C2 check
rm -f "$COMP_FILE" "$INVOC_FILE"
( cd "$_C2_REPO" && . "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh" \
    && branch_ledger_record "writing-plans" "$_C2_REPO" \
    && branch_ledger_record "requesting-code-review" "$_C2_REPO" \
    && branch_ledger_record "verification-before-completion" "$_C2_REPO" ) 2>/dev/null
: > "$HOME/.claude/.phase-gate-events.log"
_out="$(cd "$_C2_REPO" && _push)"
assert_contains "C2 ledger-covered: warn logged for missing brainstorming (no comp state)" \
    "missing=brainstorming" "$(cat "$HOME/.claude/.phase-gate-events.log" 2>/dev/null)"

# codex #1: combined C2-warn + routing-governance-deny emits EXACTLY ONE JSON object.
# Run in THIS repo (routing repo) with a chain-covered session, warn-mode C2 gap,
# and no clean verdict: stdout must be a single deny object, parseable as one.
printf '{"chain":["brainstorming","writing-plans","requesting-code-review","verification-before-completion"],"completed":[],"current_index":0}\n' > "$COMP_FILE"
printf '["requesting-code-review","verification-before-completion"]\n' > "$INVOC_FILE"
rm -f "$HOME/.claude/.skill-project-verified-${TOKEN}"
_out="$(printf '{"tool_name":"Bash","tool_input":{"command":"git push"},"transcript_path":""}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$GUARD" 2>/dev/null)"
_objs="$(printf '%s' "$_out" | jq -s 'length' 2>/dev/null)"
assert_equals "combined warn+deny path: exactly one JSON object on stdout" "1" "$_objs"
assert_contains "combined path: the one object is the hard deny" '"permissionDecision":"deny"' "$_out"
rm -f "$COMP_FILE" "$INVOC_FILE"; rm -rf "$_C2_REPO"
```

NOTE for implementer: seeding REVIEW/VERIFY in `.completed` must get the push past the global gate; if the run still trips earlier gates (e.g. routing-governance needs a clean verdict in a routing repo), the throwaway repo has no `config/default-triggers.json`, so routing-governance does not fire there — that is why the test cds into `_C2_REPO`.

- [ ] **Step 2: Run to verify the new asserts fail**

Expected: "warn names the missing step" and "deny mode" asserts FAIL (guard has no C2 leg).

- [ ] **Step 3: Implement the guard extension**

Insert AFTER the global fail-closed block's closing `fi` in `hooks/openspec-guard.sh` (read the surrounding code first; reuse its already-resolved locals):

```bash
        # --- Phase-enforcement C2: DESIGN/PLAN evidence on chain-covered pushes ---
        # (openspec/changes/phase-enforcement). WARN by default; DENY only when
        # ~/.claude/skill-config.json .phase_enforcement.outbound == "deny" —
        # that flip is gated on the replay backtest (<10% false-block), never
        # hardcoded. Evidence = the same shared predicate as skill-gate.sh.
        # Scoped to chain-covered work: an ACTIVE chain that includes
        # brainstorming, OR durable branch-ledger records of DESIGN/PLAN steps
        # (covers comp-state resets between sessions — codex #6). Ad-hoc
        # pushes stay ungated (false-block discipline).
        _pe_covered=false
        if [ -f "${_COMP_STATE}" ] && jq -e '.chain | index("brainstorming")' "${_COMP_STATE}" >/dev/null 2>&1; then
            _pe_covered=true
        elif [ "${_LEDGER_OK}" = "true" ]; then
            { branch_ledger_has "brainstorming" "${_proot}" || branch_ledger_has "writing-plans" "${_proot}"; } && _pe_covered=true
        fi
        if [ "${_PUSHGATE_SKIP}" != "true" ] && command -v jq >/dev/null 2>&1 \
           && [ "${_pe_covered}" = "true" ]; then
            if [ -f "${_PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" ]; then
                # shellcheck source=lib/phase-evidence.sh
                . "${_PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" 2>/dev/null || true
            fi
            if command -v phase_step_satisfied >/dev/null 2>&1; then
                _pe_missing=""
                for _pe_step in brainstorming writing-plans; do
                    if ! phase_step_satisfied "${_SESSION_TOKEN}" "${_pe_step}" "${_proot}"; then
                        _pe_missing="${_pe_step}"
                        break
                    fi
                done
                if [ -n "${_pe_missing}" ]; then
                    _pe_mode="$(jq -r '.phase_enforcement.outbound // "warn"' "${HOME}/.claude/skill-config.json" 2>/dev/null)" || _pe_mode="warn"
                    _PE_MSG="PHASE GATE (outbound): this chain-covered ${_GATE_ACTION} has no evidence for '${_pe_missing}'. Invoke Skill(${_pe_missing}) or record an explicit skip (phase_attest ${_pe_missing} \"<reason>\") before shipping."
                    command -v phase_gate_log >/dev/null 2>&1 && phase_gate_log "outbound" "${_pe_mode}" "${_GATE_ACTION}" "${_pe_missing}"
                    if [ "${_pe_mode}" = "deny" ]; then
                        jq -n --arg msg "${_PE_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                        exit 0
                    fi
                    # warn mode: TELEMETRY ONLY (events log + SKILL_EXPLAIN stderr).
                    # The guard emits at most ONE JSON object per run — every existing
                    # systemMessage is paired with a deny + exit 0 (verified: no
                    # warn-and-continue precedent exists). A mid-guard JSON warn that
                    # falls through would put two objects on stdout when a later
                    # check denies. Same constraint as the "Soft staleness is NOT
                    # emitted here" comment at ~line 221.
                    [ -n "${SKILL_EXPLAIN:-}" ] && printf '[openspec-guard] %s\n' "${_PE_MSG}" >&2
                fi
            fi
        fi
```

CAUTION: verify the actual local variable names at the insertion point (`_PLUGIN_ROOT` vs `PLUGIN_ROOT`, `_SESSION_TOKEN`, `_proot`, `_COMP_STATE`, `_GATE_ACTION`) by reading the guard around lines 160-300 — use the guard's own spellings verbatim. A warn that emits `{"systemMessage":...}` mid-guard must not corrupt a later deny JSON: confirm the guard emits at most one JSON object per run (if a warn already occurred, later denies still work because each emission is followed by exit 0 EXCEPT the warn — check how existing soft warnings handle this; the guard's existing "Soft staleness is NOT emitted here" comment at ~line 221 documents the constraint. If only ONE JSON object is safe, buffer the warn and emit it merged with the final decision or drop it and rely on the events log).

- [ ] **Step 4: Run tests + push-gate regressions**

```bash
/bin/bash -n hooks/openspec-guard.sh
/bin/bash tests/test-skill-gate.sh < /dev/null
/bin/bash tests/test-push-gate-failclosed.sh < /dev/null
/bin/bash tests/test-push-gate-detection.sh < /dev/null
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/openspec-guard.sh tests/test-skill-gate.sh
git commit -m "feat: outbound DESIGN/PLAN evidence leg (warn-until-backtest) in push gate

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Backtest instrument + run + threshold decision

**Files:**
- Create: `scripts/phase-gate-backtest.sh`
- Create: `docs/plans/2026-07-16-phase-gate-backtest-results.md` (findings; local)

**Interfaces:**
- Consumes: local transcripts `~/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/*.jsonl` (main sessions only — exclude `*/subagents/*` and directories).
- Produces: per-predicate table (would-have-denied events with session, ts, skill, missing step, ±context) for human true-catch/false-block classification. Exit 0 always; this is an offline instrument, not a hook.

- [ ] **Step 1: Implement the instrument** (no TDD red cycle — offline analysis script; correctness pinned by a fixture test below)

Create `scripts/phase-gate-backtest.sh`:

```bash
#!/bin/bash
# phase-gate-backtest.sh — replay Skill-invocation sequences from local
# Claude Code transcripts and report where the phase gates WOULD have fired.
# Usage: phase-gate-backtest.sh [transcripts-dir]
# Output: one line per would-have-denied event + a summary; classification
# of true-catch vs false-block is a HUMAN step (small n expected).
# Pre-registered thresholds (discovery brief 2026-07-16): deny ships <10% FB;
# 10-20% narrowed; >20% advisory-only. Not a hook: plain exit codes, no JSON.
set -u

DIR="${1:-$HOME/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills}"
CHAIN="brainstorming writing-plans executing-plans subagent-driven-development requesting-code-review verification-before-completion openspec-ship finishing-a-development-branch"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
[ -d "$DIR" ] || { echo "no transcript dir: $DIR" >&2; exit 1; }

_idx() {  # chain index of bare skill name, -1 if absent; SDD and executing-plans share slot 2
    local s="$1" i=0 c
    case "$s" in executing-plans|subagent-driven-development|agent-team-execution) echo 2; return;; esac
    for c in brainstorming writing-plans _impl requesting-code-review verification-before-completion openspec-ship finishing-a-development-branch; do
        [ "$c" = "$s" ] && { echo "$i"; return; }
        i=$(( i + 1 ))
    done
    echo -1
}

TOTAL_SESSIONS=0; TOTAL_INVOCATIONS=0; DENIES=0
for f in "$DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    TOTAL_SESSIONS=$(( TOTAL_SESSIONS + 1 ))
    # Ordered bare skill names invoked via the Skill tool in this session.
    _SEQ="$(jq -r 'select(.type=="assistant")
        | .message.content[]? | select(.type=="tool_use" and .name=="Skill")
        | (.input.skill // .input.name // "") | split(":") | last' "$f" 2>/dev/null)"
    [ -z "$_SEQ" ] && continue
    _SEEN=" "   # bare names with evidence so far (invocation = evidence in replay)
    while IFS= read -r s; do
        [ -z "$s" ] && continue
        TOTAL_INVOCATIONS=$(( TOTAL_INVOCATIONS + 1 ))
        i="$(_idx "$s")"
        if [ "$i" -gt 0 ]; then
            j=0
            for c in brainstorming writing-plans _impl requesting-code-review verification-before-completion openspec-ship finishing-a-development-branch; do
                [ "$j" -ge "$i" ] && break
                if [ "$c" != "_impl" ]; then
                    case "$_SEEN" in *" $c "*) : ;; *)
                        DENIES=$(( DENIES + 1 ))
                        printf 'DENY session=%s skill=%s missing=%s\n' "$(basename "$f" .jsonl)" "$s" "$c"
                        ;;
                    esac
                else
                    case "$_SEEN" in *" executing-plans "*|*" subagent-driven-development "*|*" agent-team-execution "*) : ;; *)
                        [ "$i" -gt 2 ] && { DENIES=$(( DENIES + 1 )); printf 'DENY session=%s skill=%s missing=implementation-step\n' "$(basename "$f" .jsonl)" "$s"; }
                        ;;
                    esac
                fi
                j=$(( j + 1 ))
            done
        fi
        _SEEN="${_SEEN}${s} "
    done <<EOF_SEQ
$_SEQ
EOF_SEQ
done
printf -- '---\nsessions=%s skill_invocations=%s would_have_denied=%s\n' "$TOTAL_SESSIONS" "$TOTAL_INVOCATIONS" "$DENIES"
printf 'Classify each DENY above as true-catch or false-block. Thresholds: <10%%FB deny | 10-20%% narrow | >20%% advisory.\n'
```

Known simplifications to DOCUMENT in the results file AND in the script's header + summary line (label: "ADVISORY-ONLY — replay error is BIDIRECTIONAL", codex #7): (a) replay treats any prior in-session tool_use as evidence, but the live hook ignores ERRORED Skill returns — replay can UNDERCOUNT live denies; (b) branch-ledger/attestation state at the time is invisible — replay can OVERCOUNT; (c) the hardcoded canonical chain omits conditional members (product-discovery). Every DENY line is human-classified before any rate is computed, which bounds all three. One DENY line per (invocation, missing-step) pair — count unique invocation events when computing rates.

- [ ] **Step 2: Fixture-pin the instrument**

Append to `tests/test-skill-gate.sh` before `print_summary`:

```bash
# --- backtest instrument: fixture replay ---
BT="${PROJECT_ROOT}/scripts/phase-gate-backtest.sh"
_BT_DIR="$(mktemp -d /tmp/psg-bt-XXXXXX)"
printf '%s\n' \
 '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers:brainstorming"}}]}}' \
 '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers:subagent-driven-development"}}]}}' \
 > "${_BT_DIR}/fixture-skip.jsonl"
_out="$(/bin/bash "$BT" "$_BT_DIR" 2>/dev/null)"
assert_contains "backtest flags the skipped writing-plans" "missing=writing-plans" "$_out"
assert_contains "backtest summary counts the deny" "would_have_denied=1" "$_out"
printf '%s\n' \
 '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers:brainstorming"}}]}}' \
 '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers:writing-plans"}}]}}' \
 '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers:subagent-driven-development"}}]}}' \
 > "${_BT_DIR}/fixture-clean.jsonl"
: > "${_BT_DIR}/fixture-skip.jsonl.bak" 2>/dev/null || true
rm -f "${_BT_DIR}/fixture-skip.jsonl"
_out="$(/bin/bash "$BT" "$_BT_DIR" 2>/dev/null)"
assert_contains "backtest clean sequence: zero denies" "would_have_denied=0" "$_out"
rm -rf "$_BT_DIR"
```

- [ ] **Step 3: Run against real transcripts, classify, decide**

```bash
bash scripts/phase-gate-backtest.sh | tee /tmp/psg-backtest-raw.txt
```
Write `docs/plans/2026-07-16-phase-gate-backtest-results.md`: raw counts, per-DENY human classification (true-catch / false-block / ambiguous with one-line justification each), computed FB rate on unique invocation events, and the resulting mode decision per pre-registered thresholds: skill-sequencing deny stands or demotes; outbound `deny` flip happens (edit `~/.claude/skill-config.json` locally) or stays warn. THE CONTROLLER (not the subagent) makes the classification call and records it.

- [ ] **Step 4: Commit**

```bash
chmod +x scripts/phase-gate-backtest.sh
git add scripts/phase-gate-backtest.sh tests/test-skill-gate.sh
git commit -m "feat: phase-gate replay backtest instrument + fixture pins

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Step-text promotion (trifecta into DESIGN step) + attestation surfacing + uptake eval pack

**Files:**
- Modify: `config/default-triggers.json` (brainstorming skill entry `precondition`)
- Modify: `config/fallback-registry.json` (SAME text — the two change together)
- Modify: `hooks/skill-activation-hook.sh` (attestation surfacing under the composition block — codex #5)
- Create: `evals/phase-enforcement-uptake.json` (follow the existing pack format in `evals/` — top-level ARRAY, judge kind pinned; read an existing pack first)
- Test: `tests/test-skill-gate.sh` (append content assertions)

**Attestation surfacing (codex #5):** in `hooks/skill-activation-hook.sh`, where the composition block is appended to `SKILL_LINES` (after the chain render — locate the section that emits the `Composition:` lines), add a fail-open block: if `~/.claude/.skill-phase-attest-${_SESSION_TOKEN}` exists and parses, append one line per entry:

```bash
# Surface active skip-attestations on EVERY prompt (phase-enforcement,
# codex #5): a skipped step must stay visible to the human and the REVIEW
# lens, not live only in logs. Fail-open; single jq fork; bounded to 6.
_ATTEST_F="${HOME}/.claude/.skill-phase-attest-${_SESSION_TOKEN}"
if [[ -f "$_ATTEST_F" ]] && command -v jq >/dev/null 2>&1; then
  _ATTEST_LINES="$(jq -r '[to_entries[] | "  ATTESTED SKIP: \(.key) — \(.value.reason // "?") (\(.value.ts // "?"))"] | .[0:6] | join("\n")' "$_ATTEST_F" 2>/dev/null)" || _ATTEST_LINES=""
  [[ -n "$_ATTEST_LINES" ]] && SKILL_LINES="${SKILL_LINES}
${_ATTEST_LINES}"
fi
```

Test (append to tests/test-skill-gate.sh — run the REAL activation hook with a seeded attest file and a feature prompt, pattern from tests/test-context.sh:1159):

```bash
# --- attestation surfacing: activation hook renders ATTESTED SKIP lines ---
printf '{"product-discovery":{"reason":"bugfix - covered","ts":"2026-07-16"}}\n' > "$ATTEST_FILE"
_hook_out="$(jq -n --arg p "implement the next feature for the app" '{"prompt":$p}' \
    | HOME="$HOME" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" 2>/dev/null)"
assert_contains "activation hook surfaces attested skips" "ATTESTED SKIP: product-discovery" "$_hook_out"
```

**Interfaces:**
- Consumes: existing `phase_compositions.DESIGN` structure (driver `brainstorming`).
- Produces: DESIGN CURRENT-step text carries the trifecta conditional verbatim; eval pack measures uptake (H2: baseline 0/5 → target ≥4/5) — EXECUTION of the eval is API-key-gated; author red-first, run if key available, else record "authored, key-blocked" in the results doc (same status as audit F6).

- [ ] **Step 1: Append failing content assertions**

```bash
# --- step-text promotion: trifecta directive in brainstorming's precondition in BOTH configs ---
for _cfg in config/default-triggers.json config/fallback-registry.json; do
    _txt="$(jq -r '.skills[] | select(.name == "brainstorming") | .precondition // empty' "${PROJECT_ROOT}/${_cfg}" 2>/dev/null)"
    assert_contains "trifecta directive in brainstorming precondition (${_cfg})" "agent-safety-review" "$_txt"
    assert_contains "discovery precondition preserved (${_cfg})" "product-discovery" "$_txt"
done
```

- [ ] **Step 2: Run to verify the new asserts fail** (fallback-registry likely lacks it; check both)

- [ ] **Step 3: Edit both configs**

The `precondition` field lives on SKILL REGISTRY entries, not on `phase_compositions` (verified: `hooks/skill-activation-hook.sh:907` reads `.skills[] | select(.name == $n) | .precondition`; the `brainstorming` entry already carries the discovery precondition at `config/default-triggers.json:48` / `config/fallback-registry.json:51`). APPEND to the existing `brainstorming` entry's `precondition` string in BOTH files, separated by a space (do not replace the discovery text):

```
"precondition": "TRIFECTA: classify private_data / untrusted_input / outbound_action from the candidate design's data flow. If >=2 are Present (or Unknowns could reach 2), invoke Skill(auto-claude-skills:agent-safety-review) before leaving DESIGN, or record the skip: phase_attest agent-safety-review \"<why the trifecta is <2>\"."
```

Mirror the identical text into `config/fallback-registry.json`'s DESIGN entry. If the DESIGN step already has a `precondition` (discovery-brief one from PR #104), APPEND with a ` | ` separator — do not replace it.

- [ ] **Step 4: Author the eval pack** (read `evals/*.json` for the exact schema first; top-level array; judge pinned; subjects = DESIGN-phase prompts with trifecta-shaped features; assertion = agent-safety-review invoked or attested)

- [ ] **Step 5: Run tests + commit**

```bash
/bin/bash tests/test-skill-gate.sh < /dev/null
bash tests/run-tests.sh < /dev/null
git add config/default-triggers.json config/fallback-registry.json evals/ tests/test-skill-gate.sh
git commit -m "feat: promote trifecta conditional into DESIGN step text + uptake eval pack

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Full-suite verification + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Added`)

- [ ] **Step 1:** `bash tests/run-tests.sh < /dev/null` — expect all files pass, zero regressions (94 existing + test-skill-gate.sh).
- [ ] **Step 2:** Live smoke: in a scratch HOME, seed a chain missing writing-plans, pipe a Skill payload for SDD through `hooks/skill-gate.sh`, confirm deny; then `phase_attest writing-plans "smoke"`, confirm allow.
- [ ] **Step 3:** CHANGELOG entry under `### Added`:

```markdown
- **phase-enforcement**: deterministic non-skippable SDLC transitions — PreToolUse `^Skill$` sequencing gate (deny out-of-order chain invocations; remedy names the missing step), explicit logged skip-attestation (`phase_attest`, gating milestones excluded by two independent locks), outbound DESIGN/PLAN evidence leg (warn-until-backtest, config-gated deny), replay backtest instrument with pre-registered thresholds, trifecta conditional promoted into DESIGN step text. Spec: `openspec/changes/phase-enforcement/`. Capability: `pdlc-safety`.
```

- [ ] **Step 4:** Commit `docs: changelog for phase-enforcement` (+trailer).

---

## Self-Review

- **Spec coverage:** Scenario 1 → Task 3 tests (deny + remedy + post-evidence allow); Scenario 2 → Tasks 1+3+6 (attest satisfies; surfaced on every prompt via the activation hook + events log); Scenario 3 → Task 1 (writer+reader locks, forged-entry test) + Task 2 (shared predicate) + Task 4 regression runs of the push-gate suites; Scenario 4 → Task 3 (no-chain/malformed/error paths); provenance rule (walker `.completed` never satisfies) → Task 2 + Task 3 pins; impl-slot aliasing → Task 2 + Task 3 pins. Backtest-gated C2 → Tasks 4+5. Step-text promotion + H2 → Task 6. Telemetry → Tasks 1-4. Config modes → Tasks 3-4.
- **Placeholder scan:** clean; remaining bounded verify-at-implementation notes (completion hook's existing ledger call shape; canary-list lib/script distinction; canary-test enumeration style) each state the exact resolution procedure.
- **Type consistency:** `phase_step_satisfied <token> <step> <proj_root>`, `phase_attested <token> <step>`, `phase_attest <step> <reason>`, `phase_gate_log <gate> <decision> <skill> <missing>`, `_phase_alias_candidates <step>`, `PHASE_IMPL_ALIASES`, invocation record `~/.claude/.skill-invocation-evidence-<token>` (JSON array of bare names) used identically across Tasks 2-6.

## Codex Sparring Adjudication (2026-07-16)

9 findings; verdict "needs revisions" — all resolved in this plan revision + committed spec amendment (20bae5d):
1. C2 double-JSON (Critical) — pre-fixed independently (warn = telemetry-only); combined warn+routing-deny regression added (Task 4). 2. Walker `.completed` trusted (Critical) — ACCEPTED: provenance split, invocation record + all-step ledger (Task 2), pins in Tasks 2/3. 3. Impl-slot alias bypass (Critical) — ACCEPTED: alias group in evidence + gate (Tasks 2/3), pins added. 4. Re-anchor erasure (Important) — ACCEPTED, folded into all-step ledger recording (Task 2). 5. Attestation surfacing (Important) — ACCEPTED: every-prompt render in activation hook (Task 6); "reason must name evidence" REJECTED (YAGNI; visibility is the friction, reason quality is human review). 6. C2 scope (Important) — ACCEPTED: ledger-covered predicate + no-comp-state test (Task 4). 7. Backtest bidirectional error (Important) — PARTIAL: advisory-only labeling + documented both-direction error (Task 5); full state replay REJECTED (disproportionate for a one-shot, human-classified calibration instrument). 8. Dogfood heuristic (Minor) — ACCEPTED: plugin-manifest identity check (Task 3). 9. Raw 0x1F (Minor) — repaired via perl, verified 0 remaining.
