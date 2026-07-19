## Why

Issue #133 (follow-up to #131 / PR #134): the push gate's session-local invocation-evidence leg (`_invoc_ok` in `hooks/openspec-guard.sh`) accepts `~/.claude/.skill-invocation-evidence-<token>` records that carry no repo/branch/SHA binding — a session that ran review/verify for feature A satisfies the STATUS gate for a later feature B push in the same session. Design D3 of `push-gate-status-bridge` accepted this widening deliberately (it rescues the PR #130 false-block repro), but the acceptance advisory could not tell a branch-bound record from an unrelated one. Separately, PR #134 review found the acceptance advisory was appended twice per milestone (chain block + global gate both call `_invoc_ok`).

## What Changes

- `hooks/skill-completion-hook.sh` additionally records `<skill> <sha>` lines (SHA = recording cwd's HEAD; skipped when unresolvable; exact pairs deduped) to a sidecar `~/.claude/.skill-invocation-evidence-sha-<token>`. The main JSON string array is format-frozen — `hooks/lib/phase-evidence.sh` and the guard's `_invoc_has` read it, so binding metadata lives in a sidecar, never in-place.
- `hooks/openspec-guard.sh` `_invoc_ok` PREFERS branch-bound sidecar records: when a record for the milestone (or a review-embedding proxy, PAIRED with `_invoc_has`'s list) has a SHA that is HEAD or a branch-local ancestor — the same rule the ledger bridge uses — the advisory upgrades to name the bound SHA. Binding is SOFT: it never gates acceptance (a hard requirement would re-break the #130 repro, where the recording cwd's SHA is unrelated to the push branch), and the sidecar alone can never satisfy the gate (acceptance authority stays the main array).
- `_invoc_ok`'s advisory is now appended once per milestone across the chain block and the global fail-closed gate (dedup; return value unchanged).
- `hooks/lib/branch-ledger.sh`: the binding rule is extracted from `branch_ledger_bridge_has` into `branch_ledger_sha_is_branch_local` + `_branch_ledger_mainline_base` (mainline refs first, `@{upstream}` LAST) so guard and bridge share one predicate; the bridge's behavior is unchanged.
- `hooks/session-start-hook.sh` state-prune: dead-token sidecars are pruned with the `.skill-invocation-evidence-*` family; the current session's sidecar is excluded.

## Capabilities

### Modified Capabilities
- `skill-routing`: push-gate STATUS-layer invocation-evidence leg gains soft SHA-binding (advisory upgrade only) and advisory dedup.

## Impact

- `hooks/skill-completion-hook.sh`, `hooks/openspec-guard.sh`, `hooks/lib/branch-ledger.sh`, `hooks/session-start-hook.sh`
- New runtime state file family: `~/.claude/.skill-invocation-evidence-sha-<token>` (GC'd with its family)
- No gate decision changes: allow/deny behavior is byte-identical for every scenario except advisory text; regression-pinned by `tests/test-push-gate-status-bridge.sh` (44 assertions) and `tests/test-state-file-cleanup.sh` (C5).
