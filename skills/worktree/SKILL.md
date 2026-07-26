---
name: worktree
description: "Isolated git worktree setup: detect existing isolation, prefer the platform's native tool, confirm the directory is ignored, run the baseline suite before work."
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

`GIT_DIR != GIT_COMMON` **and not a submodule** ⇒ you are already in a linked worktree. Report the path and branch, then go to Step 2. The submodule check also tells Step 1 which exclude file to write: submodules keep `.git` as a file, so the literal `.git/info/exclude` path does not exist there.

Otherwise you're in a normal checkout. Unless the user has already stated a preference, ask before creating anything:

> "Set up an isolated worktree? It keeps your current branch untouched."

If they decline, work in place and go to Step 2.

## Step 1 — Create it

**Native tool first.** If the harness offers one (`EnterWorktree`, `WorktreeCreate`, a `--worktree` flag), use it and skip to Step 2. It owns placement, branching, and cleanup; `git worktree add` alongside it creates state the harness cannot see or clean up.

**Git fallback**, only when no native tool exists. First pick the branch name — after the ticket or feature (`fix-checkout-retry`); if nothing suggests one, ask:

```bash
BRANCH=fix-checkout-retry        # the name chosen above
echo ".worktrees/" >> "$(git rev-parse --git-common-dir)/info/exclude"
git check-ignore -q .worktrees || { echo "still not ignored — stop here"; }
git worktree add ".worktrees/$BRANCH" -b "$BRANCH"
cd ".worktrees/$BRANCH"
```

Directory choice, in priority order: an explicit user preference, then an existing `.worktrees/` or `worktrees/` (`.worktrees` wins if both), then `.worktrees/` as the default.

Prefer the repo-local exclude file over editing `.gitignore`: same effect, no tracked-file change, no commit question. Reach it through `git rev-parse --git-common-dir`, never the literal path `.git/info/exclude` — inside a submodule `.git` is a *file*, and from a subdirectory it isn't there at all, so the literal path silently fails. **Confirm with `git check-ignore` before creating the worktree**: an unignored worktree directory puts the whole tree on track to be committed into the repo. Offer a `.gitignore` entry only if the user wants the ignore shared with the team.

If the branch or the worktree path already exists, reuse it when it is yours and clean; otherwise pick a new name — `git worktree add` refuses duplicates. If it fails on a permission error, say the sandbox blocked it and continue in the current directory.

## Step 2 — Setup and baseline

Install dependencies **the way the repo does**. Node: a `packageManager` field in `package.json` decides it; otherwise the lockfile — `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun, `package-lock.json` → npm. Python: `uv.lock` → uv, `poetry.lock` → poetry, `pdm.lock` → pdm, `requirements*.txt` → pip. Rust `Cargo.toml` → cargo, Go `go.mod` → go. Nothing decisive and no documented setup? Say what you found and ask instead of guess-installing.

Then run the test suite once and **report the result as it is**. A green baseline is what makes later failures attributable to your change; a red one is information the user needs before you start, and whether to proceed is their call.

## Step 3 — Tear down when the work lands

Worktrees and their installed dependencies do not clean themselves up, and an ignored directory never shows in `git status` — they accumulate silently. Once the branch is merged or abandoned: `git worktree remove <path>` (`--force` only when you mean to discard what is in it), then delete the branch if it has served its purpose. Tell the user when you have done this, and when you haven't.

## Completion criterion

Report the workspace path, the branch, and the baseline test result as actual command output.

---

_Condensed from [obra/superpowers](https://github.com/obra/superpowers) `using-git-worktrees` (MIT); branch naming, repo-local exclude via `--git-common-dir`, and lockfile-driven package-manager detection added._
