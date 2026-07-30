#!/bin/bash
# SIGKILL park at every step and require the user's work to survive it.
#
# The failure this exists for was found by reasoning, not by testing: a park
# that dies partway leaves files moved with nothing pointing at them, and no
# `die` handler can help because a crash runs no handler. tests/parking_matrix.sh
# injects an `mv` failure, which still returns through `die`. This kills the
# process outright, so nothing gets a chance to tidy up.
#
#   tests/parking_crash.sh                    # the skill in this checkout
#   tests/parking_crash.sh <path/to/SKILL.md> # e.g. an older tag, for RED
#
# The invariant, checked after every kill:
#
#   either the worktree still holds everything it held before parking,
#   or the state file names a parking area that restore can bring back.
#
# "Files gone from the worktree AND nothing pointing at them" is the one
# outcome that is never acceptable - that is the shape v0.17.2 fixed by
# publishing the state before the first move rather than after the last.
set -u
cd "$(dirname "$0")/.." || exit 1
export MSYS=${MSYS:-winsymlinks:nativestrict}

SKILL=${1:-skills/resolving-merge-conflicts/SKILL.md}
[ -f "$SKILL" ] || { echo "no skill at $SKILL"; exit 2; }
SKILL=$(cd "$(dirname "$SKILL")" && pwd)/$(basename "$SKILL")
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

