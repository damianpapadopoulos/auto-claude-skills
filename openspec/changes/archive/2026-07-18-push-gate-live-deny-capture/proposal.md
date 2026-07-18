# Push-gate live-invocation capture (diagnostic)

## Why

The live PreToolUse hook has DENIED `git push` twice (2026-07-15, 2026-07-17)
while replaying the identical payload through the on-disk `openspec-guard.sh`
says ALLOW. The failure is intermittent (allowed live on PR #114 with identical
evidence), invisible to replay, and forces a human `! git push` bypass — which
defeats the gate. Root cause is unconfirmed; the leading hypothesis is that the
harness executes a stale in-process/cached guard that diverges from the on-disk
file (a drift class the session-start canary *detects* but does not fix).

Content divergence between guard versions is already ruled out (every cached
version replays to ALLOW), so a code fix has no target. The only surviving
hypothesis — live-invocation divergence — is not reproducible on demand. The
productive move is to make the **next** occurrence self-documenting.

Tracked as GitHub issue #127.

## What Changes

Add **diagnostic-only** instrumentation to the push gate (no change to any
allow/deny decision):

- On a push/merge-classified invocation, `openspec-guard.sh` records a single
  JSONL line to `~/.claude/.push-gate-invocation-log` capturing which file ran
  (`$0`, `BASH_SOURCE`, `cksum`), plugin version, the live decision
  (`allow` / `deny:<gate>`), a **redacted** command, and provenance.
- On a **deny**, the record additionally carries a **true on-disk replay** of
  the guard against the exact original stdin (recursion-guarded) plus a
  `gate_status_mirror` — so a live-deny-while-replay-allows event is captured
  with both halves in one atomic record.
- If the on-disk guard never runs (stale in-process code), **no record appears**
  for that push — the drift smoking-gun.

## Impact

- Affected capability: `skill-routing` (push gate observability).
- Affected code: `hooks/openspec-guard.sh` (minimal inline: a decision var,
  seven pre-`exit` var-sets, one EXIT-trap function); new subprocess
  `scripts/push-gate-capture.sh`; tests.
- Risk: fail-open and off the decision path by construction. The capture lib is
  **never sourced** on the decision path (P0 finding from Codex sparring); it is
  a subprocess invoked only from a hardened EXIT trap. Diagnostic-only, so it is
  **excluded** from the `_GATE_ENFORCE_LIBS` canary manifest (same rationale as
  `consol-marker.sh`).
- No new outbound action, no weakened gate, no HITL change.
