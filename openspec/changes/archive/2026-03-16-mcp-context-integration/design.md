# Design: MCP Context Integration

## Architecture
The fix spans three layers: detection (session-start-hook reads ~/.claude.json for MCP server registrations), documentation (phase/tier docs corrected to use actual MCP tool names), and enforcement (openspec-guard accumulator pattern for commit-time warnings + consolidation-stop.sh for session-end reminders).

Detection augments plugin-based capability checking with a jq --slurpfile fallback that reads both user-scoped (mcpServers) and project-scoped (projects.<path>.mcpServers) entries from ~/.claude.json. Only upgrades false to true, never downgrades.

Enforcement uses an accumulator pattern in openspec-guard.sh: three independent checks (openspec-ship, consolidation, delta spec sync) each append to a _WARNINGS variable, and a single JSON output is emitted at the end. A separate Stop hook (consolidation-stop.sh) provides tier-specific guidance at session end.

## Dependencies
- jq (required for MCP fallback detection and all hook JSON output)
- ~/.claude.json (Claude Code's MCP server configuration file)
- openspec CLI (optional — for delta spec validation)
- Bash 3.2 compatibility (macOS /bin/bash)

## Decisions & Trade-offs
- **File-based over CLI detection**: `claude mcp list` is 3.7s (too slow). Reading ~/.claude.json directly is <1ms.
- **Accumulator over multiple hooks**: PreToolUse can only emit one JSON output per invocation. One hook with three checks beats three separate hooks.
- **Intent-based phase docs over exact tool names**: Forgetful's meta-tool API (discover + execute) is too verbose for phase guidance. Docs use intent language and point to the tier doc for mechanics.
- **No Forgetful PreToolUse guard**: Unlike Serena (where Grep-for-symbols is detectable), there's no reliable pattern to detect when the model should use Forgetful instead of file reads.
