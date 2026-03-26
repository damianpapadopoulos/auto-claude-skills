# Incident Analysis Skill Improvements — Design Document

**Date:** 2026-03-26
**Origin:** Review of oviva-ag/claude-code-plugin PR #38 (incident-investigation consolidation)
**Method:** Multi-Agent Debate (architect, critic, pragmatist — 2 rounds) + iterative refinement

## Problem Statement

Our `incident-analysis` skill is a proven monolithic pipeline (~450 lines) handling the
full incident lifecycle: MITIGATE → CLASSIFY → INVESTIGATE → EXECUTE → VALIDATE → POSTMORTEM.
PR #38 in the oviva-ag repo attempted to consolidate this with their incident-response skill
into a multi-agent architecture (5 agents, 7 playbooks, 24 signals). Review identified both
improvement opportunities and anti-patterns.

Key finding: the skill's existing CLASSIFY → INVESTIGATE handoff has a cascade stall risk
where CLASSIFY commits to a high-confidence wrong hypothesis (false clarity), causing
30-40 seconds of wrong-lane investigation before the contradiction test (Step 5) catches it.

## Recommended Approach

Selective enhancement of the monolithic pipeline with a bounded disambiguation mechanism.
No architectural overhaul.

---

## Ship Now (PR 1: trivial)

### `/investigate` command

Thin entry-point wrapper that extracts incident context (service, environment, symptoms,
timeframe) from structured invocation, emits a structured preamble pre-populating MITIGATE
scope inputs (service, environment, time window), and hands off to the existing pipeline.
Must not bypass MITIGATE steps (tool detection, inventory, impact quantification). ~30 lines.

**Files:** `commands/investigate.md` (new)

### `slo_burn_rate_alert` signal

New signal in signals.yaml for SLO burn rate alert detection.

```yaml
slo_burn_rate_alert:
  title: "SLO burn rate alert fired"
  base_weight: 30
  detection:
    method: event_presence
    params:
      event_type: AlertFired
      alert_name_pattern: ".*burn.?rate.*"
      recency_window_seconds: 3600
```

**Files:** `skills/incident-analysis/signals.yaml` (edit)

---

## Ship Next (PR 2: disambiguation probes)

### Problem: Cascade Stall via False Clarity

CLASSIFY can produce a confident-looking winner that is wrong. The expensive Single-Service
Deep Dive (SKILL.md line 283) runs scoped to that winner, and the contradiction test doesn't
fire until Step 5 (line 345). That's a 30-40 second window of wrong-lane investigation.

The existing machinery handles the rest: deterministic scoring (line 158), classification_credible
tier (line 180), contradiction collapse (line 186), compatibility gating (compatibility.yaml),
and low-confidence re-entry to CLASSIFY (line 199). The gap is the handoff.

### Solution: Bounded Disambiguation Probes

One cheap read-only query per runner-up, placed before the expensive deep dive, feeding
results back through the existing scorer. No new scoring logic.

#### CLASSIFY Output Changes

**Medium-confidence (60-84) and low-confidence (<60) outputs** include a bounded shortlist:

```
SHORTLIST:
  leader:      bad-release-rollback (85%)
  runner-up-1: dependency-failure (62%), probe: dependency_error_scan
  runner-up-2: config-regression (44%), probe: config_change_scan
  compatibility: [bad-release, dependency-failure] = incompatible
  disambiguation_round: pending
  classification_fingerprint: <service>/<time_window>/<pre_probe_signal_state_hash>
```

The `classification_fingerprint` is derived from the **pre-probe** evidence snapshot — the
signal states as they were before any disambiguation probes ran. This ensures the fingerprint
is stable across the probe → rerank cycle and cannot be bypassed by post-probe state changes.

**High-confidence (>=85) HITL record:** No shortlist. Stays as-is (line 208).

#### Shortlist Eligibility

A candidate qualifies as a runner-up if ALL of:
- Non-vetoed
- Confidence > 40
- evaluable_weight > 0
- Has a declared `disambiguation_probe` on its playbook
- Max 2 runner-ups

#### Medium-Confidence Path

The existing "suggested follow-up queries" (SKILL.md line 264-266) become the shortlisted
probes. No longer free-form LLM suggestions. After probes:
- Probe collects targeted evidence (aggregate-first, not raw logs)
- Existing signal evaluator recomputes affected signal states
- Scorer re-ranks unchanged
- Mark `disambiguation_round: completed` on the handoff artifact
- Normal confidence routing continues (high → HITL, medium → continue as medium, collapse, etc.)

**Post-probe medium-confidence behavior:** After one probe round, the result may still be
medium-confidence. That is fine — the flow continues as normal medium-confidence (present
findings, suggest investigation, etc.) but **without issuing another shortlisted probe round
for the same classification fingerprint.** The anti-looping rule applies to both paths.

