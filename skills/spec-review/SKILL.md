---
name: spec-review
description: Check a change against the plan or spec it was built from — requirements missing, behaviour nobody asked for, requirements implemented wrongly. Use after building against a plan, before handover. Not a correctness review; Claude Code's built-in /code-review covers that.
argument-hint: <base-sha> [spec-path]
context: fork
background: false
---

# Spec Review

One question: **does this change do what was asked, and only what was asked?**

Correctness bugs and reuse/simplification/efficiency cleanups are the built-in `/code-review`'s job — it runs as its own background subagent and reads the whole codebase. Duplicating that here would cost context and add nothing. Security is a third thing again, and belongs to `/security-review`. What none of them can know is what the change was *supposed* to do, because that lives in a plan file or a tracker issue nobody handed them. That gap is this skill.

You run as a forked subagent with none of the caller's conversation. Everything you need is below, in `$ARGUMENTS`, or on disk.

## 1. Pin the change

`$ARGUMENTS` carries a base ref (a commit SHA, `main`, `HEAD~5`) and optionally a spec path — `base=<sha> spec=<path>`, or just the two values.

With no base ref, work down this list:

1. **An open PR on this branch.**

   ```bash
   gh pr view --json baseRefName,baseRefOid,isCrossRepository
   ```

   Use **`baseRefOid`** — it is the base commit itself, so no branch name has to be turned into a ref. Confirm the object is actually here before using it, and fetch it if not:

   ```bash
   git cat-file -e <baseRefOid>^{commit} || git fetch origin <baseRefName>
   git cat-file -e <baseRefOid>^{commit}   # recheck: fetch can succeed without bringing this object
   ```

   For a fork PR, `isCrossRepository` is true and the base lives on the upstream remote.

   **If `gh` fails rather than reporting no PR, stop.** Not installed, not authenticated, offline, rate-limited, an API error — none of those are evidence that there is no pull request. Falling through to step 2 in that state reviews a PR against the wrong base and says nothing about it. Only "no pull requests found" earns the fallback; report anything else verbatim.

   Do **not** use `baseRefName` as a ref. It is a branch name — `dev`, not `origin/dev`. When no local `dev` exists the command fails loudly, which is survivable; the dangerous case is when a *stale* local `dev` exists, because then `git merge-base dev HEAD` succeeds and hands you a base from whenever that branch was last fetched, quietly adding other people's commits to the review.

   **A PR exists but its base cannot be resolved? Stop and report that.** Do not slide down to step 2 — reviewing a PR that targets `release/3.2` against `main` produces a diff full of other people's commits, and every finding drawn from it is fiction.

2. **No PR at all** — the remote's default branch:

   ```bash
   git ls-remote --symref origin HEAD            # asks the remote — the only current answer
   git symbolic-ref refs/remotes/origin/HEAD     # offline fallback; see the caveat below
   ```

   Ask the remote **first**. `refs/remotes/origin/HEAD` is written once at clone time and `git fetch` never refreshes it, so after the project renames its default branch it keeps returning the old name with exit 0 — a valid branch that is no longer the default. Use it only when the remote is unreachable, and say in the report that the answer may be stale. (`git remote set-head origin -a` repairs it.)

   `ls-remote` **only asks** — it downloads nothing. In a `--single-branch` or shallow clone (the normal shape in CI) the default branch's commit is not in the object store, so `merge-base` against it exits 128 and the review stops for no good reason. Fetch it first:

   ```bash
   git fetch origin "+refs/heads/<default>:refs/remotes/origin/<default>"
   git merge-base refs/remotes/origin/<default> HEAD
   ```

   If `merge-base` still fails afterwards, the clone is shallow past the common ancestor: say so and stop, or ask the user before deepening (`--deepen`), which can be expensive.

   Only if both lookups fail, try `origin/main` then `origin/master` — and say in the report that the default branch was **guessed**. A repository whose default is `dev` or `trunk` may well also have a `main`, and `origin/main` will resolve happily against the wrong base.

