# Setup External Skills

Download the recommended external skills that the auto-claude-skills hook routes to. These are skills not bundled with any plugin and must be cloned separately.

## Instructions

Clone each of the following skill repositories into `~/.claude/skills/`:

### 0. Cozempic (context protection)

```bash
pip install cozempic
cozempic init
```

If pip is not available, skip this step. Cozempic provides optional context protection for long sessions and agent team workflows.

### 1. doc-coauthoring (Anthropic)

```bash
git clone --depth 1 https://github.com/anthropics/skills.git /tmp/anthropic-skills
cp -r /tmp/anthropic-skills/skills/doc-coauthoring ~/.claude/skills/doc-coauthoring
rm -rf /tmp/anthropic-skills
```

### 2. webapp-testing (Anthropic)

```bash
git clone --depth 1 https://github.com/anthropics/skills.git /tmp/anthropic-skills
cp -r /tmp/anthropic-skills/skills/webapp-testing ~/.claude/skills/webapp-testing
rm -rf /tmp/anthropic-skills
```

### 3. security-scanner (matteocervelli)

```bash
git clone --depth 1 https://github.com/matteocervelli/llms.git /tmp/cervelli-llms
cp -r /tmp/cervelli-llms/.claude/skills/security-scanner ~/.claude/skills/security-scanner
rm -rf /tmp/cervelli-llms
```

## Execution

Run the bash commands above to download all three skills. If a skill directory already exists at the target path, skip it (it's already installed).

After downloading, confirm each skill is in place by checking that these files exist:
- `~/.claude/skills/doc-coauthoring/SKILL.md`
- `~/.claude/skills/webapp-testing/SKILL.md`
- `~/.claude/skills/security-scanner/SKILL.md`

Report which skills were installed and which were already present.
