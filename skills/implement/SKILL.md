---
name: implement
description: Build a piece of work end to end — plan, isolation, tests at agreed seams, verification, review — through to handover.
disable-model-invocation: true
---

# Implement

Build the work described in the plan, spec, tickets, or the understanding we just reached.

1. **Start from the plan.** Look in `$(git rev-parse --git-common-dir)/../.plans` — that resolves to the main checkout from anywhere, including inside a worktree, where an untracked `.plans/` never appears. Read the one matching this feature: it is the spec for this work, and step 7 reviews the result against it. If there is no plan and this is more than a small change, ask the user to run `/grill-me` first — building from an unwritten understanding is how the wrong thing gets built well. (`/grill-me` is user-invoked; you cannot call it yourself.)
2. **Isolate** when the change is large or the current branch matters — offer a worktree. If accepted: branch named for the ticket or feature, worktree directory kept out of version control, and the test suite run once before the first edit so later failures are attributable. (For the full discipline, ask the user to run `/worktree` — also user-invoked.)
3. **Record the base.** Before the first edit — branch or no branch — run `git rev-parse HEAD` and write the **printed SHA** into your notes and your final report. A shell variable won't survive: every command runs in a fresh shell, and step 7 needs this value verbatim.
4. **Tests first, at the agreed seams.** Use the seams named in the plan; if there is no plan, name them now and confirm them with the user. Then vertical slices: one failing test → just enough code to pass it → repeat. Expected values come from an independent source of truth, never recomputed the way the code computes them. (For the full reference, ask the user to run `/tdd`.)
5. **Keep the loop tight** — typecheck often, run the single relevant test file often, run the full suite once at the end.
6. **Prove it** — re-read the plan first; on a long run it has left your context, and the checks below are against what it actually says, not what you remember. Then `verification-before-completion`: every claim in your report carries the command output that backs it, and every decision in the plan is accounted for as built, deferred, or dropped.
7. **Review it** — `code-review`, passing the literal SHA from step 3 as the fixed point and the plan's path as the spec. Take the findings through `receiving-code-review`: check each against the codebase before acting on it.
8. **Hand over.** Present the verified result and the diff. Commit when the user has asked for one — in the ticket, in conversation, or by accepting your offer; otherwise leave the tree for their inspection.

If the work stalls on something broken rather than something unbuilt, switch to `diagnosing-bugs`.

If a decision in the plan turns out to be wrong once you are in the code, say so and amend the plan with the user. Quietly building something the plan does not describe leaves the review with nothing true to check against.

---

_Based on [mattpocock/skills](https://github.com/mattpocock/skills) `implement` (MIT), rewritten: the plan from `/grill-me` is read as the spec and carried through to review; the review base is recorded as a literal SHA before the first edit; the tdd and worktree guardrails are inlined one-line (the model cannot invoke user-invoked skills, so their full versions are pointed at the user instead); commit requires the user's say-so instead of being unconditional; exits added for a broken build and for plan drift._
