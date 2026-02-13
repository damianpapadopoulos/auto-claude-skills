#!/bin/bash
set -euo pipefail

# --- Claude Code Skill Activation Hook - Installer --------------
# https://github.com/dkpapapadopoulos/auto-claude-skills
#
# Installs skills, the hook script, and configures settings.json.
# The hook uses regex as a fast pre-filter; Claude Code itself
# handles ambiguous intent classification via the phase checkpoint.
# Safe to re-run (idempotent).
#
# Usage:
#   git clone https://github.com/dkpapapadopoulos/auto-claude-skills.git
#   cd auto-claude-skills
#   ./install.sh
# -----------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_NAME="skill-activation-hook.sh"
HOOK_SRC="$SCRIPT_DIR/$HOOK_NAME"
HOOK_DIR="$HOME/.claude/hooks"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"

echo "+==============================================+"
echo "|  Claude Code Skill Activation Hook Installer |"
echo "+==============================================+"
echo ""

# --- Preflight checks -------------------------------------------
if ! command -v jq &>/dev/null; then
  echo "[!!] jq is required. Install with: brew install jq (Mac) or sudo apt install jq (Linux)"
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "[!!] git is required."
  exit 1
fi

if [ ! -f "$HOOK_SRC" ]; then
  echo "[!!] Hook script not found at $HOOK_SRC"
  echo "   Run this from the repo root: cd claude-skill-hook && ./install.sh"
  exit 1
fi

# --- 1. Install skills ------------------------------------------
echo " Installing skills to $SKILLS_DIR..."
mkdir -p "$SKILLS_DIR"

install_skill_from_repo() {
  local repo_url="$1"
  local repo_name="$2"
  local skill_paths="$3"  # comma-separated paths inside the repo

  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf $tmp_dir" RETURN

  echo "   Cloning $repo_name..."
  git clone --depth 1 --quiet "$repo_url" "$tmp_dir/$repo_name" 2>/dev/null

  IFS=',' read -ra PATHS <<< "$skill_paths"
  for skill_path in "${PATHS[@]}"; do
    skill_path=$(echo "$skill_path" | xargs)
    local skill_name
    skill_name=$(basename "$skill_path")

    if [ -d "$tmp_dir/$repo_name/$skill_path" ] && [ -f "$tmp_dir/$repo_name/$skill_path/SKILL.md" ]; then
      if [ -d "$SKILLS_DIR/$skill_name" ]; then
        echo "   [--]  $skill_name (already installed)"
      else
        cp -r "$tmp_dir/$repo_name/$skill_path" "$SKILLS_DIR/$skill_name"
        echo "   [OK] $skill_name"
      fi
    else
      echo "   [!!]  $skill_name not found at $skill_path in $repo_name"
    fi
  done

  rm -rf "$tmp_dir/$repo_name"
}

# Anthropic official skills
install_skill_from_repo \
  "https://github.com/anthropics/skills.git" \
  "anthropic-skills" \
  "skills/doc-coauthoring,skills/webapp-testing"

# Security scanner from matteocervelli
install_skill_from_repo \
  "https://github.com/matteocervelli/llms.git" \
  "cervelli-llms" \
  ".claude/skills/security-scanner"

echo ""

# --- 2. Install hook --------------------------------------------
echo " Installing hook to $HOOK_DIR..."
mkdir -p "$HOOK_DIR"
cp "$HOOK_SRC" "$HOOK_DIR/$HOOK_NAME"
chmod +x "$HOOK_DIR/$HOOK_NAME"
echo "   [OK] $HOOK_NAME"
echo ""

# --- 3. Configure settings.json ---------------------------------
echo "  Configuring $SETTINGS..."

HOOK_CMD="\$HOME/.claude/hooks/$HOOK_NAME"

if [ ! -f "$SETTINGS" ]; then
  # Create from scratch
  cat > "$SETTINGS" << ENDJSON
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD"
          }
        ]
      }
    ]
  }
}
ENDJSON
  echo "   [OK] Created settings.json with hook"
else
  # Check if hook is already registered
  if grep -q "$HOOK_NAME" "$SETTINGS" 2>/dev/null; then
    echo "   [--]  Hook already registered in settings.json"
  else
    # Merge hook into existing settings
    BACKUP="$SETTINGS.bak.$(date +%s)"
    cp "$SETTINGS" "$BACKUP"
    echo "    Backed up to $BACKUP"

    # Use jq to merge
    HOOK_ENTRY=$(cat <<ENDJSON
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_CMD"
          }
        ]
      }
    ]
  }
}
ENDJSON
)
    # If hooks.UserPromptSubmit exists, append to it; otherwise create it
    if echo "$(cat "$SETTINGS")" | jq -e '.hooks.UserPromptSubmit' &>/dev/null; then
      jq --arg cmd "$HOOK_CMD" '.hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":$cmd}]}]' "$SETTINGS" > "$SETTINGS.tmp"
    else
      echo "$HOOK_ENTRY" | jq -s '.[0] * .[1]' "$SETTINGS" - > "$SETTINGS.tmp"
    fi
    mv "$SETTINGS.tmp" "$SETTINGS"
    echo "   [OK] Hook added to existing settings.json"
  fi
fi

echo ""

# --- 4. Check for optional plugins -------------------------------
echo " Checking for recommended plugins..."

PLUGIN_CACHE="$HOME/.claude/plugins/cache/claude-plugins-official"
MISSING_PLUGINS=""

check_plugin() {
  local name="$1"
  local install_cmd="$2"
  if [ -d "$PLUGIN_CACHE/$name" ]; then
    echo "   [OK] $name"
  else
    echo "   [!!] $name (not installed)"
    MISSING_PLUGINS="${MISSING_PLUGINS}   $install_cmd\n"
  fi
}

check_plugin "superpowers" "/plugin install superpowers@superpowers-marketplace"
check_plugin "frontend-design" "/plugin install frontend-design@claude-plugin-directory"
check_plugin "claude-code-setup" "/plugin install claude-code-setup@claude-plugin-directory"
check_plugin "claude-md-management" "/plugin install claude-md-management@claude-plugin-directory"
check_plugin "ralph-loop" "/plugin install ralph-loop@claude-plugin-directory"
check_plugin "pr-review-toolkit" "/plugin install pr-review-toolkit@claude-plugin-directory"

echo ""

# --- 5. Summary -------------------------------------------------
echo "==============================================="
echo "[OK] Installation complete!"
echo ""
echo "Skills installed:"
for d in "$SKILLS_DIR"/*/; do
  [ -f "$d/SKILL.md" ] && echo "   - $(basename "$d")"
done
echo ""
echo "Hook: $HOOK_DIR/$HOOK_NAME"
echo ""
if [ -n "$MISSING_PLUGINS" ]; then
  echo "[!!]  Missing plugins (optional but recommended)."
  echo "   First add the marketplaces:"
  echo "   /plugin marketplace add anthropics/claude-plugins-official"
  echo "   /plugin marketplace add obra/superpowers-marketplace"
  echo ""
  echo "   Then install:"
  printf '%b' "$MISSING_PLUGINS"
  echo ""
  echo "   These provide 15+ additional skills for the full"
  echo "   design -> plan -> implement -> review -> ship pipeline."
  echo "   The hook routes to the right phase; each skill chains internally."
  echo ""
fi
echo "Next steps:"
echo "  1. Restart Claude Code (exit and reopen)"
echo "  2. Test: echo '{\"prompt\":\"check for security vulnerabilities\"}' | ~/.claude/hooks/$HOOK_NAME"
echo "==============================================="
