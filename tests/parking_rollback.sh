#!/bin/bash
# Roll back one fix at a time and prove the matrix notices.
#
# tests/parking_matrix.sh runs the recipe as written in SKILL.md. This copies
# the skill, reverts a single fix in the copy, and reruns the matrix against it.
# A rollback that still passes means that case proves nothing.
set -u
cd "$(dirname "$0")/.." || exit 1
SKILL=skills/resolving-merge-conflicts/SKILL.md
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

# Does this mv scan for options *after* the first operand? GNU does (it
# permutes), BSD/macOS does not. It decides whether one rollback below can fail
# at all: in park the dash-leading name is argument 1, which every mv parses as
# an option, but in restore it is argument 2, and a non-permuting mv has already
# stopped looking by then. The missing `--` is real on GNU and inert on BSD.
MV_PERMUTES=0
_mp=$(mktemp -d); : > "$_mp/src"
( cd "$_mp" && mv src -dst ) 2>/dev/null || MV_PERMUTES=1
rm -rf "$_mp"

skips=0
skip_case() { skips=$((skips+1)); printf '  skip      %-52s %s\n' "$1" "$2"; }

# run_rollback <label> <from> <to> [<from> <to> ...]
# More than one pair because some fixes are a *move*: undoing them means taking
# lines out in one place and putting them back in another, and a single
# substitution cannot express that.
run_rollback() {
  label=$1; shift
  cp "$SKILL" "$W/s.md"
  python - "$W/s.md" "$@" <<'PY' || { echo "  SETUP  $label"; return 1; }
import io, sys
p, rest = sys.argv[1], sys.argv[2:]
if len(rest) % 2:
    sys.exit('odd number of from/to arguments')
t = io.open(p, encoding='utf-8', newline='').read()
for i in range(0, len(rest), 2):
    frm, to = rest[i], rest[i + 1]
    # Exactly one, per pair, and against the text as edited so far - never
    # "at least one". A drifted anchor that still matches somewhere is how a
    # rollback quietly stops testing what its label claims, and this repo has
    # shipped that three times. Checking the progressive text also catches a
    # second pair whose anchor the first pair just disturbed.
    if t.count(frm) != 1:
        sys.exit('anchor appears %d times: %r' % (t.count(frm), frm[:60]))
    t = t.replace(frm, to)
io.open(p, 'w', encoding='utf-8', newline='').write(t)
PY
  out=$(bash tests/parking_matrix.sh "$W/s.md" 2>&1)
  if printf '%s' "$out" | grep -q ', 0 failed'; then
    printf '  SURVIVED  %s\n' "$label"
    return 1
  fi
  printf '  caught    %-52s %s\n' "$label" "$(printf '%s' "$out" | tail -1)"
  printf '%s\n' "$out" | grep '  FAIL' | sed 's/^/              /' | head -3
  return 0
}

bad=0

run_rollback "no state file: PARK cannot cross a process boundary" \
  '   mv -- "$STATE.tmp" "$STATE" || die "cannot publish state"' \
  '   :' || bad=1

run_rollback "restore trusts an inherited PARK instead of the state file" \
  '   PARK_NAME="$(cat -- "$STATE")" || die "cannot read state"' \
  '   PARK_NAME="${PARK_NAME:?}"' || bad=1

run_rollback "no -- on the mv in park" \
  '     mv -- "$p" "$PARK/untracked/$p" || die "cannot park $p (already parked: $(tr -d -c '"'"'\000'"'"' < "$PARK/manifest" | wc -c))"' \
  '     mv "$p" "$PARK/untracked/$p" || die "cannot park $p"' || bad=1

if [ "$MV_PERMUTES" -eq 1 ]; then
  run_rollback "no -- on the mv in restore" \
    '     mv -- "$PARK/untracked/$p" "$p" || die "cannot put $p back"' \
    '     mv "$PARK/untracked/$p" "$p" || die "cannot put $p back"' || bad=1
