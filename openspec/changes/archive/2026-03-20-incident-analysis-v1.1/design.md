# Design: Incident Analysis v1.1 — One-Hop Trace Correlation

## Architecture

Extends Stage 2, Step 4 of the existing incident-analysis SKILL.md. No new files, no routing changes, no hook changes.

```
Stage 2: INVESTIGATE
  Step 3: Single-service deep dive (unchanged)
  Step 4: Autonomous Trace Correlation (NEW)
    → Extract trace_id + project_id from exemplar log entry
    → get_trace to retrieve span timeline
    → Decision tree: skip / hop / ask user
    → If hop: query Service B logs (one hop max)
    → Synthesize causal path only
  Step 5: Root cause hypothesis (unchanged, now uses two-service timeline)
```

## Dependencies
- `@google-cloud/observability-mcp` Tier 1 MCP tools (`get_trace`, `list_log_entries`) — required for Step 4
- No new packages or tools

## Decisions & Trade-offs

**Strict one-hop rule:** Prevents context exhaustion from recursive trace following. The agent correlates Service A → Service B, then stops. Fan-out to 3+ services halts and asks user.

**Two evidence paths (disjunctive):** Explicit failure (status != OK, HTTP >= 500, exception) OR timeout cascade (>= 80% root span duration with no other span >= 40%). Latency-only spans excluded.

**`search_traces` excluded from v1.1:** No trace_id = no hop. Removes an unbounded search vector. `get_trace` (direct lookup) is the only trace tool used.

**Cross-project aware:** `get_trace` uses Service A's project. `list_log_entries` for Service B uses Service B's project from span resource labels. LQL `trace=` filter uses the fully-qualified `projects/<Service B project>/traces/<TRACE_ID>` form.

**Exemplar trace selection:** When multiple failing requests exist (>1), the agent selects one exemplar from the dominant error group before entering Step 4. Prevents attempting correlation on every failing request.

**Causal path synthesis:** Only spans on the path linking Service B's failure to Service A's error are included. The full trace tree is not dumped into context.
