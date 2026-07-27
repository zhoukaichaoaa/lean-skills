---
name: resolving-merge-conflicts
description: Use when git reports conflicts during a merge, rebase, cherry-pick, revert or pull — before touching any hunk, and before staging anything.
---

# Resolving Merge Conflicts

Run every command below and **read what it printed**. Two shapes account for every silent failure this skill has ever had, and both produce output that looks correct:

- **Collapse to nothing.** A command that prints nothing still succeeds inside `$(...)`, and the outer command then runs against a shorter, plausible argument list. Never chain one into the next; run it, read the value, use the value.
- **Collapse to the first.** Several things git will hand you are *not single-valued*, and the convenient accessor quietly returns element one: `git merge-base` prints one base while criss-cross history has several, and the two disagree about which files the operation brings; `MERGE_HEAD` can hold several commits while `git rev-parse MERGE_HEAD` prints one; `<commit>^` is always parent 1 even when the operation named a different mainline; `refs/remotes/origin/HEAD` is whatever the default branch was on the day you cloned. Each returns a valid SHA with exit 0. Check the arity before you trust the value.
- **The error names the wrong cause.** Once, at step 8, git refuses and its message describes a state you can see is not true. Do not act on the message's suggestion: it points at the user's rescued work, and taking it commits exactly what this skill exists to protect. Step 8 says what to do instead.

1. **Identify the operation and its incoming side.** Which one is in progress decides both how it ends and what counts as "its" changes. Look in `$(git rev-parse --git-dir)` — `--git-dir`, not `--git-common-dir`: inside a linked worktree the conflict state lives in that worktree's own directory.

   **Read the table top to bottom and stop at the first row that matches** — the rows are not mutually exclusive. `git rebase -r` (`--rebase-merges`) replays a merge commit, and while that merge is conflicted **both** `MERGE_HEAD` and `rebase-merge/` are present. Taking the merge row there gives a boundary that is the commit the rebase just made, and a finishing command that commits successfully and leaves the rebase exactly where it was — exit 0, a new commit, nothing advanced.

   | Present | Operation | Incoming ref | Finish with | Where the operation started |
   |---|---|---|---|---|
   | `rebase-apply/` **with** `applying` | `git am` | — | `git am --continue` | not covered below; resolve the conflict and stop |
   | `rebase-merge/` or `rebase-apply/` | rebase (including `-r`) | `REBASE_HEAD` | `git rebase --continue` | `cat "$G/rebase-merge/onto"` (or `rebase-apply/onto`) |
   | `MERGE_HEAD` | merge (including `pull`) | every line of that file | `git commit` or `git merge --continue` | `git rev-parse HEAD` |
   | `CHERRY_PICK_HEAD` | cherry-pick | `CHERRY_PICK_HEAD` | `git cherry-pick --continue` | `cat "$G/sequencer/head"` if it exists, else `git rev-parse HEAD` |
   | `REVERT_HEAD` | revert | `REVERT_HEAD` | `git revert --continue` | same as cherry-pick |

   `G="$(git rev-parse --git-dir)"` — those state files live under it, and `.git` is a *file* inside a submodule or a linked worktree, so the literal path fails there.

   **None of the four present?** Then this is not one of these operations — `git stash pop` and `git apply --3way` both conflict without leaving any marker. Resolve the conflict and stop; steps 2, 4 and 9 assume an operation that has an incoming side and a start point.

   **Read `MERGE_HEAD` as a file, not with `rev-parse`.** An octopus merge writes one commit per line, and `git rev-parse MERGE_HEAD` prints only the first — exit 0, a perfectly valid SHA, and the other side's changes vanish from every calculation below.

   **If the operation was given `-m <n>`** (replaying a merge commit), the mainline it names is *not* recoverable from `.git` afterwards. `git rev-parse -q --verify <REF>^2` succeeding tells you the target is a merge commit and that `^` is therefore ambiguous — ask the user which `-m` they passed rather than assuming `^1`.

   **Record that last column now**, before you touch anything — it is the boundary step 9 checks against, and after the operation finishes there is no way to recover it. `ORIG_HEAD` is not that boundary: a single cherry-pick never sets it (`git rev-parse ORIG_HEAD` exits 128), and for a rebase it points at the pre-rebase branch tip, so `ORIG_HEAD..HEAD` also sweeps in commits that were already sitting on the new base.

