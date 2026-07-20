# memory-validate sweep — design

**Status:** approved (brainstorming), pending plan
**Date:** 2026-07-20
**Author:** improvement-miner run 2026-07-19 → normal chain
**Evidence:** improvement-miner issue #125 (rejected-STALE) — a memory proposed changing a phrase deleted from the repo ~2 months earlier; the miner trusted a stale memory. See memory `self-improvement-factory` ("Miner gap confirmed … staleness check missing").

## Problem

Claude Code auto-memory (`~/.claude/projects/<project>/memory/`) drifts silently: a memory written when true keeps citing repo artifacts (files, paths) that later move or vanish. There is no consistency gate for the memory store, unlike `.claude/knowledge/` which has `scripts/knowledge-validate.sh`. The concrete cost surfaced when improvement-miner mined a stale section and produced a dead proposal (#125).

Best-practices literature (STALE, arXiv:2605.06527; memory-architectures survey, arXiv:2603.07670) confirms fuzzy staleness *reasoning* is unreliable (best models ~55%), and the hardest class is "Implicit Conflict" — a later fact silently invalidates an earlier memory. Conclusion: ship a **narrow, deterministic, high-precision** check (does a cited repo path still exist at HEAD?) and leave fuzzy judgment to the human gate.

## Non-goals (v1)

- Superseded/age signals (revival-date-passed, PR-open-but-merged). Cut: needs network/GitHub state + prose interpretation, largest false-positive blast radius. **Revival criterion:** a real instance where an age/PR-state signal would have caught a stale memory that the anchor check missed, ≥1–2×.
- Rewriting or auto-updating memories. This is a read-only validator; humans fix.
- Line-number validity of `path:NN` anchors — too brittle against edits; we check file existence only.

## Audience & shape

Generic plugin script `scripts/memory-validate.sh <memory-dir> [repo-root]`, Bash 3.2 compatible, modeled on `scripts/knowledge-validate.sh`. Any project using auto-memory can run it; this repo is the first consumer. `repo-root` defaults to `$PWD` (or `git rev-parse --show-toplevel`); anchors resolve against that repo's HEAD.

## Posture: advisory-first, two-tier exit

- **Not CI-blocking in v1.** Run manually or as an improvement-miner bundle input. The memory store is prose; a false block on historical context costs more than a missed warning.
- **Two-tier exit contract:**
  - **ERROR (exit 1)** — structural defects (unambiguous, mirrors knowledge-validate.sh).
  - **WARN (exit 0)** — staleness (dangling repo-path anchors). Printed to stderr, never changes exit code.
- This keeps the door open to wiring it somewhere later without a fuzzy check ever being able to block.

## Checks

### ERROR tier (structural)
1. **Frontmatter shape** — every non-`MEMORY.md` `.md` has `metadata.type` ∈ `{feedback, project, reference, user}`. (Auto-memory nests `type:` under `metadata:`; extraction must read the nested field, unlike knowledge-validate's top-level `type:`.)
2. **Dangling `[[slug]]` links** — every `[[slug]]` resolves to an existing `<slug>.md` in the memory dir.
3. **Index sync (bidirectional)** — every memory file has a `MEMORY.md` entry, AND every `MEMORY.md` link `(<slug>.md)` points at an existing file. (knowledge-validate only checks the first direction; MEMORY.md is hand-maintained, so flag orphaned index entries too.)

### WARN tier (staleness — the #125 fix)
4. **Dangling repo-path anchors** — backtick-wrapped `` `path.ext` `` / `` `path.ext:line` `` references in memory bodies that do NOT resolve at repo HEAD → WARN.
   - Resolve via `git -C <repo-root> cat-file -e "HEAD:<path>"` (HEAD, not working tree — gitignored `docs/plans/` and uncommitted edits must not mask staleness).
   - **Skip fenced code blocks** (``` ``` toggles) before extraction — code snippets contain non-anchor paths.
   - **Ext allowlist** for the path shape: `sh|md|json|yml|yaml|txt|ts|js|py`. Prose like `` `--flag` `` or `` `some_var` `` cannot match.
   - Strip `:NN` line suffix before resolution.
   - **Working-tree-only note:** if a path fails at HEAD but exists on disk, emit a distinct advisory NOTE ("exists in working tree, not at HEAD"), not a staleness WARN — it's a local draft, not rot.

## Anchor extraction & Bash 3.2 notes

- Strip fenced blocks with an `awk` toggle, then `grep -oE` backtick-wrapped path-shaped tokens against the ext allowlist.
- Dedup with newline-delimited temp files + `sort -u`. No associative arrays, no `mapfile`, no `for x in $(...)` unquoted word-splitting on paths with spaces (memory paths have none, but guard anyway).
- Literal matching uses `grep -F` where the needle contains regex metacharacters (paths contain `.`), per the runtime-output-grep gotcha.
- Follows the CLAUDE.md fail-open / Bash-3.2 arithmetic rules.

## Testing

New `tests/test-memory-validate.sh` + fixtures under `tests/fixtures/memory-validate/`:
- **Red:** memory citing a path absent at HEAD → WARN (reproduces #125); dangling `[[link]]`, missing `type`, index desync (both directions) → ERROR.
- **Green:** valid memory passes; a path inside a fenced code block does NOT warn; a working-tree-only path emits the NOTE, not a WARN; exit code stays 0 when only WARNs are present.
- Wired into `tests/run-tests.sh`.
- Not a skill → skill routing-fixture/content-coverage gates do not apply.

## Integration (future, out of scope for this change)

improvement-miner Step-1 bundle could invoke `memory-validate.sh` and surface per-memory staleness alongside the evidence — deferred to issue #138's implementation (miner-side staleness gate). This change ships the primitive only.

## Sparring record

Codex (repo-grounded, bounded) drove five load-bearing corrections, all adopted: anchors WARN-only vs structural ERROR; skip fenced blocks / ext-allowlist to kill false positives; resolve at HEAD not working tree; working-tree-only advisory note; cut check-4 superseded/age from v1. Best-practices web check (STALE, memory-survey) independently supported the "narrow deterministic over fuzzy" call.
