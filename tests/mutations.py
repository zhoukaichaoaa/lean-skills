#!/usr/bin/env python3
"""Mutation-test this repository's CI assertions.

An assertion nobody has watched fail is not evidence. This breaks something the
CI claims to protect, runs the step that should notice, and records whether it
went red. A mutation that survives is a gap; the run exits non-zero.

    python tests/mutations.py            # every case
    python tests/mutations.py parity     # only cases whose label matches

Requires python (with PyYAML) and bash. The CI steps are read straight out of
.github/workflows/ci.yml, so this cannot drift from what CI actually runs.
Cases against `install.ps1` run its CI step through PowerShell, and are skipped
on platforms that do not have it.
"""
import io, os, re, shutil, subprocess, sys, tempfile

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CI = '.github/workflows/ci.yml'
LEGS = {
    'install.sh': 'sh',
    'install.ps1': 'win',          # only runnable on Windows; skipped elsewhere
    'manifests and frontmatter': 'meta',
    'git recipes in the skills actually run': 'rec',
    'platform parity': 'par',
    'parking recipes, driven from SKILL.md itself': 'park',
    'installer state matrix, driven from the real install.sh': 'imtx',
}

# Some vectors cannot exist on some platforms, and calling those "caught" is a
# lie in the flattering direction. A leg may carry an @suffix naming what it
# needs; the suffix is stripped before the CI step is looked up.
#   @posix  the vector only exists where a drive letter is NOT absolute, so it
#           is unkillable under MSYS/Cygwin no matter how good the test is
def unavailable(leg):
    if leg == 'win' and os.name != 'nt':
        return 'needs Windows'
    if leg.endswith('@posix'):
        u = subprocess.run(['uname', '-s'], capture_output=True).stdout.decode('ascii', 'replace')
        if u.startswith(('MINGW', 'MSYS', 'CYGWIN')):
            return 'needs a platform where drive letters are relative; this is %s' % u.strip()
    return None
# Git Bash makes copies for `ln -s` unless told otherwise, and this leg's guard
# vectors are all symlinks. Dropping those lines locally -- which is what this
# used to do -- silently removed the coverage instead of the obstacle; asking
# MSYS for real links keeps the local run the same script CI runs.
MSYS_LINKS = 'winsymlinks:nativestrict'

import json
VERSION = json.load(io.open(os.path.join(REPO, '.claude-plugin/plugin.json'),
                            encoding='utf-8'))['version']

root = tempfile.mkdtemp(prefix='lean-skills-mutations-')
work = None


def fresh(n):
    global work
    work = os.path.join(root, 'c%02d' % n)
    shutil.copytree(REPO, work, ignore=shutil.ignore_patterns('.git'))


def run_leg(leg):
    steps = yaml.safe_load(io.open(os.path.join(work, CI), encoding='utf-8'))['jobs']['install']['steps']
    for s in steps:
        if LEGS.get(s.get('name')) != leg.split('@')[0]:
            continue
        # The interpreter goes into a *bash* script, so a Windows path has to be
        # POSIX-ified and quoted first: written raw, bash eats the backslashes and
        # F:\python\python.exe becomes the command `F:pythonpython.exe`, which is
        # not found -- rc=127, every mutation on this leg "caught" for free.
        py = "'" + sys.executable.replace('\\', '/') + "'"
        body = s['run'].replace('python3 - ', py + ' - ')
        rt = os.path.join(work, '_rt')
        os.makedirs(rt, exist_ok=True)
        env = dict(os.environ, RUNNER_TEMP=rt, MSYS=MSYS_LINKS)
        env.pop('CLAUDE_SKILLS_DIR', None)
        if leg == 'win':
            path = os.path.join(work, '_leg.ps1')
            io.open(path, 'w', encoding='utf-8', newline='\r\n').write(body)
            return subprocess.run(
                ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path],
                cwd=work, env=env, capture_output=True, timeout=900).returncode
        path = os.path.join(work, '_leg.sh')
        io.open(path, 'w', encoding='utf-8', newline='\n').write(body)
        return subprocess.run(['bash', path], cwd=work, env=env,
                              capture_output=True, timeout=600).returncode
    raise SystemExit('no step maps to leg %r' % leg)


def edit(rel, old, new):
    p = os.path.join(work, rel)
    t = io.open(p, encoding='utf-8', newline='').read()
    if old not in t:
        raise AssertionError('anchor not found in %s: %r' % (rel, old[:60]))
    io.open(p, 'w', encoding='utf-8', newline='').write(t.replace(old, new, 1))


