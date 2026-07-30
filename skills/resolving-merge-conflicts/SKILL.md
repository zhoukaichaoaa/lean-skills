---
name: resolving-merge-conflicts
disable-model-invocation: true
description: EXPERIMENTAL, user-invoked only - the in-flight-work rescue has needed a correction in nearly every release since 0.12.0 and its state space is not exhausted; it moves your uncommitted work, so you decide when it runs. Use when git reports conflicts during a merge, rebase, cherry-pick, revert or pull — before touching any hunk, and before staging anything.
---

# Resolving Merge Conflicts

Run every command below and **read what it printed**. Two shapes account for every silent failure this skill has ever had, and both produce output that looks correct:

- **Collapse to nothing.** A command that prints nothing still succeeds inside `$(...)`, and the outer command then runs against a shorter, plausible argument list. Never chain one into the next; run it, read the value, use the value.
- **Collapse to the first.** Several things git will hand you are *not single-valued*, and the convenient accessor quietly returns element one: `git merge-base` prints one base while criss-cross history has several, and the two disagree about which files the operation brings; `MERGE_HEAD` can hold several commits while `git rev-parse MERGE_HEAD` prints one; `<commit>^` is always parent 1 even when the operation named a different mainline; `refs/remotes/origin/HEAD` is whatever the default branch was on the day you cloned. Each returns a valid SHA with exit 0. Check the arity before you trust the value.
- **The error names the wrong cause.** Once, at step 8, git refuses and its message describes a state you can see is not true. Do not act on the message's suggestion: it points at the user's rescued work, and taking it commits exactly what this skill exists to protect. Step 8 says what to do instead.

0. **Stand at the top of the working tree.** Every path below comes from `git status --porcelain`, which prints them relative to the repository root — while `git restore`, `git diff`, `git checkout` and `mv` all resolve them against the *current* directory. Run one command from a subdirectory and the mismatch is silent in both directions: `git restore --staged` and `git checkout --` exit 1 with `pathspec ... did not match`, leaving the user's work staged, and `git diff` exits **0 with an empty patch** — the first collapse shape, in this skill's own recipe.

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ```

   Inside a bare repository that command fails; there is no working tree and no conflict to resolve. Where a pathspec is passed rather than a filename, `:(literal,top)` says the same thing and is used below as a second line of defence — `top` for this, and `literal` because git also matches a pathspec as a wildcard, so a name like `a[1].txt` otherwise reaches `a1.txt`. `mv` and `mkdir` take no pathspec, so the `cd` is what makes those safe.

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
   git -c core.quotePath=false status --porcelain --untracked-files=all
   ```

   `--untracked-files=all` matters: by default `status` collapses a wholly-untracked directory to a single entry ending in `/`, and every step below reads an entry as a file. Handed `notes/`, step 8 creates a directory of that name inside the parking area and moves the directory into it, so the work returns at `notes/notes/sub/file.txt` while the parking area is cleaned up as a success. Step 8's own verification already reads the list with `-uall`; this is that same list.

   `--name-status -M` matters: with `--name-only` a rename shows up as the new path alone, and the deletion of the old path — still staged — travels into the commit unnoticed. `core.quotePath=false` matters for the same reason: by default git prints non-ASCII paths octal-escaped, and pasting that back produces `pathspec did not match`, which reads exactly like "this file is untracked".

   Sort what is left into three lists; step 4 treats them differently:

   - **Staged, not brought by the operation** — the user's, and *in the index*. For a rename, both the old and the new path belong here.
   - **Working-tree only** — first column blank in porcelain (` M`, ` D`). Tracked, so git knows them, but the index still holds the `HEAD` version; there is nothing to unstage.
   - **Untracked** (`??`). Theirs, and git does not know them at all.

   **Paths with a space are quoted no matter what.** `--porcelain` wraps any path containing a space, a quote or a backslash in C quotes, and `core.quotePath` does not turn that off — it governs non-ASCII bytes only. Pasting `"my report.txt"` back fails two different ways: `git restore --staged` rejects the whole command, and step 9's `status` silently matches nothing. Read such paths with `git status --porcelain -z --untracked-files=all`, which separates records with NUL and quotes nothing — the same `-uall` step 3's main command uses, so this line cannot rebuild the collapsed-directory list that command exists to avoid.

