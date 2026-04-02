# CLASSIFY — Scoring Formula and Decision Records

Reference material for the CLASSIFY stage. The main skill file (`SKILL.md`) contains
the stage overview, playbook discovery, and signal evaluation. This file contains
the scoring mechanics, confidence routing, and decision record templates.

### Scoring Formula

For each candidate playbook:

**Step 1 — Veto check:**
If any `veto_signals` entry has state `detected`, the playbook is disqualified. It cannot be proposed or classified as credible.

**Step 2 — Coverage gate:**
Compute `evaluable_weight = sum of weights for signals with state detected or not_detected`. Compute `max_possible = sum of all signal weights`. If `evaluable_weight / max_possible < 0.70`, the playbook is ineligible for proposal but still appears in the investigation summary.

**Step 3 — Score calculation:**
- `base_score = sum of (base_weight) for each supporting signal with state detected`
- `contradiction_score = contradiction_penalty x count(contradicting signals with state detected)` — `contradiction_penalty` is a single flat value defined per-playbook in its YAML; each detected contradicting signal subtracts this same amount (e.g., penalty=20 with 2 contradictions = -40)
- `raw_score = base_score - contradiction_score`
- `confidence = clamp(0, 100, round(raw_score / evaluable_weight x 100))` (NOT `max_possible`) — this yields a 0-100 integer
- If `evaluable_weight == 0` then `confidence = 0` and the playbook is unscored

**Step 4 — Three-tier eligibility:**

| Tier | Criteria |
|------|----------|
| `proposal_eligible` | Playbook is `commandable` AND no veto AND coverage >= 0.70 AND all `params` resolved AND all `pre_conditions` passed |
| `classification_credible` | No veto AND evaluable_weight > 0 AND coverage >= 0.70 AND confidence >= 60 |
| `unscored` | evaluable_weight == 0 OR vetoed |

**Step 5 — Winner selection:**
A playbook wins proposal if: confidence >= 85 AND margin >= 15 over the highest-scoring incompatible `proposal_eligible` runner-up AND exactly one eligible playbook at top. If there is no runner-up, the margin check passes by default. Compatibility is determined by `compatible_pairs` in `skills/incident-analysis/compatibility.yaml`.

**Step 6 — Contradiction collapse:**
If 2 or more `classification_credible` candidates have confidence >= 60 AND their categories are NOT listed in `compatible_pairs`, all candidates collapse to the investigate path. This prevents acting on ambiguous evidence.

### Confidence-Gated Routing

Based on the winning candidate's confidence:

**High confidence (>= 85, all invariants met):**
Transition to HITL GATE. Present the high-confidence decision record (see below). The user must approve before EXECUTE.

**Medium confidence (60-84):**
Present the investigation summary with the medium-confidence decision record (see below).
No command block is shown. The SHORTLIST contains pre-canned disambiguation probes from
runner-up playbooks. Execute one probe per runner-up (read-only, aggregate-first,
max_results <= 10). After probes: existing signal evaluator recomputes affected signal
states, scorer re-ranks unchanged, mark `disambiguation_round: completed`. Normal confidence
routing continues — if still medium after probes, present findings without another probe
round for the same classification fingerprint.

**Low confidence (< 60):**
Transition to INVESTIGATE Steps 1-5 only (limited investigation). Include the SHORTLIST
handoff artifact (same format as medium-confidence) so that the Targeted Disambiguation Probes section can consume it.
Findings feed back to CLASSIFY for reclassification.

### Loop Termination

- **Stall detection:** If 3 reclassification iterations pass without >= 5 point confidence improvement, stop iterating. Present all collected evidence and let the user choose: select a playbook manually, continue investigating, or escalate.
- **User override:** The user can override classification at any iteration and select a playbook directly.
- **Low-confidence with hypothesis:** If confidence remains < 60 but a root cause hypothesis has formed, present the user with three options: transition to POSTMORTEM, provide manual mitigation guidance, or continue investigation.

### Disambiguation Anti-Looping

- The `classification_fingerprint` is derived from the **pre_probe** evidence snapshot
  (service + time_window + signal_state_hash computed before any probes ran). This fingerprint
  is stable across the probe → rerank cycle.
- At most one probe round per `classification_fingerprint`. After one round, mark
  `disambiguation_round: completed` on the handoff artifact. No second probe round for the
  same fingerprint regardless of confidence level after reranking.
- Probe outcomes are cached per fingerprint. The same probe cannot rerun in the same
  classification cycle unless evidence materially changed (new log queries, new time window).
- A timed-out or failed probe leaves its target signals as `unknown_unavailable`. A
  **timed-out or failed** probe may never strengthen a candidate. A successful probe may flip
  a signal to `detected` or `not_detected`, which feeds into the normal scorer rerank and may
  change the outcome. The existing scorer math and coverage gate are unchanged.
- Signals using `distribution` or `ratio` detection methods cannot be resolved from a single
  probe query and remain `unknown_unavailable` even if named in `resolves_signals`.

### Decision Record — High Confidence

When confidence >= 85 and all invariants are met, present this record to the user:

```
CLASSIFY DECISION — HIGH CONFIDENCE

Playbook:      <playbook_id> (<playbook_name>)
Confidence:    <confidence>% (margin: <margin>pt over runner-up)
Category:      <category>
Evidence Age:  <seconds since oldest signal query>s (freshness window: <freshness_window_seconds>s)

SIGNALS EVALUATED:
  [detected]            <signal_id> (weight: <w>)
  [detected]            <signal_id> (weight: <w>)
  [not_detected]        <signal_id> (weight: <w>, contradiction: <cw>)
  [unknown_unavailable] <signal_id> (weight: <w>) — excluded from scoring

VETO SIGNALS:
  [not_detected]        <veto_signal_id> — no veto

COVERAGE: <evaluable_weight>/<max_possible> (<coverage>%)

State Fingerprint: <hash or summary of signal states used for EXECUTE recheck>

Explanation:   <one-sentence summary of why this playbook was selected over alternatives>

COMMAND:
  <interpolated command from playbook>

VALIDATION PLAN:
  stabilization_delay: <N>s
  validation_window:   <N>s
  post_conditions:     <list>

Approve to proceed to EXECUTE, or override.
```

### Decision Record — Medium Confidence

When confidence is 60-84, present this record without a command block:

```
CLASSIFY DECISION — MEDIUM CONFIDENCE

Playbook:      <playbook_id> (<playbook_name>)
Confidence:    <confidence>%
Category:      <category>

SIGNALS EVALUATED:
  [detected]            <signal_id> (weight: <w>)
  [not_detected]        <signal_id> (weight: <w>, contradiction: <cw>)
  [unknown_unavailable] <signal_id> (weight: <w>) — excluded from scoring

COVERAGE: <evaluable_weight>/<max_possible> (<coverage>%)

SHORTLIST:
  leader:      <playbook_id> (<confidence>%)
  runner-up-1: <playbook_id> (<confidence>%), probe: <query_ref>
  runner-up-2: <playbook_id> (<confidence>%), probe: <query_ref>
  compatibility: [<leader_category>, <runner_category>] = <compatible|incompatible>
  disambiguation_round: pending
  classification_fingerprint: <service>/<time_window>/<pre_probe_signal_state_hash>

Shortlist eligibility: non-vetoed, confidence > 40, evaluable_weight > 0,
has declared disambiguation_probe, max 2 runner-ups.

No command proposed at this confidence level. Gathering more evidence for reclassification.
```
