# Remediation Verification for Incident-Analysis Skill

**Date:** 2026-03-26
**Status:** Approved (design debate completed)
**Scope:** SKILL.md edits only (~15 lines), no playbook or schema changes

## Problem Statement

The incident-analysis skill generates postmortem action items without verifying whether the recommended configuration is already in place. This produces incorrect recommendations that waste engineering time and undermine trust in the postmortem process.

**Motivating example:** The 2026-03-24 backend-core postmortem recommended "Add podAntiAffinity (preferred, hostname topology)." An engineer reported that pod distribution was already configured via `topologySpreadConstraints` with `maxSkew: 1`, `topologyKey: kubernetes.io/hostname`, `whenUnsatisfiable: ScheduleAnyway`. The investigation never checked existing scheduling config.

## Root Cause Analysis

Two gaps caused the bad action item:

1. **Inventory gap:** Step 2b captures replicas, distribution, resources, and probes, but not scheduling constraints (affinity, topology spread, PDBs, taints/tolerations). The investigation saw pods co-located and jumped to "add anti-affinity" without checking what was already in place.

2. **Interpretation gap:** Even if scheduling data had been captured, no guidance helps the agent recognize that `topologySpreadConstraints` and `podAntiAffinity` serve overlapping purposes. The failure was interpretation, not just collection.

## Design Decisions (from MAD debate)

### Inventory strategy: Option A (always-on)

**Decided:** Expand Step 2b to always capture scheduling constraints for k8s workloads.

**Rejected alternatives:**
- Option B (classification-driven): Fragile — CLASSIFY runs after inventory, creating a chicken-and-egg problem. Scheduling config is relevant to 4 of 6 playbook categories, making conditional gating nearly universal anyway.
- Option C (hybrid with triggered extensions): Temporal ordering problem — signals to trigger extensions aren't available at Step 2b time. Would require a backtrack to re-run inventory, strictly worse than always-on.

**Rationale:** The deployment JSON is already fetched in Step 2b for resource requests. Extracting affinity and topologySpreadConstraints from the same JSON is zero incremental queries. One bullet point of markdown guidance.

### Verification mechanism: "Current State" field

**Decided:** Add a "Current State" field to the action items format in POSTMORTEM Step 3.

**Rejected alternatives:**
- Formal verification gate (POSTMORTEM Step 2.5 with REDUNDANT/PARTIAL/ABSENT/UNVERIFIABLE taxonomy): Overkill for guidance text. The formal classification adds machinery without proportional benefit over a forcing function.
- Simple cross-reference instruction (3 lines): Too vague — an LLM may comply inconsistently without structured output.

**Rationale:** "Current State" is a forcing function: writing "topologySpreadConstraints configured" next to "Add podAntiAffinity" makes the contradiction self-evident. Forces the agent to show its work. Achieves the same outcome as a formal gate through template structure.

**Dissenting view preserved:** The architect argued that "Current State" alone may be filled inconsistently without structured verification steps. If future postmortems show vague entries, upgrade to the architect's structured sub-step approach.

### No Constraint 4b exception needed

Inventory data already flows into the POSTMORTEM via the Step 7 synthesized summary (line 366: "Inventory and impact"). The agent reads its own synthesis during postmortem generation — no new live queries during POSTMORTEM required.

### Tiered retrieval for verification

When querying current state (in Step 2b inventory or when verifying action items):
1. **kubectl** — live cluster query (deployment spec, PDB, HPA)
2. **GitOps fallback** — `gh api` or `git show` against deployment manifests when kubectl is unavailable
3. **Flag as unverified** — "Not verified against live config" when neither is available

## Specification: Three Changes to SKILL.md

### Change 1: Step 2b inventory expansion

Add to the existing Step 2b bullet list:

```markdown
- For k8s workloads: scheduling constraints — pod affinity/anti-affinity rules, topologySpreadConstraints, node affinity, taints and tolerations. Query from the same deployment spec used for resource requests. If kubectl is unavailable, check GitOps manifests via `gh api` or `git show` as fallback.

Note: topologySpreadConstraints and podAntiAffinity both control pod distribution — if either is present, the workload has scheduling constraints. Distinguish enforcement level: soft (ScheduleAnyway, preferredDuringScheduling) vs hard (DoNotSchedule, requiredDuringScheduling).
```

### Change 2: Action item format update

Two locations in SKILL.md reference the action item format:

**Location A — POSTMORTEM Step 3 generation instruction (line ~624):**

Update from:
```
- Action items: ordered by priority, each with suggested owner and due date. Flag unassigned items with "⚠ Owner needed"
```
To:
```
- Action items: ordered by priority, each with current state, suggested owner, and due date. "Current state" describes the relevant existing configuration or deployed state for the system the action item targets — what is there today, not what should be. Check for functionally equivalent configurations, not just exact field matches. If current state cannot be determined, state "⚠ Not verified against live config." Flag unassigned items with "⚠ Owner needed"
```

**Location B — POSTMORTEM Section 3 template description (line ~514):**

Update from:
```
Include: priority, action, owner, due date, status.
```
To:
```
Include: priority, action, current state, owner, due date, status.
```

### Change 3: Tiered retrieval note

Add after the Step 2b changes:

```
When live cluster access is unavailable for inventory or action item verification, fall back to GitOps manifests (gh api repos/ORG/REPO/contents/PATH or git show) to check deployment configuration. If neither is available, flag affected inventory fields and action items as unverified.
```

## Testing Strategy (TDD per writing-skills)

### RED (baseline): Reproduce failure without changes

Scenario: Give a subagent the current SKILL.md and a simulated incident where backend-core pods are co-located on a node. The deployment already has topologySpreadConstraints configured. Verify the agent:
- Does NOT capture scheduling constraints in inventory
- Recommends "add podAntiAffinity" without checking existing config
- Produces action items without "Current State" field

### GREEN: Apply changes, re-run scenario

Same scenario with updated SKILL.md. Verify the agent:
- Captures topologySpreadConstraints in inventory
- Includes "Current State" in action items showing existing config
- Either drops the redundant recommendation or reframes it

### REFACTOR: Close loopholes

Check for rationalizations:
- Agent captures scheduling config but doesn't reference it in action items
- Agent fills "Current State" with "none" without actually checking
- Agent checks exact field match (podAntiAffinity: absent) but misses functional equivalent (topologySpreadConstraints)
