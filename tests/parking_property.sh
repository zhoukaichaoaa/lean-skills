#!/bin/bash
# Property test for the parking recipe: random worktree states, one invariant.
#
# The matrix and the rollback suite check states somebody thought of. Every
# recipe defect this project has shipped was a state nobody enumerated - a
# `notes/` directory folded into one status line, a parent that was a symlink,
# a leaf that pointed at a directory, a crash landing between the move and the
# bookkeeping. So this does not enumerate: it generates.
#
#   tests/parking_property.sh                     # 200 cases, this checkout
#   tests/parking_property.sh -n 50               # fewer cases
#   tests/parking_property.sh -s 12345            # fix the seed
#   tests/parking_property.sh -k <path/SKILL.md>  # another version, e.g. for RED
#   tests/parking_property.sh -c                  # also inject a crash per case
#
# THE INVARIANT. After park, then restore, every path the user had is in one
# of exactly two states:
#
#   (a) back where it was, byte for byte - same content, same mode, and for a
#       symlink the same target; or
#   (b) HELD: the parking area and the state file are both still there, and
#       restore named the path it is holding.
#
# Any third state is a violation. "Gone from the tree with nothing pointing at
# it" is the one this exists to catch, but so is "restore said it finished
# while the tree is short", and so is "held something the tree had room for".
#
# Not wired into the ordinary CI run: it is slow and it is random, so a red
# here must be reproducible from its seed before it means anything. Run it
# before a release, or on a schedule.
set -u
cd "$(dirname "$0")/.." || exit 1
export MSYS=${MSYS:-winsymlinks:nativestrict}

CASES=200
SEED=$(date +%s)
SKILL=skills/resolving-merge-conflicts/SKILL.md
CRASH=0
while [ $# -gt 0 ]; do
  case $1 in
    -n) CASES=$2; shift 2 ;;
    -s) SEED=$2; shift 2 ;;
    -k) SKILL=$2; shift 2 ;;
    -c) CRASH=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
# Validate rather than trust. `-n banana` used to make every arithmetic
# comparison false, so the loop ran zero times and the script exited 0 having
# tested nothing; `-n 0` did the same thing on purpose.
case $CASES in
  ''|*[!0-9]*) echo "-n needs a non-negative integer, got: $CASES" >&2; exit 2 ;;
esac
case $SEED in
  ''|*[!0-9]*) echo "-s needs a non-negative integer, got: $SEED" >&2; exit 2 ;;
esac
[ "$CASES" -gt 0 ] || { echo "-n must be at least 1" >&2; exit 2; }
[ -f "$SKILL" ] || { echo "no skill at $SKILL" >&2; exit 2; }
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
  echo "could not extract the recipe blocks from $SKILL" >&2; exit 2; }

# Can this platform make a real symlink? Git Bash needs
# MSYS=winsymlinks:nativestrict and still fails without the privilege, and
# calling those cases "passed" would be a lie in the flattering direction.
CAN_LINK=1
( cd "$W" && ln -s target probe 2>/dev/null && [ -L probe ] ) || CAN_LINK=0
rm -f "$W/probe"

# Does this filesystem carry the executable bit at all? On NTFS under Git Bash
# it does not: `chmod +x` returns 0 and leaves the mode exactly as it was. The
# generator used to flip that bit on a quarter of its files regardless, so on
# Windows those cases exercised nothing while counting as passes - the same
# flattering arithmetic this suite bans everywhere else. Probed, and counted
# separately when absent.
CAN_EXEC=1
( cd "$W" && printf '' > execprobe && chmod +x execprobe && [ -x execprobe ] ) 2>/dev/null || CAN_EXEC=0
rm -f "$W/execprobe"

pass=0; fail=0; skip=0
nocrash=0; unparseable=0
FAILED_SEEDS=

