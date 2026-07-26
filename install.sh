#!/bin/sh
# Install lean-skills into ~/.claude/skills/  (macOS, Linux, BSD, Git Bash)
set -eu

usage() {
  cat <<'EOF'
Install lean-skills into ~/.claude/skills/

  ./install.sh        prompt before overwriting an existing skill
  ./install.sh -y     overwrite without prompting
  ./install.sh -h     this help

Set CLAUDE_SKILLS_DIR to install somewhere other than ~/.claude/skills.
EOF
}

assume_yes=0
case "${1:-}" in
  -y|--yes)  assume_yes=1 ;;
  -h|--help) usage; exit 0 ;;
  "")        ;;
  *)         echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

src="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/skills"
dest="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

[ -d "$src" ] || { echo "skills/ not found next to this script" >&2; exit 1; }

# Probe the terminal by opening it, not by testing that the file exists:
# /dev/tty is present but unopenable under MSYS and most CI runners.
# The subshell keeps a failed redirection from taking the script down.
have_tty=1
( : < /dev/tty ) 2>/dev/null || have_tty=0

mkdir -p "$dest"

installed=0
kept=0
warned=0

for dir in "$src"/*/; do
  name=$(basename "$dir")

  if [ -e "$dest/$name" ] && [ "$assume_yes" -eq 0 ]; then
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

  rm -rf "${dest:?}/$name"
  cp -R "${dir%/}" "$dest/$name"
  echo "  installed $name"
  installed=$((installed + 1))
done

echo
echo "$installed installed, $kept kept -> $dest"
echo "Restart your Claude Code session to pick them up."
echo
echo "Resident (model-invoked): verification-before-completion, receiving-code-review,"
echo "                          diagnosing-bugs, code-review"
echo "Manual (user-invoked):    grill-me, implement, tdd, worktree,"
echo "                          resolving-merge-conflicts"
