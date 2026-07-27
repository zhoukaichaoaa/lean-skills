---
name: resolving-merge-conflicts
description: Use when git reports conflicts during a merge, rebase, cherry-pick, revert or pull — before touching any hunk, and before staging anything.
---

# Resolving Merge Conflicts

Run every command below and **read what it printed**. Two shapes account for every silent failure this skill has ever had, and both produce output that looks correct:

- **Collapse to nothing.** A command that prints nothing still succeeds inside `$(...)`, and the outer command then runs against a shorter, plausible argument list. Never chain one into the next; run it, read the value, use the value.
- **Collapse to the first.** Several things git will hand you are *not single-valued*, and the convenient accessor quietly returns element one: `MERGE_HEAD` can hold several commits while `git rev-parse MERGE_HEAD` prints one; `<commit>^` is always parent 1 even when the operation named a different mainline; `refs/remotes/origin/HEAD` is whatever the default branch was on the day you cloned. Each returns a valid SHA with exit 0. Check the arity before you trust the value.

1. **Identify the operation and its incoming side.** Which one is in progress decides both how it ends and what counts as "its" changes. Look in `$(git rev-parse --git-dir)` — `--git-dir`, not `--git-common-dir`: inside a linked worktree the conflict state lives in that worktree's own directory.

   | Present | Operation | Incoming ref | Finish with | Where the operation started |
   |---|---|---|---|---|
   | `MERGE_HEAD` | merge (including `pull`) | every line of that file | `git commit` or `git merge --continue` | `git rev-parse HEAD` |
   | `rebase-apply/` **with** `applying` | `git am` | — | `git am --continue` | not covered below; resolve the conflict and stop |
   | `rebase-merge/` or `rebase-apply/` | rebase | `REBASE_HEAD` | `git rebase --continue` | `cat "$G/rebase-merge/onto"` (or `rebase-apply/onto`) |
   | `CHERRY_PICK_HEAD` | cherry-pick | `CHERRY_PICK_HEAD` | `git cherry-pick --continue` | `cat "$G/sequencer/head"` if it exists, else `git rev-parse HEAD` |
   | `REVERT_HEAD` | revert | `REVERT_HEAD` | `git revert --continue` | same as cherry-pick |

   `G="$(git rev-parse --git-dir)"` — those state files live under it, and `.git` is a *file* inside a submodule or a linked worktree, so the literal path fails there.

   **None of the four present?** Then this is not one of these operations — `git stash pop` and `git apply --3way` both conflict without leaving any marker. Resolve the conflict and stop; steps 2, 4 and 9 assume an operation that has an incoming side and a start point.

   **Read `MERGE_HEAD` as a file, not with `rev-parse`.** An octopus merge writes one commit per line, and `git rev-parse MERGE_HEAD` prints only the first — exit 0, a perfectly valid SHA, and the other side's changes vanish from every calculation below.

   **If the operation was given `-m <n>`** (replaying a merge commit), the mainline it names is *not* recoverable from `.git` afterwards. `git rev-parse -q --verify <REF>^2` succeeding tells you the target is a merge commit and that `^` is therefore ambiguous — ask the user which `-m` they passed rather than assuming `^1`.

   **Record that last column now**, before you touch anything — it is the boundary step 9 checks against, and after the operation finishes there is no way to recover it. `ORIG_HEAD` is not that boundary: a single cherry-pick never sets it (`git rev-parse ORIG_HEAD` exits 128), and for a rebase it points at the pre-rebase branch tip, so `ORIG_HEAD..HEAD` also sweeps in commits that were already sitting on the new base.

2. **Work out what the operation brings.** For a merge, that is everything from the merge base to the incoming tip — **not** `HEAD..MERGE_HEAD`, which also lists every file your own side changed since the base:

   ```bash
   cat "$G/MERGE_HEAD"                                       # one line per incoming head
   # for each of them, in turn:
   git -c core.quotePath=false merge-base HEAD <that head>   # read the SHA it prints
   git -c core.quotePath=false diff --name-status -M <that literal SHA> <that head>
   ```

   With more than one incoming head, take the **union** of the results — a file only b2 brings is still the operation's, and treating it as the user's is how the second parent's work gets thrown away.

   **No SHA printed?** The two sides share no history (`--allow-unrelated-histories`, a vendored subtree, a rewritten upstream). Do not carry on with an empty base — the diff would silently compare against your working tree and invert everything below. Diff from the empty tree instead, which means "the incoming side brings all of its content":

   ```bash
   git hash-object -t tree /dev/null                                       # the empty tree's SHA
   git -c core.quotePath=false diff --name-status -M <that SHA> <that head>
   ```

   For the other three operations it is the single commit being applied — substitute the ref from step 1:

   ```bash
   git -c core.quotePath=false diff --name-status -M REBASE_HEAD^<n> REBASE_HEAD
   git -c core.quotePath=false diff --name-status -M CHERRY_PICK_HEAD^<n> CHERRY_PICK_HEAD
   git -c core.quotePath=false diff --name-status -M REVERT_HEAD^<n> REVERT_HEAD
   ```

   `<n>` is the mainline: `1` for an ordinary commit, and for a merge commit the `-m` the operation was given. Run only the row you matched; the others name refs that do not exist and fail loudly with `fatal: ambiguous argument`. On a revert the status letters are inverted — an `A` means the revert *removes* that path — so read the paths, not the letters.

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

8. **Finish it.** Stage the conflicted files and whatever you edited in step 7, then run the finishing command for this operation from step 1. If rebasing or cherry-picking, repeat from step 1 for each subsequent conflicted commit until git reports the operation complete — the boundary you recorded at the first conflict stays valid for the whole run.

9. **Prove the user's work survived.** Ask it of the paths themselves, which is exact and operation-agnostic:

   ```bash
   git -c core.quotePath=false status --porcelain -- ':(top)<every path you listed as the user's in step 3>'
   ```

   Each must still appear. A path that has gone quiet was committed by the operation. The `:(top)` prefix matters: pathspecs resolve against the current directory while step 3 printed them relative to the repository root, so running this from a subdirectory silently matches nothing and reads as "all of it was committed". If step 3's list was empty, say so — there was no in-flight work to protect, and an empty check proves nothing.

   Then cross-check against what the operation actually recorded, using the boundary from step 1:

   ```bash
   git -c core.quotePath=false log --name-only --oneline <boundary>..HEAD   # rebase, cherry-pick, revert
   git log -1 --format=%P HEAD                      # merge: list the parents, then diff against each
   git -c core.quotePath=false diff --name-only HEAD^<n> HEAD               #   an octopus merge has more than two
   ```

   `git show HEAD` is not enough: a multi-commit rebase buries the file in an earlier commit, and on a merge commit `--stat` alone hides it.

## Completion criterion

Long-form `git status` — not `--porcelain`, which stays silent about an operation stopped at a `break` — reports no operation in progress and no unresolved hunks; the project's checks pass; and step 9 found every path you listed as the user's still uncommitted, by both of its checks.

---

_From [mattpocock/skills](https://github.com/mattpocock/skills) `resolving-merge-conflicts` (MIT); heading, completion criterion and this attribution added, the absolute never-abort rule relaxed (aborting is allowed when the operation itself is a mistake), blanket `git add -A` staging removed, per-operation incoming refs and finishing commands added, and the user's in-flight work identified by diffing the index against what the operation brings from the merge base — then actually unstaged, since naming paths at commit time does not keep them out of a merge commit. Rename-aware and quote-safe as of 0.9.0._
