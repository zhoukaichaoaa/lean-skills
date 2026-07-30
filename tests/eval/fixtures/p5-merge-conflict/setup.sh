#!/usr/bin/env bash
# Leave the working tree mid-merge with a real conflict in config.py.
set -e

git init -q .
git config user.email "eval@example.invalid"
git config user.name "Eval Fixture"
printf '%s\n' '.claude/' >> .git/info/exclude

git add README.md config.py
git commit -q -m "Initial import"
base=$(git rev-parse --abbrev-ref HEAD)

git checkout -q -b feature
cat > config.py <<'PY'
"""Runtime configuration for the ingest service."""

POOL_SIZE = 16
REQUEST_TIMEOUT = 30
LOG_LEVEL = "INFO"
RETRY_ATTEMPTS = 3


def summary():
    return "pool=%d timeout=%d level=%s retries=%d" % (
        POOL_SIZE,
        REQUEST_TIMEOUT,
        LOG_LEVEL,
        RETRY_ATTEMPTS,
    )
PY
git commit -qam "feature: bigger pool, add retry attempts"

git checkout -q "$base"
cat > config.py <<'PY'
"""Runtime configuration for the ingest service."""

POOL_SIZE = 8
REQUEST_TIMEOUT = 120
LOG_LEVEL = "DEBUG"


def summary():
    return "pool=%d timeout=%d level=%s" % (
        POOL_SIZE,
        REQUEST_TIMEOUT,
        LOG_LEVEL,
    )
PY
git commit -qam "tune pool, timeout and log level for staging"

git merge feature || true

git status --porcelain | grep -q '^UU config.py' || {
  echo "setup failed: expected a conflict in config.py" >&2
  git status --porcelain >&2
  exit 1
}
echo "conflict staged as expected"
