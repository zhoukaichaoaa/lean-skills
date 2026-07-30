---
name: implement
description: Build a piece of work end to end — plan, isolation, tests at agreed seams, verification, review — through to handover.
disable-model-invocation: true
---

# Implement

Build the work described in the plan, spec, tickets, or the understanding we just reached.

1. **Start from the plan.** Look in `"$(git rev-parse --git-common-dir)/../.plans"` — quoted; it resolves to the main checkout from anywhere, including inside a worktree, where an untracked `.plans/` never appears. Inside a submodule it resolves into `.git/modules/` instead: check `git rev-parse --show-superproject-working-tree` and use the superproject when it is non-empty. Outside a repository it collapses to `/.plans` — fall back to `./.plans`. A repository created with `--separate-git-dir` puts the common dir outside the checkout, so this lands beside the git dir rather than inside the checkout. The three consumers resolve it the same way and stay consistent with each other there; the location is surprising, not broken. A layout this collection does not chase further. Read the one matching this feature: it is the spec for this work, and step 7 reviews the result against it. If there is no plan and this is more than a small change, ask the user to run `/grill-me` first — building from an unwritten understanding is how the wrong thing gets built well. (`/grill-me` is user-invoked; you cannot call it yourself.)
2. **Isolate** when the change is large or the current branch matters — offer a worktree. If accepted: branch named for the ticket or feature, worktree directory kept out of version control, and the test suite run once before the first edit so later failures are attributable. (For the full discipline, ask the user to run `/worktree` — also user-invoked.)
3. **Record the base.** Before the first edit — branch or no branch — run `git rev-parse HEAD` and write the **printed SHA** into your notes and your final report. It must be 40 hex characters: in a repository with no commits yet this prints the literal string `HEAD` on stdout, which is a usable-looking value that would silently collapse the review in step 7. A shell variable won't survive: every command runs in a fresh shell, and step 7 needs this value verbatim.

4. **Tests first, at the agreed seams.** Use the seams named in the plan; if there is no plan, name them now and confirm them with the user. Then vertical slices: one failing test → just enough code to pass it → repeat. Expected values come from an independent source of truth, never recomputed the way the code computes them. (For the full reference, ask the user to run `/tdd`.)
5. **Keep the loop tight** — typecheck often, run the single relevant test file often, run the full suite once at the end.
6. **Prove it** — re-read the plan first; on a long run it has left your context, and the checks below are against what it actually says, not what you remember. Then `verification-before-completion`: every claim in your report carries the command output that backs it, and every decision in the plan is accounted for as built, deferred, or dropped.
7. **Review it.** Run `spec-review` with the literal SHA from step 3 and the plan's path — it answers "is this what was asked for", which no other reviewer can know. Then ask the user to run the built-in `/code-review` for correctness bugs and cleanups; it reads the whole codebase in its own subagent, so there is no reason to re-derive that here. If the change touches auth, input handling or secrets, ask for `/security-review` too — neither of the other two covers security. Take every finding through `receiving-code-review`: check each against the codebase before acting on it.
8. **Re-verify whatever the review changed.** Fixing a finding invalidates the evidence from step 6 — the test run, the build, the typecheck all describe code that no longer exists. Run them again after the last edit. For user-visible behaviour, actually exercise it rather than inferring from green tests.
9. **Hand over.** Present the verified result and the diff. Commit when the user has asked for one — in the ticket, in conversation, or by accepting your offer; otherwise leave the tree for their inspection.

If the work stalls on something broken rather than something unbuilt, switch to `diagnosing-bugs`.

If a decision in the plan turns out to be wrong once you are in the code, say so and amend the plan with the user. Quietly building something the plan does not describe leaves the review with nothing true to check against.

## Completion criterion

Every decision in the plan is built, deferred, or dropped with a reason; the last edit you made has been followed by a full check run whose output you can quote; `spec-review` has run and its findings are each fixed, refuted, or waiting on the user; and you have named the two things you are handing over — the base SHA from step 3, and whether you committed. Step 7's request that the user run the built-in `/code-review` is theirs to act on: say you have asked, and do not count it as done yourself.

---

_Based on [mattpocock/skills](https://github.com/mattpocock/skills) `implement` (MIT), rewritten. Changed here: the plan from `/grill-me` is read as the spec and carried through to review; the review base is recorded as a literal SHA before the first edit; the tdd and worktree guardrails are inlined in one line each (the model cannot invoke user-invoked skills, so their full versions are pointed at the user instead); review splits between `spec-review` and Claude Code's built-in `/code-review`; a re-verification step follows review fixes, because fixing a finding invalidates the evidence gathered before it; committing requires the user's say-so instead of being unconditional; exits added for a broken build and for plan drift. Per-release detail: [NOTICE.md](https://github.com/zhoukaichaoaa/lean-skills/blob/main/NOTICE.md)._
