---
name: implement
description: Build a piece of work end to end — isolation, tests at agreed seams, verification, review — through to handover.
disable-model-invocation: true
---

# Implement

Build the work described in the spec, tickets, or the understanding we just reached.

1. **Isolate** when the change is large or the current branch matters — offer a worktree. If accepted: branch named for the ticket or feature, worktree directory git-ignored, baseline tests green before the first edit. (`/worktree` carries the full discipline.)
2. **Tests first, at agreed seams.** Name the public boundaries you intend to test and confirm them with the user. Then vertical slices: one failing test → just enough code to pass it → repeat. Expected values come from an independent source of truth, never recomputed the way the code computes them. (`/tdd` carries the full reference.)
3. **Keep the loop tight** — typecheck often, run the single relevant test file often, run the full suite once at the end.
4. **Prove it** — `verification-before-completion`: every claim in your report carries the command output that backs it.
5. **Review it** — `code-review` against the point you branched from. Take the findings through `receiving-code-review`: check each against the codebase before acting on it.
6. **Hand over.** Present the verified result and the diff. Commit when the user has asked for one — in the ticket, in conversation, or by accepting your offer; otherwise leave the tree for their inspection.

If the work stalls on something broken rather than something unbuilt, switch to `diagnosing-bugs`.

---

_Based on [mattpocock/skills](https://github.com/mattpocock/skills) `implement` (MIT), rewritten: the tdd and worktree guardrails are inlined one-line (the model cannot invoke user-invoked skills, and the full versions stay manual); commit requires the user's say-so instead of being unconditional; stall exit to diagnosing-bugs added._
