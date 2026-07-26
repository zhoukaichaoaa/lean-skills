---
name: resolving-merge-conflicts
description: Use when git reports conflicts during a merge, rebase, cherry-pick, or pull — before touching any hunk, and before staging anything.
---

# Resolving Merge Conflicts

1. **See the current state** of the merge/rebase. Check git history, and the conflicting files.

   Then separate the user's work from the merge's, using the two columns of `git status --porcelain`: the first is the index, the second the working tree. `UU` (and `AA`, `DU`, …) are the conflicts. A **blank first column** — ` M`, ` D`, `??` — means the change is in the working tree only, so the merge did not put it there: **it is the user's uncommitted work**. Write that list down now; step 5 must leave it untouched.

2. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

3. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the merge's stated goal and note the trade-off. Do **not** invent new behaviour. Resolve rather than flee — difficulty alone is never a reason to `--abort`. Abort only when the merge itself turns out to be a mistake (wrong branch, wrong base, wrong direction): say why, abort, and restart it right.

4. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the merge broke.

5. **Finish the merge/rebase.** Stage the files this merge touched — the conflicted ones from step 1, plus anything you edited in step 4 — and commit. Staging with `git add -A` would sweep the user's working-tree-only files into the merge commit; leave those alone and say in your report that they are still uncommitted. If rebasing, repeat from step 1 for each subsequent conflicted commit until the rebase reports completion.

## Completion criterion

`git status` shows no merge or rebase in progress, no unresolved hunks remain, the project's checks pass, and any working-tree edits that were not part of this merge are still uncommitted and named in your report.

---

_From [mattpocock/skills](https://github.com/mattpocock/skills) `resolving-merge-conflicts` (MIT); heading, completion criterion and this attribution added, the absolute never-abort rule relaxed (aborting is allowed when the merge itself is a mistake), blanket `git add -A` staging narrowed to the merge's own files, and the user's in-flight work identified from the two columns of `git status --porcelain` (0.6.0 — `git stash list` and `ORIG_HEAD`, tried first, cannot produce that list). Model-invoked from 0.6.0._
