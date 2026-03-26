# Remediation Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the incident-analysis skill from recommending configuration that's already in place, by expanding the inventory step and adding a "Current State" forcing function to action items.

**Architecture:** Three targeted edits to `skills/incident-analysis/SKILL.md` — inventory expansion (Step 2b), action item format update (Section 3 template + Step 3 generation instruction), and a tiered retrieval fallback note. TDD per writing-skills: baseline test first, then edits, then verification.

**Tech Stack:** Bash (SKILL.md is markdown guidance), subagent testing

**Spec:** `docs/superpowers/specs/2026-03-26-remediation-verification-design.md`

---

### Task 1: RED — Baseline test (verify the gap exists)

**Files:**
- Read: `skills/incident-analysis/SKILL.md`

- [ ] **Step 1: Run baseline pressure scenario**

Dispatch a subagent with the current SKILL.md content and this scenario prompt:

```
You are following the incident-analysis skill to write a postmortem.

Context: backend-core in namespace production experienced pod co-location on node gke-prod1-pool-a1b2c3.
3 of 7 pods landed on the same node, which then ran out of memory.

The deployment has these scheduling constraints (from kubectl get deploy backend-core -o json):
- topologySpreadConstraints: maxSkew=1, topologyKey=kubernetes.io/hostname, whenUnsatisfiable=ScheduleAnyway
- affinity: {} (empty)

The synthesized investigation summary includes:
- 7 replicas, distributed across 4 nodes (3 on gke-prod1-pool-a1b2c3, 2 on pool-d4e5f6, 1 each on pool-g7h8i9 and pool-j0k1l2)
- Node gke-prod1-pool-a1b2c3 had 92% memory utilization
- Root cause: node memory overcommit with pod co-location amplifying blast radius

Generate ONLY the Action Items section (Section 3) of the postmortem, following the SKILL.md template.
```

- [ ] **Step 2: Document baseline behavior**

Record verbatim:
1. Does the output include a "Current State" column? (Expected: NO)
2. Does any action item recommend "add podAntiAffinity" or similar scheduling change? (Expected: YES)
3. Does any action item reference the existing topologySpreadConstraints? (Expected: NO or only incidentally)

This is the RED state — the skill produces a redundant recommendation.

- [ ] **Step 3: Commit baseline results**

```bash
git add docs/superpowers/plans/2026-03-26-remediation-verification.md
git commit -m "test(incident-analysis): RED baseline for remediation verification gap"
```

---

### Task 2: GREEN — Apply the three SKILL.md changes

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:89-93` (Step 2b inventory)
- Modify: `skills/incident-analysis/SKILL.md:513-516` (Section 3 template)
- Modify: `skills/incident-analysis/SKILL.md:624` (Step 3 generation instruction)

- [ ] **Step 1: Expand Step 2b inventory with scheduling constraints**

In `skills/incident-analysis/SKILL.md`, after line 91 (`- What are the resource requests, limits, and probe configurations?`), add:

```markdown
- For k8s workloads: scheduling constraints — pod affinity/anti-affinity rules, topologySpreadConstraints, node affinity, taints and tolerations. Query from the same deployment spec used for resource requests. If kubectl is unavailable, check GitOps manifests via `gh api` or `git show` as fallback.
```

- [ ] **Step 2: Add interpretation hint after Step 2b explanation**

In `skills/incident-analysis/SKILL.md`, after line 93 (the paragraph ending "...equivalent inventory query."), add:

```markdown
Note: topologySpreadConstraints and podAntiAffinity both control pod distribution — if either is present, the workload has scheduling constraints. Distinguish enforcement level: soft (ScheduleAnyway, preferredDuringScheduling) vs hard (DoNotSchedule, requiredDuringScheduling).
```

- [ ] **Step 3: Add tiered retrieval fallback after the interpretation hint**

Immediately after the note added in Step 2, add:

```markdown
When live cluster access is unavailable for inventory or action item verification, fall back to GitOps manifests (`gh api repos/ORG/REPO/contents/PATH` or `git show`) to check deployment configuration. If neither is available, flag affected inventory fields and action items as unverified.
```

- [ ] **Step 4: Update Section 3 action items template**

In `skills/incident-analysis/SKILL.md`, replace line 516:

```
Include: priority, action, owner, due date, status.
```

With:

```
Include: priority, action, current state, owner, due date, status.
```

- [ ] **Step 5: Update Step 3 generation instruction**

In `skills/incident-analysis/SKILL.md`, replace line 624:

```
- Action items: ordered by priority, each with suggested owner and due date. Flag unassigned items with "⚠ Owner needed"
```

With:

```
- Action items: ordered by priority, each with current state, suggested owner, and due date. "Current state" describes the relevant existing configuration or deployed state for the system the action item targets — what is there today, not what should be. Check for functionally equivalent configurations, not just exact field matches. If current state cannot be determined, state "⚠ Not verified against live config." Flag unassigned items with "⚠ Owner needed"
```

- [ ] **Step 6: Syntax-check SKILL.md**

Run: `bash -n skills/incident-analysis/SKILL.md 2>&1 || echo "Not a bash file, skip"`

Verify the file is valid markdown by checking it renders:
```bash
head -5 skills/incident-analysis/SKILL.md
```
Expected: YAML frontmatter intact.

- [ ] **Step 7: Commit changes**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add remediation verification — inventory expansion + current state field"
```