# The user's tree as bytes, not as porcelain: after a crash the index can say
# anything, and what matters is whether the files are there. Mode is included
# because a recipe that restores content but drops the executable bit has not
# put the file back.
snapshot() {
  find . -path ./.git -prune -o ! -type d -print0 | LC_ALL=C sort -z |
  while IFS= read -r -d '' f; do
    if [ -L "$f" ]; then
      printf '%s link %s\n' "$f" "$(readlink -- "$f")"
    else
      # `[ -x ]`, not a glob over `ls -l`. The old spelling was
      # `case $(ls -l -- "$f") in *x*)`, and every generated name ends in
      # `.txt` - whose middle letter is an x. So the pattern matched the
      # FILENAME, every file reported mode x, and this dimension compared
      # nothing at all. Byte-dumping the ls output is what settled it.
      if [ -x "$f" ]; then m=x; else m=-; fi
      printf '%s file%s %s\n' "$f" "$m" "$(git hash-object -- "$f")"
    fi
  done
}

# ---- the generator -------------------------------------------------------
# Every name in this pool has cost this project something, or is one keystroke
# from a name that did. NTFS cannot hold `*` or a newline, so those are not
# here: a case that cannot exist on one of the two supported platforms is not
# a case, it is a skip waiting to be miscounted.
NAMES=(
  'plain.txt'
  'my notes.txt'
  '-draft.txt'
  'a[1].txt'
  "it's.txt"
  'ünïcode.txt'
  'deep/nest/ed/leaf.txt'
  'sub dir/inside it.txt'
  'trailing.space .txt'
  'two  spaces.txt'
)

# A deterministic PRNG whose state lives in a variable, NOT $RANDOM.
#
# $RANDOM cannot be used here: every `$(rnd n)` is a command substitution, so
# it runs in a subshell, and bash reseeds $RANDOM per subshell from the pid.
# The seed would control only the parent, and the generator would be genuinely
# random - which this harness caught by failing to reproduce its own failure
# twice in a row. A property test that cannot replay its counterexample is
# worse than none: it reports defects nobody can act on.
#
# So: linear congruential, state in RSTATE, result in RVAL, no subshell.
# Callers write `rnd 3` then read $RVAL.
RSTATE=0
rnd() {
  RSTATE=$(( (RSTATE * 1103515245 + 12345) & 0x7FFFFFFF ))
  RVAL=$(( (RSTATE / 65536) % $1 ))
}

# A second, independent stream for choosing the kill point.
#
# Sharing one stream tied the kill point to the conflict shape: the generator
# draws the shape with `rnd 3` and the injector then drew from whatever state
# that left, so with the case count a multiple of 3 each kill point locked onto
# a single shape (measured: N=45 reached 45 of 135 combinations; N=44 reached
# all 132). Both streams are still derived from the same seed, so a run remains
# exactly reproducible - they just no longer walk in step.
KSTATE=0
krnd() {
  KSTATE=$(( (KSTATE * 1103515245 + 12345) & 0x7FFFFFFF ))
  KVAL=$(( (KSTATE / 65536) % $1 ))
}

