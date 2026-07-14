# Design: composition-uptake-baseline

## Architecture

Mirrors the shipped discovery-precondition eval (PR #104 pattern) end to end:
self-contained prompts that embed a production-shaped SKILL ACTIVATION block
(composition chain with [DONE]/[CURRENT]/[NEXT] markers, mandatory eval line,
IMPORTANT continuation directive) followed by a task framing ("state what you
will do FIRST — name the specific Skill") and a user message. One judge
assertion per arm with PASS/FAIL criteria written against named behaviors,
matching approval-and-refusal families where relevant (arm 2 passes on any
route-through-review response, not one phrasing).

Measurement stack:
- Runner: existing `tests/run-behavioral-evals.sh` (opt-in, claude -p
  subjects, judge kind pinned per repo convention). Smoke = 1 call on arm 1
  before any full run (harness-gotchas memory).
- Baseline artifact: `tests/baselines/composition-uptake.baseline.json`
  `{judge_model, date, reps, arms:[{id, pass, total}]}` — same family as the
  two existing baselines.
- Deterministic CI layer is the STRUCTURE test only (pack shape, marker
  presence, unique ids, pinned judge) — presence-not-quality, the same
  deliberate bar as the fixture/content done-gates.

## Trade-offs

- **Measurement mode — `--bare` (REVISED at plan time):** the runner's
  `--bare` strips the plugin's own hooks from the inner subject; without it,
  the live activation hook fires on the pack prompt and injects a SECOND
  composition block over the embedded one (double-injection confound, not
  "real environment"). So subjects measure exactly the embedded directive
  surface — the model-routing-probation precedent. Repo cwd remains readable
  (CLAUDE.md reinforcement is part of the deployed reality); a fully
  clean-room arm stays a documented possible extension.
- **Informational, not gating:** run-to-run variance is unmeasured; a 5-rep
  baseline cannot gate without lying (small-n memory). Revival criterion for
  gating: two independent full runs whose per-arm rates differ by <=1/5,
  plus a pre-registered threshold.
- **Four arms, not more:** covers the audit's uptake question (does the
  model follow CURRENT-step, resist skip pressure, honor the continuation
  directive) plus one over-fire control. More arms = more cost per run with
  diminishing information; extend when a specific routing change needs it.

## Dissenting views

- The audit's tests-explorer suggested gating CI on uptake. Rejected here
  (variance unknown; probabilistic gate in CI is flake-by-design until the
  revival criterion is met) — consistent with the scheduled-behavioral-evals
  design, which runs packs on a schedule rather than per-PR.

## Decisions

1. Judge model pinned to `claude-sonnet-5` (matches discovery-precondition
   and scheduled-evals precedent); recorded in the baseline artifact.
2. Never-delete: arms are never removed, only deprecated with a dated
   rationale in the README (eval-strategy convention).
3. Trifecta: none (local fixtures, opt-in local runs, no outbound actions);
   no agent-safety-review needed.

## Implementation Notes (synced at ship time)

- Measurement executed in `deployed-ambient` fallback mode, not the designed
  `--bare`: the CLI's bare mode skips OAuth by design and authenticates only
  via ANTHROPIC_API_KEY, which this environment lacks. Double-injection was
  suppressed with the activation hook's `[no-skills]` marker on a temp pack
  copy; both modes and their non-comparability are documented in the README.
- Result: directive arms at ceiling 16/16 (subject claude-fable-5, judge
  claude-sonnet-5, 5 reps/arm + 1 pooled smoke). Over-fire control arm
  quota-blocked mid-run (subscription 429); recorded pending with rerun
  instructions — completing it is the one open follow-up.
- Review (eval-design lens, verdict With-fixes, all applied): disclosed the
  full-format mandatory-line idealization (a real 2-skill compact render
  omits it — verified against the hook; prompts deliberately NOT edited
  post-measurement), added a Threats-to-validity section (marker visibility,
  CLAUDE.md priming ⇒ ceiling is an upper bound), and extended the structure
  test with >=1-assertion and baseline measurement-contract checks (closing
  the spec-scenario-2 test gap).