#### Low-Confidence Path (Step 2b in INVESTIGATE)

New **Step 2b: Targeted Disambiguation Probes** after Extract Key Signals (line 279),
before Single-Service Deep Dive (line 283). Consumes the shortlist from CLASSIFY's
low-confidence handoff:

1. For each runner-up in the shortlist, execute its `disambiguation_probe` — one query
2. Probe evidence feeds into existing signal evaluator → recomputes signal states
3. Return to CLASSIFY scorer with updated states (one rerun, then continue normal routing)
4. Mark `disambiguation_round: completed` on the handoff artifact

#### Anti-Looping

- At most one probe round per `classification_fingerprint` (service + time_window +
  **pre-probe** signal_state_hash). The fingerprint is computed before probes run and
  carried through the rerank cycle unchanged, preventing post-probe state changes from
  generating a new fingerprint that would legally schedule another round.
- After one round, normal confidence routing continues. No forced winner — if still weak,
  collapse-to-investigate, deep investigation, or user override all remain available.
  Medium-confidence may persist post-probe, but without another probe round.
- Same probe cannot rerun in the same classification cycle. Probe outcomes are cached per
  fingerprint.

#### Probe Behavior

- **Aggregate-first:** Prefer `exists`, `count`, `distinct group count`, `latest timestamp`,
  `top offenders` over raw log entries
- **Payload cap:** `max_results <= 10`, `max_lines <= 20` per probe
- **Handoff storage:** Normalized probe result + 1-2 exemplar lines only
- **Timeout:** Results in `unknown_unavailable` for the target signal. A timed-out probe
  may never strengthen a candidate. Falls through to normal rerank. No changes to scorer math.
  The existing coverage gate (line 165) already handles `unknown_unavailable` exclusion.
- **Probes do not directly mutate signal states.** They collect evidence; the existing signal
  evaluator (line 142) recomputes states from that evidence; the scorer re-ranks unchanged.
- **Probe-to-signal recomputation contract:** A probe's `resolves_signals` declares which
  signal IDs the probe can provide evidence for. The probe result is a normalized aggregate
  (exists/count/latest_timestamp/top_offenders) plus 0-2 exemplar lines. For the evaluator
  to recompute a signal state from probe output, the signal's detection method must be
  satisfiable from aggregates: `event_presence` (→ exists/count), `threshold` (→ metric value),
  `temporal_correlation` (→ timestamps), `log_pattern` (→ match count). Signals requiring
  `distribution` or `ratio` methods cannot be resolved from a single probe query — they
  remain `unknown_unavailable` even if named in `resolves_signals`.

#### Scope Exception

The current scope restriction (SKILL.md line 16) forbids queries outside the identified
service/trace during active investigation. Dependency probes are a bounded exception:

- Allowed only for declared/known dependencies of the identified service
- Same time window as the primary investigation
- Hard cap of one query per runner-up
- Must be declared in the playbook's `disambiguation_probe`, not ad-hoc

#### Playbook Schema

```yaml
# Example: dependency-failure.yaml
queries:
  dependency_error_scan:
    kind: log_query
    description: "ERROR logs from known dependencies in same time window"
    params:
      scope: declared_dependencies
      severity: ERROR
      max_results: 10

disambiguation_probe:
  query_ref: dependency_error_scan
  resolves_signals:
    - upstream_dependency_errors
```

The `disambiguation_probe` field is optional. Playbooks without it are never shortlisted
as runner-ups. The `query_ref` must reference a key in the same playbook's `queries` map.

#### Compatibility Matrix

Unchanged. The closed-world default (compatibility.yaml line 3) applies:
- **Compatible survivors:** Leader plus secondary factor carried into synthesis
- **Incompatible survivors both >=60:** Existing collapse-to-investigate behavior (line 186)
- **Unlisted pairs:** Default incompatible. No implicit compound handling.

New compound pairs require explicit addition to `compatible_pairs` in compatibility.yaml.

#### Tests

- `tests/test-playbook-schema.sh`: Validate for all playbooks with `disambiguation_probe`:
  - `query_ref` cross-references a valid key in the same playbook's `queries` map
  - `resolves_signals` is non-empty and references canonical signal IDs from signals.yaml
  - Referenced probe query declares `max_results` (payload cap present)
  - Referenced probe query kind is read-only (no `kubectl apply/patch/delete/scale`)
  - Any signal in `resolves_signals` using `distribution` or `ratio` detection method
    emits a warning (cannot be resolved from single probe aggregates)
- Spec scenarios: bounded shortlist emission, probe execution, single-round reclassify,
  collapse on incompatible survivors
