# Design: Protected-evaluator-surface advisory

## Architecture

Mirrors the existing routing-governance shape (predicate in `verdict.sh`, consumer in `openspec-guard.sh`), but on the advisory channel instead of the deny channel.

**Surface list** (`_EVALUATOR_SURFACES` in `hooks/lib/verdict.sh`, space-separated repo-relative paths):
`hooks/openspec-guard.sh`, `hooks/lib/verdict.sh`, `hooks/lib/branch-ledger.sh`, `hooks/lib/git-command.sh`, `hooks/lib/session-token.sh` (= the drift-canary five), plus `.verify.yml`, `scripts/verify-and-record.sh`, `skills/project-verification/scripts/gate-gaming-check.sh`. Rationale: "files whose edit changes what *verified* means." Single-sourcing is enforced by test, not by a shared runtime lib: `tests/test-evaluator-surface.sh` asserts this list is a superset of `{hooks/openspec-guard.sh} ∪ _GATE_ENFORCE_LIBS` (greped from `hooks/session-start-hook.sh`), so extending the canary manifest without extending this list fails CI. A shared `gate-libs.sh` was rejected: it would touch the fragile 200ms session-start hot path (Bash-3.2 incident history) for no runtime benefit.

**Predicate** `diff_touches_evaluator <proj_root>`: branch diff `_routing_base..HEAD` name-only, exact-path match against the list; prints matched names on stdout; returns 0 iff any match. Fail-open: unresolvable base / git error ⇒ return 1 (no advisory), same discipline as `diff_touches_routing`.

**Guard integration** (`hooks/openspec-guard.sh`): inside the push block, push-only (`_gc_is_push`, not gh-merge — the branch-local diff is unrelated to a merged PR's delta, same reasoning as routing-governance), after the deny gates have passed, append to `_STALE_MSG`. **Emission fix:** `_STALE_MSG` currently reaches the user only via the SHIP-phase `_WARNINGS` block; the two early-exits before it (`no signal file`, `phase != SHIP`) silently drop pending push advisories. Both early-exits are replaced by a flush: if `_STALE_MSG` is non-empty, emit it as `additionalContext` before exiting. No `permissionDecision` is ever attached to the advisory path (attaching one would auto-approve and suppress downstream warnings — documented prior bug shape).

**Checker extension** (`gate-gaming-check.sh`): third pattern block using awk to track the current file from `+++ b/<path>` headers; within `.verify.yml`, deletion lines matching `^-[[:space:]]*(-[[:space:]]*name:|run:)` are hits → `suspect`. Additions and command rewrites (e.g. `run: true`) are out of scope — documented limit, consistent with the file's "extend the patterns, don't assume completeness" contract.

**Pathspec widening** (`scripts/verify-and-record.sh`): `git diff "$BASE"...HEAD -- '*test*' '*spec*' .verify.yml`.

## Trade-offs

- Advisory vs deny: deny variants backtested at 56–94% false-block with 0 catches (gate-status, 108 PRs); advisory has zero block cost and surfaces the self-reference for the human reviewer, which is the actual control point (PR review + GitHub branch protection).
- Test-enforced list consistency vs shared lib: CI pressure without runtime coupling; divergence is caught at merge time, not at 2am in a hook.
- Exact-path match vs prefix/glob: the surfaces are individual files, not trees; exact match cannot over-fire.

## Out-of-Scope

- Any deny/human-gate behavior (explicitly rejected; revisit only with evidence of a real missed catch).
- gh-merge coverage (branch-local diff is the wrong delta for a PR merge).
- Detecting `.verify.yml` weakening via rewrite/addition (e.g. swapping `run:` to a no-op) — removals only.
- selfpatch's other mechanisms (ledger, revert, blast radius, propose-artifact) — rejected in triage.
- `tests/` as a protected surface (TDD legitimately co-edits tests; the known false-block shape).

## Decisions

- D1: Advisory channel only; the list deliberately does NOT join `_GATE_ENFORCE_LIBS` (it is not enforcement).
- D2: List lives in `verdict.sh` next to its consumers; consistency enforced by owned CI test.
- D3: Push advisories flush on every push, not only SHIP-phase pushes (fixes a latent drop).
- D4: `verify-and-record.sh` pathspec change ships here (file exists on main); coordination note for `feat/verify-and-record` in the PR body.

## Dissenting views

- Codex pass argued `.verify.yml` alone (+ canary five) is the minimal defensible list; the wider list (verdict writer + checker) was kept because both are unambiguously "what verified means" files and the channel is advisory (noise-only cost).
