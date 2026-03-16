# Proposal: MCP Context Integration

## Problem Statement
Three MCP-based context tools (Serena, Forgetful, OpenSpec) were installed and functional, but the auto-claude-skills plugin under-utilized Serena and Forgetful: detection reported them as unavailable, phase docs referenced non-existent tool names, two phases lacked Historical Truth guidance, and there was no enforcement for memory consolidation or delta spec syncing.

## Proposed Solution
Seven-section fix: MCP config file fallback for detection, tool name corrections across 8 docs, Historical Truth steps in Implementation and Code Review, Serena PreToolUse nudge guard, Forgetful curated plugin entry, memory consolidation enforcement (commit-time + session-end), and delta spec sync check in openspec-guard.

## Out of Scope
- No changes to the openspec-ship skill itself (enforcement via guards only)
- No CI-level OpenSpec validation
- No PreToolUse guard for Forgetful (meta-tool API makes pattern matching impractical)
- No MCP health-check verification (CLI too slow for hooks)
