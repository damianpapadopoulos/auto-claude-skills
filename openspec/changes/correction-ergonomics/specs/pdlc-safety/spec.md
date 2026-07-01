## ADDED Requirements

### Requirement: Owned gate messages use expected-actual-imperative remediation

Hard-gate and could-not-verify / iterative-fix-loop messages in files this plugin owns SHALL
be phrased as expected state, then actual observed state, then an imperative remediation the
reader can execute. This applies to the `hooks/openspec-guard.sh` PUSH GATE deny strings, the
`skills/agent-team-review/SKILL.md` blocking-verdict guidance, the
`skills/runtime-validation/SKILL.md` fix-loop terminal and coverage-gap / manual-check
hand-offs, and the `hooks/consolidation-stop.sh` session-end consolidation reminder. A rewritten
message whose action is not always warranted (e.g. the consolidation reminder, when nothing
durable emerged) MUST preserve an explicit honest opt-out so the imperative does not become
theater. Genuinely-advisory
messages that offer an explicit opt-out (e.g. the SHIP-phase `…or proceed if not needed`
warnings) MUST remain advisory and MUST NOT be rewritten into imperative form. The rewrite
MUST NOT change any gate block/allow decision, verdict routing, or fix-loop iteration count —
only message wording. The imperative rewrite MUST ship only after a red-first behavioral A/B
eval demonstrates that the imperative wording produces the remediation action at a higher rate
than the prior passive wording.

#### Scenario: Hard-gate message names expected, actual, and an imperative next action
- **WHEN** a push is blocked by openspec-guard because a required chain step has not run
- **THEN** the deny message MUST state the expected completed step, the actual missing step, and an imperative "do now" remediation (invoke the named Skill, then re-run the push)

#### Scenario: Could-not-verify terminal hands off explicit actions
- **WHEN** the runtime-validation fix-rescan loop exhausts its iterations with failures remaining
- **THEN** the message MUST hand off each remaining failure as an explicit action (scenario, observed failure, and the specific fix or decision the human must make) rather than a passive "requires human review" note

#### Scenario: Imperative rewrite preserves an honest opt-out where the action is conditional
- **WHEN** the session-end consolidation reminder fires and no durable, team-relevant learning emerged this session
- **THEN** the imperative reminder MUST still offer an explicit opt-out ("if nothing durable emerged, say so and stop") so it does not force consolidation theater

#### Scenario: Opt-out advisories stay advisory
- **WHEN** an openspec-guard SHIP-phase warning offers an explicit opt-out ("…or proceed if not needed")
- **THEN** it MUST retain the opt-out and MUST NOT be rewritten into an imperative mandate (no imperative theater)

### Requirement: Correction-ergonomics lift is proven red-first with a pinned model

The correction-ergonomics rewrite SHALL be gated by an opt-in behavioral A/B pack
(`tests/fixtures/correction-ergonomics/evals/behavioral.json`) run via
`tests/run-behavioral-evals.sh --directive-file`. The baseline arm injects the prior passive
wording and MUST fail a deterministic corrective-action assertion (`tool_call` or `text`); the
treatment arm injects the imperative wording and MUST pass it. The gating run MUST pin the inner
`claude -p --model` and record the model plus the run date in the pack README. The pack MUST
include an adversarial opt-out-advisory scenario with a pre-registered safety-stop: if imperative
wording induces the agent to force a corrective action on an opt-out advisory, the ship HALTS.
Scenarios are append-only and MUST be deprecated with a dated rationale rather than deleted.

#### Scenario: Baseline red, treatment green
- **WHEN** the A/B pack runs the same scenario with passive (baseline) then imperative (treatment) wording under a pinned model
- **THEN** the baseline arm MUST fail the corrective-action assertion and the treatment arm MUST pass it, and the pinned model + run date MUST be recorded in the pack README

#### Scenario: Imperative-theater safety-stop
- **WHEN** the adversarial scenario injects an opt-out advisory in imperative-styled wording
- **THEN** if the agent forces a corrective action instead of honoring the opt-out, the gate MUST be treated as a halt condition and the rewrite MUST NOT ship until revised