# Build a repo with a random in-flight state on top of a random conflict.
# Echoes the paths it put on park's input list.
build_case() {
  d=$1
  # `-b main`, not whatever init.defaultBranch happens to say. The old code
  # created the repo with the ambient default and then did
  # `git checkout master 2>/dev/null || git checkout main`, so on a box
  # configured with defaultBranch=trunk BOTH failed, stderr went to /dev/null,
  # no conflict was ever created, and every case ran against a clean repo and
  # passed. Measured: 8/8 "passed" that way.
  rm -rf "$d"; git init -q -b main "$d" || return 1
  cd "$d" || return 1
  git config user.email t@t; git config user.name t
  git config commit.gpgsign false
  git config core.autocrlf false; git config core.safecrlf false

  printf 'base\n' > conflicted.txt
  printf 'base\n' > carrier.txt
  git add -A >/dev/null 2>&1; git commit -qm c0

  # a random conflict shape - all three leave a different set of pseudo-refs
  # and a different abort behaviour, and the recipe runs under all of them
  git checkout -qb other
  printf 'theirs\n' > conflicted.txt
  git commit -aqm theirs
  git checkout -q main
  printf 'mine\n' > conflicted.txt
  git commit -aqm mine
  rnd 3
  case $RVAL in
    0) git merge other       >/dev/null 2>&1 ;;
    1) git rebase other      >/dev/null 2>&1 ;;
    2) git cherry-pick other >/dev/null 2>&1 ;;
  esac
  # ...and it must ACTUALLY be a conflict. A generator that quietly produces
  # clean repositories reports a clean sweep and proves nothing, which is
  # exactly what the defaultBranch bug did. Exit 2 rather than 1: a broken
  # fixture is not a case to skip, it is a reason to stop.
  if ! git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 &&
     ! git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 &&
     [ ! -d .git/rebase-merge ] && [ ! -d .git/rebase-apply ] &&
     ! grep -q '^<<<<<<<' conflicted.txt 2>/dev/null; then
    echo "FIXTURE BROKEN: operation $RVAL left no conflict; the case would test nothing" >&2
    return 2
  fi

  # ...and a random pile of in-flight work on top of it
  rnd 6; n=$((1 + RVAL))
  i=0
  used=
  : > "$W/paths"
  while [ "$i" -lt "$n" ]; do
    i=$((i + 1))
    rnd ${#NAMES[@]}; p=${NAMES[$RVAL]}
    case " $used " in *" $p "*) continue ;; esac
    used="$used $p"
    dir=$(dirname -- "$p")
    [ "$dir" = "." ] || mkdir -p -- "$dir" || continue

    rnd 10; kind=$RVAL
    if [ "$kind" -lt 2 ]; then
      # A symlink: to a file, to a directory, or dangling. Where the platform
      # cannot make a real one, the shape is counted separately rather than
      # quietly becoming a plain file that passes - a skip folded into the
      # pass count is the flattering kind of lie this project keeps banning.
      if [ "$CAN_LINK" -eq 0 ]; then
        echo x >> "$W/linkskip"
        printf 'brand new\n' > "$p" || continue
      else
        rnd 3
        case $RVAL in
          0) ln -s carrier.txt -- "$p" 2>/dev/null || continue ;;
          1) mkdir -p -- "$W/ldir"; ln -s "$W/ldir" -- "$p" 2>/dev/null || continue ;;
          2) ln -s no-such-target -- "$p" 2>/dev/null || continue ;;
        esac
        echo x >> "$W/linkmade"
      fi
    elif [ "$kind" -lt 6 ]; then
      # tracked, then edited (the case park actually moves)
      printf 'committed\n' > "$p" || continue
      git add -- "$p" >/dev/null 2>&1 || continue
      git commit -qm "add" >/dev/null 2>&1
      rnd 2
      if [ "$RVAL" -eq 0 ]; then
        printf 'edited in flight\n' > "$p"
      else
        printf 'staged in flight\n' > "$p"; git add -- "$p" >/dev/null 2>&1
      fi
      rnd 4
      if [ "$RVAL" -eq 0 ]; then
        if [ "$CAN_EXEC" -eq 1 ]; then
          chmod +x -- "$p" 2>/dev/null && echo x >> "$W/execmade"
        else
          echo x >> "$W/execskip"
        fi
      fi
    else
      # untracked: park must leave these exactly where they are
      printf 'brand new\n' > "$p" || continue
    fi
    printf '%s\n' "$p" >> "$W/paths"
  done

  [ -s "$W/paths" ] || return 1
  g=$(git rev-parse --git-dir)
  : > "$g/lean-park-input"
  while IFS= read -r p; do
    printf '%s\0' "$p" >> "$g/lean-park-input"
  done < "$W/paths"
  return 0
}

