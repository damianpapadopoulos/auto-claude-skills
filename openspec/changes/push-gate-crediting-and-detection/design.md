# Design: Push-gate review crediting + precise git-write detection

## Architecture

Two hooks cooperate on push-gate readiness, and each fix lands in exactly one of
them:

- **Writer:** `hooks/skill-completion-hook.sh` (PostToolUse:Skill) records a
  durable per-(repo+branch) milestone via `branch_ledger_record` when a gating
  skill completes. Today only `requesting-code-review` and
  `verification-before-completion` are recorded (skill-completion-hook.sh:74-84).
- **Reader:** `hooks/openspec-guard.sh` (PreToolUse:Bash) reads those milestones
  (`branch_ledger_has`, plus session-local `.completed` fallbacks) and denies a
  push when REVIEW or VERIFY evidence is absent.

The readers all key off the string `requesting-code-review`. The cleanest fix is
therefore **writer-side normalization**: map every review-embedding skill to that
one canonical key at the single write site, leaving all readers untouched.

### Fix #2 — canonical REVIEW milestone from review-embedding skills

Extend the milestone `case` in `skill-completion-hook.sh`:

```sh
case "${_BARE}" in
    requesting-code-review|verification-before-completion)
        branch_ledger_record "${_BARE}" ... ;;
    subagent-driven-development|agent-team-execution|agent-team-review)
        branch_ledger_record "requesting-code-review" ... ;;
esac
```

`verification-before-completion` still records under its own key. The three
review-embedding skills record under `requesting-code-review`, so a branch
reviewed via any of them satisfies every existing gate reader with no reader
change.

### Fix #3 — first-token git-write detection

Add `command_invokes_git_write()` (in `hooks/openspec-guard.sh`, or a shared
`hooks/lib/git-command.sh` if a second caller appears). Algorithm, Bash 3.2
compatible, fail-open:

1. Split the command on shell separators `;  &&  ||  |` and newline.
2. For each segment: trim leading whitespace; strip leading `VAR=val ` /
   `env VAR=val` prefixes; take the first token.
3. If the first token is `git` or `*/git`, scan following tokens, skipping git
   global flags (`-C <path>`, `-c <kv>`, `--no-pager`, `--git-dir=…`,
   `--work-tree=…`), and return true if the next non-flag token is `push` or
   `commit`.
4. Otherwise continue; return false if no segment qualifies.

Replace the two raw `case "${_COMMAND}" in *"git push"*|*"git commit"*)` matches
(openspec-guard.sh:26 fast-path, :59 push-gate) with calls to the helper.

## Decisions

- **Writer-side normalization over reader broadening.** One change point; readers
  stay simple; no risk of the ~5 read sites drifting out of sync. (Chosen over
  editing each reader to accept a set of skill names.)
- **Credit `subagent-driven-development`, `agent-team-execution`,
  `agent-team-review`.** These three structurally embed review (SDD mandates
  per-task + whole-branch review; agent-team-execution is reviewer-gated;
  agent-team-review *is* the review). `executing-plans` is deliberately **not**
  credited — it has no mandated review step.
- **First-token detection over a read-only-tool whitelist** (gate owner's call).
  Simpler and covers the real cases; the accepted cost is documented below.

## Trade-offs / Dissenting views

- **Fix #2 widens REVIEW crediting.** It trusts that a completed review-embedding
  skill actually reviewed — the same "the-skill-ran" proxy already used for
  `requesting-code-review` (a completion event is not proof of diligence). Stricter
  alternative considered and rejected for now: have SDD's final-review step invoke
  `requesting-code-review` itself (a skill-content change, larger surface).
- **Fix #3 accepts rare false-negatives.** The prior substring match caught *every*
  real push (even `bash -c "git push"`) at the cost of blocking innocent greps —
  false-positive-heavy, false-negative-free, which is the *safe* direction for a
  security gate. First-token detection removes the false-positives but can miss
  wrapper/alias forms. Accepted because the gate is a **strong default**, not an
  absolute boundary (human-terminal push and `ACSM_SKIP_PUSH_GATE=1` are
  first-class bypasses), and agent-emitted pushes are overwhelmingly direct
  `git push …`. If a future audit shows real wrapper-form pushes slipping, revisit
  with the whitelist approach.

## Verification

Deterministic bash — TDD in the existing `tests/` shell harness (extend
`test-completion-ledger.sh` / `test-branch-ledger.sh`; add gate-detection cases).
No probabilistic/LLM behavior, so no eval pack. Safety-relevant paths (deny on
missing review; allow on read-only command) are exercised directly with crafted
PreToolUse JSON. Fail-open behavior (missing jq/git/lib) asserted.

## Out of scope

The broader phase-gate program (canonical phase→required-skill map; IMPLEMENT
edit-gate; REVIEW hardening for security-scanner/agent-team-review; DISCOVER/LEARN
bookends; a `phase status` view). Captured for a separate discovery.
