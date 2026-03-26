# Design Debate: Parallel Sub-Agents for Incident Analysis

**Date:** 2026-03-26
**Status:** Decision reached — DO NOT BUILD
**Trigger:** Review of oviva-ag/claude-code-plugin#38 (multi-agent incident investigation)

## Problem Statement

Should our sequential single-agent incident-analysis skill adopt parallel sub-agents for the initial data sweep (MITIGATE/early-INVESTIGATE), similar to Oviva's 5-agent architecture (coordinator + logs + kubernetes + metrics + code)?

## Debate Participants

| Role | Initial Position | Final Position |
|------|-----------------|----------------|
| Architect | Selective parallelism for data collection (medium confidence) | Conceded: pre-fetch bash pack only (high confidence against multi-agent) |
| Critic | Net negative (high confidence) | Maintained: no change required, bash pack if anything (high confidence) |
| Pragmatist | Against (high confidence) | Maintained: no change required, bash pack if anything (high confidence) |

## Decision: Do Not Adopt Parallel Sub-Agents

Unanimous after Round 2. The multi-agent architecture is rejected on three independent grounds:

### 1. Wall-Clock Math Doesn't Work

- Agent spawn overhead: 5-10s per agent × 3 = 15-30s before any query fires
- Each agent: parse instructions + plan queries + execute + reason + generate structured output ≈ 30-60s
- Coordinator synthesis: 15-30s
- **Parallel total: ~75-105s**
- **Sequential total: ~60-90s** (6-15s I/O + incremental reasoning)
- Net gain: zero to negative

### 2. RCA Accuracy Loss Is Concrete

Three scenarios where parallel agents produce worse outcomes:

**A. OOMKilled + memory leak:** Sequential agent sees OOMKilled, immediately queries container RSS growth slope — diagnoses leak vs limit misconfiguration. Parallel: metrics agent queries without knowing which growth rate to look for. Coordinator must infer what neither sub-agent confirmed.

**B. Node pressure + pod scheduling skew:** Sequential agent finds 6 pods on one node, immediately queries that specific node's resources. Parallel: metrics agent queries cluster-wide averages because it doesn't know which node to target.

**C. Cascading failures:** Temporal sequence across services is the cascade signature. Sequential agent sees Service A errors, pulls Service B's inbound traffic. Parallel: two agents each report errors independently — coordinator lacks temporal sequence for causality determination.

These aren't edge cases — they're the exact incidents this skill was built for.

### 3. Complexity/Frequency Ratio Is Unfavorable

- Implementation: 4-5 agent files × ~150 lines + coordinator + schema + error handling ≈ 800-1000 new lines, 8-12 hours
- Time saved per incident: 2-4 minutes on a 30-60 minute investigation
- At 3 incidents/month: **payback period 20-30 months**
- Testing gap: 3am P1 becomes first real integration test
- Maintenance: signal changes become 3-file coordination problem

## Dissenting Views

None remaining after Round 2. The architect's initial proposal (selective parallelism for data collection, reasoning stays sequential) was withdrawn after conceding the wall-clock math and RCA accuracy arguments.

## Alternative Considered: Bash Pre-Fetch Pack

All three converged on this as the only justified change, if any change is made:

- Run 3-4 parallel bash queries at MITIGATE entry (`&` + `wait`)
- Pod status, recent events, error log count, deployment history
- Returns raw data before any LLM reasoning begins
- Near-zero spawn overhead (bash, not Agent dispatch)
- No new files, no schema contract, no sub-agent coordination
- Implementation: ~1-2 hours, single prompt section addition

**Current recommendation:** No change required. The current skill is functionally sound for 1-5 incidents/month. The bash pre-fetch is available as a low-cost improvement if serial I/O during MITIGATE proves to be a real bottleneck — it hasn't been reported as one.

## Rejected Proposals

| Proposal | Rejected Because |
|----------|-----------------|
| Full multi-agent (Oviva-style) | All three grounds above |
| Selective parallelism (architect R1) | Wall-clock neutral, RCA accuracy loss on key scenarios |
| Single-agent parallel Agent sub-calls (pragmatist R1) | Re-introduces premature synthesis; pragmatist withdrew own proposal |
| Evidence_ref pointer system | Premature complexity; add only if real incidents demonstrate need |
| Domain-specialist summarization at Step 7 | Solves different problem (postmortem quality); orthogonal to parallel agents question |

## Key Insight

The real value proposition was never speed — it was context hygiene (starting CLASSIFY with 2-3K structured signal vs 15-20K raw output). But context hygiene is achievable without agents, via the existing behavioral constraints (Constraint 4: context discipline, synthesized summaries) or a simple bash pre-fetch. The sub-agent architecture is an expensive mechanism for a problem that has cheaper solutions.