# ---- the invariant -------------------------------------------------------
# $1 repo, $2 restore's own output, $3 1 if this case was crashed. Prints the
# reason on failure.
check() {
  d=$1; out=$2; crashed=$3
  ( cd "$d" || exit 1
    now=$(snapshot)
    if [ "$now" = "$BEFORE" ]; then
      # State (a): everything is back. With no crash, a leftover state file is
      # a defect - the next park refuses to start over it.
      [ -e .git/lean-parked.state ] || exit 0
      # After a crash it is not. Measured, seed 7026: the kill lands just after
      # the patch is written and before the checkout loop reverts the tree, so
      # the tree still holds the edits, `git apply --3way` finds its preimage
      # already applied ("does not match index"), and restore HOLDS rather than
      # deleting a patch it could not replay. Nothing is lost and the recipe
      # tells the user how to clear it. Holding is the correct answer there, so
      # requiring a clean state file would be requiring the wrong behaviour.
      [ "$crashed" = "1" ] || {
        echo "tree is back, but a state file was left behind"; exit 1; }
      # ...but the hold still has to be a real one, not an empty shell
      pk=".git/$(cat .git/lean-parked.state)"
      [ -d "$pk" ] || { echo "crash: state names $pk, which is not there"; exit 1; }
      case $out in
        *"$pk"*) ;;
        *) echo "crash: kept $pk but never named it in its output"; exit 1 ;;
      esac
      exit 0
    fi
    # not byte-identical, so every difference must be covered by state (b)
    [ -s .git/lean-parked.state ] || {
      echo "tree differs from before and NO state file points at anything"; exit 1; }
    pk=".git/$(cat .git/lean-parked.state)"
    [ -d "$pk" ] || { echo "state names $pk, which is not there"; exit 1; }
    [ -n "$(find "$pk" -mindepth 1 ! -type d -print 2>/dev/null | head -n 1)" ] || {
      echo "held an empty parking area while the tree is short"; exit 1; }
    # ...and restore has to have SAID so. A silent hold is a loss the user
    # never hears about, which is the same as a loss.
    case $out in
      *"$pk"*) ;;
      *) echo "kept $pk but never named it in its output"; exit 1 ;;
    esac
    # A held area is legitimate only for entries something is actually blocking.
    # A file kept in the parking area while its slot in the tree stands empty is
    # a loss wearing a different hat: restore could have put it back and did not.
    #
    # This is the check that catches v0.17.2's manifest defect, and leaving it
    # out is how the same defect walked past this suite: 139 crashed cases on
    # that version, every one of them "passed", while `my notes.txt` sat in the
    # parking area with its path in the tree free. The byte comparison above
    # cannot see it - the area exists, the state file exists, restore even named
    # the path. Only "was anything actually blocking it?" separates the two.
    # WHAT A HOLD MAY AND MAY NOT EXCUSE.
    #
    # It excuses exactly one thing: the paths park recorded in $PARK/tracked,
    # whose edits are sitting in a patch that would not apply. Those are allowed
    # to differ from BEFORE - that is what being held means.
    #
    # It excuses nothing else. A path restore never parked must come back byte
    # for byte; a path that vanished is a loss whatever the area says; and
    # nothing may appear that was not there before.
    #
    # The first version of this asked only "did a vanished path's slot stay
    # occupied". Audited against a deliberately malicious restore - one that
    # skips the patch, rewrites a file it never parked, drops litter, and
    # announces a hold as usual - that check passed 6 of 6. Both directions
    # below are what make it fail.
    printf '%s\n' "$BEFORE" > "$W/chk-before"
    printf '%s\n' "$now"    > "$W/chk-after"
    : > "$W/chk-held"
    if [ -s "$pk/tracked" ]; then
      while IFS= read -r -d '' hp; do
        printf './%s\n' "$hp" >> "$W/chk-held"
      done < "$pk/tracked"
    fi
    in_area() {   # $1 worktree-relative path -> 0 when the area is holding it
      rel=${1#./}
      [ -e "$pk/untracked/$rel" ] || [ -L "$pk/untracked/$rel" ]
    }
    # Strip the two trailing fields (type, then hash or link target) to get the
    # path back. Parameter expansion, not `rev | cut`: MSYS has no `rev`, and
    # that spelling silently produced an empty path - a red for the wrong
    # reason, indistinguishable from a real one until someone reads the message
    # and sees no path in it. Shortest-suffix match handles names with spaces,
    # including two in a row and a trailing one.
    #
    # (i) everything that existed before
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      grep -qxF -- "$line" "$W/chk-after" && continue
      p=${line% * *}
      [ -n "$p" ] || {
        echo "internal: cannot parse a snapshot line: $line"; exit 1; }
      if [ -e "$p" ] || [ -L "$p" ]; then
        # still there, but not byte-identical. Only the parked set may differ.
        grep -qxF -- "$p" "$W/chk-held" || {
          echo "changed $p, which the hold does not account for"; exit 1; }
      else
        # gone from the tree. Report which kind, because they read very
        # differently to whoever has to act on it - but both are violations.
        if in_area "$p"; then
          echo "held $p while its path in the tree was free"
        else
          echo "lost $p entirely: not in the tree, not in the parking area"
        fi
        exit 1
      fi
    done < "$W/chk-before"
    # (ii) ...and the other direction, which the first version never looked at
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      grep -qxF -- "$line" "$W/chk-before" && continue
      p=${line% * *}
      [ -n "$p" ] || {
        echo "internal: cannot parse a snapshot line: $line"; exit 1; }
      grep -qxF -- "$p" "$W/chk-held" || {
        echo "restore left $p behind, and nothing accounts for it"; exit 1; }
    done < "$W/chk-after"
    exit 0
  )
}