def drop_crlf(rel):
    p = os.path.join(work, rel)
    io.open(p, 'wb').write(io.open(p, 'rb').read().replace(b'\r\n', b'\n'))


MC = 'skills/resolving-merge-conflicts/SKILL.md'


def code_line(rel, starts):
    """The single indented recipe line in `rel` that begins with `starts`.

    Deriving the anchor beats hardcoding it: three releases running, a reworded
    recipe turned a case into a setup failure, and one case silently anchored to
    a prose sentence that merely mentioned the command. What a case is about is
    "this command is still prescribed", not the exact words around it.
    """
    lines = io.open(os.path.join(REPO, rel), encoding='utf-8').read().split('\n')
    hits = [l for l in lines if l.startswith('   ' + starts)]
    if len(hits) != 1:
        raise AssertionError('%s: %d lines start with %r, want exactly 1' % (rel, len(hits), starts))
    return hits[0]


ROLL_GOOD = '  if [ -n "$swap_target" ] && exists "$_outgoing" && ! exists "$swap_target"; then'

ROLL_BAD = '  if false; then'

ABSCASE_GOOD = '  case "$CLAUDE_SKILLS_DIR" in\n    /*) : ;;'

ABSCASE_BAD = '  case "$CLAUDE_SKILLS_DIR" in\n    " "*) : ;;\n    /*) : ;;'

# The patch line is the one the two "parks with cp/stash again" cases replace.
# It no longer *starts* with git: since 0.17.1 the pathspecs reach git over NUL
# through xargs, because `xargs -a` is not portable and the unquoted $(...) it
# replaced dropped any tracked path containing a space.
PARK_GOOD = code_line(MC, 'xargs -0 git diff --binary')

PARK_STASH = '   git stash push -u -- <each tracked path from step 4>'

def bump_a_word_count():
    """Add one to whichever number NOTICE currently claims for worktree.

    Reading the number instead of hardcoding it keeps this case working across
    releases - a hardcoded 877 stopped matching the moment the file was edited.
    """
    p = os.path.join(work, 'NOTICE.md')
    t = io.open(p, encoding='utf-8', newline='').read()
    m = re.search(r'1069 \u2192 (\d+) \u8bcd', t)
    if not m:
        raise AssertionError('NOTICE no longer states a worktree word count')
    t = t[:m.start(1)] + str(int(m.group(1)) + 1) + t[m.end(1):]
    io.open(p, 'w', encoding='utf-8', newline='').write(t)


SPLIT_GOOD = "  IFS='\n'\n  for name in $(for d in"

SPLIT_BAD = "  IFS=' '\n  for name in $(for d in"

ABS_GOOD = "  $isAbsolute = ($d -match '^[A-Za-z]:[\\\\/]') -or ($d -match '^[\\\\/][\\\\/][^\\\\/]')"

ABS_BAD = '  $isAbsolute = [IO.Path]::IsPathRooted($d)'