2. **Work out what the operation brings.** For a merge, that is everything from the merge base to the incoming tip — **not** `HEAD..MERGE_HEAD`, which also lists every file your own side changed since the base:

   ```bash
   cat "$G/MERGE_HEAD"                                # one line per incoming head
   # for each of them, in turn:
   git merge-base --all HEAD <that head>              # read every SHA it prints
   git -c core.quotePath=false diff --name-status -M <that literal SHA> <that head>
   ```

   `--all`, not plain `merge-base`: when the two sides have merged each other before — a team that repeatedly merges `main` into a feature branch produces exactly this — there is more than one merge base, and `merge-base` prints one of them with exit 0. The bases disagree about which files the operation brings, so the wrong one both leaves a file of the operation's in the index and unstages a file of the user's.

   Take the **union** across every base and every incoming head. A file that only one of them brings is still the operation's, and treating it as the user's is how the second parent's work gets thrown away.

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

   **Count the parents before you pick `<n>`** — `git rev-list --parents -n 1 <REF>` prints the commit followed by its parents:

   ```bash
   git rev-list --parents -n 1 <REF>      # count the SHAs after the first one
   ```

   - **None.** A root commit, which `git rebase --root` and a cherry-pick of a repository's first commit both replay. `<REF>^1` does not exist and exits 128. Diff from the empty tree instead: `git hash-object -t tree /dev/null` prints its SHA, and everything in the commit is what the operation brings.
   - **One.** `<n>` is `1`.
   - **More than one.** A merge commit; `<n>` is the `-m` the operation was given, which is not recoverable afterwards — ask the user.

   Run only the row you matched; the others name refs that do not exist and fail loudly with `fatal: ambiguous argument`. On a revert the status letters are inverted — an `A` means the revert *removes* that path — so read the paths, not the letters.

3. **Separate the user's work from the operation's.** The index right now holds both, and the operation is about to commit *all* of it — a merge commit takes the whole index no matter which paths you name.

   ```bash
   git -c core.quotePath=false diff --cached --name-status -M HEAD
   git -c core.quotePath=false status --porcelain
   ```

   `--name-status -M` matters: with `--name-only` a rename shows up as the new path alone, and the deletion of the old path — still staged — travels into the commit unnoticed. `core.quotePath=false` matters for the same reason: by default git prints non-ASCII paths octal-escaped, and pasting that back produces `pathspec did not match`, which reads exactly like "this file is untracked".

   Sort what is left into three lists; step 4 treats them differently:

   - **Staged, not brought by the operation** — the user's, and *in the index*. For a rename, both the old and the new path belong here.
   - **Working-tree only** — first column blank in porcelain (` M`, ` D`). Tracked, so git knows them, but the index still holds the `HEAD` version; there is nothing to unstage.
   - **Untracked** (`??`). Theirs, and git does not know them at all.

   **Paths with a space are quoted no matter what.** `--porcelain` wraps any path containing a space, a quote or a backslash in C quotes, and `core.quotePath` does not turn that off — it governs non-ASCII bytes only. Pasting `"my report.txt"` back fails two different ways: `git restore --staged` rejects the whole command, and step 9's `status` silently matches nothing. Read such paths with `git status --porcelain -z`, which separates records with NUL and quotes nothing.

4. **Take the user's staged work out of the index before you resolve anything.** This is what makes the promise in step 8 achievable:

   ```bash
   git restore --staged -- <only the staged-not-brought list>   # older git: git reset HEAD -- <paths>
   ```

   **Only that first list.** An untracked path is not in the index, and passing one makes git reject the *whole* command — the staged files you meant to rescue stay staged and get committed anyway. (A working-tree-only path is harmless to pass, but it has nothing to unstage, so listing it only obscures what you did.)

   Confirm it took: `git -c core.quotePath=false diff --cached --name-status -M HEAD` should now list only what the operation brings. A name you cannot account for from any of the three lists is a signal, not noise — usually the other half of a rename. Tell the user what you unstaged and why. If a file is *both* conflicted and something they were editing, stop and ask; you cannot split that automatically.

   (git refuses to *start* any of these operations against a dirty index, so anything staged here was staged after the conflict appeared — by them or by you.)

5. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

6. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the operation's stated goal and note the trade-off. Keep the resolution to what the two sides already do. Resolve rather than flee — difficulty alone is never a reason to `--abort`. Abort only when the operation itself turns out to be a mistake (wrong branch, wrong base, wrong direction): say why, abort, and restart it right.

7. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the operation broke.

