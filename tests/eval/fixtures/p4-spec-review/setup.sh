#!/usr/bin/env bash
# Build a repo whose HEAD is "the plan, implemented" - so the change can be
# pinned against a base ref. R4 (`remaining`) is missing and the out-of-scope
# logging plus a `reset_all()` nobody asked for are present.
set -e

git init -q .
git config user.email "eval@example.invalid"
git config user.name "Eval Fixture"
printf '%s\n' '.claude/' >> .git/info/exclude

git add README.md .plans
git commit -q -m "Add the per-key rate limiter plan"

mv _stage2/ratelimit.py _stage2/test_ratelimit.py .
rmdir _stage2

git add ratelimit.py test_ratelimit.py
git commit -q -m "Implement the per-key rate limiter from the plan"

git log --oneline