crash_note=
[ "$CRASH" -eq 1 ] && crash_note=", crash injection on"
echo "seed $SEED, $CASES cases, skill $SKILL$crash_note"
[ "$CAN_LINK" -eq 1 ] || echo "  (no real symlinks on this platform: those shapes are skipped)"

c=0
while [ "$c" -lt "$CASES" ]; do
  c=$((c + 1))
  s=$((SEED + c))
  RSTATE=$s
  KSTATE=$(( (s * 2654435761 + 1013904223) & 0x7FFFFFFF ))
  d="$W/case"
  brc=0
  ( build_case "$d" ) > "$W/build.log" 2>&1 || brc=$?
  if [ "$brc" -eq 2 ]; then
    # a broken fixture is not a skip. Skipping it is how a suite ends up
    # reporting a sweep of passes over repositories that had nothing to test.
    echo "FIXTURE BROKEN at seed $s:"
    sed 's/^/    /' "$W/build.log"
    exit 2
  elif [ "$brc" -ne 0 ]; then
    skip=$((skip + 1))
    continue
  fi
  # build_case ran in a subshell for the cd; redo the input list here
  ( cd "$d" && BEFORE=$(snapshot) && printf '%s' "$BEFORE" > "$W/before" )
  BEFORE=$(cat "$W/before")
  export BEFORE

  # `bash -c` rather than a plain subshell: when SIGKILL lands, the "Killed"
  # notice is printed by whichever shell was *waiting* on the dead process, and
  # a redirect inside that process cannot silence its own parent. So the wrapper
  # has to survive to be the one that prints it - hence no `exec` here, which
  # would replace the wrapper with the very process about to be killed and put
  # the notice back on this script's stderr. (It did, until this comment.)
  # Two things at once here, and both are load-bearing:
  #
  # `rc=$?; exit $rc` rather than a bare command, because bash execs instead of
  # forking when the last thing it has to do is one command - that would replace
  # this wrapper with the process about to be SIGKILLed and hand the "Killed"
  # notice straight back to this script's stderr. A statement after it forces
  # the fork. It must also *carry the exit code out*: a plain `; :` silences the
  # notice and throws away the 137 that proves the kill landed, which would let
  # a crash that never fired count as a crash case.
  runpark() {  # $1 script to run -> exit code of park
    bash -c 'cd "$1" && env -u PARK -u PARK_NAME -u G -u STATE bash "$2"; rc=$?; exit $rc' \
      _ "$d" "$1" >/dev/null 2>&1
  }
  KILLED_AT=-
  if [ "$CRASH" -eq 1 ]; then
    # A line ending in `||`, `&&` or a backslash is not an injection point:
    # appending `kill -9 $$` after it makes the kill that operator's right-hand
    # operand, so what runs is a different recipe from the one under test and
    # the case gets banked as a valid non-crash. The current park block has two
    # such lines (22 and 73); both were verified benign, but benign is not
    # accounted for.
    PTS=$(awk 'NF && $1 !~ /^#/ {
        if ($0 ~ /\|\|[ \t]*$/ || $0 ~ /&&[ \t]*$/ || $0 ~ /\\[ \t]*$/) next
        print NR }' "$W/park.sh")
    set -- $PTS
    krnd $#
    k=$(eval echo "\${$(( KVAL + 1 ))}")
    awk -v k="$k" 'NR==k {print; print "kill -9 $$"; next} {print}' "$W/park.sh" > "$W/park-c.sh"
    if bash -n "$W/park-c.sh" 2>/dev/null; then
      runpark "$W/park-c.sh"; prc=$?
      # 137 = SIGKILL. Anything else means the injected kill was never reached -
      # park exited early, or the line sits in a branch this case does not take.
      # The case is still a valid non-crash case, but counting it as crash
      # coverage would be inventing evidence, so it is tallied on its own.
      if [ "$prc" -eq 137 ]; then
        KILLED_AT=$k
      else
        nocrash=$((nocrash + 1))
      fi
    else
      # injecting inside an if/while header is a syntax error, not a test case
      runpark "$W/park.sh"
      unparseable=$((unparseable + 1))
    fi
  else
    runpark "$W/park.sh"
  fi

  rout=$( cd "$d" && env -u PARK -u PARK_NAME -u G -u STATE bash "$W/restore.sh" 2>&1 )

  # The relaxed branch keys off whether THIS case actually died, not off
  # whether -c was passed: a case where the kill never fired is an ordinary
  # case, and holding it to the ordinary standard is the whole point.
  did_crash=0
  [ "$KILLED_AT" = "-" ] || did_crash=1
  if detail=$(check "$d" "$rout" "$did_crash"); then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    FAILED_SEEDS="$FAILED_SEEDS $s"
    printf '  FAIL  seed %s: %s\n' "$s" "$detail"
    printf '        killed after park.sh line: %s\n' "$KILLED_AT"
    [ "$KILLED_AT" = "-" ] || printf '          %s\n' "$(sed -n "${KILLED_AT}p" "$W/park.sh")"
    printf '        paths in this case:\n'
    sed 's/^/          /' "$W/paths"
    printf '        restore said:\n'
    printf '%s\n' "$rout" | sed 's/^/          /'
    printf '        state / parking area:\n'
    ( cd "$d" && {
        if [ -e .git/lean-parked.state ]; then
          printf '          state -> %s\n' "$(cat .git/lean-parked.state)"
          find ".git/$(cat .git/lean-parked.state)" -mindepth 1 2>/dev/null |
            sed 's/^/          /' | head -n 8
        else
          printf '          (no state file)\n'
        fi
      } )
    if [ "$fail" -ge 5 ]; then
      echo "  (stopping after 5 failures; rerun one with -n 1 -s $((s - 1)))"
      break
    fi
  fi
