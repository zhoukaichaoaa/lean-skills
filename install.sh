#!/bin/sh
# Install lean-skills into ~/.claude/skills/  (macOS, Linux, BSD, Git Bash)
set -eu

usage() {
  cat <<'EOF'
Install lean-skills into ~/.claude/skills/

  ./install.sh              prompt before overwriting an existing skill
  ./install.sh -y           overwrite without prompting
  ./install.sh --adopt      also take over same-named directories that carry no
                            ownership marker (this is how you upgrade from a
                            version before 0.7.0, which did not write markers)
  ./install.sh --uninstall  remove this collection's skills from the target
  ./install.sh -h           this help

Set CLAUDE_SKILLS_DIR to an absolute path to target somewhere other than
~/.claude/skills.
EOF
}

mode=install
assume_yes=0
adopt=0
while [ $# -gt 0 ]; do
  case $1 in
    -y|--yes)       assume_yes=1 ;;
    -a|--adopt)     adopt=1 ;;
    -u|--uninstall) mode=uninstall ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# Physical path (symlinks resolved) of the skills we ship.
src=$(CDPATH= cd -- "$(dirname -- "$0")/skills" 2>/dev/null && pwd -P) || {
  echo "skills/ not found next to this script" >&2; exit 1; }

# A set-but-blank or relative CLAUDE_SKILLS_DIR all cause the same harm: writing
# somewhere the caller did not mean. Only an absolute path is a real answer.
if [ "${CLAUDE_SKILLS_DIR+set}" = set ]; then
  # Blank first, then absolute, and with no exemption for a leading blank. The
  # other order accepted " /tmp/x": it matched the leading-blank arm, and the
  # blank test then saw a non-empty string. POSIX reads that path's first
  # component as a space, so it is relative — and the install landed under the
  # current directory. (Shell patterns, not `tr`: BSD and GNU `tr` disagree
  # about whether '\t' means a tab.)
  case "$CLAUDE_SKILLS_DIR" in
    *[![:blank:]]*) : ;;
    *) echo "CLAUDE_SKILLS_DIR is set but blank — unset it for the default, or give it a path" >&2; exit 2 ;;
  esac
  # `C:/skills` is absolute under Git Bash, MSYS and Cygwin, and a *relative*
  # path called "C:" everywhere else - accepting it on Linux would create a
  # directory named C: in the current one. Ask the platform, do not assume.
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) drive_letters_are_absolute=1 ;;
    *)                    drive_letters_are_absolute=0 ;;
  esac
  case "$CLAUDE_SKILLS_DIR" in
    /*) : ;;
    [A-Za-z]:[\\/]*)
      [ "$drive_letters_are_absolute" -eq 1 ] || {
        echo "CLAUDE_SKILLS_DIR must be an absolute path; '$CLAUDE_SKILLS_DIR' is a drive-letter path, which is relative on $(uname -s)" >&2
        exit 2
      } ;;
    *) echo "CLAUDE_SKILLS_DIR must be an absolute path (got: '$CLAUDE_SKILLS_DIR')" >&2; exit 2 ;;
  esac
fi
dest=${CLAUDE_SKILLS_DIR:-}
if [ -z "$dest" ]; then
  [ -n "${HOME:-}" ] || { echo "set HOME or CLAUDE_SKILLS_DIR" >&2; exit 1; }
  dest=$HOME/.claude/skills
fi

# Record exactly the directories we create, deepest first, so a refused run
# unwinds its own work and never removes a directory that already existed.
created_levels=''
if [ ! -d "$dest" ]; then
  [ "$mode" = uninstall ] && { echo "nothing installed at $dest"; exit 0; }
  p=$dest
  while [ -n "$p" ] && [ ! -d "$p" ]; do
    created_levels="${created_levels}${p}
"
    parent=$(dirname -- "$p")
    [ "$parent" = "$p" ] && break
    p=$parent
  done
  mkdir -p "$dest"
fi
dest_abs=$(CDPATH= cd -- "$dest" && pwd -P)

undo_created() {
  printf '%s' "$created_levels" | while IFS= read -r d; do
    [ -n "$d" ] && rmdir "$d" 2>/dev/null || true
  done
}
refuse() { undo_created; echo "refusing: target $dest_abs is the source (or aliases it)" >&2; exit 2; }

# Guard in three layers. The prefix comparisons are free and catch ordinary
# paths in both directions. The canaries are filesystem truth: reads traverse
# symlinks, junctions and bind mounts, so a marker seen from the other side
# proves aliasing that no amount of name canonicalisation would reveal.
case "$dest_abs/" in "$src"/*) refuse ;; esac
case "$src/" in "$dest_abs"/*) refuse ;; esac

# Is the target the source, or inside it? Walk up from the target looking for a
# canary planted in the source.
canary=.lean-skills-canary-$$
seen=0
if : > "$src/$canary" 2>/dev/null; then
  up=$dest_abs
  i=0
  while [ -n "$up" ] && [ "$i" -lt 64 ]; do
    if [ -e "$up/$canary" ]; then seen=1; break; fi
    parent=$(dirname -- "$up"); [ "$parent" = "$up" ] && break; up=$parent
    i=$((i + 1))
  done
  rm -f "$src/$canary"
  [ "$seen" -eq 1 ] && refuse
else
  echo "warning: source is not writable, so the aliasing check is weaker than usual" >&2
fi

# Is the source inside the target? The walk above cannot see that — the source's
# canary sits below the target, not above it. Plant one in the target and walk up
# from the source instead.
seen=0
if : > "$dest_abs/$canary" 2>/dev/null; then
  up=$src
  i=0
  while [ -n "$up" ] && [ "$i" -lt 64 ]; do
    if [ -e "$up/$canary" ]; then seen=1; break; fi
    parent=$(dirname -- "$up"); [ "$parent" = "$up" ] && break; up=$parent
    i=$((i + 1))
  done
  rm -f "$dest_abs/$canary"
  [ "$seen" -eq 1 ] && refuse
else
  undo_created
  echo "cannot write to target $dest_abs" >&2; exit 1
fi

# Every directory we install carries this marker, with this exact first line.
# Uninstall removes only directories that have it, so a skill of your own that
# happens to share a name with one of ours survives.
# `-e` follows the link and answers about the *target*, so a symlink whose
# target is missing - an unmounted disk, a moved directory - reads as "nothing
# here". Every decision about the user's property has to see the link itself,
# or the install replaces it without ever consulting the ownership marker.
exists() { [ -e "$1" ] || [ -L "$1" ]; }

marker=.lean-skills
# Anything interrupted mid-swap leaves scratch directories behind. Claude Code
# loads every directory under the skills root, so an orphaned one would show up
# as a skill named `.lean-skills-staging-1234`.
#
# While the swap is open, `outgoing` is not scratch — it is the only copy of an
# installed skill. Put it back before sweeping, or a failed `mv` turns cleanup
# into the thing that destroys it.
swap_target=''
cleanup() {
  [ -n "${dest_abs:-}" ] || return 0
  _staging=$dest_abs/.lean-skills-staging-$$
  _outgoing=$dest_abs/.lean-skills-outgoing-$$
  if [ -n "$swap_target" ] && [ -d "$_outgoing" ] && ! exists "$swap_target"; then
    if mv "$_outgoing" "$swap_target" 2>/dev/null; then
      echo "  restored  ${swap_target##*/} (install did not finish)" >&2
    else
      # Both moves failed. An orphan directory is ugly; a deleted skill is gone.
      echo "  WARNING: could not restore ${swap_target##*/} — your copy is at $_outgoing" >&2
      rm -rf "$_staging"
      return 0
    fi
  fi
  rm -rf "$_staging" "$_outgoing"
}
trap cleanup EXIT INT TERM HUP
marker_line='installed by lean-skills; uninstall removes only directories carrying this file'