- Eval fixture: false-clarity case (Service A looks like bad-release at 85%, dependency probe
  reveals upstream failure with dependency-failure scoring >=60. Since `bad-release` and
  `dependency-failure` are unlisted in `compatible_pairs` (default incompatible), reclassify
  triggers contradiction collapse to investigate path — NOT a direct flip to dependency-failure)
- Eval fixture: probe timeout/failure leaves target signal `unknown_unavailable`, does not
  strengthen runner-up
- Eval fixture: after one probe round per fingerprint, CLASSIFY does not issue a second
  shortlist/probe round, continues normal routing
- Eval fixture: dependency probe outside declared dependency scope is rejected by scope
  restriction
- Regression check: high-confidence HITL record unchanged, scorer math and contradiction
  collapse behavior intact

**Files:**
- `skills/incident-analysis/SKILL.md` (edit — CLASSIFY output templates, Step 2b, scope exception)
- `skills/incident-analysis/playbooks/dependency-failure.yaml` (edit — add queries + probe)
- `skills/incident-analysis/playbooks/config-regression.yaml` (edit — add queries + probe)
- `skills/incident-analysis/playbooks/infra-failure.yaml` (edit — add queries + probe)
- `tests/test-playbook-schema.sh` (edit — add disambiguation_probe validation)

---

## Ship Later (PR 3: source code analysis)

### Step 4b: Source Analysis (Conditional) — within INVESTIGATE

**Revised 2026-03-26:** Repositioned from a separate named stage between INVESTIGATE and
EXECUTE to Step 4b within INVESTIGATE, between Step 4 (trace correlation) and Step 5
(hypothesis formation). Rationale: trace correlation can shift investigation to Service B,
making earlier code analysis wasted; code evidence must be available before hypothesis
formation, not after.

- **Placement:** INVESTIGATE Step 4b — runs after Step 4 if trace correlation ran; if
  Step 4 was skipped, runs immediately before Step 5 on the currently scoped service
- **Gate:** Bad-release category only. Triggers when `recent_deploy_detected` signal is
  detected OR deploy timestamp falls within incident window or 4h before incident start.
  Config-regression, dependency-failure, and infra-failure do not trigger Step 4b.
- **Entry conditions:** Actionable stack frame (skip minified/compiled/generated) AND
  resolvable deployed ref
- **Post-hop rule:** If Step 4 shifted investigation to Service B, resolve Service B's
  workload identity from trace/log resource labels, then do one bounded deployment-metadata
  lookup for that workload. If workload identity is ambiguous, skip with reason.
- **Action:** Resolve deployed ref → commit SHA; map 1-2 top stack frames to source files;
  read code at deployed ref (not HEAD); check last 3 commits within 48h for regressions
- **Output contract:**
  ```yaml
  source_analysis:
    status: skipped | reviewed_no_regression | candidate_found | unavailable
    skip_reason: "..." (when status is skipped or unavailable)
    deployed_ref: "v2.3.1"
    resolved_commit_sha: "abc123..."
    source_files:
      - path: "src/.../UserController.java"
        line: 142
        code_context: "user.toDto()  // NPE if null"
        status: analyzed | not_found | access_denied
    regression_candidates:
      - commit_sha: "def456..."
        summary: "removed null check in getUser()"
        files: ["UserController.java"]
  ```
- **Bounded evidence:** Relevant hunk + context only, never full files or diffs
- **Failure:** Fail-open with explicit warning. Not silent.
- **Token budget:** SKILL.md holds ~15-20 lines inline + reference pointer. Full procedure
  in `references/source-analysis.md`, loaded only when active.
- **Tests:** Positive assertion `### Step 4b` before `### Step 5` (line-number comparison
  with `assert_not_empty` guards), negative assertion `## SOURCE_ANALYSIS` does not exist
  as separate stage

**Gate:** At least one real incident fixture must exercise Step 4b before shipping.

**Files:**
- `skills/incident-analysis/SKILL.md` (edit — add Step 4b within INVESTIGATE)
- `skills/incident-analysis/references/source-analysis.md` (new)
- `tests/test-skill-content.sh` (edit — ordering + negative assertions)

---

## Ship Later (PR 4: eval runner)

### Routing Accuracy Tests

Add incident-analysis routing cases to `tests/test-routing.sh`. Assert SLO burn rate,
node resource exhaustion, and service latency prompts route correctly.

### Output Quality Tests

New `tests/test-incident-analysis-output.sh` with fixtures from real incident postmortems.
Ground truth must be human-authored from real incidents, not derived from current skill outputs.

**Gate:** Fixtures from real incident postmortems only. No synthetic cases authored by the
skill developer.

**Files:**
- `tests/test-routing.sh` (edit)
- `tests/test-incident-analysis-output.sh` (new)
- `tests/fixtures/incident-analysis/*.json` (new)

---

## ~~Ship Later (PR 5: K8s signals)~~ — DROPPED (already exists)

