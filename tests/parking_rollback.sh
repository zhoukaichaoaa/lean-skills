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

# The untracked-parking loop, taken from the document itself.
UNTRACKED_LOOP=$(awk '/^   for p in \$UNTRACKED; do$/,/^   done$/' "$SKILL")
[ -n "$UNTRACKED_LOOP" ] || { echo "cannot find the untracked loop in $SKILL"; exit 2; }

# label | python replacement applied to the copy | states expected to break
run_rollback() {
  label=$1; frm=$2; to=$3
  cp "$SKILL" "$W/s.md"
  python - "$W/s.md" "$frm" "$to" <<'PY' || { echo "  SETUP  $label"; return 1; }
import io, sys
p, frm, to = sys.argv[1], sys.argv[2], sys.argv[3]
t = io.open(p, encoding='utf-8', newline='').read()
if t.count(frm) != 1:
    sys.exit('anchor appears %d times: %r' % (t.count(frm), frm[:60]))
io.open(p, 'w', encoding='utf-8', newline='').write(t.replace(frm, to))
PY
  out=$(bash tests/parking_matrix.sh "$W/s.md" 2>&1)
  if printf '%s' "$out" | grep -q '^0 failed$\|, 0 failed'; then
    printf '  SURVIVED  %s\n' "$label"
    return 1
  fi
  printf '  caught    %-46s %s\n' "$label" "$(printf '%s' "$out" | tail -1)"
  printf '%s\n' "$out" | grep '  FAIL' | sed 's/^/              /' | head -4
  return 0
}

bad=0
run_rollback "no cd to the worktree root" \
  '   cd "$(git rev-parse --show-toplevel)"
   G="$(git rev-parse --git-dir)"' \
  '   G="$(git rev-parse --git-dir)"' || bad=1

# Note: with the cd in place, :(top) is redundant by design. Removing it alone
# changes nothing, so there is no honest case for it here - it is defence in
# depth, not independently proven by this suite.

run_rollback "no empty-patch guard" \
  '   if [ -s "$PARK/tracked.patch" ]; then' \
  '   if true; then' || bad=1

run_rollback "untracked side not parked" \
  "$UNTRACKED_LOOP" \
  '   :' || bad=1

# The recipe loops per path, so an unknown path costs one iteration rather
# than the command. The trap only fires when every path goes in at once.
run_rollback "unstage every path in one command" \
  '     for p in $STAGED; do git restore --staged -- ":(top)$p"; done' \
  '     git restore --staged -- $(for p in $TRACKED $UNTRACKED; do printf ":(top)%s\\n" "$p"; done)' || bad=1

# A re-scan cannot see a symlink: find -type f skips it, so it is parked,
# never restored, and deleted with the parking area - while the block exits 0.
run_rollback "restore re-scans instead of reading the manifest" \
  '   while IFS= read -r -d '"''"' p; do' \
  '   for p in $(cd "$PARK/untracked" && find . -type f | sed "s|^./||"); do' || bad=1

# Not a case: the leftover guard cannot fail while the manifest is correct,
# so removing it alone changes nothing. It is the second line of defence for
# a manifest that missed something, and the manifest case above is what
# actually demonstrates the loss.

run_rollback "no collision guard on the way back" \
  '     if [ -e "$p" ] || [ -L "$p" ]; then CLASH=1; continue; fi' \
  '     :' || bad=1

echo
if [ "$bad" -eq 0 ]; then echo "every rollback was caught"; else echo "at least one rollback survived"; fi
[ "$bad" -eq 0 ]
