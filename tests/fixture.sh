#!/bin/sh
# Fetch a file out of a released tag, or die loudly naming the gate that wanted it.
#
#   tests/fixture.sh <tag> <path-in-repo> <dest> <what gate needs it>
#
# WHY THIS EXISTS. Every RED gate in CI proves itself by running against a
# released version: "the crash suite must fail on v0.17.2", "shellcheck must
# reject v0.17.0's park block". Each of them used to fetch its fixture inline:
#
#     git show "$old:path" > "$dest" 2>/dev/null || continue
#
# `actions/checkout` does not fetch tags by default, so `git show v0.17.2:...`
# failed on every run - and `|| continue` turned "I cannot reach the fixture"
# into "there is nothing to check". Seven gates. None of them ever executed.
# Every leg stayed green. The Windows leg is the plainest proof: its log says
# `fatal: invalid object name 'v0.12.0'.` and its conclusion says `success`.
#
# It surfaced in 0.17.7 only because a newly added gate forgot the fallback and
# exited 128. A missing safety net is what exposed the missing safety nets.
#
# So the fallback is not "improved" here, it is removed and centralised: this
# script is the only way a gate fetches a fixture, and it cannot be told to
# keep going. There is nothing left to forget.
#
# On success it prints one line. That line is the evidence the gate ran at all -
# a silent gate and an absent gate look identical in a log otherwise.
set -eu

[ $# -eq 4 ] || {
  echo "fixture.sh: need <tag> <path> <dest> <gate>" >&2
  exit 2
}
tag=$1
path=$2
dest=$3
gate=$4

# Where the released tags live. In CI that is the checkout itself, so `.` is
# the default. tests/mutations.py is the exception: its work copy is made with
# copytree(ignore='.git') on purpose - copying the index instead would carry
# this repo's uncommitted state along and break every "is the tree clean at the
# end?" assertion - so it points this at the real repository. Without it the
# gates would fail there for want of an object store, which is the same silence
# in different clothes.
repo=${LEAN_FIXTURE_REPO:-.}

if ! err=$(git -C "$repo" show "$tag:$path" 2>&1 >"$dest"); then
  echo "CI GATE BROKEN: cannot read '$path' from $tag" >&2
  echo "  this fixture is what proves: $gate" >&2
  echo "  looked in: $repo" >&2
  echo "  git said: $err" >&2
  echo "  (checkout must fetch tags - see fetch-depth in the workflow)" >&2
  exit 1
fi

[ -s "$dest" ] || {
  echo "CI GATE BROKEN: $tag:$path came back empty" >&2
  echo "  this fixture is what proves: $gate" >&2
  exit 1
}

echo "fixture ok: $tag:$path -> $gate"