extract() {
  awk -v tag="# lean-skills:$1" '
    $0 ~ /^ *```/ { if (inb) { inb=0 }; next }
    index($0, tag) { inb=1 }
    inb { sub(/^   /, ""); print }
  ' "$SKILL"
}
extract park    > "$W/park.sh"
extract restore > "$W/restore.sh"
{ [ -s "$W/park.sh" ] && [ -s "$W/restore.sh" ]; } || {
  echo "could not extract the recipe blocks from $SKILL"; exit 2; }

pass=0; fail=0; skip=0
report() {
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL  %s\n        %s\n' "$1" "$3"; fi
}
skipped() { skip=$((skip+1)); printf '  skip  %s: %s\n' "$1" "$2"; }

# The user's tree, as bytes. Deliberately not the porcelain: after a crash the
# index can say anything, and what matters is whether the files are there.
snapshot() {
  find . -path ./.git -prune -o ! -type d -print0 | LC_ALL=C sort -z |
  while IFS= read -r -d '' f; do
    if [ -L "$f" ]; then printf '%s link %s\n' "$f" "$(readlink -- "$f")"
    else printf '%s file %s\n' "$f" "$(git hash-object -- "$f")"; fi
  done
}

build_repo() {
  rm -rf "$1"; git init -q "$1"; cd "$1" || exit 1
  git config user.email t@t; git config user.name t; git config commit.gpgsign false
  git config core.autocrlf false; git config core.safecrlf false
  mkdir -p sub
  printf 'base\n'  > f.txt
  printf 'orig\n'  > tracked.txt
  printf 'orig\n'  > sub/deep.txt
  git add -A; git commit -qm c0
  git checkout -qb feat; printf 'theirs\n' > f.txt; git commit -aqm feat
  git checkout -q master 2>/dev/null || git checkout -q main
  printf 'mine\n' > f.txt; git commit -aqm mine
  git rebase feat >/dev/null 2>&1
  # the user's in-flight work: tracked edits plus untracked files, including
  # names that have cost this project releases
  printf 'edited\n' > tracked.txt
  printf 'edited\n' > sub/deep.txt
  printf 'wip\n'    > brandnew.txt
  printf 'wip\n'    > ./-draft.txt
  printf 'wip\n'    > 'my notes.txt'
  printf 'RES\n' > f.txt; git add f.txt
  g=$(git rev-parse --git-dir)
  : > "$g/lean-park-input"
  printf '%s\0' tracked.txt sub/deep.txt brandnew.txt -draft.txt 'my notes.txt' \
    >> "$g/lean-park-input"
}

# After a kill, one of these must hold.
#
# Note what is deliberately NOT accepted: "restore kept the parking area and
# said so" on its own. Keeping is legitimate when a path came back into
# existence during the operation, or when the patch will not apply - a real
# obstacle the user has to see. It is not legitimate as a resting place for a
# file nothing is blocking, which is exactly how the manifest bug passed: the
# file sat parked, the worktree had a free slot for it, and restore exited 0.
# So a kept area is only allowed for entries whose path is genuinely occupied.
check_invariant() {   # $1 repo -> prints the reason on failure
  d=$1
  ( cd "$d" || exit 1
    if [ ! -s .git/lean-parked.state ]; then
      [ "$(snapshot)" = "$BEFORE" ] || {
        echo "no state file, yet the tree already lost something"; exit 1; }
      exit 0
    fi
    pk=".git/$(cat .git/lean-parked.state)"
    env -u PARK -u PARK_NAME -u G -u STATE bash "$W/restore.sh" >/dev/null 2>&1 \
      || { echo "state exists but restore refused it"; exit 1; }
    if [ ! -e .git/lean-parked.state ]; then
      # restore claims it finished: the tree has to actually be back
      [ "$(snapshot)" = "$BEFORE" ] || { echo "restore cleaned up on an incomplete tree"; exit 1; }
      exit 0
    fi
    # restore held on to the area. That is legitimate only if it is holding
    # something: an area kept empty while the tree is short of what it had is
    # the same loss wearing a different hat.
    if [ "$(snapshot)" != "$BEFORE" ]; then
      [ -n "$(find "$pk" -mindepth 1 ! -type d -print 2>/dev/null | head -n 1)" ] || {
        echo "kept an empty parking area while the tree is incomplete"; exit 1; }
    fi
    # ...and every file still in there must be blocked by an occupied path.
    #
    # THIS LOOKS LIKE DEAD CODE AGAINST HEAD AND IS NOT. 0.17.5 stopped creating
    # $PARK/untracked when the untracked side became inform-rather-than-take-over,
    # so against the current recipe `find` walks a path that is not there, the
    # error goes to /dev/null, and this loop never runs. But this suite takes a
    # SKILL.md argument precisely so it can be aimed at older releases, and
    # against v0.17.2 - the release whose manifest defect it was written for -
    # that directory exists and this clause is the live one.
    #
    # Measured, 0.17.7: deleting it takes the v0.17.2 RED from 4 failed to 2.
    # What goes missing is exactly the point of it - "killed after line 69",
    # which is the move/manifest window itself, and the mid-move case.
    # Dead for HEAD, load-bearing for the RED. Do not remove it for being quiet.
    find "$pk/untracked" -mindepth 1 ! -type d -print0 2>/dev/null > "$W/held" || :
    while IFS= read -r -d '' src; do
      p=${src#"$pk/untracked/"}
      { [ -e "$p" ] || [ -L "$p" ]; } || {
        echo "held $p in the parking area while its path in the tree was free"; exit 1; }
    done < "$W/held"
  )
}

# ---- granularity 1: killed between statements ----------------------------
# This is the shape that actually happens: every Bash call a model makes is its
# own process, so "died between two steps" is the ordinary case, not the exotic one.
PTS=$(awk 'NF && $1 !~ /^#/ {print NR}' "$W/park.sh")
for k in $PTS; do
  doctored="$W/park-$k.sh"
  awk -v k="$k" 'NR==k {print; print "kill -9 $$"; next} {print}' "$W/park.sh" > "$doctored"
  # inserting inside an if/while header is a syntax error, not a test case
  if ! bash -n "$doctored" 2>/dev/null; then
    skipped "kill after line $k" "injection there is not a parse-able program"
    continue
  fi
  d="$W/r$k"
  build_repo "$d" >/dev/null 2>&1
  BEFORE=$(snapshot)
  export BEFORE
  ( cd "$d" && bash "$doctored" ) >/dev/null 2>&1
  rc=$?
  # 137 = SIGKILL. Anything else means the kill never happened and this
  # iteration proved nothing, so say so rather than bank a pass.
  if [ "$rc" -ne 137 ]; then
    skipped "kill after line $k" "park exited $rc, never reached the kill"
    continue
  fi
  detail=$(check_invariant "$d" "$k")
  report "killed after line $k" "$?" "$detail"
done

# ---- granularity 2: killed mid-command, after the side effect -------------
# Harsher: the move has already happened on disk when the process dies, so the
# recipe never gets to write it down. This is the window a record-after-effect
# ordering leaves open.
mid_case() {
  d="$W/mid"
  build_repo "$d" >/dev/null 2>&1
  BEFORE=$(snapshot)
  export BEFORE
  bin="$W/midbin"; mkdir -p "$bin"
  real_mv=$(command -v mv)
  { printf '#!/bin/sh\n'
    printf '# do the move, then kill the caller before it can record anything\n'
    printf 'for a in "$@"; do case "$a" in */untracked/brandnew.txt)\n'
    printf '  %s "$@"; kill -9 "$PPID"; exit 0 ;; esac; done\n' "$real_mv"
    printf 'exec %s "$@"\n' "$real_mv"; } > "$bin/mv"
  chmod +x "$bin/mv"
  ( cd "$d" && PATH="$bin:$PATH" bash "$W/park.sh" ) >/dev/null 2>&1
  detail=$(check_invariant "$d" mid)
  report "killed mid-move, after the file was already moved" "$?" "$detail"
}
mid_case

echo
echo "$pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ]
