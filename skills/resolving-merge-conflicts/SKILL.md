---
name: resolving-merge-conflicts
description: Use when git reports conflicts during a merge, rebase, cherry-pick, revert or pull — before touching any hunk, and before staging anything.
---

# Resolving Merge Conflicts

Run every command below and **read what it printed**. Never wrap one in `$(...)` and feed it straight to the next: a command that produces nothing still succeeds inside a substitution, and the outer command then runs against a different, plausible-looking argument list. Every silent failure this skill has ever had took that shape.

1. **Identify the operation and its incoming side.** Which one is in progress decides both how it ends and what counts as "its" changes. Look in `$(git rev-parse --git-dir)` — `--git-dir`, not `--git-common-dir`: inside a linked worktree the conflict state lives in that worktree's own directory.

   | Present | Operation | Incoming ref | Finish with |
   |---|---|---|---|
   | `MERGE_HEAD` | merge (including `pull`) | `MERGE_HEAD` | `git commit` or `git merge --continue` |
   | `rebase-merge/` or `rebase-apply/` | rebase | `REBASE_HEAD` | `git rebase --continue` |
   | `CHERRY_PICK_HEAD` | cherry-pick | `CHERRY_PICK_HEAD` | `git cherry-pick --continue` |
   | `REVERT_HEAD` | revert | `REVERT_HEAD` | `git revert --continue` |

2. **Work out what the operation brings.** For a merge, that is everything from the merge base to the incoming tip — **not** `HEAD..MERGE_HEAD`, which also lists every file your own side changed since the base:

   ```bash
   git -c core.quotePath=false merge-base HEAD MERGE_HEAD   # read the SHA it prints
   git -c core.quotePath=false diff --name-status -M <that literal SHA> MERGE_HEAD
   ```

   **No SHA printed?** The two sides share no history (`--allow-unrelated-histories`, a vendored subtree, a rewritten upstream). Do not carry on with an empty base — the diff would silently compare against your working tree and invert everything below. Use the empty tree instead: `git hash-object -t tree /dev/null` prints its SHA, and diffing from it means "the incoming side brings all of its content".

   For the other three operations it is the single commit being applied — substitute the ref from step 1:

   ```bash
   git -c core.quotePath=false diff --name-status -M REBASE_HEAD^ REBASE_HEAD
   git -c core.quotePath=false diff --name-status -M CHERRY_PICK_HEAD^ CHERRY_PICK_HEAD
   git -c core.quotePath=false diff --name-status -M REVERT_HEAD^ REVERT_HEAD
   ```

   Run only the row you matched; the others name refs that do not exist and fail loudly with `fatal: ambiguous argument`.

3. **Separate the user's work from the operation's.** The index right now holds both, and the operation is about to commit *all* of it — a merge commit takes the whole index no matter which paths you name.

   ```bash
   git -c core.quotePath=false diff --cached --name-status -M HEAD
   git -c core.quotePath=false status --porcelain
   ```

   `--name-status -M` matters: with `--name-only` a rename shows up as the new path alone, and the deletion of the old path — still staged — travels into the commit unnoticed. `core.quotePath=false` matters for the same reason: by default git prints non-ASCII paths octal-escaped, and pasting that back produces `pathspec did not match`, which reads exactly like "this file is untracked".

   Sort what is left into three lists; step 4 treats them differently:

   - **Staged, not brought by the operation** — the user's, and *in the index*. For a rename, both the old and the new path belong here.
   - **Working-tree only** — first column blank in porcelain (` M`, ` D`). Theirs, but not in the index; nothing to undo.
   - **Untracked** (`??`). Theirs, and git does not know them at all.

4. **Take the user's staged work out of the index before you resolve anything.** This is what makes the promise in step 8 achievable:

   ```bash
   git restore --staged -- <only the staged-not-brought list>   # older git: git reset HEAD -- <paths>
   ```

   **Only that first list.** Untracked and working-tree-only paths are not in the index, and passing one makes git reject the *whole* command, so the staged files you meant to rescue stay staged and get committed anyway.

   Confirm it took: `git -c core.quotePath=false diff --cached --name-status -M HEAD` should now list only what the operation brings. A name you cannot account for from any of the three lists is a signal, not noise — usually the other half of a rename. Tell the user what you unstaged and why. If a file is *both* conflicted and something they were editing, stop and ask; you cannot split that automatically.

   (git refuses to *start* any of these operations against a dirty index, so anything staged here was staged after the conflict appeared — by them or by you.)

5. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

6. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the operation's stated goal and note the trade-off. Keep the resolution to what the two sides already do. Resolve rather than flee — difficulty alone is never a reason to `--abort`. Abort only when the operation itself turns out to be a mistake (wrong branch, wrong base, wrong direction): say why, abort, and restart it right.

7. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the operation broke.

8. **Finish it.** Stage the conflicted files and whatever you edited in step 7, then run the finishing command for this operation from step 1. If rebasing or cherry-picking, note the SHA you started from (`git rev-parse ORIG_HEAD`) and repeat from step 1 for each subsequent conflicted commit until git reports the operation complete.

## Completion criterion

Long-form `git status` — not `--porcelain`, which stays silent about an operation stopped at a `break` — reports no operation in progress and no unresolved hunks; the project's checks pass; and every path you listed as the user's is still uncommitted. Prove that last one across **every** commit the operation produced, not just the tip:

```bash
git log --name-only --oneline <the SHA from step 8>..HEAD
```

A multi-commit rebase buries the user's file in an earlier commit, where `git show HEAD` cannot see it.

---

_From [mattpocock/skills](https://github.com/mattpocock/skills) `resolving-merge-conflicts` (MIT); heading, completion criterion and this attribution added, the absolute never-abort rule relaxed (aborting is allowed when the operation itself is a mistake), blanket `git add -A` staging removed, per-operation incoming refs and finishing commands added, and the user's in-flight work identified by diffing the index against what the operation brings from the merge base — then actually unstaged, since naming paths at commit time does not keep them out of a merge commit. Rename-aware and quote-safe as of 0.9.0._
