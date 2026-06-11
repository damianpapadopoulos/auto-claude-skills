# Tasks: Fix Token Singleton Race

## 1. TDD — regression tests (RED)

- [ ] 1.1 `tests/test-session-token-race.sh`: lib unit checks + scenarios 1–6
      from the delta spec (two interleaved sessions; guard keys to payload
      token; singleton fallback; completion-hook keying; re-stamp)
- [ ] 1.2 Verify RED under `/bin/bash`

## 2. Implementation (GREEN)

- [ ] 2.1 `hooks/lib/session-token.sh` (new)
- [ ] 2.2 `session-start-hook.sh` sources lib for token format
- [ ] 2.3 Convert `openspec-guard.sh` (batched jq, payload-first)
- [ ] 2.4 Convert `skill-activation-hook.sh` (capture-once stdin, single jq
      `\x1f` join, payload-first, singleton re-stamp)
- [ ] 2.5 Convert `skill-completion-hook.sh` (merged jq extraction)
- [ ] 2.6 Convert `consolidation-stop.sh` (read stdin, payload-first)
- [ ] 2.7 Convert `compact-recovery-hook.sh` (move stdin read to top)
- [ ] 2.8 `/bin/bash -n` every edited hook; verify GREEN; full suite
      `bash tests/run-tests.sh </dev/null`

## 3. Ship

- [ ] 3.1 CHANGELOG entry under [Unreleased]
- [ ] 3.2 Review → verification → openspec-ship sync → PR referencing #51
