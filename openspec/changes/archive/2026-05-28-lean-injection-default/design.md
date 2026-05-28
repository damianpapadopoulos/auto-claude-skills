# Design: Lean Injection Tier as Default

## Architecture

`_format_output()` selects an injection-verbosity tier by conversation depth and selected-skill count. The prompt-1 / 3+-skill branch previously rendered a verbose template (Step-1/2/3 scaffold + registry-derived phase-guide table). This change inverts that branch's default:

- **Default (no env):** lean render — `SKILL ACTIVATION` header, `${SKILL_LINES}` (carrying `MUST INVOKE` + `Skill(...)`), composition chain/lines, the "You MUST print a brief evaluation" directive, eval `**Phase:**` line, domain hint, composition directive. The scaffold and phase guide are omitted.
- **`SKILL_VERBOSE=1`:** verbose render — the prior full template, including the phase-guide table built from `REGISTRY.phase_guide`.

The existing `SKILL_VERBOSE=1 → _PROMPT_COUNT=1` override (forces the full-tier branch at any depth) composes correctly: it routes into this branch and the inner `${SKILL_VERBOSE:-0}` check then selects the verbose render.

## Dependencies

None. Pure Bash/jq display-layer change. No new packages, APIs, or registry-shape changes.

## Decisions & Trade-offs

- **Why ship directly (not behind a behavioral A/B):** a debate + Codex sparring pass established that a model-in-loop compliance experiment (Phase 1) was disproportionate (~2 days + millions of tokens) to a once-per-session 217-token prize, and the existing behavioral-eval harness could not even exercise the hook injection (it inlines SKILL.md, not hook output). A deterministic test proves the lean variant retains all compliance-carrying text, bounding the residual risk to a single prompt per session.
- **Why `SKILL_VERBOSE` as the gate (not a new flag):** `SKILL_VERBOSE` already means "force the full experience" and already forces `_PROMPT_COUNT=1`. Reusing it as the verbose render selector minimizes config surface and gives an instant rollback hatch.
- **Rejected — Phase 1 behavioral experiment:** parked; revival trigger is observed invocation-compliance regression in real use.
- **Rejected — keep `SKILL_LEAN_TIER` measurement flag:** replaced by the inverted `SKILL_VERBOSE` default; a standalone lean flag was redundant once lean became the default.

## Implementation Notes (synced at ship time)

- Measurement (`build a secure frontend component and review it for security`, real 37-skill registry): verbose 3314 bytes / lean 2443 bytes / saving 871 bytes (~217 tokens, 26%). Reproducible 3×.
- Code review (pr-review-toolkit:code-reviewer) found no critical/important issues; one low cosmetic (cleanup-trap stderr noise) fixed.
