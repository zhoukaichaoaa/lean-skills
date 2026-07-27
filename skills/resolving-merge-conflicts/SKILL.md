---
name: resolving-merge-conflicts
description: Use when git reports conflicts during a merge, rebase, cherry-pick, or pull — before touching any hunk, and before staging anything.
---

# Resolving Merge Conflicts

1. **Identify the operation and the base.** Which one is in progress decides how it ends, and they are not interchangeable:

   | Present in `$(git rev-parse --git-dir)` | Operation | Finish with |
   |---|---|---|
   | `MERGE_HEAD` | merge (including `pull`) | `git commit` or `git merge --continue` |
   | `rebase-merge/` or `rebase-apply/` | rebase | `git rebase --continue` |
   | `CHERRY_PICK_HEAD` | cherry-pick | `git cherry-pick --continue` |
   | `REVERT_HEAD` | revert | `git revert --continue` |

2. **Separate the user's work from the operation's, before touching anything.** The index at this moment holds both. Two commands settle it:

   ```bash
   git diff --cached --name-only HEAD            # everything currently staged
   git diff --name-only HEAD MERGE_HEAD          # what this operation actually touches
   ```

   Anything staged that the operation does not touch is **the user's** — they staged it before or during the conflict, and committing it here buries their work inside a merge commit where it does not belong. Files with a blank first column in `git status --porcelain` (` M`, ` D`, `??`) are theirs too. Write both lists down now; step 5 must leave them alone. If the lists are not empty, say so before you continue — the user may want to unstage or stash first.

   (For rebase and cherry-pick, compare against `REBASE_HEAD` / `CHERRY_PICK_HEAD` instead of `MERGE_HEAD`.)

3. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

4. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the operation's stated goal and note the trade-off. Do **not** invent new behaviour. Resolve rather than flee — difficulty alone is never a reason to `--abort`. Abort only when the operation itself turns out to be a mistake (wrong branch, wrong base, wrong direction): say why, abort, and restart it right.

5. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the merge broke.

6. **Finish it.** Stage only the conflicted files and whatever you edited in step 5, then use the finishing command for this operation from step 1. Never `git add -A`: it sweeps in everything from step 2, and a merge commit stages the whole index whether or not you named the files. If rebasing or cherry-picking, repeat from step 1 for each subsequent conflicted commit until git reports the operation complete.

## Completion criterion

`git status` shows no operation in progress and no unresolved hunks; the project's checks pass; and every file you listed in step 2 is still unstaged or still uncommitted, named in your report as untouched.

---

_From [mattpocock/skills](https://github.com/mattpocock/skills) `resolving-merge-conflicts` (MIT); heading, completion criterion and this attribution added, the absolute never-abort rule relaxed (aborting is allowed when the operation itself is a mistake), blanket `git add -A` staging removed, per-operation finishing commands added, and the user's in-flight work identified by diffing the index against what the operation touches — `git stash list`/`ORIG_HEAD` (used before 0.6.0) cannot produce that list, and the porcelain first column alone misses work staged during the conflict. Model-invoked from 0.6.0._
