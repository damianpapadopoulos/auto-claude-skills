# Design: push-gate-invoc-sha-binding

## Architecture

Writer → sidecar → reader, layered on the #131 status bridge:

1. **Writer** (`skill-completion-hook.sh`, PostToolUse on `^Skill$`): after the existing append to the main JSON string array, append `"<skill> <sha>"` to `~/.claude/.skill-invocation-evidence-sha-<token>` where `<sha>` is `git rev-parse HEAD` in the hook's cwd. If HEAD is unresolvable (non-repo cwd), skip the line — the reader degrades to the unbound advisory. Exact `<skill> <sha>` duplicates are skipped (`grep -qxF`), so the file is bounded by distinct (skill, sha) pairs per session.
2. **Binding predicate** (`hooks/lib/branch-ledger.sh`): `branch_ledger_sha_is_branch_local <sha> <proj_root> <head> <base>` — accept iff `sha == head`, or `sha` is an ancestor of `head` NOT reachable from the mainline merge-base `base`; empty `base` ⇒ exact-head only. `_branch_ledger_mainline_base` resolves `base` (mainline refs first, `@{upstream}` LAST — the U7 self-tracking-upstream shadow bug). Both extracted from `branch_ledger_bridge_has`, which now calls them; bridge behavior unchanged (U1–U7 pinned).
3. **Reader** (`openspec-guard.sh` `_invoc_ok`): after `_invoc_has` accepts (main array — the sole acceptance authority), scan the sidecar for the milestone name or its review-embedding proxies. First branch-bound SHA found upgrades the advisory to "recorded at <sha> on this branch … SHA-bound — issue #133"; otherwise the #131 "not branch-bound" advisory stands. Base resolution is cached once per guard run.

## Decisions & Trade-offs

- **Soft vs hard binding — SOFT chosen, hard is a non-goal.** In the #130 repro the session cwd is a different checkout than the push branch, so the recording cwd's SHA is legitimately unrelated to the push HEAD. A hard SHA requirement would re-introduce exactly the false-block #131 fixed. Soft binding upgrades reviewer-facing signal without changing any decision.
- **Sidecar vs versioned format.** The main string array is read by `phase-evidence.sh` (`phase_step_satisfied`) and `_invoc_has`; an in-place format change (array of objects) would break both readers and any cached-plugin-version skew. A sidecar keeps the main file format-frozen and is independently GC-able.
- **Advisory dedup via `_INVOC_NOTED` guard, not call-site restructuring.** The chain block and global gate legitimately both consult the leg (either can be reached first depending on composition state); making the append idempotent per milestone is smaller than restructuring the call graph, and keeps the return value identical.
- **Sidecar can never satisfy the gate.** `_invoc_has` runs first and both advisory branches merely annotate; red-team pinned by G11 (bound sidecar without the main array still denies). A forged sidecar therefore changes zero decisions — it shares the same agent-writable trust class as every other evidence file the gate reads.
- **GC**: the sidecar deliberately matches the `.skill-invocation-evidence-*` prune glob (dead-token cleanup for free); only the current session's sidecar is excluded, mirroring the main file's exclusion.

## Dependencies

None new. Bash 3.2, `jq` optional (sidecar writer is grep/printf only; reader is inside already-jq-gated guard paths).
