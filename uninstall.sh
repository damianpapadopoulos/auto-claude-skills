#!/bin/bash
set -euo pipefail

HOOK_NAME="skill-activation-hook.sh"
HOOK_DIR="$HOME/.claude/hooks"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"

echo "+==============================================+"
echo "|  Claude Code Skill Activation Hook Uninstall |"
echo "+==============================================+"
echo ""

# Remove hook script
if [ -f "$HOOK_DIR/$HOOK_NAME" ]; then
  rm "$HOOK_DIR/$HOOK_NAME"
  echo "[OK] Removed hook: $HOOK_DIR/$HOOK_NAME"
else
  echo "[--]  Hook not found (already removed)"
fi

# Remove hook from settings.json
if [ -f "$SETTINGS" ] && grep -q "$HOOK_NAME" "$SETTINGS" 2>/dev/null; then
  BACKUP="$SETTINGS.bak.$(date +%s)"
  cp "$SETTINGS" "$BACKUP"
  jq "del(.hooks.UserPromptSubmit[] | select(.hooks[]?.command | contains(\"$HOOK_NAME\")))" "$SETTINGS" > "$SETTINGS.tmp"
  mv "$SETTINGS.tmp" "$SETTINGS"
  echo "[OK] Removed hook from settings.json (backup: $BACKUP)"
else
  echo "[--]  Hook not in settings.json"
fi

# Prompt about skills
echo ""
echo "The following skills were installed by this hook:"
for skill in doc-coauthoring webapp-testing security-scanner; do
  if [ -d "$SKILLS_DIR/$skill" ]; then
    echo "   - $SKILLS_DIR/$skill"
  fi
done
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
  echo "   [--]  Skills kept"
fi

echo ""
echo "[OK] Uninstall complete. Restart Claude Code to apply."
