#!/bin/bash
# Drive the parking recipe *as written in the skill* through a state matrix.
#
# The recipe blocks in resolving-merge-conflicts/SKILL.md are marked
# `# lean-skills:park` and `# lean-skills:restore` and are executable shell.
# This extracts them and runs them, so the test cannot pass by matching prose
# and cannot drift by reimplementing the rule: if the block in the document is
# wrong, these cases fail.
#
#   tests/parking_matrix.sh                    # the skill in this checkout
#   tests/parking_matrix.sh <path/to/SKILL.md> # e.g. an older tag, for RED
#
# Each case runs in its own process and reports its own exit code. The pass
# condition is exact: after the whole rebase, the working tree, the index and
# the untracked files must be byte-for-byte what they were before parking.
set -u

SKILL=${1:-skills/resolving-merge-conflicts/SKILL.md}
[ -f "$SKILL" ] || { echo "no skill at $SKILL"; exit 2; }
SKILL=$(cd "$(dirname "$SKILL")" && pwd)/$(basename "$SKILL")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

extract() {   # $1 = park|restore ; prints the block, or nothing if absent
  awk -v tag="# lean-skills:$1" '
    $0 ~ /^ *```/ { if (inb) { inb=0 }; next }
    index($0, tag) { inb=1 }
    inb { sub(/^   /, ""); print }
  ' "$SKILL"
}
extract park    > "$WORK/park.sh"
extract restore > "$WORK/restore.sh"

RUNNABLE=1
if [ ! -s "$WORK/park.sh" ] || [ ! -s "$WORK/restore.sh" ]; then RUNNABLE=0; fi

pass=0; fail=0
report() {                       # $1 label  $2 rc  $3 detail
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL  %s\n        %s\n' "$1" "$3"; fi
}

# ---------------------------------------------------------------- fixtures
# $1 dir  $2 state  $3 "sub" to run the recipe from a subdirectory
# The rebase replays two commits onto feat; the first conflicts on f.txt.
make_repo() {
  rm -rf "$1"; git init -q "$1"; cd "$1" || exit 1
  git config user.email t@t; git config user.name t; git config commit.gpgsign false
  git config core.autocrlf false; git config core.safecrlf false
  mkdir -p sub deep/er
  printf 'base\n' > f.txt
  printf 'orig\n'  > tracked.txt
  printf 'gone\n'  > doomed.txt
  printf 'old\n'   > ren-old.txt
  printf 'x\n'     > deep/er/nested.txt
  git add -A; git commit -qm c0
  git checkout -qb feat; printf 'theirs\n' > f.txt; git commit -aqm feat1
  git checkout -q master 2>/dev/null || git checkout -q main
  printf 'm1\n' > f.txt; git commit -aqm mine1
  printf 'm2\n' > f.txt
  if [ "${2:-}" = clash ]; then printf 'made-by-rebase\n' > ren-new.txt; git add ren-new.txt; fi
  git add -A; git commit -qm mine2
  git rebase feat >/dev/null 2>&1
}

# put the user's in-flight work in place, then unstage it the way step 4 does
apply_state() {
  case $1 in
    tracked)     printf 'edited\n' > tracked.txt ;;
    staged)      printf 'edited\n' > tracked.txt; git add tracked.txt
                 git restore --staged -- tracked.txt ;;
    deleted)     git rm -q doomed.txt; git restore --staged -- doomed.txt ;;
    renamed|clash)
                 git mv ren-old.txt ren-new.txt
                 git restore --staged -- ren-old.txt ren-new.txt 2>/dev/null ;;
    untrackedonly)
                 printf 'wip\n' > brandnew.txt; mkdir -p deep/er; printf 'wip2\n' > deep/er/mine.txt ;;
    mixed)       printf 'edited\n' > tracked.txt
                 git rm -q doomed.txt; git restore --staged -- doomed.txt
                 printf 'wip\n' > brandnew.txt ;;
    none)        : ;;
  esac
}

snapshot() {   # porcelain plus the bytes of every non-git file
  git -c core.quotePath=false status --porcelain --untracked-files=all | LC_ALL=C sort
  find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s %s\n' "$f" "$(git hash-object "$f")"
  done
}

# ---------------------------------------------------------------- one case
run_case() {          # $1 state  $2 ""|sub
  state=$1; where=${2:-root}
  d="$WORK/$state-$where"
  ( make_repo "$d" "$state" >/dev/null 2>&1
    apply_state "$state"
    TRACKED=$(git status --porcelain --untracked-files=all | grep -v '^??' | grep -v '^UU' | cut -c4-)
    UNTRACKED=$(git status --porcelain --untracked-files=all | grep '^??' | cut -c4-)
    export TRACKED UNTRACKED
    before=$(snapshot)
    printf 'RES0\n' > f.txt; git add f.txt

    [ "$where" = sub ] && cd sub
    if [ "$RUNNABLE" -eq 1 ] && { [ -n "$TRACKED" ] || [ -n "$UNTRACKED" ]; }; then
      . "$WORK/park.sh" || exit 21
    fi
    cd "$d" || exit 22

    n=0
    while [ $n -lt 12 ]; do
      G=$(git rev-parse --git-dir)
      [ -d "$G/rebase-merge" ] || [ -d "$G/rebase-apply" ] || break
      n=$((n+1))
      if [ -n "$(git diff --name-only --diff-filter=U)" ]; then printf 'RES%s\n' "$n" > f.txt; git add f.txt; fi
      GIT_EDITOR=true git rebase --continue >/dev/null 2>&1
    done
    G=$(git rev-parse --git-dir)
    if [ -d "$G/rebase-merge" ] || [ -d "$G/rebase-apply" ]; then
      echo "rebase never finished (state=$state)" >&2; exit 23
    fi

    [ "$where" = sub ] && cd sub
    if [ "$RUNNABLE" -eq 1 ] && [ -n "${PARK:-}" ]; then . "$WORK/restore.sh" || exit 24; fi
    cd "$d" || exit 25

    if [ "$state" = clash ]; then
      # The operation created the very path the user's untracked file wanted.
      # The right outcome is not "identical to before": the operation's version
      # stays, the user's copy survives in the parking area, nothing is
      # silently overwritten.
      [ "$(cat ren-new.txt)" = "made-by-rebase" ] || {
        echo "the operation's file was overwritten by the parked copy" >&2; exit 28; }
      pk=$(find "$(git rev-parse --git-dir)" -maxdepth 1 -name 'lean-parked-*' | head -1)
      { [ -n "$pk" ] && [ -f "$pk/untracked/ren-new.txt" ]; } || {
        echo "the user's copy was not preserved" >&2; exit 29; }
    else
      # the conflicted file is the operation's, not the user's: drop it from both
      after=$(snapshot | grep -v '^\(UU\|M \|MM\) f\.txt$' | grep -v '^\./f\.txt ')
      want=$(printf '%s\n' "$before" | grep -v '^\(UU\|M \|MM\) f\.txt$' | grep -v '^\./f\.txt ')
      if [ "$after" != "$want" ]; then
        echo "state differs (state=$state where=$where)" >&2
        diff <(printf '%s\n' "$want") <(printf '%s\n' "$after") | head -8 >&2
        exit 26
      fi
    fi
    # no parking directory may survive a clean run
    if [ "$state" != clash ] && [ -n "$(find "$(git rev-parse --git-dir)" -maxdepth 1 -name 'lean-parked-*')" ]; then
      echo "parking directory left behind" >&2; exit 27
    fi
  ) 2>"$WORK/err.$state.$where"
  rc=$?
  detail=$(grep -vE "^warning:|Falling back|^Applied|^error: patch failed|^Checking patch" "$WORK/err.$state.$where" | head -3 | tr '
' ' ')
  report "$state / $where" "$rc" "rc=$rc ${detail:-（无额外输出）}"
}

echo "recipe source: $SKILL"
if [ "$RUNNABLE" -eq 0 ]; then
  echo "  !! this skill has no runnable lean-skills:park / :restore blocks"
fi
for s in tracked staged deleted renamed untrackedonly mixed none clash; do
  run_case "$s" root
  run_case "$s" sub
done

# Abandoning after parking must leave the work recoverable, not gone: the patch
# and the moved files are the only copy at that point.
abandon_case() {
  d="$WORK/abandoned"
  ( make_repo "$d" mixed >/dev/null 2>&1
    apply_state mixed
    TRACKED=$(git status --porcelain --untracked-files=all | grep -v '^??' | grep -v '^UU' | cut -c4-)
    UNTRACKED=$(git status --porcelain --untracked-files=all | grep '^??' | cut -c4-)
    export TRACKED UNTRACKED
    want_tracked=$(git hash-object tracked.txt)
    want_new=$(git hash-object brandnew.txt)
    printf 'RES0
' > f.txt; git add f.txt
    . "$WORK/park.sh" || exit 31
    git rebase --abort >/dev/null 2>&1            # the user changes their mind
    [ -d "$PARK" ] || { echo "the parking area did not survive the abort" >&2; exit 32; }
    [ -s "$PARK/tracked.patch" ] || { echo "the patch is gone" >&2; exit 33; }
    [ "$(git hash-object "$PARK/untracked/brandnew.txt")" = "$want_new" ]       || { echo "the untracked bytes did not survive" >&2; exit 34; }
    git apply --3way "$PARK/tracked.patch" >/dev/null 2>&1 || exit 35
    [ "$(git hash-object tracked.txt)" = "$want_tracked" ]       || { echo "the tracked change did not come back" >&2; exit 36; }
  ) 2>"$WORK/err.abandoned"
  rc=$?
  detail=$(grep -vE "^warning:|Falling back|^Applied|^Checking patch" "$WORK/err.abandoned" | head -2 | tr '
' ' ')
  report "abandoned after parking" "$rc" "rc=$rc ${detail:-(no extra output)}"
}
[ "$RUNNABLE" -eq 1 ] && abandon_case
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
