---
name: prototype-lab
description: Produce 3 thin comparable variants of a proposed design with a comparison artifact and mandatory Human Validation Plan
---

# Prototype Lab

Build exactly 3 thin, comparable variants of a proposed design so the user can evaluate concrete alternatives before committing to a direction.

## When to Use

During DESIGN phase when competing approaches are identified. Fires on trigger match alongside brainstorming (which remains the process driver). The user or DESIGN phase guidance may suggest prototyping; this skill does not depend on brainstorming internally escalating to it.

**Relationship to design-debate:**
- design-debate **reasons** about options (3 agents argue)
- prototype-lab **builds** comparable artifacts (3 thin variants)
- They are complementary. design-debate can precede prototype-lab.

## Step 1: Identify Variant Scope

Determine what "a variant" means for this project:

| Project type | Variant contents |
|-------------|-----------------|
| New skill | SKILL.md draft + routing entry + one behavioral test |
| New hook | Script draft + config entry + one syntax test |
| New feature | Implementation sketch + one test |
| Architecture decision | Thin proof-of-concept code + one integration test |

Default: 3 variants. User can override ("just compare these 2").

## Step 2: Build Variants

For each variant (A, B, C):
1. Create the minimum artifacts defined in Step 1
2. Keep each variant thin — enough to evaluate the approach, not production-ready
3. Label clearly: **Variant A**, **Variant B**, **Variant C**
4. Note key trade-offs for each

## Step 3: Write Comparison Artifact

Save to `docs/plans/YYYY-MM-DD-<topic>-prototype-lab.md`:

```
# Prototype Comparison: <Topic>

**Date:** YYYY-MM-DD
**Variants:** 3

## Variant A: <Name>
**Approach:** <1-2 sentences>
**Trade-offs:** <pros and cons>
**Artifact:** <path or inline>

## Variant B: <Name>
**Approach:** <1-2 sentences>
**Trade-offs:** <pros and cons>
**Artifact:** <path or inline>

## Variant C: <Name>
**Approach:** <1-2 sentences>
**Trade-offs:** <pros and cons>
**Artifact:** <path or inline>

## Recommendation
**Chosen:** Variant <X>
**Reasoning:** <why this over the others>

## Human Validation Plan
<REQUIRED — how the user will test the chosen option with real usage>
<AI-simulated testing may inform the draft but never replaces this section>
<Describe: who tests, what they test, what success looks like>

## Success Signals
<What to measure after shipping to confirm the choice was right>
```

## Step 4: Present to User

Show the comparison artifact. Ask the user to choose a variant. Only the chosen variant proceeds to writing-plans. The others are archived in the comparison artifact.

## Constraints

- 3 variants is the default
- Human Validation Plan is mandatory — the skill must not proceed without it
- AI-simulated user testing may inform the draft but never replaces real-user validation
- For auto-claude-skills, "prototype" means repo-native artifacts (SKILL.md, bash scripts, routing config, tests)
- Variants are disposable — only the chosen variant survives
