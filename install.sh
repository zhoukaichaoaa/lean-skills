#!/usr/bin/env bash
# Install lean-skills into ~/.claude/skills/
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

[ -d "$SRC" ] || { echo "skills/ not found next to this script" >&2; exit 1; }

mkdir -p "$DEST"

for dir in "$SRC"/*/; do
  name="$(basename "$dir")"
  if [ -e "$DEST/$name" ]; then
    printf 'overwrite existing %s? [y/N] ' "$name"
    read -r reply </dev/tty
    case "$reply" in [yY]*) ;; *) echo "  skipped $name"; continue ;; esac
    rm -rf "${DEST:?}/$name"
  fi
  cp -r "$dir" "$DEST/$name"
  echo "  installed $name"
done

echo
echo "Installed to $DEST — restart your Claude Code session to pick them up."
echo
echo "Resident (model-invoked): verification-before-completion, diagnosing-bugs,"
echo "                          tdd, code-review, resolving-merge-conflicts"
echo "Manual (user-invoked):    grill-me, implement, worktree, receiving-code-review"
