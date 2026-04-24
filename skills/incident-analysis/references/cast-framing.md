# CAST framing — mental-model gaps, systemic factors, hindsight-bias language

One-pager reference for Step 7 (synthesis) items 9–10 and the Step 8 completeness gate Q12. Keep synthesis prose grounded in evidence; use this file for definitions, shape, and replacement patterns.

## Why this exists

CAST (Causal Analysis based on Systems Theory) reframes the three gaps the standard postmortem template under-covers:

1. **Mental-model gaps** — what controllers (humans or automation) *believed* vs. what was true. Action items often imply a belief was wrong; naming the belief makes the correction targetable (runbook, training, dashboard redesign) rather than code-only.
2. **Systemic factors** — the 5 categories below. The standard template surfaces some piecemeal; CAST forces a check of all 5.
3. **Hindsight-bias language** — "should have", "failed to", etc., presented as guidance after the fact but inaccessible to the controller in the moment. Replace with evidence-grounded framing.

## The 5 systemic-factor categories

Answer each in the postmortem (Section 6) and in Step 7 synthesis (item 10). If a category genuinely does not apply, write `N/A — <reason>`. A bare "N/A" blocks Q12 per the completeness-gate resolution rule.

### Safety Culture
**Definition:** Implicit norms, assumptions, and priorities that shape how risk is evaluated and acted on during normal operations.
**Example:** "Deploys that pass CI and survive a 24h post-deploy window are assumed safe. Pool saturation was not treated as a safety-critical state during deployment windows."

### Communication/Coordination
**Definition:** Channels, handoffs, and shared awareness between controllers (teams, services, automation). Gaps in who-knows-what or who-signals-whom.
**Example:** "FluxCD deployed goal-setting with no channel to observe live backend-core health. No coordination between deployment automation and runtime signals."

### Management of Change
**Definition:** Processes governing how changes (deploys, config, schema, dependencies) are introduced, observed, and rolled back. Soak windows, change windows, rollback playbooks.
**Example:** "The April 7 deploy's effects manifested 36h later. No post-deploy soak-window monitoring process exists org-wide."

### Safety Information System
**Definition:** The observability stack operators depend on to perform their control role — dashboards, alerts, logs, SLOs. Gaps where the controller is missing information needed to detect or diagnose.
**Example:** "Pool-utilization metrics absent from the backend-core dashboard. Operators could not observe the saturating resource that caused the outage."

### Environmental Change
**Definition:** Drift in traffic, data shape, dependency behavior, or ambient load that moved the system into a higher-risk state without an explicit signal.
**Example:** "Traffic growth and accumulated N+1 patterns in a newly-active endpoint pushed pool utilization into a regime the service had never operated in."

## Mental-model-gap shape

One bullet per relevant controller (human or automation) in Step 7 item 9 and in postmortem Section 7:

```
<controller> believed <X>; actual was <Y>.
```

**Examples:**

- *backend-core team* believed *deploys that survive 24h post-deploy are safe*; actual was *saturation effects can manifest 36h later after traffic ramps on a new endpoint*.
- *frontend error-handling logic* believed *a 502 response means the session is invalid*; actual was *502 can indicate transient infrastructure failure during pod termination — the session is still valid after retry*.

**Rule:** The existence of a postmortem action item is evidence that some controller's prior belief was wrong. Name the belief explicitly. If you can't name it, you haven't identified the controller whose model the action item updates.

**`N/A`** is acceptable only when the incident has a single controller whose model was correct (pure hardware failure, external dependency outage with no diagnostic ambiguity). State the reason.

## Hindsight-bias language — list and replacements

These phrases smuggle omniscience into the narrative. Replace them with evidence-grounded shapes.

| Hindsight phrase | Why it's biased | Evidence-grounded replacement |
|---|---|---|
| `should have <Xed>` | Implies the controller had the information to act differently in the moment. | "Controller's model at T was <Y>; evidence that would have prompted <X> was <where it lived / why it wasn't visible>." |
| `failed to <X>` | Blames the controller for an outcome visible only in retrospect. | "Controller did <actual action>. The path to <X> required <information/tool/signal that was absent>." |
| `could have easily <X>` | Claims low cost that would be obvious only after knowing the cause. | "After the cause is known, <X> is low-cost. At incident time, the cause was unknown; candidate actions included <list>." |
| `obviously <X>` | Pretends the conclusion was available before the investigation. | "The investigation established <X> after checking <evidence>." |
| `it was clear that <X>` | Same as "obviously". | "Evidence for <X> came from <source> at T+<duration>." |

**Self-check at Step 7 synthesis:** scan the prose for the left-column phrases. If any remain, either rewrite with the right-column shape or move the claim to an open question if the evidence isn't there.

**Reviewer check in postmortem:** the postmortem template section 7 ends with a "Hindsight-bias check" reminder. A reviewer who sees a left-column phrase should ask for the replacement or for the supporting evidence.

## Minimal-viable output

For incidents where the CAST framing genuinely adds nothing (e.g., a 5-minute config typo caught immediately), the Step 7 output can look like:

```
Mental model gaps:
- N/A — single controller (deploying engineer), belief was correct; rollback took <2 min.

Systemic factors:
- Safety Culture: N/A — ad-hoc change outside normal deploy flow.
- Communication/Coordination: N/A — single engineer, no cross-team handoff involved.
- Management of Change: Config change bypassed PR review; no pre-merge lint caught the typo.
- Safety Information System: Alert fired within 90s; detection path worked.
- Environmental Change: N/A — no traffic/data-shape change involved.
```

Each category must have either a non-empty observation or `N/A — <reason>`. Bare `N/A` blocks Q12.

**Token equivalence:** `N/A — <reason>`, `N/A - <reason>` (ASCII hyphen), and `not_applicable — <reason>` are all accepted by the Q12 gate. What blocks closure is a bare token with no reason: `N/A`, `not_applicable`, `N/A —`, or equivalent empty-reason forms.
