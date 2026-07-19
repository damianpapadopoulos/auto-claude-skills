# Tasks: push-gate-invoc-sha-binding

## Completed

- [x] 1.1 Red-first tests: U8a–g (binding predicate), H3a–c (sidecar writer), D1a–c (advisory dedup), G8–G10 (guard binding scenarios) in tests/test-push-gate-status-bridge.sh; C5a/C5b (sidecar GC) in tests/test-state-file-cleanup.sh — 9 assertions observed red before implementation
- [x] 1.2 Extract `branch_ledger_sha_is_branch_local` + `_branch_ledger_mainline_base` from `branch_ledger_bridge_has` (behavior-identical refactor; U1–U7 unchanged)
- [x] 1.3 Sidecar writer in skill-completion-hook.sh (`<skill> <sha>`, dedup per pair, skip on unresolvable HEAD)
- [x] 1.4 Guard `_invoc_ok`: per-milestone advisory dedup + soft binding preference with SHA-bound advisory upgrade
- [x] 1.5 session-start GC: exclude current session's sidecar; dead-token sidecars pruned with family
- [x] 1.6 Code review (zero critical/important; three minors applied: G11 sidecar-alone-denies pin, garbage-line tolerance fixture, `command -v` consistency guard)
- [x] 1.7 Full suite 101/101 files green; clean verdict recorded at aca3461 via scripts/verify-and-record.sh

Execution plan lived in issue #133's consolidated implementation-context comment (no docs/plans artifact this session); see git log commits a28bf81, aca3461.