---

### Task 3: GREEN — Run the same scenario with updated SKILL.md

**Files:**
- Read: `skills/incident-analysis/SKILL.md` (updated)

- [ ] **Step 1: Run the same pressure scenario from Task 1**

Dispatch a subagent with the UPDATED SKILL.md and the identical scenario prompt from Task 1, Step 1.

- [ ] **Step 2: Verify GREEN behavior**

Check the output:
1. Does the output include a "Current State" column? (Expected: YES)
2. Does any action item's "Current State" reference the existing topologySpreadConstraints? (Expected: YES)
3. Is the podAntiAffinity recommendation either dropped or reframed as "investigate why existing constraints didn't prevent co-location"? (Expected: YES)

If all three pass, GREEN is achieved.

- [ ] **Step 3: If GREEN fails, diagnose and adjust**

If the agent still produces a redundant recommendation:
- Check if it captured scheduling constraints in its inventory reasoning
- Check if "Current State" was filled with a generic value instead of the actual config
- Adjust the SKILL.md wording to be more specific and re-test

---

### Task 4: REFACTOR — Close loopholes

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` (if loopholes found)

- [ ] **Step 1: Test loophole — exact field match vs functional equivalence**

Dispatch a subagent with the updated SKILL.md and a VARIANT scenario:

```
Same as the base scenario, but the action item draft says:
"Add podAntiAffinity with preferredDuringSchedulingIgnoredDuringExecution for hostname topology"

The deployment has topologySpreadConstraints (maxSkew=1, kubernetes.io/hostname, ScheduleAnyway) but NO podAntiAffinity field.

Generate the Action Items section. Does your "Current State" column recognize topologySpreadConstraints as functionally equivalent to the proposed podAntiAffinity?
```

Expected: The agent recognizes the functional equivalence and either drops the item or notes the existing constraint in "Current State."

- [ ] **Step 2: Test loophole — "not verified" lazy default**

Dispatch a subagent with a scenario where kubectl IS available but the agent might skip verification:

```
Same base scenario. kubectl is available and the deployment spec has been queried.
The topologySpreadConstraints are in your inventory.

Generate action items. Every action item targeting deployed infrastructure MUST have a specific "Current State" value derived from the inventory, not "⚠ Not verified."
```

Expected: Agent fills in specific config values, not the unverified fallback.

- [ ] **Step 3: If loopholes found, patch SKILL.md and re-test**

Add explicit guidance to close any loopholes discovered. Commit:

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "refactor(incident-analysis): close remediation verification loopholes"
```

---

### Task 5: Run project tests

**Files:**
- Run: `tests/run-tests.sh`

- [ ] **Step 1: Run the full test suite**

```bash
bash tests/run-tests.sh
```

Expected: All tests pass. The SKILL.md changes are markdown content — they don't affect routing, registry, or context formatting.

- [ ] **Step 2: Verify routing is unaffected**

```bash
bash tests/test-routing.sh
```

Expected: All routing tests pass. incident-analysis skill routing triggers are unchanged.

- [ ] **Step 3: Commit test results confirmation**

No commit needed if tests pass — the SKILL.md edit commit from Task 2 is the deliverable.