4. **Take the user's staged work out of the index before you resolve anything.** This is what makes the promise in step 8 achievable:

   ```bash
   git restore --staged -- ':(literal,top)<each staged-not-brought path>'   # older git: git reset HEAD -- ':(literal,top)<path>'
   ```

   **`:(literal,top)`, one path per pathspec.** `top` because status prints paths from the repo root, and a bare path resolves against wherever you happen to be standing. `literal` because status also prints names like `a[1].txt`, and **git matches a pathspec both literally and as a wildcard** — so without it this command unstages `a1.txt` as well, a file the user never named, and exits **0** without a word. The same omission in step 5's `git checkout --` fails the opposite way: if `a1.txt` happens to be one of the conflicted paths, git rejects the *whole* command (`error: path 'a1.txt' is unmerged`) and nothing gets parked at all.

   **Only that first list.** An untracked path is not in the index, and passing one makes git reject the *whole* command — the staged files you meant to rescue stay staged and get committed anyway. (A working-tree-only path is harmless to pass, but it has nothing to unstage, so listing it only obscures what you did.)

   Confirm it took: `git -c core.quotePath=false diff --cached --name-status -M HEAD` should now list only what the operation brings. A name you cannot account for from any of the three lists is a signal, not noise — usually the other half of a rename. Tell the user what you unstaged and why. If a file is *both* conflicted and something they were editing, stop and ask; you cannot split that automatically.

   (git refuses to *start* any of these operations against a dirty index, so anything staged here was staged after the conflict appeared — by them or by you.)

5. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

6. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the operation's stated goal and note the trade-off. Keep the resolution to what the two sides already do. Resolve rather than flee — difficulty alone is never a reason to `--abort`. Abort only when the operation itself turns out to be a mistake (wrong branch, wrong base, wrong direction): say why, park first if rebasing, abort, and restart it right.

   **A rebase abort destroys the rescued work.** `git rebase --abort` hard-resets tracked files, so the modifications step 4 moved into the working tree do not survive it. Mid-conflict the obvious holding places are worse than they look: `git stash` refuses outright on an unmerged index, `git commit -a` *succeeds* and commits the conflict markers along with everything else, and a pathspec commit (`git commit -m … -- <path>`) — refused during a merge or cherry-pick — does succeed during a rebase, at the price of baking the rescued path into the rebased history as a commit rather than returning it uncommitted. Parking is the one exit that keeps the work uncommitted. Before aborting a rebase, run step 8's parking, or at minimum write `git diff --binary -- ':(literal,top)<each rescued path>' > "$G/rescue.patch"` and move rescued untracked files aside — which is also what unblocks the abort when a rescued untracked path collides with one tracked on the original head, since git refuses the reset outright rather than overwrite it. Merge, cherry-pick and revert aborts keep working-tree modifications and need none of this.

7. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the operation broke.

