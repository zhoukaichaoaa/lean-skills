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

With no base ref, work down this list and stop at the first that resolves:

1. The PR's base branch, if this branch has an open PR — `gh pr view --json baseRefName -q .baseRefName`.
2. The remote's default branch — `git symbolic-ref refs/remotes/origin/HEAD` (or `origin/main`, `origin/master`).
3. Nothing. Make "no base ref, and none could be inferred" the whole report.

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

In order: the path the caller passed; a tracker issue referenced in the commit messages (`#123`, `Closes #45` — fetch with `gh issue view <n>`); a plan from `/grill-me` at `$(git rev-parse --git-common-dir)/../.plans` (that path resolves to the main checkout from inside a worktree too, where an untracked `.plans/` never appears); a spec file under `docs/`, `specs/`, or `.scratch/`.

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

_Descended from [mattpocock/skills](https://github.com/mattpocock/skills) `code-review` (MIT), now narrow: the Standards axis and the Fowler smell baseline are dropped, and the Correctness/Risk axis with them — Claude Code's built-in `/code-review` covers both in its own background subagent, and a personal skill named `code-review` silently replaces that built-in ([docs](https://code.claude.com/docs/en/skills#where-skills-live)). What is left is the one axis nothing else can do. Renamed from `code-review` and narrowed in 0.7.0._
