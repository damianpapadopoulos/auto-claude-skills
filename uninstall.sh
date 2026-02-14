#!/bin/bash
set -euo pipefail

# --- Claude Code Skill Activation Hook - Uninstaller -------------
# Handles legacy (manual) installs only.
# Plugin installs are removed via: /plugin uninstall auto-claude-skills
# -----------------------------------------------------------------

HOOK_NAME="skill-activation-hook.sh"
HOOK_DIR="$HOME/.claude/hooks"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"

echo "+==============================================+"
echo "|  auto-claude-skills Uninstaller (legacy)     |"
echo "+==============================================+"
echo ""
echo "Note: If you installed via /plugin install, use:"
echo "  /plugin uninstall auto-claude-skills"
echo ""

# Remove hook script
if [ -f "$HOOK_DIR/$HOOK_NAME" ]; then
  rm "$HOOK_DIR/$HOOK_NAME"
  echo "[OK] Removed hook: $HOOK_DIR/$HOOK_NAME"
else
  echo "[--] Hook not found (already removed or plugin-managed)"
fi

# Remove hook from settings.json
if [ -f "$SETTINGS" ] && command -v jq &>/dev/null && grep -q "$HOOK_NAME" "$SETTINGS" 2>/dev/null; then
  BACKUP="$SETTINGS.bak.$(date +%s)"
  cp "$SETTINGS" "$BACKUP"
  jq "del(.hooks.UserPromptSubmit[] | select(.hooks[]?.command | contains(\"$HOOK_NAME\")))" "$SETTINGS" > "$SETTINGS.tmp"
  mv "$SETTINGS.tmp" "$SETTINGS"
  echo "[OK] Removed hook from settings.json (backup: $BACKUP)"
else
  echo "[--] Hook not in settings.json"
fi

# Prompt about skills
echo ""
echo "The following skills may have been installed by this hook:"
FOUND_SKILLS=false
for skill in doc-coauthoring webapp-testing security-scanner; do
  if [ -d "$SKILLS_DIR/$skill" ]; then
    echo "   - $SKILLS_DIR/$skill"
    FOUND_SKILLS=true
  fi
done

if [ "$FOUND_SKILLS" = true ]; then
  echo ""
  read -p "Remove these skills? (y/N) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    for skill in doc-coauthoring webapp-testing security-scanner; do
      if [ -d "$SKILLS_DIR/$skill" ]; then
        rm -rf "$SKILLS_DIR/$skill"
        echo "   [OK] Removed $skill"
      fi
    done
  else
    echo "   [--] Skills kept"
  fi
else
  echo "   (none found)"
fi

echo ""
echo "[OK] Uninstall complete. Restart Claude Code to apply."
