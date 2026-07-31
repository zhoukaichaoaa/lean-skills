#!/bin/sh
# Can the recipe or script in <file> actually RUN on this platform?
#
#   tests/can_stage.sh <file> <gate description>
#
#   exit 0 - yes; prints nothing, the caller proceeds with its gate
#   exit 1 - no;  prints one line naming the gate and what blocks it
#
# WHY THIS EXISTS. A RED gate proves a suite still catches an old defect by
# running that old release. If the old release dies on something *else* first -
# a GNU-only construct this platform's tools reject - the suite finds no
# violation and the gate reads as a pass. Measured, 0.17.7: v0.17.0's park
# builds pathspecs with `xargs -0 -a`, BSD xargs rejects `-a` outright, so on
# macOS the recipe never reached the line under test, the property test
# correctly reported nothing wrong, and the gate went green having proved
# nothing at all.
#
# A gate that cannot be staged is a SKIP TO BE COUNTED. Never a pass.
#
# Each probe asks the platform rather than guessing from `uname`: the question
# is not "is this macOS" but "does this xargs take -a". Constructs come from
# 0.17.1, which is where every one of them cost a release.
#
# Only *blocking* constructs belong here. `tr -cd '\0'` versus `tr -d -c '\000'`
# is a behaviour difference, not a stoppage - the recipe still runs, so the gate
# can still be staged and should be allowed to speak.
set -eu

[ $# -eq 2 ] || { echo "can_stage.sh: need <file> <gate>" >&2; exit 2; }
f=$1
gate=$2
[ -f "$f" ] || { echo "can_stage.sh: no such file: $f" >&2; exit 2; }

# Comments are stripped first, and that is load-bearing: v0.17.2's park carries
# the sentence "`xargs -a` is a GNU extension that BSD/macOS xargs rejects" in a
# comment. Grepping the raw text would rule that recipe unstageable on BSD on
# the strength of a remark about the very fault it fixed.
#
# <file> may be a whole SKILL.md or an already-extracted block; both work. A
# recipe's own comments are indented `#` lines in either form, and the markdown
# prose around them does not spell these constructs the way a command line does.
# Verified both ways against v0.17.0 (blocked) and v0.17.2 (stageable).
body=$(grep -v '^[[:space:]]*#' "$f" || true)

skip() {
  echo "gate skipped (counted, NOT a pass): $gate"
  echo "  fixture cannot run on this platform: $1"
  exit 1
}

# `xargs -a FILE`: GNU extension. BSD xargs exits with "illegal option".
if printf '%s\n' "$body" | grep -q 'xargs .*-a ' &&
   ! xargs -a /dev/null true >/dev/null 2>&1; then
  skip "uses 'xargs -a', which this platform's xargs rejects"
fi

# `dirname --`: BSD dirname takes no options, so the `--` that was meant to
# protect a leading-dash name becomes the operand.
if printf '%s\n' "$body" | grep -q 'dirname --' &&
   ! dirname -- /a/b >/dev/null 2>&1; then
  skip "uses 'dirname --', which this platform's dirname takes as an operand"
fi

# `find ... -quit`: not in every find.
if printf '%s\n' "$body" | grep -q -- '-quit' &&
   ! find . -maxdepth 0 -quit >/dev/null 2>&1; then
  skip "uses 'find -quit', which this platform's find does not have"
fi

exit 0
