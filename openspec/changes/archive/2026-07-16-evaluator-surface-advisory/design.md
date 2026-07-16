# Design: Protected-evaluator-surface advisory

## Architecture

Mirrors the existing routing-governance shape (predicate in `verdict.sh`, consumer in `openspec-guard.sh`), but on the advisory channel instead of the deny channel.

**Surface list** (`_EVALUATOR_SURFACES` in `hooks/lib/verdict.sh`, space-separated repo-relative paths):
`hooks/openspec-guard.sh`, `hooks/lib/verdict.sh`, `hooks/lib/branch-ledger.sh`, `hooks/lib/git-command.sh`, `hooks/lib/session-token.sh` (= the drift-canary five), plus `.verify.yml`, `scripts/verify-and-record.sh`, `skills/project-verification/scripts/gate-gaming-check.sh`, and `hooks/skill-completion-hook.sh` (review addition: the branch-ledger milestone writer — the gate trusts what it records). The activation-hook walker is deliberately excluded: it is the most-edited file in the repo, and listing it would make the advisory near-constant noise. Rationale: "files whose edit changes what *verified* means or what the gate trusts." Single-sourcing is enforced by test, not by a shared runtime lib: `tests/test-evaluator-surface.sh` asserts this list is a superset of `{hooks/openspec-guard.sh} ∪ _GATE_ENFORCE_LIBS` (greped from `hooks/session-start-hook.sh`), so extending the canary manifest without extending this list fails CI. A shared `gate-libs.sh` was rejected: it would touch the fragile 200ms session-start hot path (Bash-3.2 incident history) for no runtime benefit.

**Predicate** `diff_touches_evaluator <proj_root>`: branch diff `_routing_base..HEAD` name-only, exact-path match against the list; prints matched names on stdout; returns 0 iff any match. Fail-open: unresolvable base / git error ⇒ return 1 (no advisory), same discipline as `diff_touches_routing`.

**Guard integration** (`hooks/openspec-guard.sh`): inside the push block, push-only (`_gc_is_push`, not gh-merge — the branch-local diff is unrelated to a merged PR's delta, same reasoning as routing-governance), after the deny gates have passed, append to `_STALE_MSG`. **Emission fix:** `_STALE_MSG` currently reaches the user only via the SHIP-phase `_WARNINGS` block; the two early-exits before it (`no signal file`, `phase != SHIP`) silently drop pending push advisories. Both early-exits are replaced by a flush: if `_STALE_MSG` is non-empty, emit it as `additionalContext` before exiting. No `permissionDecision` is ever attached to the advisory path (attaching one would auto-approve and suppress downstream warnings — documented prior bug shape).

**Checker extension** (`gate-gaming-check.sh`): third pattern block using awk to track the current file from BOTH diff headers (`+++ /dev/null` — whole-file deletion, the maximal weakening — falls back to the `---` side path; any single-letter prefix tolerated so `diff.mnemonicPrefix`/`noprefix` gitconfigs cannot silently disable detection; both writers additionally pin canonical prefixes with `-c diff.mnemonicPrefix=false -c diff.noprefix=false`). Semantics are ENTRY-removal, not line-removal: a `- name:` deleted and not re-added flags → `suspect`; `run:`-line rewrites, additions, and renames that re-add a name do not. Review-driven: `suspect` feeds `verdict_is_clean`, which routing-governance hard-requires, so a line-level pattern turned benign `run:`-rewrites into push denies — the exact false-block shape this feature forbids.

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

## Implementation Notes (synced at ship time)

- Detector semantics changed during review from line-removal to ENTRY-removal (a `- name:` deleted and not re-added): the line-level pattern turned benign `run:`-rewrites into `suspect`, which `verdict_is_clean` → routing-governance converts into a push DENY — the false-block shape this feature forbids. Red-first fixtures pin both directions.
- Review additions beyond the upfront design: `+++ /dev/null` fallback (whole-file `.verify.yml` deletion previously escaped), diff-prefix pinning + tolerance (`diff.mnemonicPrefix` silently disabled detection), push-only advisory flush (was leaking branch-local staleness onto `gh pr merge`), `hooks/skill-completion-hook.sh` added to the surface list, SKILL.md manual pathspec widened for writer parity, and `_branch_diff_names` extracted (shared by routing + evaluator predicates).

## Dissenting views

- Codex pass argued `.verify.yml` alone (+ canary five) is the minimal defensible list; the wider list (verdict writer + checker) was kept because both are unambiguously "what verified means" files and the channel is advisory (noise-only cost).
