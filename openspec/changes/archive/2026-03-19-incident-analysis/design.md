# Design: Incident Analysis Skill

## Architecture

The skill follows the "Brain vs Hands" separation pattern:

```
Routing Layer (default-triggers.json)
  → gcp-observability hint (expanded triggers + INCIDENT ANALYSIS text)
  → incident-analysis skill entry (domain, priority 20, DEBUG/SHIP)
       |
       v
Brain: skills/incident-analysis/SKILL.md
  State Machine: MITIGATE → INVESTIGATE → POSTMORTEM
  Behavioral Constraints (always active):
    1. HITL Gate — no autonomous mutations
    2. Scope Restriction — no global searches during incidents
    3. Temp-File Execution Pattern — mktemp for LQL (Tier 2 only)
    4. Context Discipline — behavioral synthesis before POSTMORTEM
       |
       v
Hands: Tiered Execution
  Tier 1: @google-cloud/observability-mcp (structured calls, pagination)
  Tier 2: gcloud CLI via Bash (temp-file pattern for LQL safety)
  Tier 3: Guidance-only (Cloud Console instructions)
```

Session-start hook detects gcloud availability and emits `Observability tools: gcloud=true/false` in additionalContext (informational, not a routing gate).

## Dependencies

- `gcloud` CLI (Tier 2) or `@google-cloud/observability-mcp` (Tier 1) — both optional, graceful degradation
- `jq` — for test registry helpers
- No new npm/pip/brew packages added to the plugin itself

## Decisions & Trade-offs

**MCP vs Skill+Bash:** Unlike security-scanner (which correctly uses Skill+Bash for stateless CLI tools), log analysis has fundamentally different interaction characteristics: complex LQL syntax, unbounded result volume, multi-hop correlation. MCP is justified for Tier 1 because it's a purpose-built API client (not wrapping a CLI), handles pagination transparently, and bundles logs + metrics + traces + errors. Tier 2 (gcloud CLI) retained for universal availability.

**Tiered approach vs single implementation:** Follows the unified-context-stack's existing degradation pattern (Context7 → Context Hub → WebSearch). Users with full GCP tooling get the best experience; users with just gcloud still get structured investigation; users with neither get manual guidance.

**Stage numbering (not SDLC phases):** Internal stages named MITIGATE/INVESTIGATE/POSTMORTEM to avoid collision with the plugin's SDLC phase concept (DEBUG, SHIP, etc.).

**Temp-file pattern for LQL:** LLMs hallucinate complex shell escaping. Writing LQL to a session-scoped temp file (`mktemp`) and reading it via `$(cat "$LQL_FILE")` eliminates this failure mode entirely. The `;` cleanup operator handles gcloud failures.

**Postmortem template as schema (~50 tokens):** Embedded as structural constraints (7 required section headers), not a full boilerplate. Zero-config resilience: works in repos without template files.

**Domain role (not process):** The skill provides observability expertise but doesn't replace `systematic-debugging` as the process skill. Both fire together: `systematic-debugging` (process) + `incident-analysis` (domain).
