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



# Load-bearing, and only falsifiable because the matrix now feeds one
# malformed list. Before that case existed this rollback would have
# SURVIVED: every other input in the suite is built with printf '%s\0'.
run_rollback "park stops checking that the input list is NUL-terminated" \
  '   [ "$(tail -c 1 -- "$G/lean-park-input" | tr -d -c '"'"'\000'"'"' | wc -c)" -eq 1 ] ||
     die "input list is not NUL-terminated - build it with printf '"'"'%s\\0'"'"'"' \
  '   :' || bad=1

# Two guards in the recipe have no case here, and that is a statement rather
# than an omission:
#   * the directory entry guard in park's precheck - with step 3 asking for
#     `--untracked-files=all`, a legal list cannot contain a directory, so
#     rolling the guard back cannot turn anything red. It is defence in
#     depth, exactly like the two `specs` guards below it in the recipe.
#   * either half of the parent-symlink protection on its own - the walk and
#     the LANDED physical-path check are two layers over one vector, and
#     measurement says removing either alone leaves the matrix at 45/0/0.
#     They are rolled back together below; pinning one would be a case that
#     cannot fail.

#   * publishing the state before the first change to the working tree - with
#     the untracked side gone, park's only worktree change is `git checkout`,
#     and a wrong publish order costs nothing the *matrix* can see. Its
#     evidence moved to tests/parking_crash.sh, where moving the publish after
#     the checkout loop turns three kill points red (lines 75-77). A rollback
#     here would survive, so there is not one.
# No case for the two `specs` guards in the park block. They are defence in
# depth: with the NUL-termination check above them, a legal input list always
# yields one spec per entry, so `-s "$PARK/specs"` and the arity comparison are
# unreachable from any input this suite can build. Rolling them back therefore
# cannot turn the matrix red, and a rollback that cannot fail is decoration.
# They are labelled as such in the recipe rather than given a fabricated case.





# The 0.17.5 promise, and the only thing standing behind it. Untracked work is
# no longer moved, so the single thing the recipe still owes the user about it
# is *saying which paths it left alone*. Silence there is indistinguishable
# from having handled them. Deleting three guard cases along with the machinery
# they guarded is only honest if the replacement behaviour carries its own
# standing red, rather than a one-off demonstration at release time.
run_rollback "park stops reporting the untracked work it left alone" \
  '   [ -z "$LEFT" ] || printf '"'"'park: left in place, untracked and untouched:\n%s'"'"' "$LEFT"' \
  '   :' || bad=1

echo
if [ "$bad" -eq 0 ]; then
  echo "every rollback that could run was caught ($skips skipped)"
else
  echo "at least one rollback survived ($skips skipped)"
fi
[ "$bad" -eq 0 ]