3. Nothing resolves. Make "no base ref, and none could be inferred" the whole report.

**Never fall back to `@{upstream}`.** On a feature branch that has been pushed, the upstream *is* this branch: `git merge-base HEAD @{upstream}` returns HEAD, the diff comes back empty, and you review only the uncommitted scraps while every commit on the branch escapes silently. You are a forked subagent — you cannot ask a question and wait for an answer, so a wrong default here is never corrected.

```bash
git merge-base <base-ref> HEAD          # run it, read the SHA it prints
git diff <that-literal-sha>             # committed *and* uncommitted work
git log <that-literal-sha>..HEAD --oneline
git status --porcelain                  # untracked files are invisible to diff
```

Use the **printed SHA** in each later command. A shell variable does not survive to the next command, and an empty one silently degrades `git diff` into an unstaged-only diff — a smaller, wrong review. If `merge-base` fails, the base shares no history with `HEAD` (or the clone is shallow): stop and say so.

Read any untracked files that belong to the change; they are additions the diff cannot show.

## 2. Find the spec

In order: the path the caller passed; a tracker issue referenced in the commit messages (`#123`, `Closes #45` — fetch with `gh issue view <n>`); a plan from `/grill-me` at `"$(git rev-parse --git-common-dir)/../.plans"` (that resolves to the main checkout from inside a worktree too; inside a **submodule** it lands in `.git/modules/` instead, so check `git rev-parse --show-superproject-working-tree` and use the superproject when it is non-empty, and outside a repository fall back to `./.plans`); a spec file under `docs/`, `specs/`, or `.scratch/`.

A repository created with `--separate-git-dir` puts the common dir outside the checkout, so `.plans` lands beside the git dir rather than inside the checkout. The three consumers resolve it the same way and stay consistent with each other there; the location is surprising, not broken. A layout this collection does not chase further.

**Take a plan only if it matches this change** — its slug or title names the branch or feature. Several candidates, or none that match: report that and stop. (Do not judge by file age: a plan written before a `git pull` is older than the base commit and still the right plan.) A stale plan from another feature yields confident, entirely fictional findings, which is worse than no review.

If there is no spec at all, say so and stop. Inventing one from the diff reviews the change against itself.

## 3. Report

- **Missing or partial** — requirements the spec asked for that the change does not deliver.
- **Unasked-for** — behaviour in the change the spec does not call for. Check the spec's *Out of scope* section explicitly if it has one.
- **Wrong** — requirements that look implemented but where the implementation does not match what was specified.

Quote the spec line for every finding, and cite `file:line` in the change. Mark each **Critical** (a stated requirement is missing or wrong in a way that ships broken behaviour), **Important** (partial, or unrequested behaviour a reviewer would question), or **Minor**. Order the report by severity.

Close with the spec's decisions you confirmed as correctly built — a report listing only problems leaves the caller unable to tell coverage from silence.

## Completion criterion

Every decision or requirement in the spec appears exactly once in your report: built, missing, partial, wrong, or explicitly deferred by the spec itself. If you could not check one, say which and why.

---

_Descended from [mattpocock/skills](https://github.com/mattpocock/skills) `code-review` (MIT), now narrow. Dropped: the Standards axis, the Fowler smell baseline, and the Correctness/Risk axis — Claude Code's built-in `/code-review` covers the last two in its own background subagent, and a personal skill named `code-review` silently replaces that built-in ([docs](https://code.claude.com/docs/en/skills#where-skills-live)), so this one was renamed. What is left is the one axis nothing else can do: whether the change matches the plan it was built from. Added here: the base resolution order, `context: fork` / `background: false`, and `$ARGUMENTS`, since a forked subagent inherits none of the caller's context. Per-release detail: [NOTICE.md](https://github.com/zhoukaichaoaa/lean-skills/blob/main/NOTICE.md)._
