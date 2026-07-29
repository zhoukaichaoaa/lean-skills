"""Every rollback anchor must appear exactly once in the current SKILL.md.

The suite already enforces this at run time, but each check costs a full matrix
run. This does the same arithmetic in a second, so a stale anchor is found
before an hour of CI, not after.
"""
import io, os, re, sys
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
skill = io.open('skills/resolving-merge-conflicts/SKILL.md', encoding='utf-8', newline='').read()
rb = io.open('tests/parking_rollback.sh', encoding='utf-8', newline='').read()

# pull the first quoted argument of every run_rollback call, the `from` side
calls = re.findall(r"run_rollback \"[^\"]*\" *\\\n((?:.*\n)*?)(?=\S|\Z)", rb)
bad = 0
n = 0
for block in calls:
    # each argument is a single-quoted bash string; take the first one
    m = re.match(r"\s*'((?:[^']|'\"'\"')*)'", block)
    if not m:
        continue
    frm = m.group(1).replace("'\"'\"'", "'")
    n += 1
    c = skill.count(frm)
    head = frm.strip().split('\n')[0][:58]
    print('%d  %s' % (c, head))
    if c != 1:
        bad += 1
        print('     ^^^ STALE: appears %d times, run_rollback requires exactly 1' % c)
print('\n%d anchors checked, %d stale' % (n, bad))
sys.exit(1 if bad else 0)
