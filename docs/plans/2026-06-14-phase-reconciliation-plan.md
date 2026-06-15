# Phase-Reconciliation Advisory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an advisory-only `PHASE REALITY:` block to the activation hook that, when the routed phase is SHIP, nudges (never blocks) if the repo shows no committed work (Rule B) or the composition chain skipped REVIEW (Rule A).

**Architecture:** ~28 lines appended to `hooks/skill-activation-hook.sh` right after the `[design-guard]` block (after line 1561), gated to `PRIMARY_PHASE == SHIP`. Mirrors the design-guard idiom: read cheap local state (git + composition `.completed`), append `[i]` advisory lines to `SKILL_LINES`, emit a `SKILL_EXPLAIN` breadcrumb, stay silent on the happy path. Fail-open on every sub-check. No hard-block, no `gh`/network, no new state file, no config changes.

**Tech Stack:** Bash 3.2 (`/bin/bash`), git (local only), jq, the `tests/test-routing.sh` harness (`run_hook`/`extract_context`/`assert_contains`/`assert_not_contains`, `setup_test_env`/`install_registry`/`teardown_test_env`).

**Design source:** `openspec/changes/phase-reconciliation/{proposal,design}.md` + `specs/skill-routing/spec.md`. Read those first.

**Verified facts (confirmed against source — do not re-derive):**
- Insertion point: immediately after `hooks/skill-activation-hook.sh:1561` (`SKILL_LINES="${SKILL_LINES}${DESIGN_COMPLETENESS}"`), before the next block.
- `PRIMARY_PHASE` is set by line 640; `_PROJECT_ROOT` resolved at line 107 (`${SKILL_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}`); `_SESSION_TOKEN` available.
- jq membership idiom matches `hooks/openspec-guard.sh:60-62`.
- The hook has NO `set -e` (a non-matching `[[ ]]` returning 1 is harmless).
- SHIP-routing test prompt: `"let's ship this and merge the branch to main"` (from `test_ship_prompt_matches`).
- `run_hook()` (test-routing.sh:19-24) does NOT pass `SKILL_PROJECT_ROOT` — Rule B tests need a new `run_hook_in_repo` helper. There is NO existing git-fixture test to copy; build one.

---

## File Structure

- `hooks/skill-activation-hook.sh` — MODIFY: one new `PHASE REALITY` block after line 1561. Owns the entire feature.
- `tests/test-routing.sh` — MODIFY: add `run_hook_in_repo` + `_make_phase_git_repo` helpers and 5 sibling tests near the design-guard tests (~line 5580+).
- `CHANGELOG.md` — MODIFY: `[Unreleased]` accumulator entry.

No other files. `config/*` untouched (routing-orthogonal).

---

## Task 1: Rule B — no-work-under-SHIP git advisory

**Files:**
- Modify: `hooks/skill-activation-hook.sh` (after line 1561)
- Modify: `tests/test-routing.sh` (helpers + 3 tests)

- [ ] **Step 1: Add test helpers + the failing tests**

In `tests/test-routing.sh`, after the existing helper block (near `run_hook` ~line 24, or just before the design-guard tests ~line 5365), add these two helpers:

```bash
# Run the activation hook with SKILL_PROJECT_ROOT pinned to a fixture repo,
# so the hook's line-107 _PROJECT_ROOT resolution targets it.
run_hook_in_repo() {
    local prompt="$1" repo="$2"
    jq -n --arg p "${prompt}" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${repo}" \
        bash "${HOOK}" 2>/dev/null
}

# Create a throwaway git repo whose origin/main == HEAD (0 commits ahead, clean tree).
_make_phase_git_repo() {
    local d="$1"
    mkdir -p "${d}"
    git -C "${d}" init -q
    git -C "${d}" config user.email t@example.com
    git -C "${d}" config user.name tester
    git -C "${d}" commit -q --allow-empty -m base
    git -C "${d}" update-ref refs/remotes/origin/main HEAD
}
```

Then add three tests near the design-guard tests (~line 5580+), and register each by calling it right after its definition (sibling style):

