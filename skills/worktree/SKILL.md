---
name: worktree
description: "Isolated git worktree setup: detect existing isolation, prefer the platform's native tool, verify gitignore, green baseline before work."
disable-model-invocation: true
---

# Worktree

Work happens in an isolated workspace. Detect existing isolation, then prefer the harness's native tool, then fall back to git.

## Step 0 — Detect existing isolation

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
git rev-parse --show-superproject-working-tree 2>/dev/null   # non-empty ⇒ submodule
```

`GIT_DIR != GIT_COMMON` **and not a submodule** ⇒ you are already in a linked worktree. Report the path and branch, then go to Step 2. A submodule looks the same on the first check and is not a worktree — that's what the second command settles.

Otherwise you're in a normal checkout. Unless the user has already stated a preference, ask before creating anything:

> "Set up an isolated worktree? It keeps your current branch untouched."

If they decline, work in place and go to Step 2.

## Step 1 — Create it

**Native tool first.** If the harness offers one (`EnterWorktree`, `WorktreeCreate`, a `/worktree` command, a `--worktree` flag), use it and skip to Step 2. It owns placement, branching, and cleanup; `git worktree add` alongside it creates state the harness cannot see or clean up.

**Git fallback**, only when no native tool exists. First pick the branch name — after the ticket or feature (`fix-checkout-retry`); if nothing suggests one, ask:

```bash
BRANCH=fix-checkout-retry        # the name chosen above
git check-ignore -q .worktrees || echo ".worktrees/" >> .gitignore   # then commit
git worktree add ".worktrees/$BRANCH" -b "$BRANCH"
cd ".worktrees/$BRANCH"
```

Directory choice, in priority order: an explicit user preference, then an existing `.worktrees/` or `worktrees/` (`.worktrees` wins if both), then `.worktrees/` as the default. Verify it is git-ignored before creating anything inside it — an unignored worktree directory commits the entire tree into the repo.

If `git worktree add` fails on a permission error, say the sandbox blocked it and continue in the current directory.

## Step 2 — Setup and baseline

Install dependencies for whatever the project is (`package.json` → `npm install`, `Cargo.toml` → `cargo build`, `pyproject.toml` → `poetry install`, `go.mod` → `go mod download`), then run the test suite once.

A green baseline is what makes every later failure attributable to your change. If the baseline is red, report the failures and let the user decide whether to proceed.

## Completion criterion

Report the workspace path, the branch, and the baseline test result as actual command output.

---

_Condensed from [obra/superpowers](https://github.com/obra/superpowers) `using-git-worktrees` (MIT)._
