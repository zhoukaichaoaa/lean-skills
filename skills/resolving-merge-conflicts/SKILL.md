---
name: resolving-merge-conflicts
description: Resolve an in-progress merge/rebase conflict hunk-by-hunk by intent, then finish the operation.
disable-model-invocation: true
---

# Resolving Merge Conflicts

1. **See the current state** of the merge/rebase. Check git history, and the conflicting files.

2. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

3. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the merge's stated goal and note the trade-off. Do **not** invent new behaviour. Resolve rather than flee — difficulty alone is never a reason to `--abort`. Abort only when the merge itself turns out to be a mistake (wrong branch, wrong base, wrong direction): say why, abort, and restart it right.

4. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the merge broke.

5. **Finish the merge/rebase.** Stage everything and commit. If rebasing, continue the rebase process until all commits are rebased.

---

_From [mattpocock/skills](https://github.com/mattpocock/skills) `resolving-merge-conflicts` (MIT); heading and this attribution added, and the absolute never-abort rule relaxed — aborting is allowed when the merge itself is a mistake._
