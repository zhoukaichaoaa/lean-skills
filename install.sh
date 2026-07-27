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
while [ $# -gt 0 ]; do
  case $1 in
    -y|--yes)       assume_yes=1 ;;
    -u|--uninstall) mode=uninstall ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# Physical path (symlinks resolved) of the skills we ship.
src=$(CDPATH= cd -- "$(dirname -- "$0")/skills" 2>/dev/null && pwd -P) || {
  echo "skills/ not found next to this script" >&2; exit 1; }

# Set-but-empty is a mistake, not a request for the default: falling back would
# quietly write to the home directory the caller was trying to override.
if [ "${CLAUDE_SKILLS_DIR+set}" = set ] && [ -z "$CLAUDE_SKILLS_DIR" ]; then
  echo "CLAUDE_SKILLS_DIR is set but empty — unset it for the default, or give it a path" >&2
  exit 2
fi
dest=${CLAUDE_SKILLS_DIR:-}
if [ -z "$dest" ]; then
  [ -n "${HOME:-}" ] || { echo "set HOME or CLAUDE_SKILLS_DIR" >&2; exit 1; }
  dest=$HOME/.claude/skills
fi

created=0
if [ -d "$dest" ]; then
  dest_abs=$(CDPATH= cd -- "$dest" && pwd -P)
elif [ "$mode" = uninstall ]; then
  echo "nothing installed at $dest"; exit 0
else
  created=1
  mkdir -p "$dest"
  dest_abs=$(CDPATH= cd -- "$dest" && pwd -P)
fi

# rmdir -p stops at the first non-empty parent, so this only unwinds what we made.
undo_created() { [ "$created" -eq 1 ] && rmdir -p "$dest_abs" 2>/dev/null || true; }
refuse() { undo_created; echo "refusing: target $dest_abs is the source (or aliases it)" >&2; exit 2; }

# Guard in two layers. The prefix comparison is free and catches ordinary paths;
# the probe is filesystem truth — it survives symlinks, junctions, bind mounts,
# and case-folding, because it asks "does a file I just wrote into the target
# appear inside the source?" rather than trying to canonicalise names.
case "$dest_abs/" in "$src"/*) refuse ;; esac
case "$src/" in "$dest_abs"/*) refuse ;; esac

# `pwd -P` above already resolved symlinks, so the prefix test covers linked
# paths here. The canary is the belt to that suspenders: it also catches
# aliases `pwd -P` cannot see, such as a bind mount or a hard-linked tree.
canary=.lean-skills-canary-$$
if : > "$src/$canary" 2>/dev/null; then
  up=$dest_abs
  i=0
  while [ -n "$up" ] && [ "$i" -lt 64 ]; do
    if [ -e "$up/$canary" ]; then rm -f "$src/$canary"; refuse; fi
    parent=$(dirname -- "$up")
    [ "$parent" = "$up" ] && break
    up=$parent
    i=$((i + 1))
  done
  rm -f "$src/$canary"
fi

probe=.lean-skills-probe-$$
if : > "$dest_abs/$probe" 2>/dev/null; then
  rm -f "$dest_abs/$probe"
else
  echo "cannot write to target $dest_abs" >&2; exit 1
fi

# Every directory we install carries this marker. Uninstall removes only the
# directories that have it, so a skill of your own that happens to share a name
# with one of ours survives.
marker=.lean-skills

if [ "$mode" = uninstall ]; then
  removed=0
  spared=0
  for dir in "$src"/*/; do
    name=$(basename "$dir")
    if [ -e "$dest_abs/$name" ]; then
      if [ -f "$dest_abs/$name/$marker" ]; then
        rm -rf "${dest_abs:?}/$name"
        echo "  removed   $name"
        removed=$((removed + 1))
      else
        echo "  kept      $name (not installed by lean-skills)"
        spared=$((spared + 1))
      fi
    fi
  done
  echo
  echo "$removed removed from $dest_abs; $spared left in place because they are not ours."
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

  # A directory without our marker belongs to the user, whatever it is called.
  # Never replace it, even with -y.
  if [ -d "$dest_abs/$name" ] && [ ! -f "$dest_abs/$name/$marker" ]; then
    echo "  kept      $name (yours, not ours — install elsewhere with CLAUDE_SKILLS_DIR)" >&2
    kept=$((kept + 1))
    continue
  fi

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

  # Copy beside the target first, then swap, so an interrupted copy leaves the
  # previously installed skill intact instead of a half-written one.
  staging=$dest_abs/.lean-skills-staging-$$
  rm -rf "$staging"
  cp -R "${dir%/}" "$staging"
  rm -rf "${dest_abs:?}/$name"
  mv "$staging" "$dest_abs/$name"
  echo "installed by lean-skills; uninstall removes only directories carrying this file" > "$dest_abs/$name/$marker"
  echo "  installed $name"
  installed=$((installed + 1))
done

echo
echo "$installed installed, $kept kept -> $dest_abs"
echo "Restart your Claude Code session to pick them up. Remove later with --uninstall."
echo
echo "Resident (model-invoked): verification-before-completion, receiving-code-review,"
echo "                          diagnosing-bugs, code-review, resolving-merge-conflicts"
echo "Manual (user-invoked):    grill-me, implement, tdd, worktree"
