---
name: resolving-merge-conflicts
description: Use when git reports conflicts during a merge, rebase, cherry-pick, revert or pull — before touching any hunk, and before staging anything.
---

# Resolving Merge Conflicts

1. **Identify the operation and its incoming side.** Which one is in progress decides both how it ends and what counts as "its" changes. Look in `$(git rev-parse --git-dir)` — note `--git-dir`, not `--git-common-dir`: inside a linked worktree the conflict state lives in that worktree's own directory.

   | Present | Operation | Incoming ref | Finish with |
   |---|---|---|---|
   | `MERGE_HEAD` | merge (including `pull`) | `MERGE_HEAD` | `git commit` or `git merge --continue` |
   | `rebase-merge/` or `rebase-apply/` | rebase | `REBASE_HEAD` | `git rebase --continue` |
   | `CHERRY_PICK_HEAD` | cherry-pick | `CHERRY_PICK_HEAD` | `git cherry-pick --continue` |
   | `REVERT_HEAD` | revert | `REVERT_HEAD` | `git revert --continue` |

2. **Separate the user's work from the operation's, before touching anything.** The index right now holds both, and the operation is about to commit *all* of it — a merge commit takes the whole index no matter which paths you name.

   ```bash
   git diff --cached --name-only HEAD                                   # everything staged
   git diff --name-only $(git merge-base HEAD MERGE_HEAD) MERGE_HEAD    # merge: what it brings
   git diff --name-only REBASE_HEAD^ REBASE_HEAD                        # rebase / cherry-pick / revert:
                                                                        # the single commit being applied
   ```

   Diff from the **merge base**, not from `HEAD`: `HEAD..MERGE_HEAD` also lists every file your side changed since the base, so a file the user edited that the merge never touches would be misfiled as the operation's.

   Staged files the operation does not bring are **the user's**, as are working-tree-only changes — first column blank in `git status --porcelain` (` M`, ` D`) — and untracked files (`??`). Write that list down.

3. **Take the user's work out of the index before you resolve anything.** This is the step that makes the promise in step 6 achievable:

   ```bash
   git restore --staged <each user file>      # older git: git reset HEAD -- <file>
   ```

   The edits stay in the working tree; they are simply no longer queued for the operation's commit. Tell the user what you unstaged and why. If a file is *both* conflicted and something they were editing, stop and ask — you cannot split that automatically.

   (Note: git refuses to *start* a merge, rebase, cherry-pick or revert against a dirty index, so anything staged here was staged after the conflict appeared — by them or by you.)

4. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

5. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the operation's stated goal and note the trade-off. Keep the resolution to what the two sides already do. Resolve rather than flee — difficulty alone is never a reason to `--abort`. Abort only when the operation itself turns out to be a mistake (wrong branch, wrong base, wrong direction): say why, abort, and restart it right.

6. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the operation broke.

7. **Finish it.** Stage the conflicted files and whatever you edited in step 6, then run the finishing command for this operation from step 1. If rebasing or cherry-picking, repeat from step 1 for each subsequent conflicted commit until git reports the operation complete.

## Completion criterion

`git status` shows no operation in progress and no unresolved hunks; the project's checks pass; and every file you listed in step 2 is still uncommitted — `git status --porcelain` shows it, and `git show --stat HEAD` does not.

---

_From [mattpocock/skills](https://github.com/mattpocock/skills) `resolving-merge-conflicts` (MIT); heading, completion criterion and this attribution added, the absolute never-abort rule relaxed (aborting is allowed when the operation itself is a mistake), blanket `git add -A` staging removed, per-operation incoming refs and finishing commands added, and the user's in-flight work identified by diffing the index against what the operation brings from the merge base — then actually unstaged, since naming paths at commit time does not keep them out of a merge commit. Model-invoked from 0.6.0._
