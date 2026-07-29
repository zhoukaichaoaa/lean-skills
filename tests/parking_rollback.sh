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

run_rollback "no -- on dirname/mv in park" \
  '     mv -- "$p" "$PARK/untracked/$p" || die "cannot park $p (already parked: $(tr -cd '"'"'\0'"'"' < "$PARK/manifest" | wc -c))"' \
  '     mv "$p" "$PARK/untracked/$p" || die "cannot park $p"' || bad=1

run_rollback "no -- on dirname/mv in restore" \
  '     mv -- "$PARK/untracked/$p" "$p" || die "cannot put $p back"' \
  '     mv "$PARK/untracked/$p" "$p" || die "cannot put $p back"' || bad=1

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
  '     mv -- "$p" "$PARK/untracked/$p" || die "cannot park $p (already parked: $(tr -cd '"'"'\0'"'"' < "$PARK/manifest" | wc -c))"
     printf '"'"'%s\0'"'"' "$p" >> "$PARK/manifest" || die "parked $p but could not record it"' \
  '     printf '"'"'%s\0'"'"' "$p" >> "$PARK/manifest"
     mv -- "$p" "$PARK/untracked/$p" || die "cannot park $p (already parked: $(tr -cd '"'"'\0'"'"' < "$PARK/manifest" | wc -c))"' || bad=1

run_rollback "no collision guard on the way back" \
  '     if [ -e "$p" ] || [ -L "$p" ]; then HELD=1; continue; fi' \
  '     :' || bad=1


echo
if [ "$bad" -eq 0 ]; then echo "every rollback was caught"; else echo "at least one rollback survived"; fi
[ "$bad" -eq 0 ]