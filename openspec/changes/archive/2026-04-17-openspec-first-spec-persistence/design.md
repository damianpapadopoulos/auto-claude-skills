# Design: OpenSpec-First Spec Persistence

## Architecture

A single preset flag (`openspec_first`) controls artifact destination. Composition hints are rewritten at session-start based on the flag, so the LLM sees a coherent instruction set per session — not conflicting guidance from multiple sources.

### Data flow

```
~/.claude/skill-config.json  →  session-start Step 6b (preset resolution)
                                     │
                                     ▼
                              Step 6c (openspec_first check)
                                     │
                             IF openspec_first=true:
                                mutate DEFAULT_JSON.phase_compositions.DESIGN.hints
                                mutate DEFAULT_JSON.phase_compositions.PLAN.hints
                                     │
                                     ▼
                              Step 8 (extract phase_compositions) → cache
                                     │
                                     ▼
                              Activation context (LLM sees rewritten hints)
```

### Mutation target

`DEFAULT_JSON` (the full registry source) is mutated BEFORE Step 8 extracts `phase_compositions` into `PHASE_COMPOSITIONS`. This ensures a single source of truth: downstream code sees already-rewritten hints.

### Regex patterns

Three hints are rewritten by jq `test()` pattern matching (not by index, which would be fragile):

- `PERSIST DESIGN` — DESIGN phase persistence instruction
- `DESIGN.PLAN CONTRACT` — DESIGN-to-PLAN transition gate (the `.` matches `→` as a single UTF-8 character under oniguruma)
- `CARRY SCENARIOS` — PLAN phase scenario-forward instruction

## Dependencies

- jq 1.5+ (oniguruma regex for UTF-8 `.` matching `→`)
- Bash 3.2 (macOS default)
- No new packages or external dependencies

## Decisions & Trade-offs

**Preset-gated vs. always-on (Approach A rejected):** Always-on would force OpenSpec upfront for all repos. Rejected because exploratory/solo work benefits from low-ceremony `docs/plans/` scratch space and this plugin is used across diverse contexts.

**Graduation gate (Approach B rejected):** "Start in docs/plans, graduate to openspec/changes at approval" was considered. Rejected because detecting "approval" is fuzzy, devs forget, and the preset-based toggle is more predictable.

**Mutation at session-start vs. per-prompt evaluation:** Hints are rewritten once at session-start rather than having the LLM evaluate a flag per prompt. The LLM sees one coherent instruction set, not conditional logic embedded in hint text.

**Preset name `spec-driven` vs `team`:** `spec-driven` describes what the mode does (drives workflow around specs); `team` implies collaboration tooling that this change doesn't provide.

**Capability auto-creation (plug-and-play preferred):** New capabilities are auto-created under `openspec/specs/<new-capability>/` rather than gating on user approval. Safeguard: visible activation-context warning (`⚠️ NEW CAPABILITY: ...`) lets the user course-correct before archive.

**Idempotent openspec-ship (sync if exists, create if not):** Preserves backward compatibility. A repo that upgrades mid-feature with no upfront change folder still ships successfully via retrospective path.

**Out of scope (v1):** CI `openspec validate` gate, CODEOWNERS integration, capability taxonomy inference, graduation automation, mid-flight spec iteration helpers. Documented as v2 follow-ups in the design doc.
