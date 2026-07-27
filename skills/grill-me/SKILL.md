---
name: grill-me
description: A relentless interview that pins down a plan or design, ending in a written plan the rest of the work is built and reviewed against.
disable-model-invocation: true
---

# Grill Me

The interview without the document is worth nothing the moment this session ends.

## 1. The interview

Interview me relentlessly about every aspect of this until we reach a shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions **one at a time**, waiting for my answer before continuing. Asking multiple questions at once is bewildering.

If a *fact* can be found by exploring the environment (filesystem, git history, tools, the web), look it up rather than asking me. The *decisions* are mine — put each one to me and wait.

## 2. The plan

Write the resolved tree to `<plans>/<slug>.md`, where the slug names the feature and `<plans>` is:

- in a git repository: **`$(git rev-parse --git-common-dir)/../.plans`** — that resolves to the main checkout's `.plans/` from anywhere, including inside a linked worktree, which an untracked `.plans/` never gets copied into;
- outside one: `.plans/` in the current directory.

`/implement` and `spec-review` look it up the same way; a plan somewhere else is a plan they will not find, so move it only if you also tell them where.

In a git repository, keep it out of the way by appending `.plans/` to `$(git rev-parse --git-common-dir)/info/exclude` — check the line isn't already there first. Outside one, skip that step. Do not commit it; that is my call, and if I want it shared, ask whether it belongs in `.gitignore` or in `docs/`.

If the file already exists, ask whether to replace it or start a new slug. Report the path you wrote to.

Write for a reader with **zero context** — a later session, a colleague, or a subagent that will never see this conversation.

```markdown
# <what we are building>

## Problem
What is wrong today, from the user's side.

## Decisions
Each one: what was decided, and **why**. The reason is what stops a later
reader — including you, next week — relitigating a settled question.

## Seams to test
The public boundaries the tests will sit at, as agreed. Existing seams beat
new ones; the highest seam that reaches the behaviour beats a deeper one.

## Out of scope
What I explicitly said no to. This is what makes scope creep visible at review.

## Open questions
What we deliberately deferred, and what would settle each. An unanswered
question recorded here is fine; one silently answered on my behalf is not.
```

Then show me the document and stop. Building it is `/implement`, which reads this file as its spec — and `code-review` reviews the result against it.

## Completion criterion

- Every branch resolved in the interview appears under **Decisions** with its reason; a question you answered on my behalf is an unresolved branch, not a decision.
- Every branch I deferred appears under **Open questions**.
- **Seams to test** names each boundary as a concrete public interface — `/implement` writes its tests against this list, so "the usual seams" is an empty section.
- **Out of scope** records every item I explicitly ruled out — this is what makes scope creep visible at review.
- The document stands alone: someone who did not sit through this interview can build from it without asking me anything I already answered here. A decision that reads "as discussed" fails this.
- The file is written, you have reported its path, and I have read it and said it matches.

---

_Merged from [mattpocock/skills](https://github.com/mattpocock/skills) `grill-me` + `grilling` (MIT) into one user-invoked skill; the plan document, its template and the completion criterion are additions — upstream persists decisions through `to-spec` and an issue tracker, which this collection does not require._
