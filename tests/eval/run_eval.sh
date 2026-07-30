#!/usr/bin/env bash
#
# Trigger-rate eval for the resident (model-invocable) skills in this collection.
#
# Measures one thing only: does the model invoke the right skill, unprompted,
# in a situation the skill's description claims to cover.
#
# Run manually before a release. NOT part of CI - it spends API budget.
#
#   tests/eval/run_eval.sh                       # all scenarios, N=5
#   tests/eval/run_eval.sh --n 1 --scenarios p1-verification
#   tests/eval/run_eval.sh --out /tmp/eval-out --model claude-opus-5
#
# Then grade:
#
#   python3 tests/eval/grade.py <out-dir>
#
# Isolation notes - both matter, do not "simplify" them away:
#   * Skills under test are copied into each run's <workdir>/.claude/skills
#     (PROJECT scope) rather than being read from ~/.claude/skills. This tests
#     the skills in THIS working tree, not whatever happens to be installed.
#   * --setting-sources project,local drops user settings, which is what
#     disables user-level plugins. Plugin collections (e.g. superpowers) ship
#     skills with names identical to ours; with them loaded the eval measures
#     a name collision rather than a trigger rate.
#   Consequence of the two together: user-scope skills are NOT loaded, so the
#   project-scope copy is the only source of skills. That is deliberate.
#
# Portability: bash 3.2 (stock macOS) and Git Bash on Windows.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
FIXTURE_ROOT="$SCRIPT_DIR/fixtures"

ALL_SCENARIOS="p1-verification p2-code-review p3-diagnose p4-spec-review p5-merge-conflict n1-qa n2-reading"

N=5
MODEL="claude-opus-5"
SCENARIOS="$ALL_SCENARIOS"
OUT=""
WORKROOT=""
MAX_BUDGET="4.0"
MAX_ATTEMPTS=3

while [ $# -gt 0 ]; do
  case "$1" in
    --n)          N="$2"; shift 2 ;;
    --model)      MODEL="$2"; shift 2 ;;
    --scenarios)  SCENARIOS="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    --workroot)   WORKROOT="$2"; shift 2 ;;
    --max-budget) MAX_BUDGET="$2"; shift 2 ;;
    -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
[ -n "$OUT" ] || OUT="$SCRIPT_DIR/results/$RUN_ID"
[ -n "$WORKROOT" ] || WORKROOT="${TMPDIR:-/tmp}/lean-skills-eval/$RUN_ID"

mkdir -p "$OUT" "$WORKROOT" || exit 1

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Scoped command rules, never a bare `Bash`/`PowerShell`: a run must be able to
# execute the fixture's own tests and git, and nothing wider.
#
# BOTH tool names are required. On Windows the agent drives commands through the
# PowerShell tool and never touches Bash; on macOS/Linux it is the other way
# round. Allowing only one silently starves every run on the other platform -
# the model then cannot run the fixture's tests, which is precisely the
# behaviour scenario p1 exists to measure.
#
# No rule may contain a space: the list is word-split on expansion, and prefix
# matching means `python:*` already covers `python -m unittest ...`.
ALLOWED_TOOLS="Read Glob Grep Edit Write Skill Task TodoWrite \
Bash(python:*) Bash(python3:*) Bash(py:*) Bash(pytest:*) Bash(git:*) \
Bash(ls:*) Bash(cat:*) Bash(head:*) Bash(tail:*) Bash(grep:*) Bash(find:*) \
Bash(sed:*) Bash(awk:*) Bash(wc:*) Bash(sort:*) Bash(diff:*) Bash(echo:*) \
Bash(pwd:*) Bash(mkdir:*) Bash(cp:*) Bash(mv:*) Bash(rm:*) Bash(chmod:*) \
Bash(true:*) Bash(test:*) \
PowerShell(python:*) PowerShell(python3:*) PowerShell(py:*) \
PowerShell(pytest:*) PowerShell(git:*) PowerShell(ls:*) PowerShell(dir:*) \
PowerShell(cat:*) PowerShell(echo:*) PowerShell(pwd:*) PowerShell(cd:*) \
PowerShell(Get-ChildItem:*) PowerShell(Get-Content:*) PowerShell(Get-Location:*) \
PowerShell(Set-Location:*) PowerShell(Test-Path:*) PowerShell(Select-String:*) \
PowerShell(Select-Object:*) PowerShell(Measure-Object:*) PowerShell(Write-Output:*) \
PowerShell(New-Item:*) PowerShell(Copy-Item:*) PowerShell(Move-Item:*) \
PowerShell(Remove-Item:*) PowerShell(Compare-Object:*) PowerShell(findstr:*)"

