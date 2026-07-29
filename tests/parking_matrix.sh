#!/bin/bash
# Drive the parking recipe *as written in the skill*, in the shape Claude Code
# actually runs it: park, continue and restore are three separate processes.
#
# The blocks in resolving-merge-conflicts/SKILL.md are marked
# `# lean-skills:park` and `# lean-skills:restore` and are executable shell.
# This extracts and runs them, so the document is the thing under test.
#
#   tests/parking_matrix.sh                    # the skill in this checkout
#   tests/parking_matrix.sh <path/to/SKILL.md> # e.g. an older tag, for RED
#
# The pass condition is exact: after the whole rebase the working tree, the
# index and the untracked files must be what they were before parking, compared
# by type, content or link target, and mode.
set -u
export MSYS=${MSYS:-winsymlinks:nativestrict}

SKILL=${1:-skills/resolving-merge-conflicts/SKILL.md}
[ -f "$SKILL" ] || { echo "no skill at $SKILL"; exit 2; }
SKILL=$(cd "$(dirname "$SKILL")" && pwd)/$(basename "$SKILL")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

extract() {
  awk -v tag="# lean-skills:$1" '
    $0 ~ /^ *```/ { if (inb) { inb=0 }; next }
    index($0, tag) { inb=1 }
    inb { sub(/^   /, ""); print }
  ' "$SKILL"
}
extract park    > "$WORK/park.sh"
extract restore > "$WORK/restore.sh"
RUNNABLE=1
{ [ -s "$WORK/park.sh" ] && [ -s "$WORK/restore.sh" ]; } || RUNNABLE=0

probe=$(mktemp -d); SYMLINKS=0
if ln -s target "$probe/l" 2>/dev/null && [ -L "$probe/l" ]; then SYMLINKS=1; fi
rm -rf "$probe"

# A newline in a name: count with -print0, never with wc -l -- the name itself
# contains the separator wc counts, so the old probe always said "unsupported".
NEWLINE_OK=0
_nl=$(mktemp -d)
if printf x > "$_nl/$(printf 'a\nb')" 2>/dev/null &&
   [ "$(find "$_nl" -type f -print0 | tr -cd '\0' | wc -c)" -eq 1 ] &&
   [ -e "$_nl/$(printf 'a\nb')" ]; then NEWLINE_OK=1; fi
rm -rf "$_nl"

pass=0; fail=0; skip=0
report() {
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL  %s\n        %s\n' "$1" "$3"; fi
}
# $1 how many cases did not run, $2 why. The count matters: one call standing
# for six unrun cases makes the skip total disagree with the case total, and the
# whole point of reporting skips apart is that the numbers add up.
skipped() { skip=$((skip+$1)); printf '  skip  %s case(s): %s\n' "$1" "$2"; }

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
  # A *tracked* path with a space. The untracked ones were never enough: the
  # patch is built from the tracked list only, so a recipe that word-splits its
  # pathspecs drops this file silently and every existing case still passed.
  printf 'orig\n'  > 'my tracked notes.txt'
  printf 'g\n'     > 'a[1].txt'
  # a decoy: the glob a[1].txt matches a1.txt, so a pathspec without :(literal)
  # would revert a file the user never named. Brackets are used rather than a
  # `*` deliberately -- NTFS cannot store a `*` at all, and MSYS substitutes a
  # private-use character for it, so the name the shell wrote and the bytes on
  # disk differ and git can never find the file. Brackets are legal everywhere,
  # so this decoy works on all three platforms instead of being skipped on one.
  printf 'decoy\n'  > 'a1.txt'
  git add -A; git commit -qm c0
  git checkout -qb feat; printf 'theirs\n' > f.txt; git commit -aqm feat1
  git checkout -q master 2>/dev/null || git checkout -q main
  printf 'm1\n' > f.txt; git commit -aqm mine1
  printf 'm2\n' > f.txt
  # `clash` builds the untracked-collision scenario, and it is worth spelling
  # out because two rounds of review looked straight past it. mine2 creates
  # ren-new.txt, the rebase stops on mine1's conflict, so mine2 has NOT been
  # replayed and ren-new.txt is absent from the worktree. apply_state then
  # renames into that very name, leaving it *untracked during the conflict* -
  # exactly the shape the skill calls out ("a rename in flight is the common
  # way to land there"). Without parking, `--continue` refuses with "The
  # following untracked working tree files would be overwritten by merge".
  # Measured: deleting the untracked half of the recipe turns clash / root,
  # clash / sub and park fails partway red. This case is that guard rail.
  if [ "${2:-}" = clash ]; then printf 'made-by-rebase\n' > ren-new.txt; git add ren-new.txt; fi
  git add -A; git commit -qm mine2
  git rebase feat >/dev/null 2>&1
}

apply_state() {
  case $1 in
    tracked)      printf 'edited\n' > tracked.txt ;;
    staged)       printf 'edited\n' > tracked.txt; git add tracked.txt
                  git restore --staged -- tracked.txt ;;
    deleted)      git rm -q doomed.txt; git restore --staged -- doomed.txt ;;
    renamed|clash)
                  git mv ren-old.txt ren-new.txt
                  git restore --staged -- ren-old.txt ren-new.txt 2>/dev/null ;;
    untrackedonly)
                  printf 'wip\n' > brandnew.txt; mkdir -p deep/er; printf 'wip2\n' > deep/er/mine.txt ;;
    mixed)        printf 'edited\n' > tracked.txt
                  git rm -q doomed.txt; git restore --staged -- doomed.txt
                  printf 'wip\n' > brandnew.txt ;;
    spacepath)    printf 'wip\n' > 'my notes.txt'          # untracked, moved by mv
                  printf 'edited\n' > 'my tracked notes.txt'  # tracked, carried by the patch
                  printf 'edited\n' > tracked.txt ;;
    utf8path)     printf 'wip\n' > "$(printf 'caf\303\251.txt')"; printf 'edited\n' > tracked.txt ;;
    dashpath)     printf 'wip\n' > ./-draft.txt ;;
    globpath)     printf 'wip
' > './new[2].txt'; printf 'wip
' > './new{3}.txt' ;;
    quotepath)    printf 'wip\n' > './say "hi".txt' ;;
    tabpath)      printf 'wip\n' > "$(printf 'ta\tb.txt')" ;;
    spacesaround) printf 'wip\n' > './ lead and trail .txt' ;;
    newlinepath)  printf 'wip\n' > "$(printf 'two\nlines.txt')" ;;
    symlink)      ln -s tracked.txt userlink ;;
    brokenlink)   ln -s nowhere-at-all userbroken ;;
    linkmixed)    ln -s tracked.txt userlink; ln -s nowhere userbroken
                  printf 'edited\n' > tracked.txt
                  printf 'wip\n' > brandnew.txt ;;
    none)         : ;;
  esac
}

snapshot() {   # porcelain, plus type + content/target + mode, NUL-safe
  git -c core.quotePath=false status --porcelain --untracked-files=all | LC_ALL=C sort
  find . -path ./.git -prune -o ! -type d -print0 | LC_ALL=C sort -z |
  while IFS= read -r -d '' f; do
    if [ -L "$f" ]; then printf '%s link %s\n' "$f" "$(readlink -- "$f")"
    else printf '%s file %s %s\n' "$f" "$(git hash-object -- "$f")" "$(ls -l -- "$f" | cut -c1-10)"; fi
  done
}

write_input() {   # step 4's list, as the NUL file the recipe reads
  local g p x
  g=$(git rev-parse --git-dir)
  : > "$g/lean-park-input"
  git status --porcelain=v1 -z --untracked-files=all |
  while IFS= read -r -d '' entry; do
    x=${entry:0:2}
    p=${entry:3}
    case $x in UU|AA|DD|AU|UA|DU|UD|'M '|'A ') continue ;; esac
    printf '%s\0' "$p" >> "$g/lean-park-input"
  done
}

run_case() {          # $1 state  $2 root|sub
  state=$1; where=${2:-root}
  d="$WORK/$state-$where"
  ( set -u
    make_repo "$d" "$state" >/dev/null 2>&1
    apply_state "$state"
    before=$(snapshot)
    printf 'RES0\n' > f.txt; git add f.txt
    write_input
    g=$(git rev-parse --git-dir)
    runfrom="$d"; [ "$where" = sub ] && runfrom="$d/sub"
    parked=0
    if [ "$RUNNABLE" -eq 1 ] && [ -s "$g/lean-park-input" ]; then
      parked=1
      # ---- process A: park -------------------------------------------------
      ( cd "$runfrom" && . "$WORK/park.sh" ) || exit 21
      st="$d/.git/lean-parked.state"
      [ -s "$st" ] || { echo "park left no state file" >&2; exit 22; }
      pk="$d/.git/$(cat "$st")"
      # everything it recorded must already be out of the worktree
      while IFS= read -r -d '' p; do
        if [ -e "$d/$p" ] || [ -L "$d/$p" ]; then echo "still present after park: $p" >&2; exit 23; fi
      done < "$pk/manifest"
      # ...and every tracked path it claimed must be clean in the worktree now.
      # Without this a path the recipe silently failed to touch looks identical
      # before and after, and the round-trip passes having done nothing.
      while IFS= read -r -d '' p; do
        if [ -n "$(cd "$d" && git status --porcelain -- ":(literal,top)$p")" ]; then
          echo "tracked path not parked: $p" >&2; exit 31
        fi
      done < "$pk/tracked"
    else
      rm -f "$g/lean-park-input"
    fi
    # ---- process B: drive the rebase --------------------------------------
    ( cd "$d"
      n=0
      while [ $n -lt 12 ]; do
        gg=$(git rev-parse --git-dir)
        [ -d "$gg/rebase-merge" ] || [ -d "$gg/rebase-apply" ] || break
        n=$((n+1))
        if [ -n "$(git diff --name-only --diff-filter=U)" ]; then printf 'RES%s\n' "$n" > f.txt; git add f.txt; fi
        GIT_EDITOR=true git rebase --continue >/dev/null 2>&1
      done ) || true
    if [ -d "$d/.git/rebase-merge" ] || [ -d "$d/.git/rebase-apply" ]; then
      echo "rebase never finished (state=$state)" >&2; exit 24
    fi
    # ---- process C: restore, with nothing carried over --------------------
    if [ "$parked" -eq 1 ]; then
      ( cd "$runfrom" && env -u PARK -u PARK_NAME -u G -u STATE bash "$WORK/restore.sh" ) || exit 25
    fi

    if [ "$state" = clash ]; then
      [ "$(cat ren-new.txt)" = "made-by-rebase" ] || { echo "the operation's file was overwritten" >&2; exit 28; }
      pk=$(find "$d/.git" -maxdepth 1 -name 'lean-parked-*' -type d | head -1)
      { [ -n "$pk" ] && [ -f "$pk/untracked/ren-new.txt" ]; } || { echo "the user's copy was not preserved" >&2; exit 29; }
      [ -s "$d/.git/lean-parked.state" ] || { echo "state dropped while work is held" >&2; exit 30; }
    else
      after=$(snapshot | grep -v '^\(UU\|M \|MM\) f\.txt$' | grep -v '^\./f\.txt ')
      want=$(printf '%s\n' "$before" | grep -v '^\(UU\|M \|MM\) f\.txt$' | grep -v '^\./f\.txt ')
      if [ "$after" != "$want" ]; then
        echo "state differs (state=$state where=$where)" >&2
        diff <(printf '%s\n' "$want") <(printf '%s\n' "$after") | head -8 >&2
        exit 26
      fi
      if [ -n "$(find "$d/.git" -maxdepth 1 -name 'lean-parked-*')" ] || [ -e "$d/.git/lean-parked.state" ]; then
        echo "parking directory or state left behind" >&2; exit 27
      fi
    fi
  ) 2>"$WORK/err.$state.$where"
  rc=$?
  detail=$(grep -vE '^warning:|Falling back|^Applied|^Checking patch' "$WORK/err.$state.$where" | head -3 | tr '\n' ' ')
  report "$state / $where" "$rc" "rc=$rc ${detail:-(no extra output)}"
}

echo "recipe source: $SKILL"
[ "$RUNNABLE" -eq 1 ] || echo "  !! this skill has no runnable lean-skills:park / :restore blocks"

for s in tracked staged deleted renamed untrackedonly mixed none clash \
         spacepath utf8path dashpath globpath quotepath tabpath spacesaround; do
  run_case "$s" root
  run_case "$s" sub
done
if [ "$SYMLINKS" -eq 1 ]; then
  for s in symlink brokenlink linkmixed; do run_case "$s" root; run_case "$s" sub; done
else
  skipped 6 "symlink / brokenlink / linkmixed, root and sub (this platform makes copies, not links)"
fi
if [ "$NEWLINE_OK" -eq 1 ]; then
  run_case newlinepath root; run_case newlinepath sub
else
  skipped 2 "newlinepath, root and sub (this filesystem cannot hold a newline in a name)"
fi

# ---- park fails partway through the untracked moves ----------------------
partial_case() {
  d="$WORK/partial"
  ( set -u
    make_repo "$d" >/dev/null 2>&1
    printf 'wip\n' > one.txt; printf 'wip\n' > two.txt; printf 'wip\n' > three.txt
    printf 'RES0\n' > f.txt; git add f.txt
    before=$(snapshot)
    write_input
    # The shim lives outside the repo. Inside it, the test's own tooling shows up
    # as untracked work in the very tree it is about to compare - a test that
    # contaminates its subject cannot answer the question it is asking.
    pbin="$WORK/partial-bin"; mkdir -p "$pbin"
    real_mv=$(command -v mv)
    { printf '#!/bin/sh\n'
      printf 'for a in "$@"; do case "$a" in */untracked/two.txt) echo "mv: injected" >&2; exit 1 ;; esac; done\n'
      printf 'exec %s "$@"\n' "$real_mv"; } > "$pbin/mv"
    chmod +x "$pbin/mv"
    OLD_PATH=$PATH; PATH="$pbin:$PATH"
    [ "$(command -v mv)" = "$pbin/mv" ] || { PATH=$OLD_PATH; echo "shim not on PATH" >&2; exit 41; }
    ( cd "$d" && . "$WORK/park.sh" ) >/dev/null 2>&1
    prc=$?
    PATH=$OLD_PATH
    [ "$prc" -ne 0 ] || { echo "park returned 0 after a failed move" >&2; exit 42; }
    # whatever it claims to have parked must actually be there
    pk=$(find "$d/.git" -maxdepth 1 -name 'lean-parked-*' -type d | head -1)
    [ -n "$pk" ] || { echo "no parking area at all" >&2; exit 43; }
    while IFS= read -r -d '' q; do
      [ -e "$pk/untracked/$q" ] || { echo "manifest names $q but it is not parked" >&2; exit 44; }
      if [ -e "$d/$q" ]; then echo "manifest names $q but it is also still in the tree" >&2; exit 45; fi
    done < "$pk/manifest"
    # the file whose move failed must still be where the user left it
    [ -f "$d/two.txt" ] || { echo "two.txt was lost by the failed move" >&2; exit 46; }
    # Everything above only says the wreck is self-consistent. What the user
    # needs is their work back, and that is a different claim: the parking area
    # has to be findable, and restore has to hand it over. Without this the case
    # passes on a state where the files exist but nothing can reach them.
    [ -s "$d/.git/lean-parked.state" ] || {
      echo "park failed leaving $pk with nothing pointing at it" >&2; exit 47; }
    ( cd "$d" && env -u PARK -u PARK_NAME -u G -u STATE bash "$WORK/restore.sh" ) >/dev/null 2>&1 \
      || { echo "restore would not recover a half-finished parking" >&2; exit 48; }
    after=$(snapshot)
    if [ "$after" != "$before" ]; then
      echo "the tree did not come back to what it was before parking" >&2
      diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -8 >&2
      exit 49
    fi
    [ -z "$(find "$d/.git" -maxdepth 1 -name 'lean-parked-*')" ] \
      || { echo "the parking area outlived a successful recovery" >&2; exit 50; }
    [ ! -e "$d/.git/lean-parked.state" ] \
      || { echo "the state file outlived a successful recovery" >&2; exit 51; }
  ) 2>"$WORK/err.partial"
  rc=$?
  report "park fails partway" "$rc" "rc=$rc $(head -2 "$WORK/err.partial" | tr '\n' ' ')"
}
[ "$RUNNABLE" -eq 1 ] && partial_case

# ---- a parked name that is also a glob, beside a conflicted file ----------
# :(literal) is not decoration, but proving that needs the one arrangement in
# which its absence changes anything, and the obvious decoy is not it. Step 4's
# list excludes exactly two kinds of path: ones that are staged and nothing more
# -- where the worktree already equals the index, so a glob reaching them
# changes nothing -- and *conflicted* ones. So the only reachable damage is a
# conflicted file whose name a parked name matches as a glob.
#
# Measured, with a1.txt unmerged and a[1].txt holding the user's edit:
#   git checkout -- ':(literal,top)a[1].txt'  -> rc=0, a1.txt still has 3 stages
#   git checkout -- ':(top)a[1].txt'          -> error: path 'a1.txt' is unmerged
# which makes it the pathspec trap once more: the whole command is rejected,
# parking stops, and the user's edit is neither parked nor safe.
literal_case() {
  d="$WORK/globconflict"
  ( set -u
    rm -rf "$d"; git init -q "$d"; cd "$d" || exit 1
    git config user.email t@t; git config user.name t; git config commit.gpgsign false
    git config core.autocrlf false; git config core.safecrlf false
    printf 'base\n' > a1.txt
    printf 'base\n' > 'a[1].txt'
    git add -A; git commit -qm c0
    git checkout -qb feat; printf 'theirs\n' > a1.txt; git commit -aqm feat1
    git checkout -q master 2>/dev/null || git checkout -q main
    printf 'mine\n' > a1.txt; git commit -aqm mine1
    git rebase feat >/dev/null 2>&1
    [ "$(git ls-files -u -- a1.txt | wc -l)" -eq 3 ] \
      || { echo "the fixture produced no conflict on a1.txt" >&2; exit 51; }

    printf 'wip\n' > 'a[1].txt'
    wip_before=$(git hash-object -- 'a[1].txt')
    conflict_before=$(git hash-object -- a1.txt)

    # step 4's list: the conflicted path is excluded, exactly as the skill says
    g=$(git rev-parse --git-dir)
    printf '%s\0' 'a[1].txt' > "$g/lean-park-input"

    ( cd "$d" && . "$WORK/park.sh" ) || exit 52
    [ "$(git hash-object -- a1.txt)" = "$conflict_before" ] \
      || { echo "parking rewrote the conflicted file" >&2; exit 53; }
    [ "$(git ls-files -u -- a1.txt | wc -l)" -eq 3 ] \
      || { echo "parking resolved the conflict behind the user's back" >&2; exit 54; }

    # finish the operation the way the user would
    printf 'RESOLVED\n' > a1.txt; git add a1.txt
    GIT_EDITOR=true git rebase --continue >/dev/null 2>&1
    if [ -d "$g/rebase-merge" ] || [ -d "$g/rebase-apply" ]; then
      echo "rebase never finished" >&2; exit 55
    fi

    ( cd "$d" && env -u PARK -u PARK_NAME -u G -u STATE bash "$WORK/restore.sh" ) || exit 56
    [ "$(git hash-object -- 'a[1].txt')" = "$wip_before" ] \
      || { echo "the user's edit did not come back" >&2; exit 57; }
    [ "$(cat a1.txt)" = "RESOLVED" ] \
      || { echo "the resolution was overwritten on the way back" >&2; exit 58; }
  ) 2>"$WORK/err.literal"
  rc=$?
  report "glob name beside a conflicted file" "$rc" \
    "rc=$rc $(grep -vE '^warning:|Falling back|^Applied|^Checking patch' "$WORK/err.literal" | head -2 | tr '\n' ' ')"
}
[ "$RUNNABLE" -eq 1 ] && literal_case

# ---- the input list is not NUL-separated ---------------------------------
# Every other case in this file builds the list with write_input, which always
# uses printf '%s\0'. So nothing here has ever fed the recipe a malformed list,
# and the NUL check in park was unfalsifiable: delete it and the whole matrix
# stays green. `-s` does not help - a list written with '\n' is not empty, so
# it passes, and then every `read -d ''` reads nothing and park runs to
# completion having parked not one file while the patch covers the whole tree.
malformed_input_case() {
  d="$WORK/badinput"
  ( set -u
    make_repo "$d" >/dev/null 2>&1
    printf 'wip\n'    > listed.txt        # the path the user would name
    printf 'EDITED\n' > tracked.txt       # modified, and never named
    before=$(snapshot)
    g=$(git rev-parse --git-dir)
    printf '%s\n' listed.txt > "$g/lean-park-input"   # newline, not NUL
    ( cd "$d" && . "$WORK/park.sh" ) >/dev/null 2>&1
    prc=$?
    [ "$prc" -ne 0 ] || { echo "park accepted a newline-separated list" >&2; exit 61; }
    [ -z "$(find "$d/.git" -maxdepth 1 -name 'lean-parked-*')" ] \
      || { echo "park built a parking area from a malformed list" >&2; exit 62; }
    [ ! -e "$d/.git/lean-parked.state" ] \
      || { echo "park published state from a malformed list" >&2; exit 63; }
    # the list is still where step 4 left it, so it can be rebuilt and retried
    [ -s "$g/lean-park-input" ] || { echo "park consumed the list it rejected" >&2; exit 64; }
    after=$(snapshot)
    if [ "$after" != "$before" ]; then
      echo "the worktree moved on a list park refused" >&2
      diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -6 >&2
      exit 65
    fi
  ) 2>"$WORK/err.badinput"
  rc=$?
  report "input list is not NUL-separated" "$rc" \
    "rc=$rc $(grep -vE '^warning:' "$WORK/err.badinput" | head -2 | tr '\n' ' ')"
}
[ "$RUNNABLE" -eq 1 ] && malformed_input_case

echo
echo "$pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ]