CASES = [
    # Two more parking cases were removed in 0.15.0: their anchor strings now
    # appear twice in the skill, so a single-replacement mutation left one copy
    # behind and could never fail. parking_rollback.sh covers both behaviourally.
    # The parking contracts these used to assert textually are now covered
    # behaviourally by tests/parking_rollback.sh, which reverts each fix in a
    # copy of the skill and reruns the real recipe. A text anchor could only
    # say the command is present; the rollback says the procedure breaks
    # without it.
    # (label, leg, mutation)
    ('parity: continue-on-error hides a step', 'par', lambda: edit(
        CI, "      - name: install.sh\n        if: runner.os != 'Windows'",
        "      - name: install.sh\n        continue-on-error: true\n        if: runner.os != 'Windows'")),
    ('parity: macos dropped from the matrix', 'par', lambda: edit(
        CI, 'os: [ubuntu-latest, macos-latest, windows-latest]',
        'os: [ubuntu-latest, windows-latest]')),
    ('parity: macos excluded from the matrix', 'par', lambda: edit(
        CI, '        os: [ubuntu-latest, macos-latest, windows-latest]',
        '        os: [ubuntu-latest, macos-latest, windows-latest]\n'
        '        exclude:\n          - os: macos-latest')),
    ('parity: a second job with a gated step', 'par', lambda: edit(
        CI, 'jobs:\n  install:',
        "jobs:\n  extra:\n    runs-on: ubuntu-latest\n    steps:\n"
        "      - if: runner.os == 'Linux'\n        run: echo sneaky\n  install:")),
    ('parity: step body short-circuits on macOS', 'par', lambda: edit(
        CI, '          set -euo pipefail\n          M=skills/resolving-merge-conflicts/SKILL.md',
        '          set -euo pipefail\n          [ "$(uname)" = Darwin ] && exit 0\n'
        '          M=skills/resolving-merge-conflicts/SKILL.md')),

    ('installer: retired name survives uninstall', 'sh', lambda: edit(
        'install.sh', 'for name in $retired; do', 'for name in ; do')),
    ('installer: --uninstall --adopt stops working', 'sh', lambda: edit(
        'install.sh', 'if is_ours "$dest_abs/$name" || [ "$adopt" -eq 1 ]; then',
        'if is_ours "$dest_abs/$name"; then')),
    ('installer: marker match back to a substring', 'sh', lambda: edit(
        'install.sh', '  [ "$first" = "$marker_line" ]',
        '  case "$first" in *"$marker_line"*) return 0 ;; *) return 1 ;; esac')),
    ('installer: cleanup deletes the backup', 'sh', lambda: edit(
        'install.sh', ROLL_GOOD, ROLL_BAD)),
    ('installer: swap_target never set', 'sh', lambda: edit(
        'install.sh', '  swap_target=$dest_abs/$name          # the window opens here',
        '  : # window not tracked')),
    # the 0.11.0 shape: one case whose blank arm skips the absolute check,
    # followed by a blank test that a leading-blank path passes
    ('installer: leading blank accepted as absolute', 'sh', lambda: edit(
        'install.sh', ABSCASE_GOOD, ABSCASE_BAD)),
    ('installer: install.ps1 flattened to LF', 'sh', lambda: drop_crlf('install.ps1')),
    ('installer: ps1 refusals go back to exit 1', 'win', lambda: edit(
        'install.ps1', 'function Deny($msg, $code = 2) {', 'function Deny($msg, $code = 1) {')),
    # split on spaces again, which is what made a directory called
    # "two words" impossible to uninstall
    ('installer: a space-named skill breaks uninstall', 'sh', lambda: edit(
        'install.sh', SPLIT_GOOD, SPLIT_BAD)),
    ('manifest: the marketplace pin goes stale', 'meta', lambda: edit(
        '.claude-plugin/marketplace.json', '"ref": "v', '"ref": "vX')),
    # the 0.13.2 data-loss bug: --adopt can take over a plain file or a broken
    # link, and a rollback gated on -d skips those, after which rm -rf deletes
    # them. The CI leg's fault injection only ever occupies with a directory, so
    # it cannot see this; install_matrix.sh occupies with each in turn.
    ('installer: rollback only restores directories', 'imtx', lambda: edit(
        'install.sh', 'exists "$_outgoing" && ! exists "$swap_target"',
        '[ -d "$_outgoing" ] && ! exists "$swap_target"')),
    ('skill: step 3 back to --name-only, losing renames', 'rec', lambda: edit(
        'skills/resolving-merge-conflicts/SKILL.md',
        'git -c core.quotePath=false diff --cached --name-status -M HEAD',
        'git -c core.quotePath=false diff --cached --name-only HEAD')),
    ('installer: ps1 loses its symlink-aware test', 'win', lambda: edit(
        'install.ps1', 'function Test-Exists($p) {', 'function Test-Exists-DISABLED($p) {')),
    ('skill: parks with cp again', 'rec', lambda: edit(
        'skills/resolving-merge-conflicts/SKILL.md', PARK_GOOD,
        '   cp <every path from step 4> "$G/lean-parked/"')),
    ('installer: -e again instead of symlink-aware exists', 'sh', lambda: edit(
        'install.sh', 'exists() { [ -e "$1" ] || [ -L "$1" ]; }',
        'exists() { [ -e "$1" ]; }')),
    ('installer: drive letters absolute everywhere again', 'sh@posix', lambda: edit(
        'install.sh', 'MINGW*|MSYS*|CYGWIN*) drive_letters_are_absolute=1 ;;',
        'MINGW*|MSYS*|CYGWIN*|*) drive_letters_are_absolute=1 ;;')),
    ('installer: ps1 back to IsPathRooted', 'win', lambda: edit(
        'install.ps1', ABS_GOOD, ABS_BAD)),
    ('repo: a skill companion file deleted', 'sh',
     lambda: os.remove(os.path.join(work, 'skills/tdd/mocking.md'))),

    ('manifest: plugin and marketplace names drift', 'meta', lambda: edit(
        '.claude-plugin/plugin.json', '"name": "lean-skills"', '"name": "lean-skills-2"')),
    ('manifest: marketplace points at another repo', 'meta', lambda: edit(
        '.claude-plugin/marketplace.json', 'zhoukaichaoaa/lean-skills.git',
        'someone-else/not-lean-skills.git')),
    ('manifest: skill count inflated to 19', 'meta', lambda: edit(
        '.claude-plugin/plugin.json', '9 skills, 4 resident', '19 skills, 4 resident')),
    ('changelog: version demoted from a heading', 'meta', lambda: edit(
        'CHANGELOG.md', '## %s —' % VERSION, '## Unreleased (was %s) —' % VERSION)),
    ('notice: a continuation row splits one file in two', 'meta', lambda: edit(
        'NOTICE.md', '| `skills/worktree/SKILL.md` |',
        '| `skills/worktree/SKILL.md`(cont) | - | extra |' + chr(10) + '| `skills/worktree/SKILL.md` |')),
    ('footnote: a version number creeps back in', 'meta', lambda: edit(
        'skills/worktree/SKILL.md', 'Per-release detail:', 'Renamed in 0.3.0. Per-release detail:')),
    ('footnote: the pointer to NOTICE is dropped', 'meta', lambda: edit(
        'skills/tdd/SKILL.md', 'Per-release detail: [NOTICE.md](https://github.com/zhoukaichaoaa/lean-skills/blob/main/NOTICE.md).', '')),
    ('notice: a word count drifts by one', 'meta', bump_a_word_count),

    ('skill: @{upstream} back as a prescribed command', 'rec', lambda: edit(
        'skills/spec-review/SKILL.md',
        '   git symbolic-ref refs/remotes/origin/HEAD     # offline fallback; see the caveat below',
        '   git merge-base HEAD @{upstream}                # offline fallback; see the caveat below')),
    ('skill: parks with git stash again', 'rec', lambda: edit(
        'skills/resolving-merge-conflicts/SKILL.md', PARK_GOOD, PARK_STASH)),
    ('skill: merge-base loses --all', 'rec', lambda: edit(
        'skills/resolving-merge-conflicts/SKILL.md',
        'git merge-base --all HEAD <that head>', 'git merge-base HEAD <that head>')),
    ('skill: a path recipe loses core.quotePath', 'rec', lambda: edit(
        'skills/resolving-merge-conflicts/SKILL.md',
        "   git -c core.quotePath=false status --porcelain -- ':(top)first-path'",
        "   git status --porcelain -- ':(top)first-path'")),
    ('skill: a recipe un-fenced into prose', 'rec', lambda: edit(
        'skills/resolving-merge-conflicts/SKILL.md',
        '   ```bash\n   cat "$G/MERGE_HEAD"', '   cat "$G/MERGE_HEAD"')),
]