```bash
test_phase_reality_flags_ship_with_no_work() {
    echo "-- test: PHASE REALITY fires at SHIP with 0 commits ahead and clean tree --"
    setup_test_env
    install_registry
    local repo="${HOME}/pr-norepo-work"
    _make_phase_git_repo "${repo}"

    local context
    context="$(extract_context "$(run_hook_in_repo "let's ship this and merge the branch to main" "${repo}")")"

    assert_contains "no-work advisory fires" "PHASE REALITY" "${context}"
    assert_contains "no-work wording present" "No committed work" "${context}"

    teardown_test_env
}
test_phase_reality_flags_ship_with_no_work

test_phase_reality_silent_when_commits_exist() {
    echo "-- test: PHASE REALITY silent at SHIP when commits are ahead of origin/main --"
    setup_test_env
    install_registry
    local repo="${HOME}/pr-has-work"
    _make_phase_git_repo "${repo}"
    git -C "${repo}" commit -q --allow-empty -m work   # now 1 ahead of origin/main

    local context
    context="$(extract_context "$(run_hook_in_repo "let's ship this and merge the branch to main" "${repo}")")"

    assert_not_contains "no advisory when work exists" "PHASE REALITY" "${context}"

    teardown_test_env
}
test_phase_reality_silent_when_commits_exist

test_phase_reality_failopen_no_origin() {
    echo "-- test: PHASE REALITY silent at SHIP when origin/main is absent (fail-open) --"
    setup_test_env
    install_registry
    local repo="${HOME}/pr-no-origin"
    mkdir -p "${repo}"
    git -C "${repo}" init -q
    git -C "${repo}" config user.email t@example.com
    git -C "${repo}" config user.name tester
    git -C "${repo}" commit -q --allow-empty -m base   # no refs/remotes/origin/main created

    local context
    context="$(extract_context "$(run_hook_in_repo "let's ship this and merge the branch to main" "${repo}")")"

    assert_not_contains "no advisory when origin/main unresolved" "PHASE REALITY" "${context}"

    teardown_test_env
}
test_phase_reality_failopen_no_origin
```

- [ ] **Step 2: Run the tests to verify they fail (red)**

Run: `/bin/bash tests/test-routing.sh 2>&1 | grep -E "phase_reality|FAIL|Tests (run|passed|failed)" | head`
Expected: `test_phase_reality_flags_ship_with_no_work` FAILS (no `PHASE REALITY` emitted yet). The two silent tests may already "pass" vacuously (nothing emitted) — that's fine; the fire test is the red signal. Confirm the fire test fails for the right reason (string absent), not a harness error.

- [ ] **Step 3: Implement the SHIP block + Rule B**

In `hooks/skill-activation-hook.sh`, immediately after line 1561 (`    SKILL_LINES="${SKILL_LINES}${DESIGN_COMPLETENESS}"` and its closing `fi`), insert:

```bash
# --- PHASE REALITY: advisory-only reconciliation of claimed SHIP vs repo state.
# Advisory only (never blocks); fail-open on every sub-check. SHIP-only: at
# REVIEW, requesting-code-review is the current step and a clean tree is usually
# benign recap, so both rules would false-fire there.
if [[ "${PRIMARY_PHASE}" == "SHIP" ]]; then
  _PR_MSG=""

  # Rule B (no committed work): 0 commits ahead of origin/main AND clean tree.
  # origin/main literal (matches openspec-guard.sh; robust on un-pushed branches).
  _PR_AHEAD="$(git -C "$_PROJECT_ROOT" rev-list --count origin/main..HEAD 2>/dev/null)"
  [[ "$_PR_AHEAD" =~ ^[0-9]+$ ]] || _PR_AHEAD=-1   # detached/no-origin/error => silent
  _PR_DIRTY="$(git -C "$_PROJECT_ROOT" status --porcelain 2>/dev/null)"
  if [[ "$_PR_AHEAD" -eq 0 ]] && [[ -z "$_PR_DIRTY" ]]; then
    _PR_MSG="${_PR_MSG}
  [i]  No committed work on this branch (0 commits ahead of origin/main, clean tree) — SHIP phase may be premature."
  fi

  if [[ -n "$_PR_MSG" ]]; then
    SKILL_LINES="${SKILL_LINES}
PHASE REALITY:${_PR_MSG}"
  fi
  [[ -n "${SKILL_EXPLAIN:-}" ]] && \
    echo "[skill-hook]   [phase-reality] ahead=${_PR_AHEAD:-na} dirty=${_PR_DIRTY:+1} phase=${PRIMARY_PHASE}" >&2
fi
```

(Rule A will be added inside this same `if` block in Task 2.)

- [ ] **Step 4: Run the tests to verify they pass (green) + syntax check**