cat > "$OUT/run-meta.json" <<EOF
{
  "run_id": "$RUN_ID",
  "date_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "model_requested": "$MODEL",
  "cli_version": "$(claude --version 2>/dev/null | head -n1)",
  "n_per_scenario": $N,
  "scenarios": "$SCENARIOS",
  "repo_root": "$REPO_ROOT",
  "setting_sources": "project,local",
  "permission_mode": "acceptEdits",
  "skills_source": "project-scope copy of \$REPO/skills"
}
EOF

echo "run id     : $RUN_ID"
echo "out        : $OUT"
echo "workroot   : $WORKROOT"
echo "model      : $MODEL"
echo "N          : $N"
echo "scenarios  : $SCENARIOS"
echo

for scenario in $SCENARIOS; do
  fixture="$FIXTURE_ROOT/$scenario"
  if [ ! -d "$fixture" ]; then
    echo "!! no fixture for $scenario, skipping" >&2
    continue
  fi
  mkdir -p "$OUT/$scenario"
  prompt=$(cat "$fixture/PROMPT.txt")

  i=1
  while [ "$i" -le "$N" ]; do
    workdir="$WORKROOT/$scenario/run$i"
    rm -rf "$workdir" 2>/dev/null
    mkdir -p "$workdir/.claude/skills"

    # fixture payload
    if [ -d "$fixture/files" ]; then
      cp -R "$fixture/files/." "$workdir/"
    fi
    # skills under test, at project scope
    cp -R "$REPO_ROOT/skills/." "$workdir/.claude/skills/"
    # per-fixture setup (git history, merge conflicts, ...)
    if [ -f "$fixture/setup.sh" ]; then
      ( cd "$workdir" && bash "$fixture/setup.sh" ) > "$OUT/$scenario/run$i.setup.log" 2>&1
      if [ $? -ne 0 ]; then
        echo "!! setup failed for $scenario run$i (see run$i.setup.log)" >&2
        i=$((i + 1))
        continue
      fi
    fi

    attempt=1
    while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
      printf '%s run%s (attempt %s) ... ' "$scenario" "$i" "$attempt"
      ( cd "$workdir" && claude -p "$prompt" \
          --output-format json \
          --model "$MODEL" \
          --setting-sources project,local \
          --permission-mode acceptEdits \
          --max-budget-usd "$MAX_BUDGET" \
          --allowedTools $ALLOWED_TOOLS \
      ) > "$OUT/$scenario/run$i.json" 2> "$OUT/$scenario/run$i.stderr"

      status=$(python3 "$SCRIPT_DIR/_result_status.py" "$OUT/$scenario/run$i.json" 2>/dev/null \
               || python "$SCRIPT_DIR/_result_status.py" "$OUT/$scenario/run$i.json" 2>/dev/null)
      echo "$status"
      case "$status" in
        ok) break ;;
        *)  attempt=$((attempt + 1)) ;;
      esac
    done

    # transcript: locate by session id under the config dir
    sid=$(python3 "$SCRIPT_DIR/_result_status.py" --session-id "$OUT/$scenario/run$i.json" 2>/dev/null \
          || python "$SCRIPT_DIR/_result_status.py" --session-id "$OUT/$scenario/run$i.json" 2>/dev/null)
    if [ -n "$sid" ]; then
      tpath=$(find "$CONFIG_DIR/projects" -name "$sid.jsonl" -print 2>/dev/null | head -n1)
      if [ -n "$tpath" ]; then
        cp "$tpath" "$OUT/$scenario/run$i.transcript.jsonl"
      else
        echo "!! transcript not found for session $sid" >&2
      fi
    fi

    # post-run snapshot of the working tree (minus the injected skills)
    mkdir -p "$OUT/$scenario/run$i.after"
    ( cd "$workdir" && find . -path ./.claude -prune -o -path ./.git -prune \
        -o -name __pycache__ -prune -o -type f -print ) \
      | while IFS= read -r f; do
          d=$(dirname "$f")
          mkdir -p "$OUT/$scenario/run$i.after/$d"
          cp "$workdir/$f" "$OUT/$scenario/run$i.after/$f" 2>/dev/null
        done

    i=$((i + 1))
  done
done

echo
echo "done. grade with:"
echo "  python3 $SCRIPT_DIR/grade.py $OUT"