8. **Finish it.** Stage the conflicted files and whatever you edited in step 7, then run the finishing command for this operation from step 1.

   **Rebase only: park the user's tracked modifications first.** `git rebase --continue` needs a working tree with nothing modified except the conflict you just resolved. The paths you rescued in step 4 are now unstaged modifications, and it refuses with *"You must edit all merge conflicts and then mark them as resolved using git add"* — a message about conflicts, while `git diff --name-only --diff-filter=U` prints nothing. The only unstaged path in sight is the user's, so the obvious next move is to `git add` it, and the rebase then commits the very work step 4 rescued.

   **Park everything they have in flight, not just the tracked side.** An untracked file does not block the commit you are continuing — but a *later* commit in the same rebase may create that path, and then git stops with `error: The following untracked working tree files would be overwritten by merge` and the rebase cannot finish. A rename in flight is the common way to land there: its new path is untracked, and the operation may well be creating it too.

   **Nothing in flight? Skip this whole step.** With an empty path list `git diff --binary --` diffs the *entire tree*, so the patch would capture the conflict resolution you just staged — the same mistake `git stash` makes.

   ```bash
   # lean-skills:park
   # Every step says what it does on failure: `set -e` is unreliable when a
   # block is sourced rather than executed, and a model runs these a line at a
   # time. A silent failure here is how work gets left in the tree and then
   # overwritten by the operation.
   set -e
   die() { echo "park: $1" >&2; exit 1; }
   cd "$(git rev-parse --show-toplevel)" || die "no worktree"
   G="$(git rev-parse --git-dir)" || die "no git dir"
   STATE="$G/lean-parked.state"
   [ ! -e "$STATE" ] || die "an unfinished parking is still open: $STATE. Run the restore block; if you have already taken its contents back by hand, delete $STATE"
   # $G/lean-park-input is step 4's list, one NUL-terminated path per entry.
   # Every entry names a leaf - a file, a symlink, never a directory. `git status`
   # prints a directory only when it is not asked for `--untracked-files=all`,
   # which is why step 3 asks for it.
   #   : > "$G/lean-park-input"
   #   printf '%s\0' 'each/path/from/step 4' >> "$G/lean-park-input"
   # Everything below the split is read-only until the split says there is
   # tracked work to move: a `die` after a state file is published leaves an
   # open parking area the next run refuses to step over.
   [ -s "$G/lean-park-input" ] || die "no input list"
   [ "$(tail -c 1 -- "$G/lean-park-input" | tr -d -c '\000' | wc -c)" -eq 1 ] ||
     die "input list is not NUL-terminated - build it with printf '%s\\0'"
   # Split, and *say* what is being left alone. Untracked work is not moved:
   # measured, leaving it in place cannot lose it - if a commit still to be
   # replayed would create that path, git refuses the whole step by name
   # ("The following untracked working tree files would be overwritten"), the
   # operation stays exactly where it is and the file is untouched. Moving it
   # pre-empted a refusal that was already safe, specific and reversible, and
   # cost this skill an mv loop, a manifest, a collision guard and a parent
   # walk. Step 8 says what to do when that refusal appears.
   TRACKED="$G/lean-park-tracked.tmp"; : > "$TRACKED" || die "cannot start a list"
   LEFT=
   while IFS= read -r -d '' p; do
     if git ls-files --error-unmatch -z -- ":(literal,top)$p" >/dev/null 2>&1
     then printf '%s\0' "$p" >> "$TRACKED" || die "cannot record $p"
     else LEFT="$LEFT  $p
   "
     fi
   done < "$G/lean-park-input"
   [ -z "$LEFT" ] || printf 'park: left in place, untracked and untouched:\n%s' "$LEFT"
   if [ ! -s "$TRACKED" ]; then
     rm -f -- "$TRACKED"
     rm -f -- "$G/lean-park-input"
     echo "park: no tracked work to move; nothing was parked and no state was written"
     exit 0
   fi
   PARK_NAME="lean-parked-$(date +%s)-$$"
   PARK="$G/$PARK_NAME"
   [ ! -e "$PARK" ] || die "name collision: $PARK"
   mkdir -p -- "$PARK" || die "cannot create $PARK"
   # Publish the state *before* the first change to the working tree. A step
   # that fails partway - and a crash, which no rollback code can catch - would
   # otherwise leave the patch inside $PARK with nothing pointing at it, and
   # restore refuses to look for a parking area it was not told about.
   printf '%s\n' "$PARK_NAME" > "$STATE.tmp" || die "cannot write state"
   mv -- "$STATE.tmp" "$STATE" || die "cannot publish state"
   mv -- "$TRACKED" "$PARK/tracked" || die "cannot take the tracked list"
   mv -- "$G/lean-park-input" "$PARK/input" || die "cannot take the input list"
   # NUL all the way into git: `xargs -a` is a GNU extension that BSD/macOS
   # xargs rejects outright, and a newline-joined `$(...)` would be split on
   # whitespace by the shell, so a tracked path with a space in it would
   # silently never reach the patch.
   : > "$PARK/specs"
   while IFS= read -r -d '' p; do
     printf ':(literal,top)%s\0' "$p" >> "$PARK/specs" || die "cannot build pathspecs"
   done < "$PARK/tracked"
   # xargs runs the command once even when its input is empty, and `git diff
   # --binary --` with no pathspec diffs the *entire tree*. Defence in depth:
   # the split above already guarantees a non-empty tracked list, so neither
   # branch is reachable from a legal input, and the suite does not prove them.
   [ -s "$PARK/specs" ] || die "no pathspecs built from the tracked list"
   [ "$(tr -d -c '\000' < "$PARK/specs" | wc -c)" -eq "$(tr -d -c '\000' < "$PARK/tracked" | wc -c)" ] ||
     die "built fewer pathspecs than the tracked list holds"
   xargs -0 git diff --binary -- < "$PARK/specs" > "$PARK/tracked.patch" || die "git diff failed"
   while IFS= read -r -d '' p; do
     git checkout -- ":(literal,top)$p" || die "cannot restore $p from the index"
   done < "$PARK/tracked"
   ```

   **`git checkout --` takes tracked paths only, and so does everything else that reads a pathspec.** This is the rule, not the instance: **any git command given a pathspec it does not recognise rejects the whole command** (`error: pathspec ... did not match any file(s) known to git`, exit 1) rather than skipping that one path. It has now bitten `git restore --staged`, `git stash push`, `git checkout --` and `git restore --staged` again on the way back. `git diff` is the one exception — it ignores paths it does not know, which is why the patch line above can name them all.

   **A patch, because a copy cannot carry what a change is.** `cp` moves file *contents*, and the user's work is not always contents: a deleted path has nothing to copy, a rename is two paths, `a/config.txt` and `b/config.txt` collapse onto each other in one flat directory, and a mode change is invisible. `git diff --binary` records all of it. The untracked side has none of those problems — a new file is only content — so moving it is enough, as long as the directory structure comes along.

   **`git stash` is the wrong tool here, and quietly so.** A stash always records the **whole index**, which during a conflict holds the resolution you just staged. Popping it later replays that stale resolution over the rebased file and produces a `UU` conflict neither side asked for. Popping *during* the rebase is worse — the next commit may conflict too, and `git stash pop` against an unmerged index fails with `error: could not write index`, which reads like the work is gone when it is still in the stash.

   **Restore only once the whole operation is over.** A rebase of several commits stops at each conflicting one, so repeat step 1 through here for each. Only when long-form `git status` reports no operation in progress:

   ```bash
   # lean-skills:restore
   set -e
   die() { echo "restore: $1" >&2; exit 1; }
   cd "$(git rev-parse --show-toplevel)" || die "no worktree"
   G="$(git rev-parse --git-dir)" || die "no git dir"   # recomputed: nothing is inherited
   STATE="$G/lean-parked.state"
   [ -s "$STATE" ] || die "no parking is open"
   PARK_NAME="$(cat -- "$STATE")" || die "cannot read state"
   case "$PARK_NAME" in
     lean-parked-*) ;;
     *) die "state does not name a parking area: $PARK_NAME" ;;
   esac
   case "$PARK_NAME" in
     */*|*..*) die "state names a path, not a basename" ;;
   esac
   PARK="$G/$PARK_NAME"
   [ -d "$PARK" ] || die "state points at $PARK, which is not there. If you have already taken its contents back by hand, delete $STATE; nothing else will run until you do"
   HELD=0
   if [ -s "$PARK/tracked.patch" ]; then
     git apply --3way "$PARK/tracked.patch" || HELD=1
     # only the paths we parked: `git diff --cached` lists the whole index, and
     # unstaging all of it would tear down whatever the user or the operation
     # had staged for reasons of their own
     while IFS= read -r -d '' p; do
       git restore --staged -- ":(literal,top)$p" || die "cannot unstage $p"
     done < "$PARK/tracked"
   fi
   if [ "$HELD" -eq 0 ]; then
     rm -f -- "$STATE" && rm -rf -- "$PARK"
   else
     echo "kept $PARK - the patch is still in it; tell the user the path before you go on"
   fi
   ```

   - **The patch is empty** — the user had only untracked work, which is a perfectly ordinary case. Do not run `git apply` on it: an empty patch exits **128** with `No valid patches in input`, and reading that as the next case reports a conflict that does not exist. Go straight to the untracked files.
   - **`git apply` exit 0** — the tracked work went back. Unstage exactly the paths recorded in `$PARK/tracked` when you parked, and nothing else. Not `git diff --cached`: that lists the *whole* index, so unstaging all of it tears down whatever the user or the operation had staged for their own reasons. And not the untracked paths either — that is the pathspec trap again, and it would leave a staged deletion the next commit sweeps up.
   - **Non-zero on a non-empty patch** — the operation changed one of these paths too, and `--3way` has written conflict markers rather than choosing for you. That is the honest answer, and the reason this is not a `cp`: a copy would have silently overwritten the operation's version. **Keep the patch**, name it to the user, and resolve those hunks with them.

   **If a parking area is ever left behind, say where it is and what is in it.** `$G/lean-parked-*` holds `tracked.patch` (apply it with `git apply --3way`), `untracked/` (the files as they were, path structure intact) and `manifest` (the NUL-separated record of what was moved). Nothing in there is lost — but nothing outside it knows it is there either, so a parking area the user is not told about is the same as one they cannot find. Tell them the path, then take it back with them.

   Then move them back **from the record written while parking**, one refusal per occupied path.

   **A manifest, not a re-scan.** Deriving the list again with `find -type f` misses anything that is not a regular file: a symlink is `-type l`, so it is parked, never found on the way back, and then deleted with the parking area — while the block still exits 0. The manifest is NUL-separated because a newline is a legal character in a path. And the parking area is removed only when it is *empty of non-directories*, so even a manifest that missed something cannot turn into a deletion.

   ```bash
   # for each file under "$PARK/untracked": if the path now exists, do NOT overwrite it
   ```

   A path that is occupied means the operation created something there — exactly the collision that made the parking necessary. Leave the operation's version, leave the user's copy in `$PARK`, and tell them both paths. Delete `$PARK` only when every file has been moved back.

   **Then check, do not assume.** Compare `git status --porcelain --untracked-files=all` against the state the rescue is meant to leave: the same paths, with rescued tracked work unstaged (` M` / ` D`) and rescued additions untracked (`??`). A path that reads staged where the rescue left it unstaged is the failure this step exists to prevent, and step 9's existence check cannot see it.

   Merge, cherry-pick and revert do not need any of this — all three finish with the user's modifications sitting in the working tree, exit 0, and commit nothing of theirs.

   If rebasing or cherry-picking, repeat from step 1 for each subsequent conflicted commit until git reports the operation complete — the boundary you recorded at the first conflict stays valid for the whole run.

9. **Prove the user's work survived.** Ask it of the paths themselves, which is exact and operation-agnostic:

   ```bash
   git -c core.quotePath=false status --porcelain -- ':(literal,top)first-path' ':(literal,top)second-path'
   ```

   **One `:(literal,top)` argument per path.** Several paths inside a single pair of quotes is *one* pathspec containing spaces; it matches nothing, exits 0, and reads exactly like "all of it was committed". A rename forces this case — step 3 puts both the old and the new path on the list.

   Each must still appear, **in the state the rescue left it** — not the column step 3 recorded, which step 4 changed on purpose: a staged modification (`M `) must now read ` M`, a staged addition (`A `) must now read `??`, a staged deletion (`D `) must now read ` D`; working-tree-only and untracked paths keep their step-3 column, and a combined column (`MM`, `AM`, `MD`) lands on the same ` M` / `??` / ` D` its staged half maps to. The check is directional: a rescued path that reads staged at all is one `git commit` away from being swept up, and existence alone proves nothing. Compare the first two characters against this mapping, not just the name.

   A path that has gone quiet was committed by the operation. Both halves of `:(literal,top)` matter here for the same reasons they do in step 4: `top` because pathspecs resolve against the current directory while status printed them relative to the repository root, so running this from a subdirectory silently matches nothing and reads the same wrong way; `literal` because git matches a pathspec as a wildcard too, so asking about `a[1].txt` reports whatever `a1.txt` is doing and calls it the answer. If step 3's list was empty, say so — there was no in-flight work to protect, and an empty check proves nothing.

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
