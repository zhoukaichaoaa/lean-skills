---
name: implement
description: Build a piece of work end to end, from an agreed plan through review.
disable-model-invocation: true
---

# Implement

Build the work described in the spec, tickets, or the understanding we just reached.

1. **Isolate** if the change is large or the current branch matters — run `worktree`.
2. **Agree the seams** you will test at, then build with `tdd` at those seams.
3. **Keep the loop tight** while working: typecheck often, run the single relevant test file often, run the full suite once at the end.
4. **Prove it** — `verification-before-completion`. Every claim in your report carries the command output that backs it.
5. **Review it** — `code-review` against the point you branched from.
6. **Commit** to the current branch.

If the work stalls on something broken rather than something unbuilt, stop and switch to `diagnosing-bugs`.

---

_Based on [mattpocock/skills](https://github.com/mattpocock/skills) `implement` (MIT); the isolation and verification steps are additions._
