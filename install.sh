#!/bin/sh
# Install lean-skills into ~/.claude/skills/  (macOS, Linux, BSD, Git Bash)
set -eu

usage() {
  cat <<'EOF'
Install lean-skills into ~/.claude/skills/

  ./install.sh              prompt before overwriting an existing skill
  ./install.sh -y           overwrite without prompting
  ./install.sh --uninstall  remove exactly this collection's skills from the target
  ./install.sh -h           this help

Set CLAUDE_SKILLS_DIR to target somewhere other than ~/.claude/skills.
Upgrading across versions that renamed or removed a skill: --uninstall, then install.
EOF
}

mode=install
assume_yes=0
case "${1:-}" in
  -y|--yes)       assume_yes=1 ;;
  -u|--uninstall) mode=uninstall ;;
  -h|--help)      usage; exit 0 ;;
  "")             ;;
  *)              echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

# Physical paths (symlinks resolved) so the guard below cannot be fooled.
src=$(CDPATH= cd -- "$(dirname -- "$0")/skills" 2>/dev/null && pwd -P) || {
  echo "skills/ not found next to this script" >&2; exit 1; }

dest="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
created=0
if [ "$mode" = uninstall ]; then
  dest_abs=$(CDPATH= cd -- "$dest" 2>/dev/null && pwd -P) || {
    echo "nothing installed at $dest"; exit 0; }
else
  [ -d "$dest" ] || created=1
  mkdir -p "$dest"
  dest_abs=$(CDPATH= cd -- "$dest" && pwd -P)
fi

# Refuse to operate on the source itself — a CLAUDE_SKILLS_DIR pointing at this
# repo's skills/ would otherwise delete the source before copying it. If we just
# created the target while probing, remove it again: a refused install must not
# leave a stray directory behind (rmdir -p stops at the first non-empty parent).
case "$dest_abs/" in
  "$src"/*)
    [ "$created" -eq 1 ] && rmdir -p "$dest_abs" 2>/dev/null || true
    echo "refusing: target $dest_abs is the source (or inside it)" >&2
    exit 2 ;;
esac

if [ "$mode" = uninstall ]; then
  removed=0
  for dir in "$src"/*/; do
    name=$(basename "$dir")
    if [ -e "$dest_abs/$name" ]; then
      rm -rf "${dest_abs:?}/$name"
      echo "  removed   $name"
      removed=$((removed + 1))
    fi
  done
  echo
  echo "$removed removed from $dest_abs — only this collection's skills; anything else was left alone."
  exit 0
fi

# Probe the terminal by opening it, not by testing that the file exists:
# /dev/tty is present but unopenable under MSYS and most CI runners.
have_tty=1
( : < /dev/tty ) 2>/dev/null || have_tty=0

installed=0
kept=0
warned=0

for dir in "$src"/*/; do
  name=$(basename "$dir")

  if [ -e "$dest_abs/$name" ] && [ "$assume_yes" -eq 0 ]; then
    reply=''
    if [ "$have_tty" -eq 1 ]; then
      printf 'overwrite existing %s? [y/N] ' "$name" >&2
      read -r reply < /dev/tty 2>/dev/null || reply=''
    elif [ "$warned" -eq 0 ]; then
      echo "No terminal for prompts — existing skills kept. Rerun with -y to overwrite." >&2
      warned=1
    fi
    case "$reply" in
      [yY]*) ;;
      *) echo "  kept      $name"; kept=$((kept + 1)); continue ;;
    esac
  fi

  rm -rf "${dest_abs:?}/$name"
  cp -R "${dir%/}" "$dest_abs/$name"
  echo "  installed $name"
  installed=$((installed + 1))
done

echo
echo "$installed installed, $kept kept -> $dest_abs"
echo "Restart your Claude Code session to pick them up. Remove later with --uninstall."
echo
echo "Resident (model-invoked): verification-before-completion, receiving-code-review,"
echo "                          diagnosing-bugs, code-review"
echo "Manual (user-invoked):    grill-me, implement, tdd, worktree,"
echo "                          resolving-merge-conflicts"
