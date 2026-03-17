# Setup

Configure auto-claude-skills: install recommended companion plugins, enable agent teams, and download external skills.

## Instructions

### 0. Recommended plugins and MCPs

**Ask the user:** "Would you like to install recommended companion plugins? These provide 15+ additional skills and MCP integrations that the routing engine discovers automatically."

Present the following plugins. For each one, check if it's already installed by looking for its directory in `~/.claude/plugins/cache/`. Skip any that are already present.

**Marketplaces** (needed first):
```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add obra/superpowers-marketplace
```

**Core plugins (essential for SDLC loop):**
| Plugin | Source | What it adds |
|--------|--------|-------------|
| superpowers | superpowers-marketplace | brainstorming, TDD, debugging, planning, code review, and more |
| frontend-design | claude-plugins-official | High-quality frontend interface design |
| claude-md-management | claude-plugins-official | CLAUDE.md auditing and maintenance |
| claude-code-setup | claude-plugins-official | Claude Code automation recommendations |
| pr-review-toolkit | claude-plugins-official | Structured PR review with specialist agents |

**MCP plugins (SDLC data sources):**
| Plugin | Source | What it adds |
|--------|--------|-------------|
| context7 | claude-plugins-official | Up-to-date library/framework documentation via MCP |
| github | claude-plugins-official | GitHub repository management, PR creation, issue tracking via MCP |

Note: Atlassian (Jira/Confluence) is available as a claude.ai managed integration — connect it via `/mcp` in Claude Code. No marketplace install needed.

**Phase enhancer plugins (improve specific phases):**
| Plugin | Source | Phase | What it adds |
|--------|--------|-------|-------------|
| commit-commands | claude-plugins-official | SHIP | Structured commit workflows and branch-to-PR automation |
| security-guidance | claude-plugins-official | IMPLEMENT | Write-time security guard (passive hook) |
| feature-dev | claude-plugins-official | DESIGN | Parallel exploration and architecture agents |
| hookify | claude-plugins-official | DESIGN | Custom behavior rule authoring |
| skill-creator | claude-plugins-official | DESIGN | Skill eval/improvement with benchmarking |

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

### 4. security-scanner (built-in)

The `security-scanner` skill is now bundled with auto-claude-skills. No external installation needed.

If you have the old matteocervelli version at `~/.claude/skills/security-scanner/`, remove it:
```bash
rm -rf ~/.claude/skills/security-scanner
```

For best results, install the CLI tools the skill orchestrates. Check which are missing:

```bash
command -v semgrep && echo "semgrep: installed" || echo "semgrep: MISSING"
command -v trivy && echo "trivy: installed" || echo "trivy: MISSING"
command -v gitleaks && echo "gitleaks: installed" || echo "gitleaks: MISSING"
```

For each missing tool, **ask the user:** "The security-scanner skill works best with [tool]. Would you like to install it?"

If the user agrees, install and initialize each missing tool:

**Semgrep** (SAST — code vulnerability scanning):
```bash
brew install semgrep
```
Then download rules (~30s):
```bash
semgrep --version && semgrep scan --config auto --test . 2>/dev/null; echo "Semgrep ready"
```

**Trivy** (dependency CVE scanning):
```bash
brew install trivy
```
Then download vulnerability database (~60s):
```bash
trivy --version && trivy fs --download-db-only 2>/dev/null && echo "Trivy DB ready"
```

**Gitleaks** (secret detection):
```bash
brew install gitleaks
```
Then verify:
```bash
gitleaks version && echo "Gitleaks ready"
```

If the user declines any tool, note that the corresponding scan type will be unavailable and the skill will skip it gracefully. Semgrep is the highest-value tool — recommend it first.

### 5. Prerequisites (uv package manager)

Serena and Forgetful Memory require the `uv` package manager (Python package installer).

Check if `uv` is available:
```bash
command -v uv || command -v "$HOME/.local/bin/uv" || command -v "$HOME/.cargo/bin/uv"
```

If not found, **ask the user:** "Serena and Forgetful Memory require the `uv` package manager. Would you like to install it? (`curl -LsSf https://astral.sh/uv/install.sh | sh`)"

If the user agrees:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

After installation, verify with `uv --version` (may need to add `~/.local/bin` to PATH for the current session).

If the user declines, note that Serena and Forgetful Memory will be unavailable and proceed to Step 6.

### 6. Context Stack tools

These tools enhance context retrieval with library docs, code navigation, persistent memory, and post-execution documentation.

Note: Context7 is already installed via Step 0 (marketplace plugin) and is not duplicated here.

**Detection:** Before presenting the table, check which tools are already installed:
- `chub`: `command -v chub`
- `openspec`: `command -v openspec`
- `serena`: run `claude mcp list` and check for a `serena` entry
- `forgetful`: run `claude mcp list` and check for a `forgetful` entry

Check `npm` availability. If `npm` is missing, note that chub and OpenSpec can't be installed.

Present only the missing tools. If none are missing, skip this step.

**Ask the user:** "Would you like to install the Context Stack tools? These enhance context retrieval with library docs, code navigation, persistent memory, and post-execution documentation."

| Tool | Type | Install command | Scope | Prerequisite |
|------|------|----------------|-------|-------------|
| Context Hub CLI (`chub`) | npm global | `npm install -g @aisuite/chub` | Global | npm |
| OpenSpec | npm global | `npm install -g @fission-ai/openspec@latest` | Global | npm |
| Serena | MCP server | `claude mcp add serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context claude-code --project "$(pwd)"` | Project-scoped | uv |
| Forgetful Memory | MCP server | `claude mcp add forgetful --scope user -- uvx forgetful-ai` | User (global) | uv |

If uv was not installed in Step 5, skip Serena and Forgetful Memory with a note.

The Serena command captures the current working directory at install time, making it project-scoped. Check for an existing serena MCP registration before adding a duplicate.

After installation, verify MCP servers with `claude mcp list` (look for "Connected" status) and CLIs with `command -v`.

## Execution

Run each step in order. For steps 0 and 1, use AskUserQuestion to get the user's preference before taking action. For steps 2-4, if a skill directory already exists at the target path, skip it. For steps 5 and 6, use AskUserQuestion to get the user's preference before installing, and skip tools that are already installed.

After setup, confirm what was configured:
- Companion plugins: which were installed or skipped
- Agent teams: enabled or skipped
- Cozempic: installed or skipped
- `~/.claude/skills/doc-coauthoring/SKILL.md` exists
- `~/.claude/skills/webapp-testing/SKILL.md` exists
- `security-scanner`: bundled with auto-claude-skills (no external install needed)
- `uv`/`uvx`: available or skipped
- `chub`: available or skipped
- `openspec`: available or skipped
- Serena MCP: connected or skipped
- Forgetful Memory MCP: connected or skipped
