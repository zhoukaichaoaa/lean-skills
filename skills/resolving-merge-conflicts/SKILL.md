---
name: resolving-merge-conflicts
description: Resolve an in-progress merge/rebase conflict hunk-by-hunk by intent, then finish the operation.
disable-model-invocation: true
---

# Resolving Merge Conflicts

1. **See the current state** of the merge/rebase. Check git history, and the conflicting files. Note which files were already dirty before the merge began (`git stash list`, the operation's ORIG_HEAD, what the user says they were mid-way through) — those edits belong to the user, not to this merge.

2. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

3. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the merge's stated goal and note the trade-off. Do **not** invent new behaviour. Resolve rather than flee — difficulty alone is never a reason to `--abort`. Abort only when the merge itself turns out to be a mistake (wrong branch, wrong base, wrong direction): say why, abort, and restart it right.

4. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the merge broke.

5. **Finish the merge/rebase.** Stage the files this merge touched — `git diff --name-only --diff-filter=U` lists what was conflicted, plus anything you edited in step 4 — and commit. Staging with `git add -A` would sweep the user's unrelated work-in-progress into the merge commit; leave those files alone and say they're still uncommitted. If rebasing, repeat from step 1 for each subsequent conflicted commit until the rebase reports completion.

## Completion criterion

`git status` shows no merge or rebase in progress, no unresolved hunks remain, the project's checks pass, and any working-tree edits that were not part of this merge are still uncommitted and named in your report.

---

_From [mattpocock/skills](https://github.com/mattpocock/skills) `resolving-merge-conflicts` (MIT); heading, completion criterion and this attribution added, the absolute never-abort rule relaxed (aborting is allowed when the merge itself is a mistake), and blanket `git add -A` staging narrowed to the merge's own files._
