# Design: Remediation Verification

## Architecture
The fix operates at two points in the incident-analysis skill's pipeline:
1. **Inventory (Step 2b):** Captures scheduling constraints from the same deployment spec already fetched for resource requests — zero incremental queries
2. **Postmortem (Step 3):** "Current State" field in action items forces the agent to document what exists before recommending changes

Data flow: Step 2b inventory -> Step 7 synthesized summary (carries scheduling data across Constraint 4 boundary) -> POSTMORTEM Step 3 action items (agent reads its own synthesis to populate "Current State")

## Dependencies
None. All changes are markdown guidance edits to a single file.

## Decisions & Trade-offs

**Inventory strategy: Option A (always-on) over Option C (hybrid)**
A MAD debate (architect/critic/pragmatist) evaluated three approaches. The hybrid (conditional trigger based on incident classification) was rejected because of a temporal ordering problem: CLASSIFY runs after inventory, so the signals needed to trigger the extension aren't available at Step 2b time. Always-on was chosen because scheduling config comes from the same deployment JSON already fetched — zero incremental cost.

**Verification mechanism: "Current State" field over formal verification gate**
The architect proposed a POSTMORTEM Step 2.5 with REDUNDANT/PARTIAL/ABSENT/UNVERIFIABLE taxonomy. This was rejected as overkill for guidance text. The critic's "Current State" field achieves the same outcome through a simpler forcing function: writing "topologySpreadConstraints configured" next to "Add podAntiAffinity" makes the contradiction self-evident.

**No Constraint 4b exception needed**
Inventory data already flows into the POSTMORTEM via the Step 7 synthesized summary (line 366). No new live queries during POSTMORTEM required.
