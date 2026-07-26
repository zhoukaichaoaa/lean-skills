---
name: implement
description: Build a piece of work end to end — isolation, tests at agreed seams, verification, review — through to handover.
disable-model-invocation: true
---

# Implement

Build the work described in the spec, tickets, or the understanding we just reached.

1. **Isolate** when the change is large or the current branch matters — offer a worktree. If accepted: branch named for the ticket or feature, worktree directory kept out of version control, and the test suite run once before the first edit so later failures are attributable. (For the full discipline, ask the user to run `/worktree` — a user-invoked skill you cannot call yourself.)
2. **Record the base.** Before the first edit — branch or no branch — run `git rev-parse HEAD` and write the **printed SHA** into your notes and your final report. A shell variable won't survive: every command runs in a fresh shell, and step 6 needs this value verbatim.
3. **Tests first, at agreed seams.** Name the public boundaries you intend to test and confirm them with the user. Then vertical slices: one failing test → just enough code to pass it → repeat. Expected values come from an independent source of truth, never recomputed the way the code computes them. (For the full reference, ask the user to run `/tdd`.)
4. **Keep the loop tight** — typecheck often, run the single relevant test file often, run the full suite once at the end.
5. **Prove it** — `verification-before-completion`: every claim in your report carries the command output that backs it.
6. **Review it** — `code-review`, passing the literal SHA from step 2 as the fixed point. Take the findings through `receiving-code-review`: check each against the codebase before acting on it.
7. **Hand over.** Present the verified result and the diff. Commit when the user has asked for one — in the ticket, in conversation, or by accepting your offer; otherwise leave the tree for their inspection.

If the work stalls on something broken rather than something unbuilt, switch to `diagnosing-bugs`.

---

_Based on [mattpocock/skills](https://github.com/mattpocock/skills) `implement` (MIT), rewritten: the review base is recorded as a literal SHA before the first edit; the tdd and worktree guardrails are inlined one-line (the model cannot invoke user-invoked skills, so their full versions are pointed at the user instead); commit requires the user's say-so instead of being unconditional; stall exit to diagnosing-bugs added._
