#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
GEMINI_HOME="${GEMINI_HOME:-$HOME/.gemini}"

echo "==> Installing compound-engineering review skills to Gemini CLI..."
echo "    Repo:   $REPO_ROOT"
echo "    Target: $GEMINI_HOME/skills/"

# Build Gemini skills from plugin source
bun run src/index.ts install compound-engineering --to gemini

# Deploy skills
SKILLS_SRC="$REPO_ROOT/.gemini/skills"
SKILLS_DST="$GEMINI_HOME/skills"

if [ ! -d "$SKILLS_SRC" ]; then
  echo "ERROR: Build output not found at $SKILLS_SRC"
  exit 1
fi

# Create target if needed
mkdir -p "$SKILLS_DST"

# Copy skills (overwrite existing)
SKILL_COUNT=0
for d in "$SKILLS_SRC"/*/; do
  name="$(basename "$d")"
  rm -rf "$SKILLS_DST/$name"
  cp -r "$d" "$SKILLS_DST/$name"
  SKILL_COUNT=$((SKILL_COUNT + 1))
done

# Clean up build artifact
rm -rf "$REPO_ROOT/.gemini"

# Deploy commands if generated
COMMANDS_SRC="$REPO_ROOT/.gemini/commands"
if [ -d "$COMMANDS_SRC" ]; then
  mkdir -p "$GEMINI_HOME/commands"
  cp -r "$COMMANDS_SRC"/* "$GEMINI_HOME/commands/" 2>/dev/null || true
fi

echo "==> Deployed $SKILL_COUNT skills to $SKILLS_DST"
echo "==> Verify: gemini skills list | head"
echo ""
echo "Usage:"
echo "  gemini -m gemini-3.1-pro-preview --approval-mode yolo \\"
echo "    --include-directories ~/.gemini/commands/ce \\"
echo "    -p \"Use the ce-review skill to review changes in report-only mode with base:HEAD~1\""