done

echo
echo "$pass passed, $fail failed, $skip skipped"
# Symlink coverage is reported on its own line and never folded into the pass
# count: on a platform that cannot make one, "200 passed" would otherwise read
# as though the symlink shapes had been exercised.
made=0; [ -f "$W/linkmade" ] && made=$(wc -l < "$W/linkmade")
lskip=0; [ -f "$W/linkskip" ] && lskip=$(wc -l < "$W/linkskip")
echo "symlink shapes: $made generated, $lskip skipped for lack of platform support"
xmade=0; [ -f "$W/execmade" ] && xmade=$(wc -l < "$W/execmade")
xskip=0; [ -f "$W/execskip" ] && xskip=$(wc -l < "$W/execskip")
echo "executable-bit shapes: $xmade generated, $xskip skipped for lack of platform support"
# Crash coverage is reported separately for the same reason: a case whose
# injected kill never fired is a real case, but it is not crash evidence, and
# folding it in would overstate what this run proved.
if [ "$CRASH" -eq 1 ]; then
  echo "crash injection: $((pass + fail - nocrash - unparseable)) cases actually died (SIGKILL), $nocrash never reached the kill, $unparseable injection points unparseable"
  nexcl=$(awk 'NF && $1 !~ /^#/ && ($0 ~ /\|\|[ 	]*$/ || $0 ~ /&&[ 	]*$/ || $0 ~ /\[ 	]*$/)' "$W/park.sh" | grep -c . || true)
  echo "  ($nexcl line(s) excluded from the injection set: a kill appended there would become the right-hand side of a continuation operator)"
fi
[ -z "$FAILED_SEEDS" ] || echo "reproduce:$(for s in $FAILED_SEEDS; do printf ' -n 1 -s %s' $((s - 1)); done)"

# Green means something was actually proved. `fail == 0` on its own is true of
# a run that graded nothing at all - every case skipped, or the loop never
# entered. Require that as many cases were attempted as were asked for, and
# that at least one of them was graded.
attempted=$((pass + fail + skip))
if [ "$attempted" -ne "$CASES" ]; then
  echo "attempted $attempted of $CASES requested cases - not a clean run" >&2
  exit 1
fi
if [ "$((pass + fail))" -eq 0 ]; then
  echo "every case was skipped; nothing was graded" >&2
  exit 1
fi
[ "$fail" -eq 0 ]
