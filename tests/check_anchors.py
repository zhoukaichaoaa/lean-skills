"""Every rollback anchor must appear exactly once in the current SKILL.md.

The suite already enforces this at run time, but each check costs a full matrix
run. This does the same arithmetic in a second, so a stale anchor is found
before an hour of CI, not after.

It also insists that the number of anchors it managed to read equals the number
of `run_rollback` calls in the file. An earlier version skipped a call it could
not parse and printed a total one short - the same silent-skip shape this suite
exists to catch, wearing the costume of the tool that checks for it.
"""
import io, os, re, sys
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
skill = io.open('skills/resolving-merge-conflicts/SKILL.md', encoding='utf-8', newline='').read()
rb = io.open('tests/parking_rollback.sh', encoding='utf-8', newline='').read()

# One entry per call site: the label, then everything up to the next call or the
# end of the argument list. Splitting on the call keyword rather than matching a
# whole invocation avoids depending on how the arguments happen to be wrapped.
parts = re.split(r'(?m)^\s*run_rollback\s+"([^"]*)"', rb)
invocations = (len(parts) - 1) // 2
assert invocations > 0, 'no run_rollback calls found - has the suite been renamed?'

bad = 0
read = 0
for i in range(1, len(parts), 2):
    label, block = parts[i], parts[i + 1]
    # the `from` side is the first single-quoted bash string after the label
    m = re.search(r"'((?:[^']|'\"'\"')*)'", block)
    if not m:
        print('UNREADABLE  %s' % label)
        print('     ^^^ could not find a quoted anchor for this call; refusing to '
              'report a total that leaves it out')
        bad += 1
        continue
    frm = m.group(1).replace("'\"'\"'", "'")
    read += 1
    c = skill.count(frm)
    print('%d  %-58s  %s' % (c, frm.strip().split('\n')[0][:58], label[:44]))
    if c != 1:
        bad += 1
        print('     ^^^ STALE: appears %d times, run_rollback requires exactly 1' % c)

print('\n%d run_rollback calls, %d anchors read, %d stale' % (invocations, read, bad))
if read != invocations:
    print('MISMATCH: %d call(s) contributed no anchor to the total above' % (invocations - read))
    bad += 1
sys.exit(1 if bad else 0)
