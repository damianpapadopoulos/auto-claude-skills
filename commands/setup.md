# Setup

Configure auto-claude-skills: install recommended companion plugins, enable agent teams, and download external skills.

## Instructions

### 0. Recommended plugins

**Ask the user:** "Would you like to install recommended companion plugins? These provide 15+ additional skills that the routing engine discovers automatically."

Present the following plugins. For each one, check if it's already installed by looking for its directory in `~/.claude/plugins/cache/`. Skip any that are already present.

**Marketplaces** (needed first):
```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add obra/superpowers-marketplace
```

**Plugins:**
| Plugin | Source | What it adds |
|--------|--------|-------------|
| superpowers | superpowers-marketplace | brainstorming, TDD, debugging, planning, code review, and more |
| frontend-design | claude-plugins-official | High-quality frontend interface design |
| claude-md-management | claude-plugins-official | CLAUDE.md auditing and maintenance |
| claude-code-setup | claude-plugins-official | Claude Code automation recommendations |
| pr-review-toolkit | claude-plugins-official | Structured PR review with specialist agents |

For each plugin the user wants, run:
```bash
claude plugin install <plugin-name>@<marketplace>
```

If the user declines, skip this step entirely.

### 1. Agent Teams (recommended)

This plugin includes skills that use collaborative agent teams (agent-team-execution, agent-team-review, design-debate). These require the experimental agent teams feature to be enabled.

**Ask the user:** "Would you like to enable collaborative agent teams? This sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your Claude Code settings. Agent teams allow multiple specialist agents to work in parallel on complex tasks."

If the user agrees, add the environment variable to `~/.claude/settings.json`:

```bash
# Read current settings, add the env var, write back
jq '.env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

If the setting already exists, skip this step and inform the user it's already enabled.

### 2. Cozempic (context protection)

```bash
pip install cozempic
cozempic init
```

If pip is not available, skip this step. Cozempic provides optional context protection for long sessions and agent team workflows.

### 3. Anthropic skills (doc-coauthoring, webapp-testing)

Clone the Anthropic skills repo once and copy both skills:

```bash
git clone --depth 1 https://github.com/anthropics/skills.git /tmp/anthropic-skills
cp -r /tmp/anthropic-skills/skills/doc-coauthoring ~/.claude/skills/doc-coauthoring
cp -r /tmp/anthropic-skills/skills/webapp-testing ~/.claude/skills/webapp-testing
rm -rf /tmp/anthropic-skills
```

### 4. security-scanner (matteocervelli)

```bash
git clone --depth 1 https://github.com/matteocervelli/llms.git /tmp/cervelli-llms
cp -r /tmp/cervelli-llms/.claude/skills/security-scanner ~/.claude/skills/security-scanner
rm -rf /tmp/cervelli-llms
```

### 5. MCP servers (optional, project-aware)

**Ask the user:** "Would you like MCP server recommendations based on your project? MCP servers give Claude access to external tools like databases, browsers, and cloud services."

If the user agrees, scan the project for tech stack signals and recommend relevant MCP servers:

| Project signal | Recommended MCP | What it enables |
|---------------|----------------|-----------------|
| Frontend code (React, Vue, Svelte, HTML) | Playwright MCP | Browser automation, screenshots, DOM inspection, accessibility snapshots |
| `.github/` or CI config | GitHub MCP | PR management, issue tracking, code search |
| `docker-compose.yml` with Postgres/MySQL | Database MCP | Query execution, schema inspection |
| Slack/Discord config or mentions | Slack/Discord MCP | Team notifications, channel management |
| Kubernetes manifests or cloud config | Cloud platform MCPs | Infrastructure management |

For the full directory of available MCP servers, see: https://github.com/punkpeye/awesome-mcp-servers

Guide the user through configuring any recommended servers in `~/.claude/settings.json` under the `mcpServers` key.

## Execution

Run each step in order. For steps 0 and 1, use AskUserQuestion to get the user's preference before taking action. For steps 2-4, if a skill directory already exists at the target path, skip it. For step 5, only recommend MCPs relevant to the detected project.

After setup, confirm what was configured:
- Companion plugins: which were installed or skipped
- Agent teams: enabled or skipped
- Cozempic: installed or skipped
- `~/.claude/skills/doc-coauthoring/SKILL.md` exists
- `~/.claude/skills/webapp-testing/SKILL.md` exists
- `~/.claude/skills/security-scanner/SKILL.md` exists
- MCP servers: which were recommended and configured, or skipped