def main():
    want = sys.argv[1] if len(sys.argv) > 1 else ''
    cases = [c for c in CASES if want in c[0]]
    if not cases:
        sys.exit('no case matches %r' % want)
    # A mutation is "caught" when its leg goes red. That inference is only
    # valid if the leg is green to begin with: a leg broken for some unrelated
    # reason reports every mutation as caught while proving nothing at all.
    # So establish the baseline first and refuse to interpret a red one.
    legs = sorted({c[1] for c in cases if not unavailable(c[1])})
    for j, leg in enumerate(legs):
        fresh(900 + j)
        rc = run_leg(leg)
        print('baseline  leg %-4s rc=%d%s' % (leg, rc, '' if rc == 0 else '  <-- RED'))
        if rc != 0:
            print('\nleg %r fails unmutated; its mutation results mean nothing' % leg)
            shutil.rmtree(root, ignore_errors=True)
            return 1

    survivors, skipped = [], []
    for i, (label, leg, mutate) in enumerate(cases, 1):
        why = unavailable(leg)
        if why:
            # counted apart, never as caught: an unexecuted mutation is not
            # evidence of anything
            print('skipped   %s (%s)' % (label, why))
            skipped.append(label)
            continue
        fresh(i)
        try:
            mutate()
        except Exception as e:
            print('SETUP  %s -- %s' % (label, e))
            survivors.append(label)
            continue
        rc = run_leg(leg)
        ok = rc != 0
        print('%s %s' % ('caught   ' if ok else 'SURVIVED ', label))
        if not ok:
            survivors.append(label)
    ran = len(cases) - len(skipped)
    print('\n%d/%d caught, %d skipped' % (ran - len(survivors), ran, len(skipped)))
    shutil.rmtree(root, ignore_errors=True)
    return 1 if survivors else 0


if __name__ == '__main__':
    sys.exit(main())