else
  # Not a weakness in the test and not a reason to drop the `--`: on this mv the
  # vector cannot exist, while on GNU it silently mangles the restore of any
  # path whose name starts with a dash.
  skip_case "no -- on the mv in restore" "this mv does not scan for options after the first operand"
fi

# An honest :(literal) case does exist, contrary to the note that used to sit
# here -- that note generalised from `b*c.txt`, which NTFS genuinely cannot
# store, while `a[1].txt` is legal everywhere. But the first version of this
# case rolled back the *specs* line and SURVIVED, because the patch is built
# with `git diff`, which is forgiving, and because a decoy that is merely
# staged has a worktree already equal to its index. The line that actually
# bites is the checkout: step 4's list excludes conflicted paths, so a
# conflicted file is precisely what the recipe must not reach, and reaching it
# is rejected outright (`error: path 'a1.txt' is unmerged`).
run_rollback "checkout loses :(literal) and reaches a conflicted file" \
  '     git checkout -- ":(literal,top)$p" || die "cannot restore $p from the index"' \
  '     git checkout -- ":(top)$p" || die "cannot restore $p from the index"' || bad=1

run_rollback "manifest written before the move succeeds" \
  '     mv -- "$p" "$PARK/untracked/$p" || die "cannot park $p (already parked: $(tr -d -c '"'"'\000'"'"' < "$PARK/manifest" | wc -c))"
     printf '"'"'%s\0'"'"' "$p" >> "$PARK/manifest" || die "parked $p but could not record it"' \
  '     printf '"'"'%s\0'"'"' "$p" >> "$PARK/manifest"
     mv -- "$p" "$PARK/untracked/$p" || die "cannot park $p (already parked: $(tr -d -c '"'"'\000'"'"' < "$PARK/manifest" | wc -c))"' || bad=1

# The fix this checks is a *move*, so undoing it is two edits: take the
# publish out of the top and put it back after the last move, which is
# exactly v0.17.1's order. Nothing else changes, so if the matrix stays
# green the recovery assertion in partial_case is not doing its job.
run_rollback "state published after the moves, as in v0.17.1" \
  '   printf '"'"'%s\n'"'"' "$PARK_NAME" > "$STATE.tmp" || die "cannot write state"
   mv -- "$STATE.tmp" "$STATE" || die "cannot publish state"
   mv -- "$G/lean-park-input" "$PARK/input" || die "cannot take the input list"' \
  '   mv -- "$G/lean-park-input" "$PARK/input" || die "cannot take the input list"' \
  '   done < "$PARK/untracked.list"' \
  '   done < "$PARK/untracked.list"
   printf '"'"'%s\n'"'"' "$PARK_NAME" > "$STATE.tmp" || die "cannot write state"
   mv -- "$STATE.tmp" "$STATE" || die "cannot publish state"' || bad=1

# Load-bearing, and only falsifiable because the matrix now feeds one
# malformed list. Before that case existed this rollback would have
# SURVIVED: every other input in the suite is built with printf '%s\0'.
run_rollback "park stops checking that the input list is NUL-terminated" \
  '   [ "$(tail -c 1 -- "$G/lean-park-input" | tr -d -c '"'"'\000'"'"' | wc -c)" -eq 1 ] ||
     die "input list is not NUL-terminated - build it with printf '"'"'%s\\0'"'"'"' \
  '   :' || bad=1

# No case for the two `specs` guards in the park block. They are defence in
# depth: with the NUL-termination check above them, a legal input list always
# yields one spec per entry, so `-s "$PARK/specs"` and the arity comparison are
# unreachable from any input this suite can build. Rolling them back therefore
# cannot turn the matrix red, and a rollback that cannot fail is decoration.
# They are labelled as such in the recipe rather than given a fabricated case.

run_rollback "no collision guard on the way back" \
  '     if [ -e "$p" ] || [ -L "$p" ]; then HELD=1; continue; fi' \
  '     :' || bad=1


echo
if [ "$bad" -eq 0 ]; then
  echo "every rollback that could run was caught ($skips skipped)"
else
  echo "at least one rollback survived ($skips skipped)"
fi
[ "$bad" -eq 0 ]