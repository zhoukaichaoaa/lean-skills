#!/bin/bash
# Drive install.sh through a state matrix, running the real script.
#
# The installer replaces and deletes directories under the user's control, so
# each case asserts the exit code, the full tree (type, content, mode and link
# target of every entry), and that no staging or outgoing directory survives.
#
#   tests/install_matrix.sh                 # this checkout's install.sh
#   tests/install_matrix.sh <path/to/sh>    # e.g. an older tag, for RED
set -u
cd "$(dirname "$0")/.." || exit 1
INSTALLER=${1:-$PWD/install.sh}
case $INSTALLER in /*|[A-Za-z]:*) ;; *) INSTALLER=$PWD/$INSTALLER ;; esac
[ -f "$INSTALLER" ] || { echo "no installer at $INSTALLER"; exit 2; }

export MSYS=${MSYS:-winsymlinks:nativestrict}
probe=$(mktemp -d); SYMLINKS=0
if ln -s target "$probe/l" 2>/dev/null && [ -L "$probe/l" ]; then SYMLINKS=1; fi
rm -rf "$probe"

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SRCROOT=$W/src; mkdir -p "$SRCROOT"
cp -R skills "$SRCROOT/"; cp "$INSTALLER" "$SRCROOT/install.sh"; chmod +x "$SRCROOT/install.sh"
MARKER='installed by lean-skills; uninstall removes only directories carrying this file'

pass=0; fail=0
report() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); printf '  ok    %s\n' "$1"
           else fail=$((fail+1)); printf '  FAIL  %s\n        %s\n' "$1" "$3"; fi; }

tree_of() {   # type + content/target + mode of everything under $1
  find "$1" -mindepth 1 | LC_ALL=C sort | while IFS= read -r e; do
    rel=${e#"$1"/}
    if [ -L "$e" ]; then printf '%s link %s\n' "$rel" "$(readlink "$e")"
    elif [ -d "$e" ]; then printf '%s dir\n' "$rel"
    else printf '%s file %s %s\n' "$rel" "$(git hash-object "$e")" "$(ls -l "$e" | cut -c1-10)"; fi
  done
}

no_scratch() {   # no staging or outgoing may survive, ever
  [ -z "$(find "$1" -maxdepth 1 -name '.lean-skills-staging-*' -o -maxdepth 1 -name '.lean-skills-outgoing-*' 2>/dev/null)" ]
}

# $1 label  $2 occupant  $3 args  $4 expected exit  $5 expect: keep|replace
case_run() {
  label=$1; occupant=$2; args=$3; want_rc=$4; expect=$5
  d=$W/t$((pass+fail))-$(echo "$label" | tr -c 'a-z0-9' '-')
  ( mkdir -p "$d/target"
    case $occupant in
      none)   : ;;
      dir)    mkdir -p "$d/target/tdd"; printf 'USERS\n' > "$d/target/tdd/SKILL.md" ;;
      ours)   mkdir -p "$d/target/tdd"; printf 'OLD\n' > "$d/target/tdd/SKILL.md"
              printf '%s\n' "$MARKER" > "$d/target/tdd/.lean-skills" ;;
      file)   printf 'USERS FILE\n' > "$d/target/tdd" ;;
      link)   printf 'elsewhere\n' > "$d/elsewhere"; ln -s ../elsewhere "$d/target/tdd" ;;
      broken) ln -s nowhere-at-all "$d/target/tdd" ;;
    esac
    before=$(tree_of "$d/target")
    set +e
    CLAUDE_SKILLS_DIR="$d/target" "$SRCROOT/install.sh" $args >"$d/out" 2>&1
    rc=$?
    set -e
    [ "$rc" -eq "$want_rc" ] || { echo "exit $rc, want $want_rc" >&2; exit 11; }
    no_scratch "$d/target" || { echo "scratch left behind" >&2; exit 12; }
    case $expect in
      keep)
        # the occupant must be untouched, byte for byte, type for type
        got=$(tree_of "$d/target" | grep '^tdd')
        want=$(printf '%s\n' "$before" | grep '^tdd')
        [ "$got" = "$want" ] || { echo "occupant changed:" >&2; diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") >&2; exit 13; } ;;
      replace)
        [ -f "$d/target/tdd/SKILL.md" ] || { echo "tdd was not installed" >&2; exit 14; }
        grep -qxF "$MARKER" "$d/target/tdd/.lean-skills" || { echo "no marker" >&2; exit 15; }
        diff -r --exclude=.lean-skills "$SRCROOT/skills/tdd" "$d/target/tdd" >/dev/null \
          || { echo "installed tdd differs from source" >&2; exit 16; } ;;
      gone)
        [ ! -e "$d/target/tdd" ] && [ ! -L "$d/target/tdd" ] || { echo "tdd survived uninstall" >&2; exit 17; } ;;
    esac
  ) 2>"$W/err" ; rc=$?
  report "$label" "$rc" "$(head -2 "$W/err" | tr '\n' ' ')"
}

echo "installer under test: $INSTALLER"

# ---- fresh install ------------------------------------------------------
case_run "fresh install"                 none  "-y"          0 replace

# ---- an occupant we did not install: kept by default, adopted on request
for occ in dir file $( [ "$SYMLINKS" -eq 1 ] && echo link broken ); do
  case_run "occupied by $occ, default"   "$occ" "-y"         3 keep
  case_run "occupied by $occ, --adopt"   "$occ" "-y --adopt" 0 replace
done

# ---- managed upgrade: ours, no prompt needed ----------------------------
case_run "managed upgrade"               ours  "-y"          0 replace

# ---- uninstall ----------------------------------------------------------
uninstall_case() {   # $1 label  $2 occupant  $3 args  $4 rc  $5 expect
  label=$1; occ=$2; args=$3; want=$4; expect=$5
  d=$W/u$((pass+fail))
  ( mkdir -p "$d/target"
    CLAUDE_SKILLS_DIR="$d/target" "$SRCROOT/install.sh" -y >/dev/null 2>&1
    case $occ in
      ours)   : ;;
      dir)    rm -rf "$d/target/tdd"; mkdir -p "$d/target/tdd"; printf 'USERS\n' > "$d/target/tdd/SKILL.md" ;;
      file)   rm -rf "$d/target/tdd"; printf 'USERS FILE\n' > "$d/target/tdd" ;;
      broken) rm -rf "$d/target/tdd"; ln -s nowhere "$d/target/tdd" ;;
    esac
    before=$(tree_of "$d/target" | grep '^tdd')
    set +e; CLAUDE_SKILLS_DIR="$d/target" "$SRCROOT/install.sh" --uninstall $args >/dev/null 2>&1; rc=$?; set -e
    [ "$rc" -eq "$want" ] || { echo "exit $rc, want $want" >&2; exit 21; }
    no_scratch "$d/target" || { echo "scratch left behind" >&2; exit 22; }
    if [ "$expect" = keep ]; then
      got=$(tree_of "$d/target" | grep '^tdd')
      [ "$got" = "$before" ] || { echo "occupant changed during uninstall" >&2; exit 23; }
    else
      { [ ! -e "$d/target/tdd" ] && [ ! -L "$d/target/tdd" ]; } || { echo "tdd survived" >&2; exit 24; }
    fi
  ) 2>"$W/err"; rc=$?
  report "$label" "$rc" "$(head -2 "$W/err" | tr '\n' ' ')"
}
uninstall_case "uninstall ours"                 ours   ""        0 gone
uninstall_case "uninstall keeps a user dir"     dir    ""        3 keep
uninstall_case "uninstall keeps a user file"    file   ""        3 keep
[ "$SYMLINKS" -eq 1 ] && uninstall_case "uninstall keeps a broken link" broken "" 3 keep
uninstall_case "uninstall --adopt takes a dir"  dir    "--adopt" 0 gone

# ---- fault injection at each stage of the swap --------------------------
inject_case() {   # $1 label  $2 occupant  $3 which mv fails
  label=$1; occ=$2; which=$3
  d=$W/i$((pass+fail)); mkdir -p "$d/bin" "$d/target"
  REAL_MV=$(command -v mv)
  {
    printf '#!/bin/sh\n'
    case $which in
      aside)  printf 'case "$2" in *.lean-skills-outgoing-*) echo "mv: injected" >&2; exit 1 ;; esac\n' ;;
      inplace) printf 'case "$1" in *.lean-skills-staging-*) case "$2" in */tdd) echo "mv: injected" >&2; exit 1 ;; esac ;; esac\n' ;;
    esac
    printf 'exec %s "$@"\n' "$REAL_MV"
  } > "$d/bin/mv"
  chmod +x "$d/bin/mv"
  ( case $occ in
      dir)  mkdir -p "$d/target/tdd"; printf 'USERS\n' > "$d/target/tdd/SKILL.md" ;;
      file) printf 'USERS FILE\n' > "$d/target/tdd" ;;
      broken) ln -s nowhere "$d/target/tdd" ;;
    esac
    before=$(tree_of "$d/target" | grep '^tdd')
    OLD_PATH=$PATH; PATH="$d/bin:$PATH"
    [ "$(command -v mv)" = "$d/bin/mv" ] || { PATH=$OLD_PATH; echo "shim not on PATH" >&2; exit 31; }
    set +e; CLAUDE_SKILLS_DIR="$d/target" "$SRCROOT/install.sh" -y --adopt >"$d/out" 2>&1; set -e
    PATH=$OLD_PATH
    grep -q 'injected' "$d/out" || { echo "the injection never fired" >&2; exit 32; }
    got=$(tree_of "$d/target" | grep '^tdd')
    [ "$got" = "$before" ] || { echo "the occupant was not restored:" >&2
      diff <(printf '%s\n' "$before") <(printf '%s\n' "$got") >&2; exit 33; }
    no_scratch "$d/target" || { echo "scratch left behind" >&2; exit 34; }
  ) 2>"$W/err"; rc=$?
  report "$label" "$rc" "$(head -3 "$W/err" | tr '\n' ' ')"
}
for occ in dir file $( [ "$SYMLINKS" -eq 1 ] && echo broken ); do
  inject_case "swap-in fails over a $occ" "$occ" inplace
  # the other half of the window: moving the old target aside is what fails
  inject_case "move-aside fails over a $occ" "$occ" aside
done

echo
[ "$SYMLINKS" -eq 1 ] || echo "  (symlink cases skipped: this platform makes copies)"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
