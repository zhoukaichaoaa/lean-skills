#!/usr/bin/env python3
"""Mutation-test this repository's CI assertions.

An assertion nobody has watched fail is not evidence. This breaks something the
CI claims to protect, runs the step that should notice, and records whether it
went red. A mutation that survives is a gap; the run exits non-zero.

    python tests/mutations.py            # every case
    python tests/mutations.py parity     # only cases whose label matches

Requires python (with PyYAML) and bash. The CI steps are read straight out of
.github/workflows/ci.yml, so this cannot drift from what CI actually runs.
Windows-only steps are skipped here; the `install.ps1` leg is exercised by CI.
"""
import io, os, shutil, subprocess, sys, tempfile

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CI = '.github/workflows/ci.yml'
LEGS = {
    'install.sh': 'sh',
    'manifests and frontmatter': 'meta',
    'git recipes in the skills actually run': 'rec',
    'platform parity': 'par',
}
# Git Bash cannot make real symlinks, so those vectors are dropped locally.
NO_SYMLINKS = ('link-root', 'link-src', 'link-chain')

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
        if LEGS.get(s.get('name')) != leg:
            continue
        body = s['run'].replace('python3 - ', sys.executable + ' - ')
        if leg == 'sh' and os.name == 'nt':
            body = '\n'.join(l for l in body.splitlines()
                             if not any(v in l for v in NO_SYMLINKS))
        path = os.path.join(work, '_leg.sh')
        io.open(path, 'w', encoding='utf-8', newline='\n').write(body)
        rt = os.path.join(work, '_rt')
        os.makedirs(rt, exist_ok=True)
        env = dict(os.environ, RUNNER_TEMP=rt)
        env.pop('CLAUDE_SKILLS_DIR', None)
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


GUARD_GOOD = '  case "$CLAUDE_SKILLS_DIR" in\n    *[![:blank:]]*) : ;;\n    *) echo "CLAUDE_SKILLS_DIR is set but blank — unset it for the default, or give it a path" >&2; exit 2 ;;\n  esac\n  case "$CLAUDE_SKILLS_DIR" in\n    /*|[A-Za-z]:[\\\\/]*) : ;;\n    *) echo "CLAUDE_SKILLS_DIR must be an absolute path (got: \'$CLAUDE_SKILLS_DIR\')" >&2; exit 2 ;;\n  esac'

GUARD_BAD = '  case "$CLAUDE_SKILLS_DIR" in\n    "" |" "*) : ;;\n    /*|[A-Za-z]:[\\\\/]*) : ;;\n    *) echo "CLAUDE_SKILLS_DIR must be an absolute path (got: \'$CLAUDE_SKILLS_DIR\')" >&2; exit 2 ;;\n  esac\n  case "$CLAUDE_SKILLS_DIR" in\n    *[![:blank:]]*) : ;;\n    *) echo "CLAUDE_SKILLS_DIR is set but blank — unset it for the default, or give it a path" >&2; exit 2 ;;\n  esac'

CASES = [
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
        'install.sh', '  if [ -n "$swap_target" ] && [ -d "$_outgoing" ] && [ ! -e "$swap_target" ]; then',
        '  if false; then')),
    ('installer: swap_target never set', 'sh', lambda: edit(
        'install.sh', '  swap_target=$dest_abs/$name          # the window opens here',
        '  : # window not tracked')),
    # the 0.11.0 shape: one case whose blank arm skips the absolute check,
    # followed by a blank test that a leading-blank path passes
    ('installer: leading blank accepted as absolute', 'sh', lambda: edit(
        'install.sh', GUARD_GOOD, GUARD_BAD)),
    ('installer: install.ps1 flattened to LF', 'sh', lambda: drop_crlf('install.ps1')),
    ('repo: a skill companion file deleted', 'sh',
     lambda: os.remove(os.path.join(work, 'skills/tdd/mocking.md'))),

    ('manifest: plugin and marketplace names drift', 'meta', lambda: edit(
        '.claude-plugin/plugin.json', '"name": "lean-skills"', '"name": "lean-skills-2"')),
    ('manifest: marketplace points at another repo', 'meta', lambda: edit(
        '.claude-plugin/marketplace.json', 'zhoukaichaoaa/lean-skills.git',
        'someone-else/not-lean-skills.git')),
    ('manifest: skill count inflated to 19', 'meta', lambda: edit(
        '.claude-plugin/plugin.json', '9 skills, 5 resident', '19 skills, 5 resident')),
    ('changelog: version demoted from a heading', 'meta', lambda: edit(
        'CHANGELOG.md', '## %s —' % VERSION, '## Unreleased (was %s) —' % VERSION)),
    ('notice: a word count drifts by one', 'meta', lambda: edit(
        'NOTICE.md', '1069 → 877 词', '1069 → 878 词')),

    ('skill: @{upstream} back as a prescribed command', 'rec', lambda: edit(
        'skills/spec-review/SKILL.md',
        '   git symbolic-ref refs/remotes/origin/HEAD     # offline fallback; see the caveat below',
        '   git merge-base HEAD @{upstream}                # offline fallback; see the caveat below')),
    ('skill: stash push loses its -u', 'rec', lambda: edit(
        'skills/resolving-merge-conflicts/SKILL.md',
        'git stash push -u -- <the paths you unstaged in step 4>',
        'git stash push -- <the paths you unstaged in step 4>')),
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
    survivors = []
    for i, (label, leg, mutate) in enumerate(cases, 1):
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
    print('\n%d/%d caught' % (len(cases) - len(survivors), len(cases)))
    shutil.rmtree(root, ignore_errors=True)
    return 1 if survivors else 0


if __name__ == '__main__':
    sys.exit(main())
