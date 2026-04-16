# Design: Hypothesis-to-Learning Loop

## Architecture

Data flows through five touch points:

```
DISCOVER              SHIP (openspec-ship)     SHIP (write-learn-baseline)     LEARN
   │                       │                         │                          │
   Save discovery.md ──► Parse Hypotheses           │                          │
   Set discovery_path    Extract → session state ──► Read state                │
                              │                    Detect ship event           │
                              └──────────────────► Write baseline.json ─────► Read baseline
                                                        │                    Report per-H
```

- **DISCOVER → disk:** product-discovery saves brief with Hypotheses section to `docs/plans/YYYY-MM-DD-<slug>-discovery.md`
- **DISCOVER → state:** `openspec_state_set_discovery_path` writes discovery_path to session state via targeted jq merge
- **SHIP (openspec-ship) → state:** Step 7a-bis parses hypotheses from the discovery artifact while it's still at its live path, writes structured array to `changes.<slug>.hypotheses` in session state
- **SHIP (write-learn-baseline) → disk:** After finishing-a-development-branch resolves, detects merge/PR from git state, writes denormalized baseline to `~/.claude/.skill-learn-baselines/<slug>.json`
- **LEARN → report:** outcome-review reads baseline, uses hypothesis metric fields for targeted PostHog queries, presents Hypothesis Validation table

## Dependencies

No new dependencies. Uses existing jq, bash, and OpenSpec CLI.

## Decisions & Trade-offs

- **Prose with structured suffix over YAML frontmatter:** Hypotheses use inline markdown fields (Metric/Baseline/Target/Window) rather than YAML blocks. Keeps discovery conversational while giving outcome-review greppable data.
- **Dedicated helper over 7th positional arg:** `openspec_state_set_discovery_path` is a separate function rather than extending `openspec_state_upsert_change`. Avoids fragile 7-arg positional calls and preserves existing callers.
- **Denormalized snapshot over file references:** Learn-baseline copies hypothesis entries from session state rather than storing file paths. Survives archive reorganization and branch switches.
- **Hypothesis extraction in openspec-ship over write-learn-baseline:** Extraction happens in Step 7a-bis while the discovery artifact is still at its live path, before Step 7b archives it. This eliminates filesystem dependencies from the baseline writer.
- **Post-finishing composition step over modifying finishing skill:** write-learn-baseline detects the ship outcome from git state rather than modifying the Superpowers-owned finishing skill.