8. **Finish it.** Stage the conflicted files and whatever you edited in step 7, then run the finishing command for this operation from step 1.

   **Rebase only: park the user's tracked modifications first.** `git rebase --continue` needs a working tree with nothing modified except the conflict you just resolved. The paths you rescued in step 4 are now unstaged modifications, and it refuses with *"You must edit all merge conflicts and then mark them as resolved using git add"* — a message about conflicts, while `git diff --name-only --diff-filter=U` prints nothing. The only unstaged path in sight is the user's, so the obvious next move is to `git add` it, and the rebase then commits the very work step 4 rescued.

   **Only tracked modifications need parking.** An untracked file does not block `--continue` and is never committed by it; leave it alone.

   Park the changes as a patch — not the files:

   ```bash
   G="$(git rev-parse --git-dir)"                          # from step 1
   P="$G/lean-parked-$(date +%s).patch"
   test ! -e "$P"                                          # never reuse a name
   git diff --binary -- <each tracked path from step 4> > "$P"
   test -s "$P"                                            # nothing captured means nothing to park
   git checkout -- <the same paths>                        # now the tree is clean
   ```

   **A patch, because a copy cannot carry what a change is.** `cp` moves file *contents*, and the user's work is not always contents: a deleted path has nothing to copy, a rename is two paths, `a/config.txt` and `b/config.txt` collapse onto each other in one flat directory, and a mode change is invisible. `git diff --binary` records all of it — paths, deletions, renames, modes, binary content — and it is the same patch format `git apply` reads back.

   **A fresh name each time.** A fixed one silently mixes today's work with whatever an interrupted run left behind. Refuse rather than overwrite.

   **`git stash` is the wrong tool here, and quietly so.** A stash always records the **whole index**, which during a conflict holds the resolution you just staged. Popping it later replays that stale resolution over the rebased file and produces a `UU` conflict neither side asked for. Popping *during* the rebase is worse — the next commit may conflict too, and `git stash pop` against an unmerged index fails with `error: could not write index`, which reads like the work is gone when it is still in the stash.

   **Restore only once the whole operation is over.** A rebase of several commits stops at each conflicting one, so repeat step 1 through here for each. Only when long-form `git status` reports no operation in progress:

   ```bash
   git apply --3way "$P"          # read the exit code
   ```

   - **Exit 0** — the work went back cleanly. It landed in the index, so put it back the way step 4 left it and then drop the patch:

     ```bash
     git restore --staged -- <the same paths>
     rm -f "$P"
     ```

   - **Non-zero** — the operation changed one of these paths too, and `--3way` has written conflict markers rather than choosing for you. That is the honest answer, and the reason this is not a `cp`: a copy would have silently overwritten the operation's version. **Keep the patch**, name it to the user, and resolve those hunks with them. Delete it only after they confirm their work is back.

   Merge, cherry-pick and revert do not need any of this — all three finish with the user's modifications sitting in the working tree, exit 0, and commit nothing of theirs.

   If rebasing or cherry-picking, repeat from step 1 for each subsequent conflicted commit until git reports the operation complete — the boundary you recorded at the first conflict stays valid for the whole run.

9. **Prove the user's work survived.** Ask it of the paths themselves, which is exact and operation-agnostic:

   ```bash
   git -c core.quotePath=false status --porcelain -- ':(top)first-path' ':(top)second-path'
   ```

   **One `:(top)` argument per path.** Several paths inside a single pair of quotes is *one* pathspec containing spaces; it matches nothing, exits 0, and reads exactly like "all of it was committed". A rename forces this case — step 3 puts both the old and the new path on the list.

   Each must still appear. A path that has gone quiet was committed by the operation. The `:(top)` prefix matters too: pathspecs resolve against the current directory while step 3 printed them relative to the repository root, so running this from a subdirectory silently matches nothing and reads the same wrong way. If step 3's list was empty, say so — there was no in-flight work to protect, and an empty check proves nothing.

   Then cross-check against what the operation actually recorded, using the boundary from step 1:

   ```bash
   git -c core.quotePath=false log --name-only --diff-merges=first-parent --oneline <boundary>..HEAD
   git log -1 --format=%P HEAD                      # merge: list the parents, then diff against each
   git -c core.quotePath=false diff --name-only HEAD^<n> HEAD               #   an octopus merge has more than two
   ```

   `--diff-merges=first-parent` is what makes a merge commit report anything at all: by default `git log` shows no file names for a merge, so a path swept into one is invisible in a listing that otherwise looks complete. `git rebase -r` produces merge commits, so this matters on the rebase line too, not only for merges.

   `git show HEAD` is not enough either: a multi-commit rebase buries the file in an earlier commit, and on a merge commit `--stat` alone hides it.

## Completion criterion

Long-form `git status` — not `--porcelain`, which stays silent about an operation stopped at a `break` — reports no operation in progress and no unresolved hunks; the project's checks pass; and step 9 found every path you listed as the user's still uncommitted, by both of its checks.

---

_From [mattpocock/skills](https://github.com/mattpocock/skills) `resolving-merge-conflicts` (MIT) — the upstream skill is a five-step outline; nearly all of what is above was written for this collection. Kept from it: find the primary sources, understand each change's intent, preserve both intents where possible, run the project's checks. Changed here: the absolute never-abort rule relaxed (aborting is right when the operation itself is the mistake); blanket `git add -A` staging removed; per-operation incoming refs, boundaries and finishing commands added; the user's in-flight work identified by diffing the index against what the operation brings from the merge base, then actually unstaged — naming paths at commit time does not keep them out of a merge commit. Per-release detail: [NOTICE.md](https://github.com/zhoukaichaoaa/lean-skills/blob/main/NOTICE.md)._
