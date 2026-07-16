# Proposal: phase-enforcement

## Why

The Superpowers SDLC chain and this plugin's designated-point supplements are
enforced today by prompt-injected guidance plus exactly one deterministic
boundary (the push/merge gate). Everything earlier is advisory, and advisory
fails in practice: on 2026-07-16, with the chain rendered on every prompt, an
agent session skipped `writing-plans` entirely and compressed brainstorming's
approval gate — two user corrections in one session (direct observation,
discovery brief `docs/plans/2026-07-16-phase-enforcement-discovery.md`).
User directive (stated twice, escalated): phases must not be skippable; the
enforcing mechanism must manage transitions and handover; this must live at
the plugin level, not in agent memory.

Evidence base: composition CURRENT-step directives reach 16/16 uptake while
hint-adjacent advisories reach 0/5 (audit F6, PR #105); the only deny-family
backtest ever run here (push-gate staleness variants, PR #114) showed 56–94%
false-block with 0 catches — so every new deny predicate in this change is
backtest-gated with pre-registered thresholds before it ships as a deny.

## What Changes

1. **`hooks/skill-gate.sh` (new, PreToolUse `^Skill$`)** — the Skill-sequencing
   gate. When a composition chain is active and the invoked skill is a chain
   member, invoking step *i* is DENIED (push-gate deny shape, remedy naming the
   exact predecessor `Skill(...)` to run) while any required predecessor *j<i*
   lacks evidence. Evidence = `.completed` (completion-hook invocation record)
   ∪ branch ledger ∪ explicit skip-attestation. Allow on: no active chain,
   non-chain skill, re-invocation of current/completed steps, unreadable or
   malformed state (deny only on positive violation evidence).
2. **Skip-attestation** (`hooks/lib/phase-attest.sh`, new) — helper writes
   `~/.claude/.skill-phase-attest-<token>` (`step → {reason, ts}`). An attested
   step satisfies the sequencing and outbound checks; every attestation is
   logged, surfaced in the gate-status block and at REVIEW.
   `requesting-code-review` and `verification-before-completion` are
   hard-excluded — attestation never satisfies the push gate's milestones.
3. **`hooks/openspec-guard.sh` (extended)** — chain-covered pushes additionally
   require DESIGN (`brainstorming`) + PLAN (`writing-plans`) evidence from the
   same sources. This predicate ships as a deny ONLY if the replay backtest
   shows <10% false-block (10–20% → narrowed scope; inconclusive → warn-only
   with dated revisit).
4. **`scripts/phase-gate-backtest.sh` (new)** — replays local session
   transcripts, reconstructs Skill-invocation sequences and chain state,
   reports would-have-denied per predicate with true-catch vs false-block
   classification. Runs red-first against pre-registered thresholds.
5. **Step-text promotion (`config/default-triggers.json`)** — the trifecta
   (agent-safety-review) conditional moves into DESIGN CURRENT-step text
   (16/16-uptake placement); measured by a red-first behavioral uptake eval.
6. **Telemetry** — every gate decision (deny, allow-by-scope,
   attest-satisfied) appends to `~/.claude/.phase-gate-events.log`
   (compact-events pattern); feeds the 4-week dogfood kill criterion
   (>10% user-judged false-blocks → that predicate demotes to advisory).
7. **Config** — `phase_enforcement` block in `~/.claude/skill-config.json`:
   per-boundary `deny | warn | off`; default deny in this repo (dogfood),
   warn for external consumers this release.

## Capabilities

### Modified
- `pdlc-safety` — deterministic phase-transition enforcement joins the
  existing push-gate milestone protections (extends the capability that owns
  gating-milestone integrity, audit F1/F2).

## Impact

- Touched: new `hooks/skill-gate.sh`, new `hooks/lib/phase-attest.sh`,
  `hooks/openspec-guard.sh`, `hooks/hooks.json` (PreToolUse `^Skill$`
  registration), `config/default-triggers.json` (step text), new
  `scripts/phase-gate-backtest.sh`, new `tests/test-skill-gate.sh`,
  push-gate regression additions.
- No existing gate is weakened: C1/C2 strictly add denies; attestation cannot
  satisfy REVIEW/VERIFY (regression-pinned). Human `!` bypass preserved by
  construction. All new code Bash 3.2, fail-open on errors.
- Out of scope: Edit/Write deny (O3) unless the backtest clears <10%
  false-block AND shows ≥1 true catch; non-chain work; artifact-quality
  judgment; cross-repo branch-binding beyond the existing ledger.
