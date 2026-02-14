#!/bin/bash
set -euo pipefail

# --- Claude Code Skill Activation Hook - Installer --------------
# https://github.com/damianpapadopoulos/auto-claude-skills
#
# Preferred install: /plugin install auto-claude-skills (inside Claude Code)
# This script is a bootstrap fallback for manual installs
# and handles downloading external skills either way.
#
# Safe to re-run (idempotent).
# -----------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_NAME="skill-activation-hook.sh"
HOOK_SRC="$SCRIPT_DIR/hooks/$HOOK_NAME"
HOOK_DIR="$HOME/.claude/hooks"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"
PLUGIN_CACHE="$HOME/.claude/plugins/cache"

echo "+==============================================+"
echo "|  auto-claude-skills Installer                |"
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
  echo "    Run this from the repo root: cd auto-claude-skills && ./install.sh"
  exit 1
fi

# --- Check if plugin system is available -------------------------
PLUGIN_INSTALLED=false
if [ -d "$PLUGIN_CACHE" ]; then
  # Check if auto-claude-skills is already installed as a plugin
  if find "$PLUGIN_CACHE" -path "*/auto-claude-skills/*/.claude-plugin/plugin.json" -print -quit 2>/dev/null | grep -q .; then
    PLUGIN_INSTALLED=true
  fi
fi

if [ "$PLUGIN_INSTALLED" = true ]; then
  echo "[OK] auto-claude-skills is already installed as a plugin."
  echo "    The hook is registered automatically via hooks/hooks.json."
  echo ""
  echo "    To update:  /plugin update auto-claude-skills"
  echo "    To remove:  /plugin uninstall auto-claude-skills"
  echo ""
else
  echo "Plugin install (recommended):"
  echo "    Inside Claude Code, run:"
  echo "    /plugin install auto-claude-skills"
  echo ""
  read -p "Install manually instead (legacy mode)? (y/N) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo " Installing hook (legacy mode)..."

    # --- Install hook script ---
    mkdir -p "$HOOK_DIR"
    cp "$HOOK_SRC" "$HOOK_DIR/$HOOK_NAME"
    chmod +x "$HOOK_DIR/$HOOK_NAME"
    echo "   [OK] $HOOK_NAME -> $HOOK_DIR/"

    # --- Configure settings.json ---
    HOOK_CMD="\$HOME/.claude/hooks/$HOOK_NAME"

    if [ ! -f "$SETTINGS" ]; then
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
    elif grep -q "$HOOK_NAME" "$SETTINGS" 2>/dev/null; then
      echo "   [--] Hook already registered in settings.json"
    else
      BACKUP="$SETTINGS.bak.$(date +%s)"
      cp "$SETTINGS" "$BACKUP"
      echo "   Backed up to $BACKUP"

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
      if echo "$(cat "$SETTINGS")" | jq -e '.hooks.UserPromptSubmit' &>/dev/null; then
        jq --arg cmd "$HOOK_CMD" '.hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":$cmd}]}]' "$SETTINGS" > "$SETTINGS.tmp"
      else
        echo "$HOOK_ENTRY" | jq -s '.[0] * .[1]' "$SETTINGS" - > "$SETTINGS.tmp"
      fi
      mv "$SETTINGS.tmp" "$SETTINGS"
      echo "   [OK] Hook added to existing settings.json"
    fi
    echo ""
  else
    echo "Skipping manual install."
    echo ""
  fi
fi

# --- Download external skills ------------------------------------
echo " Download external skills?"
echo "   These are standalone skill repos that the hook routes to:"
echo "   - doc-coauthoring (Anthropic)"
echo "   - webapp-testing (Anthropic)"
echo "   - security-scanner (matteocervelli)"
echo ""
read -p "Download now? (Y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  echo ""
  mkdir -p "$SKILLS_DIR"

  install_skill_from_repo() {
    local repo_url="$1"
    local repo_name="$2"
    local skill_paths="$3"

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
          echo "   [--] $skill_name (already installed)"
        else
          cp -r "$tmp_dir/$repo_name/$skill_path" "$SKILLS_DIR/$skill_name"
          echo "   [OK] $skill_name"
        fi
      else
        echo "   [!!] $skill_name not found at $skill_path in $repo_name"
      fi
    done

    rm -rf "$tmp_dir/$repo_name"
  }

  install_skill_from_repo \
    "https://github.com/anthropics/skills.git" \
    "anthropic-skills" \
    "skills/doc-coauthoring,skills/webapp-testing"

  install_skill_from_repo \
    "https://github.com/matteocervelli/llms.git" \
    "cervelli-llms" \
    ".claude/skills/security-scanner"

  echo ""
fi

# --- Check for recommended plugins ------------------------------
echo " Checking for recommended plugins..."

OFFICIAL_CACHE="$HOME/.claude/plugins/cache/claude-plugins-official"
MISSING_PLUGINS=""

check_plugin() {
  local name="$1"
  local install_cmd="$2"
  if [ -d "$OFFICIAL_CACHE/$name" ]; then
    echo "   [OK] $name"
  else
    echo "   [!!] $name (not installed)"
    MISSING_PLUGINS="${MISSING_PLUGINS}   $install_cmd\n"
  fi
}

check_plugin "superpowers" "/plugin install superpowers@superpowers-marketplace"
check_plugin "frontend-design" "/plugin install frontend-design@claude-plugins-official"
check_plugin "claude-code-setup" "/plugin install claude-code-setup@claude-plugins-official"
check_plugin "claude-md-management" "/plugin install claude-md-management@claude-plugins-official"
check_plugin "ralph-loop" "/plugin install ralph-loop@claude-plugins-official"
check_plugin "pr-review-toolkit" "/plugin install pr-review-toolkit@claude-plugins-official"

echo ""

# --- Summary -----------------------------------------------------
echo "==============================================="
echo "[OK] Done!"
echo ""
if [ -d "$SKILLS_DIR" ]; then
  echo "Skills installed:"
  for d in "$SKILLS_DIR"/*/; do
    [ -f "$d/SKILL.md" ] && echo "   - $(basename "$d")"
  done
  echo ""
fi
if [ -n "$MISSING_PLUGINS" ]; then
  echo "[!!] Missing plugins (optional but recommended)."
  echo "   First add the marketplaces:"
  echo "   /plugin marketplace add anthropics/claude-plugins-official"
  echo "   /plugin marketplace add obra/superpowers-marketplace"
  echo ""
  echo "   Then install:"
  printf '%b' "$MISSING_PLUGINS"
  echo ""
fi
echo "Next: restart Claude Code to apply changes."
echo "==============================================="