The proposed `node_resource_exhaustion_signal` and `pod_crashloop_backoff` signals already
exist in `signals.yaml` under their canonical IDs:
- `node_memory_overcommit` (line 119) — same metric, same threshold, same sustained duration
- `crash_loop_detected` (line 197) — same event type and recency window
- Plus 5 additional K8s infrastructure signals: `multi_pod_probe_timeout` (line 102),
  `kubelet_housekeeping_degraded` (line 132), `kernel_memory_pressure` (line 143),
  `memory_underrequested` (line 159), `node_metrics_normal` (line 171)

No new K8s signals needed. The debate's original concern (playbooks firing on heuristics)
is already addressed by the existing signal vocabulary.

---

## Rejected

### Multi-Agent Parallel Architecture — KILL (unanimous)

The causal chain — log finding → targeted k8s query → targeted metric query → hypothesis —
is the core value of the skill. Parallel agents break this chain. The coordinator synthesis
problem (reconciling independent findings without shared context) produces lower-quality
hypotheses than sequential investigation that carries context forward.

Wall-clock savings ~0-10 seconds (tool execution is ~30-60s total, agent spawn overhead
negates gains). Context budget 3-4x higher. Investigation breadth under time pressure is
better served by disambiguation probes than by spawning agents.

### K8s MCP Tool Interface — DEFER

kubectl via Bash is stateless and works. MCP only justified for interactive/stateful
capabilities. **Revisit trigger:** K8s incident postmortem showing heuristic analysis
missed or significantly delayed root cause.

---

## Deferred

### Hybrid Decomposition (Decouple MITIGATE/POSTMORTEM)

Decouple MITIGATE and POSTMORTEM as independent concerns (separate trigger, context budget,
evolution path) while keeping CLASSIFY+INVESTIGATE monolithic. Not urgent — the monolith
isn't causing concrete problems yet.

**Revisit trigger:** SKILL.md exceeds ~600 lines.

---

## Dissenting Views (from design debate)

- **Critic:** Cascade stall remains partially unmodeled. Disambiguation probes address the
  most common false-clarity cases but cannot catch all wrong-lane commits. The only full
  solution would be maintaining a true differential through INVESTIGATE, which was rejected
  as over-engineering given the existing contradiction test at Step 5.
- **Critic:** Hybrid decomposition deserves more thought than "defer." POSTMORTEM templating
  and MITIGATE decision trees consume tokens that could be freed.
- **Pragmatist:** Source code analysis should only ship with a real incident case validating
  need, not just structural fixtures.

## Trade-offs Accepted

1. **Prompt-driven probe triggering** — shortlist eligibility is deterministic but the
   probe execution is prompt-driven. Less predictable than pure code. Mitigated by
   aggregate-first payloads, payload caps, and single-round constraint.
2. **Token cost of new stages/signals** — reference-file pattern (load on demand) mitigates.
3. **Evals ground truth discipline** — requires real incident data, slower fixture authoring.
4. **Probes cannot catch all false-clarity cases** — only candidates with declared
   `disambiguation_probe` are shortlisted. Novel failure modes still require Step 5
   contradiction test. Accepted as the right trade-off vs. full differential rewrite.

## Assumptions

1. "Declared/known dependencies" come from already-available service metadata, manifests,
   or prior scoped evidence. V1 does not invent a new dependency discovery subsystem.
2. Probe execution stays in one agent. Separate subagents are explicitly out of scope because
   they add coordination overhead without improving the causal investigation chain.
3. If later latency optimization is needed, probe I/O may be parallelized within the same
   agent, but that is not part of this change.
4. Signals requiring `distribution` or `ratio` detection methods cannot be resolved from
   single probe queries — they remain `unknown_unavailable` if named in `resolves_signals`.

## Shipping Order

| # | Scope | Effort | Gate |
|---|-------|--------|------|
| 1 | `/investigate` command + `slo_burn_rate_alert` signal | ~1 hour | None |
| 2 | Disambiguation probes: CLASSIFY shortlist, Step 2b, playbook probes, schema tests | ~2 days | Schema + spec scenarios |
| 3 | Eval runner + routing tests + output quality fixtures | ~1 day | Fixtures from real incidents |
| 4 | SOURCE_ANALYSIS stage + source-analysis.md | ~1-2 days | Real incident fixture (uses PR 3 runner) |
| 5 | Hybrid decomposition | TBD | SKILL.md > 600 lines |
| 6 | K8s MCP tool interface | TBD | K8s postmortem showing heuristic failure |

PR 3 (eval runner) must land before PR 4 (SOURCE_ANALYSIS) because the source analysis gate
requires a real incident fixture, which needs the eval runner to execute.

~~K8s signals~~ dropped — signals already exist under canonical IDs.