Run:
```bash
/bin/bash -n hooks/skill-activation-hook.sh && echo "syntax OK"
/bin/bash tests/test-routing.sh 2>&1 | grep -E "phase_reality|Tests (run|passed|failed)"
```
Expected: syntax OK; the three `phase_reality` tests pass; overall suite failed count unchanged from baseline.

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: phase-reality SHIP advisory for no committed work (#58 Gap 3)"
```

---

## Task 2: Rule A — SHIP-skipped-REVIEW advisory

**Files:**
- Modify: `hooks/skill-activation-hook.sh` (inside the SHIP block from Task 1)
- Modify: `tests/test-routing.sh` (2 tests + a composition-state seed helper)

- [ ] **Step 1: Add the seed helper + failing tests**

In `tests/test-routing.sh`, add a helper that seeds composition state (mirrors `_seed_plan_state`'s token-write pattern):

```bash
# Seed composition state: chain contains requesting-code-review, completed lacks it.
_seed_comp_chain_missing_review() {
    local token="$1"
    printf '%s' "${token}" > "${HOME}/.claude/.skill-session-token"
    jq -n '{
        chain: ["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion"],
        completed: ["brainstorming","writing-plans","executing-plans"],
        current_index: 3,
        updated_at: "2026-06-14T00:00:00Z"
    }' > "${HOME}/.claude/.skill-composition-state-${token}"
}
```

Then two tests. NOTE on isolation: Rule A's test must keep Rule B silent so the assertion is unambiguous — point `SKILL_PROJECT_ROOT` at the no-origin repo (Rule B fail-open → silent), so only Rule A can fire.

```bash
test_phase_reality_flags_ship_chain_skipped_review() {
    echo "-- test: PHASE REALITY fires at SHIP when chain has but completed lacks requesting-code-review --"
    setup_test_env
    install_registry
    _seed_comp_chain_missing_review "comp-token-1"
    local repo="${HOME}/pr-a-no-origin"
    mkdir -p "${repo}"; git -C "${repo}" init -q
    git -C "${repo}" config user.email t@example.com; git -C "${repo}" config user.name tester
    git -C "${repo}" commit -q --allow-empty -m base   # no origin/main => Rule B silent

    local context
    context="$(extract_context "$(run_hook_in_repo "let's ship this and merge the branch to main" "${repo}")")"

    assert_contains "review-skip advisory fires" "PHASE REALITY" "${context}"
    assert_contains "review-skip wording present" "has not completed REVIEW" "${context}"

    teardown_test_env
}
test_phase_reality_flags_ship_chain_skipped_review