# The whole first line must equal the marker, byte for byte (a trailing CR is
# tolerated so a file written on Windows still counts). A substring test would
# claim - and rm -rf - any directory whose marker merely quotes this sentence,
# and install.ps1 compares for equality, so a looser test here would also make
# the two platforms disagree about who owns a directory.
is_ours() {
  [ -f "$1/$marker" ] || return 1
  first=$(head -n 1 "$1/$marker" 2>/dev/null | tr -d '\r')
  [ "$first" = "$marker_line" ]
}

# Skills this collection used to ship. They are gone from skills/, so the loops
# below would never look at them, and a stale copy would sit in the target for
# ever — `code-review` in particular keeps shadowing Claude Code's built-in one.
retired='code-review'

if [ "$mode" = uninstall ]; then
  removed=0
  spared=0
  # IFS=newline, not the default: a directory called "two words" would otherwise
  # be split into two names that match nothing, and the real one is never removed.
  old_ifs=${IFS-}
  IFS='
'
  for name in $(for d in "$src"/*/; do basename "$d"; done; printf '%s\n' "$retired"); do
    IFS=$old_ifs
    exists "$dest_abs/$name" || continue
    if is_ours "$dest_abs/$name" || [ "$adopt" -eq 1 ]; then
      rm -rf "${dest_abs:?}/$name"
      echo "  removed   $name"
      removed=$((removed + 1))
    else
      echo "  kept      $name (no ownership marker)"
      spared=$((spared + 1))
    fi
    IFS='
'
  done
  IFS=${old_ifs-}
  echo
  echo "$removed removed from $dest_abs, $spared kept."
  if [ "$spared" -gt 0 ]; then
    echo
    echo "Those $spared are either yours or were installed before 0.7.0, which did" >&2
    echo "not write markers. Nothing distinguishes the two from here — inspect them," >&2
    echo "then rerun with --adopt to remove them anyway." >&2
    exit 3
  fi
  exit 0
fi

# Probe the terminal by opening it, not by testing that the file exists:
# /dev/tty is present but unopenable under MSYS and most CI runners.
have_tty=1
( : < /dev/tty ) 2>/dev/null || have_tty=0

installed=0
kept=0
unmarked=0
warned=0

for dir in "$src"/*/; do
  name=$(basename "$dir")

  # Anything at our name without our marker is either yours or a pre-0.7.0
  # install of ours. We cannot tell, so we do not guess: keep it unless --adopt.
  adopting=0
  if exists "$dest_abs/$name" && ! is_ours "$dest_abs/$name" && [ "$adopt" -eq 1 ]; then
    adopting=1
  fi
  if exists "$dest_abs/$name" && ! is_ours "$dest_abs/$name" && [ "$adopt" -eq 0 ]; then
    echo "  kept      $name (no ownership marker)"
    kept=$((kept + 1))
    unmarked=$((unmarked + 1))
    continue
  fi

  if exists "$dest_abs/$name" && [ "$assume_yes" -eq 0 ]; then
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
  [ "$adopting" -eq 1 ] && echo "  adopting  $name (had no marker; replacing its contents)" >&2
  staging=$dest_abs/.lean-skills-staging-$$
  rm -rf "$staging"
  cp -R "${dir%/}" "$staging"
  echo "$marker_line" > "$staging/$marker"
  # Move the old one aside rather than deleting it first: between the rm and the
  # mv the skill used to be simply gone, and an interrupt there left the target
  # with no copy at all. Now the window contains a rename, and whatever survives
  # is cleaned up by the trap.
  outgoing=$dest_abs/.lean-skills-outgoing-$$
  rm -rf "$outgoing"
  swap_target=$dest_abs/$name          # the window opens here
  exists "$dest_abs/$name" && mv "$dest_abs/$name" "$outgoing"
  mv "$staging" "$dest_abs/$name"
  swap_target=''                       # ...and closes only once the new copy is in place
  rm -rf "$outgoing"
  echo "  installed $name"
  installed=$((installed + 1))
done

# Retire what we no longer ship.
old_ifs=${IFS-}
IFS='
'
for name in $retired; do
  IFS=$old_ifs
  exists "$dest_abs/$name" || continue
  if is_ours "$dest_abs/$name" || [ "$adopt" -eq 1 ]; then
    rm -rf "${dest_abs:?}/$name"
    echo "  retired   $name (no longer part of this collection)"
  else
    echo "  kept      $name (retired, no ownership marker)"
    kept=$((kept + 1)); unmarked=$((unmarked + 1))
  fi
  IFS='
'
done
IFS=${old_ifs-}

echo
echo "$installed installed, $kept kept -> $dest_abs"
if [ "$unmarked" -gt 0 ]; then
  echo
  echo "$unmarked of those carry no ownership marker. If they are yours, leave them." >&2
  echo "If you installed lean-skills before 0.7.0 — which did not write markers —" >&2
  echo "this is your upgrade, and it did not happen: rerun with --adopt." >&2
  exit 3
fi
if [ -n "$created_levels" ]; then
  echo "First install here — restart your Claude Code session to pick the skills up."
else
  echo "Claude Code picks these up in the current session; no restart needed."
fi
echo "Remove later with --uninstall."
echo
echo "Resident (model-invoked): verification-before-completion, receiving-code-review,"
echo "                          diagnosing-bugs, spec-review, resolving-merge-conflicts"
echo "Manual (user-invoked):    grill-me, implement, tdd, worktree"
