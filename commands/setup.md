# Setup External Skills

Download the recommended external skills that the auto-claude-skills hook routes to. These are skills not bundled with any plugin and must be cloned separately.

## Instructions

### 0. Agent Teams (recommended)

This plugin includes skills that use collaborative agent teams (agent-team-execution, agent-team-review, design-debate). These require the experimental agent teams feature to be enabled.

**Ask the user:** "Would you like to enable collaborative agent teams? This sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your Claude Code settings. Agent teams allow multiple specialist agents to work in parallel on complex tasks."

If the user agrees, add the environment variable to `~/.claude/settings.json`:

```bash
# Read current settings, add the env var, write back
jq '.env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

If the setting already exists, skip this step and inform the user it's already enabled.

### 1. Cozempic (context protection)

```bash
pip install cozempic
cozempic init
```

If pip is not available, skip this step. Cozempic provides optional context protection for long sessions and agent team workflows.

### 2. doc-coauthoring (Anthropic)

```bash
git clone --depth 1 https://github.com/anthropics/skills.git /tmp/anthropic-skills
cp -r /tmp/anthropic-skills/skills/doc-coauthoring ~/.claude/skills/doc-coauthoring
rm -rf /tmp/anthropic-skills
```

### 3. webapp-testing (Anthropic)

```bash
git clone --depth 1 https://github.com/anthropics/skills.git /tmp/anthropic-skills
cp -r /tmp/anthropic-skills/skills/webapp-testing ~/.claude/skills/webapp-testing
rm -rf /tmp/anthropic-skills
```

### 4. security-scanner (matteocervelli)

```bash
git clone --depth 1 https://github.com/matteocervelli/llms.git /tmp/cervelli-llms
cp -r /tmp/cervelli-llms/.claude/skills/security-scanner ~/.claude/skills/security-scanner
rm -rf /tmp/cervelli-llms
```

## Execution

Run each step in order. For step 0, use AskUserQuestion to get the user's preference before modifying settings. For steps 1-4, if a skill directory already exists at the target path, skip it.

After setup, confirm what was configured:
- Agent teams: enabled or skipped
- Cozempic: installed or skipped
- `~/.claude/skills/doc-coauthoring/SKILL.md` exists
- `~/.claude/skills/webapp-testing/SKILL.md` exists
- `~/.claude/skills/security-scanner/SKILL.md` exists