test_phase_reality_silent_no_chain() {
    echo "-- test: PHASE REALITY review-rule silent at SHIP when no composition chain exists --"
    setup_test_env
    install_registry
    # No composition-state file seeded. Use a repo with commits ahead so Rule B is also silent.
    local repo="${HOME}/pr-a-has-work"
    _make_phase_git_repo "${repo}"
    git -C "${repo}" commit -q --allow-empty -m work

    local context
    context="$(extract_context "$(run_hook_in_repo "let's ship this and merge the branch to main" "${repo}")")"

    assert_not_contains "no review-skip advisory without a chain" "has not completed REVIEW" "${context}"

    teardown_test_env
}
test_phase_reality_silent_no_chain
```

- [ ] **Step 2: Run to verify red**

Run: `/bin/bash tests/test-routing.sh 2>&1 | grep -E "chain_skipped_review|silent_no_chain|Tests (run|passed|failed)"`
Expected: `test_phase_reality_flags_ship_chain_skipped_review` FAILS (Rule A not implemented). `test_phase_reality_silent_no_chain` passes vacuously.

- [ ] **Step 3: Implement Rule A inside the SHIP block**

In `hooks/skill-activation-hook.sh`, inside the `if [[ "${PRIMARY_PHASE}" == "SHIP" ]]; then` block from Task 1, after the Rule B section and before the `if [[ -n "$_PR_MSG" ]]` emission, insert:

```bash
  # Rule A (chain skipped REVIEW): chain contains requesting-code-review but
  # .completed does not. Self-scoping (checks .chain membership). Token-rotation
  # safe: stale/foreign/empty state lacks the .chain member => silent.
  # NOTE: SILENT by design when no composition-state file exists (single/zero-skill
  # prompt, e.g. the no-chain "debugging an API key" case) — Rule B covers that.
  # Do not "fix" this silence.
  _PR_COMP="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN:-default}"
  if [[ -f "$_PR_COMP" ]] && \
     jq -e '((.chain // []) | index("requesting-code-review")) != null
            and ((.completed // []) | index("requesting-code-review")) == null' \
        "$_PR_COMP" >/dev/null 2>&1; then
    _PR_MSG="${_PR_MSG}
  [i]  Chain has not completed REVIEW (requesting-code-review not in .completed) — run it before SHIP."
  fi
```

- [ ] **Step 4: Run to verify green + syntax**

Run:
```bash
/bin/bash -n hooks/skill-activation-hook.sh && echo "syntax OK"
/bin/bash tests/test-routing.sh 2>&1 | grep -E "phase_reality|chain_skipped|silent_no_chain|Tests (run|passed|failed)"
```
Expected: syntax OK; all five phase-reality tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-routing.sh
git commit -m "feat: phase-reality SHIP advisory for skipped REVIEW (#58 Gap 3)"
```

---

## Task 3: Non-SHIP silence test, full suite, CHANGELOG

**Files:**
- Modify: `tests/test-routing.sh` (1 test)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add the non-SHIP silence test**

```bash
test_phase_reality_silent_non_ship_phase() {
    echo "-- test: PHASE REALITY silent at non-SHIP phases (no git/jq cost path) --"
    setup_test_env
    install_registry
    local repo="${HOME}/pr-nonship"
    _make_phase_git_repo "${repo}"   # 0 ahead + clean: would fire IF phase were SHIP

    # A design/build prompt routes to a non-SHIP phase (brainstorming = DESIGN).
    local context
    context="$(extract_context "$(run_hook_in_repo "let's design a brand new authentication system from scratch" "${repo}")")"

    assert_not_contains "no phase-reality block off SHIP" "PHASE REALITY" "${context}"

    teardown_test_env
}
test_phase_reality_silent_non_ship_phase
```

- [ ] **Step 2: Run the full suite under Bash 3.2**

Run: `/bin/bash tests/run-tests.sh 2>&1 | tail -8`
Expected: all test files pass, 0 failed (including `test-routing.sh` with the 6 new phase-reality tests). Capture this output as the verification evidence. If anything fails, STOP and fix before committing.

- [ ] **Step 3: Add the CHANGELOG entry (accumulator — do NOT add a version header)**

Under the existing `## [Unreleased]` → `### Added` in `CHANGELOG.md`, add:

```markdown
- **Phase-reconciliation advisory (Gap 3)** — at `PRIMARY_PHASE == SHIP`, the activation hook now emits an advisory `PHASE REALITY:` `[i]` note when (a) the branch has 0 commits ahead of `origin/main` with a clean tree ("no committed work"), or (b) the composition chain contains but hasn't completed `requesting-code-review`. Advisory-only, SHIP-only, fail-open on every sub-check (missing git, no `origin/main`, detached HEAD, missing/stale composition state, missing jq), silent on the happy path and all non-SHIP phases. No hard-block (the `openspec-guard.sh` push gate remains the enforcement boundary), no network, no new state, no config changes. (#58 Gap 3)
```

- [ ] **Step 4: Commit**

```bash
git add tests/test-routing.sh CHANGELOG.md
git commit -m "test: phase-reality non-SHIP silence + changelog (#58 Gap 3)"
```

---

## Self-Review Checklist (run before REVIEW)

- [ ] **Spec coverage:** `specs/skill-routing/spec.md` — "SHIP-phase no-work advisory" (3 scenarios) → Task 1; "SHIP-phase REVIEW-skip advisory" (3 scenarios incl. silent-no-chain + silent-non-SHIP) → Tasks 2 + 3. Every scenario maps to a test.
- [ ] **Bash 3.2:** numeric guard `^[0-9]+$` before the `-eq` comparison; no quoted `$(( ))`; no `\b`/`\d`/`(?:)`; `git -C "$_PROJECT_ROOT"` quoted; `/bin/bash -n` clean.
- [ ] **Fail-open:** every git call `2>/dev/null`; `_PR_AHEAD=-1` sentinel; jq guarded with `2>/dev/null`; the whole block only runs at SHIP and leaves `SKILL_LINES` untouched on any failure.
- [ ] **No placeholders:** every code/test block above is literal and complete.
- [ ] **Test isolation:** Rule A test uses a no-origin repo (Rule B silent); Rule B fire test has no composition-state file (Rule A silent). Confirmed.

---

## Out of Scope (do NOT implement)

- Any hard-block / push-gate teeth (deferred — revival: advisory ignored → bad push, ≥2 logged).
- `gh`/PR-state (deferred — off-budget).
- tests-ran-this-session marker; REVIEW/IMPLEMENT-phase checks; softening the always-on label; config changes.
