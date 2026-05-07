# Routing-test stub

Minimal placeholder used as `SKILL_PATH` for Serena routing/propagation evals.
Behavioral-eval runner injects this into a `<skill_guidance>` wrapper around the
user request. We pass a near-empty stub here because the test is about
hook-driven routing, not skill-content compliance — we do not want
incident-analysis or another rich skill steering Claude into an unrelated
workflow during the eval.

When given a request, use the most appropriate tools available to answer it.
