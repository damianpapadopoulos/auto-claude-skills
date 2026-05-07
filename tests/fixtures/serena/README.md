# Serena routing behavioral evals

Opt-in fixtures that exercise the Serena triggering redesign (PR #25) end-to-end via `claude -p`. Currently one scenario: **subagent-propagation**.

## What this tests

The redesign's subagent strategy delegates Serena-guidance propagation to Claude itself: the SessionStart banner instructs the parent context to include `Serena available — prefer find_symbol over Grep for symbol lookups` in any Task spawn prompt for code work. That delegation is the most untested claim in the design — bash hermetic tests cover "the banner contains the instruction," not "Claude follows the instruction in practice."

This fixture asks Claude to spawn a subagent and to print the spawn prompt before invoking Task. Three assertions then check, against the printed prompt:
1. Claude actually planned a Task spawn,
2. The spawn prompt contains a Serena reference (banner copy or close paraphrase),
3. The user's symbol-search task is carried into the subagent.

If the second assertion fails repeatedly across variance runs, the propagation strategy is failing in practice. That is high-signal input for the 14-day revival evaluation — it would mean the parked Read / Glob matchers' "subagent inheritance via banner" assumption is wishful thinking and any future revival decision should weight in-band Grep-nudge coverage more heavily.

## How to run

This pack is **not** in the default `tests/run-tests.sh` path. It costs real `claude -p` invocations and is non-deterministic. Trigger explicitly:

```bash
BEHAVIORAL_EVALS=1 SKILL_PATH=tests/fixtures/serena/skill-stub.md \
    bash tests/run-behavioral-evals.sh \
    --pack tests/fixtures/serena/behavioral.json \
    --scenario subagent-propagation \
    --variance 5
```

`SKILL_PATH` overrides the default (incident-analysis SKILL.md). The stub at `tests/fixtures/serena/skill-stub.md` is intentionally near-empty so the `<skill_guidance>` wrapper does not steer Claude into an unrelated workflow.

`--variance 5` (or higher) is **strongly recommended**. Single-run results are noisy. The variance report classifies each assertion as `stable` (≥90% pass), `flaky` (50–89%), or `broken` (<50%). Project memory `project_cast_fixture_zero_signal` documents why single runs of behavioral fixtures can mislead — design the fixture so it can fail honestly, not just fail because the model derailed.

## Required safety setup

Two known runner caveats apply (project memory `feedback_inner_claude_p_tool_access`):

1. **The runner does not pass `--disallowedTools` to the inner `claude -p` invocation.** The inner process has full Edit / Write / Bash access and **has reverted committed code in past fixture-authoring sessions**. Do not run this fixture from the live development repo — clone or worktree to a separate path first:
   ```bash
   git worktree add ../auto-claude-skills-evals fix/serena-telemetry-followups
   cd ../auto-claude-skills-evals
   BEHAVIORAL_EVALS=1 SKILL_PATH=tests/fixtures/serena/skill-stub.md \
       bash tests/run-behavioral-evals.sh \
       --pack tests/fixtures/serena/behavioral.json \
       --scenario subagent-propagation \
       --variance 5
   # When done:
   cd -; git worktree remove ../auto-claude-skills-evals
   ```
   The runner-level fix to add `--disallowedTools "Edit Write Bash"` is tracked separately; until it lands, sandbox via worktree.

2. **`serena=true` must be true in the registry that the inner `claude -p` sees.** If the inner Claude session does not have Serena MCP installed and registered, the SessionStart banner will not include the Serena propagation line and the assertion will fail for the wrong reason. Verify Serena availability in the eval workspace before interpreting failures.

## Interpreting results

| Variance result | Interpretation |
|---|---|
| All 3 assertions `stable` | Subagent propagation works as designed. |
| Assertion 1 (`task\|explore\|subagent\|spawn`) flaky/broken | Claude is not interpreting the prompt as a Task-spawn request. Reword the user prompt; the test is not measuring propagation yet. |
| Assertion 2 (Serena reference) `flaky` | Propagation works some of the time. Treat as weak signal — banner instruction is not load-bearing on its own. |
| Assertion 2 `broken` | Propagation is failing in practice. The 14-day revival evaluation should not assume subagent inheritance via banner; weight in-band Grep-nudge coverage instead. |
| Assertion 3 (user task carried) flaky/broken | Spawn prompts are too generic. Independent of propagation but worth investigating. |

Fixture is intentionally narrow — one scenario, one mechanism. Routing-correctness ("does Claude actually use Serena when nudged?") is left to telemetry rather than synthetic evals; see `scripts/serena-telemetry-report.sh`.
