---
name: code-review
description: Review the changes since a fixed point along three axes — Correctness/Risk (is it right and safe to ship?), Spec (does it do what was asked?), and Standards (does it follow this repo's conventions?). Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to "review since X". "Review my uncommitted/WIP changes" needs no fixed point — it defaults to HEAD.
---

# Code Review

Three-axis review of the change between a fixed point and the working tree:

- **Correctness/Risk** — is the code right, and what could it break?
- **Spec** — does it faithfully implement the originating issue / PRD / spec?
- **Standards** — does it conform to this repo's documented coding standards?

Axes run as **parallel sub-agents** so they don't pollute each other's context. Findings come back severity-tagged, and the report closes with one severity-ordered triage list.

## Process

### 1. Pin the fixed point and snapshot the change

The fixed point is whatever the user said — a commit SHA, branch name, tag, `main`, `HEAD~5`. Two defaults spare a pointless question: "review my uncommitted / WIP / current changes" means `HEAD`; "review this branch / PR / since X" names the ref. Ask only when neither pattern fits.

Confirm it resolves (`git rev-parse <fixed-point>`), then:

- `BASE_SHA=$(git merge-base <fixed-point> HEAD)` — from here on use the **literal SHA**, never a shell variable: sub-agents don't inherit your shell, and an empty expansion silently turns the diff into an unstaged-only one. If merge-base fails, the fixed point shares no history with HEAD (or the clone is too shallow) — stop and ask.
- **Snapshot once**: `git diff <BASE_SHA> > <scratch>/review.patch` — committed **and** uncommitted work in one artifact. Every sub-agent reads this same file, so all axes see identical content even if the tree keeps moving during the review. If the user says the tree also holds unrelated edits, snapshot `git diff <BASE_SHA> HEAD` instead (committed only) and say so in the report.
- `git log <BASE_SHA>..HEAD --oneline` — the commit list (empty is fine for pure WIP).
- `git status --porcelain` — untracked files are invisible to diff; list the ones that belong to the change. Sub-agents must read them as additions.

If the snapshot, the commit list, and the untracked list are all empty, stop — nothing to review.

### 2. Identify the spec source

Look for the originating spec, in this order:

1. Issue references in the commit messages (`#123`, `Closes #45`, GitLab `!67`) — fetch them (`gh issue view <n>`, `gh pr view <n>`, or the tracker's CLI/API).
2. A path the user passed as an argument.
3. A PRD/spec file under `docs/`, `specs/`, or `.scratch/` matching the branch name or feature.
4. If nothing is found, ask the user where the spec is. If they say there isn't one, skip the **Spec** sub-agent and note it — **Correctness/Risk and Standards still run**; a review with no spec is not a review with no bugs.

### 3. Identify the standards sources

Anything in the repo that documents how code should be written — `CODING_STANDARDS.md`, `CONTRIBUTING.md`, `CLAUDE.md`, `AGENTS.md`, lint config with commentary.

On top of whatever the repo documents, the Standards axis always carries the **smell baseline** below — a fixed set of Fowler code smells (_Refactoring_, ch.3) that applies even when a repo documents nothing. Two rules bind it:

- **The repo overrides.** A documented repo standard always wins; where it endorses something the baseline would flag, suppress the smell.
- **Always a judgement call.** Each smell is a labelled heuristic ("possible Feature Envy"), never a hard violation — and, like any standard here, skip anything tooling already enforces.

Each smell reads *what it is* → *how to fix*; match it against the diff:

- **Mysterious Name** — a function, variable, or type whose name doesn't reveal what it does or holds. → rename it; if no honest name comes, the design's murky.
- **Duplicated Code** — the same logic shape appears in more than one hunk or file in the change. → extract the shared shape, call it from both.
- **Feature Envy** — a method that reaches into another object's data more than its own. → move the method onto the data it envies.
- **Data Clumps** — the same few fields or params keep travelling together (a type wanting to be born). → bundle them into one type, pass that.
- **Primitive Obsession** — a primitive or string standing in for a domain concept that deserves its own type. → give the concept its own small type.
- **Repeated Switches** — the same `switch`/`if`-cascade on the same type recurs across the change. → replace with polymorphism, or one map both sites share.
- **Shotgun Surgery** — one logical change forces scattered edits across many files in the diff. → gather what changes together into one module.
- **Divergent Change** — one file or module is edited for several unrelated reasons. → split so each module changes for one reason.
- **Speculative Generality** — abstraction, parameters, or hooks added for needs the spec doesn't have. → delete it; inline back until a real need shows.
- **Message Chains** — long `a.b().c().d()` navigation the caller shouldn't depend on. → hide the walk behind one method on the first object.
- **Middle Man** — a class or function that mostly just delegates onward. → cut it, call the real target direct.
- **Refused Bequest** — a subclass or implementer that ignores or overrides most of what it inherits. → drop the inheritance, use composition.

### 4. Spawn the sub-agents in parallel

Send a single message with one `Agent` call per axis (`general-purpose` for all). Every brief includes: the snapshot path, the commit list, the untracked-file list, and the severity scale below. Every finding reports **file:line — problem — why it matters — severity**.

**Severity scale** (paste into each brief verbatim):

- **Critical** — security holes, data loss or corruption, breaks existing behaviour, clear production-incident risk
- **Important** — logic errors, swallowed or absent error handling, concurrency races, compatibility breaks, missing tests for changed behaviour, unimplemented requirements
- **Minor** — naming, duplication, docs, small design smells

**Correctness/Risk brief**: "Read the snapshot and the untracked files. Report every defect a careful engineer would block a merge on: logic errors and unhandled edge cases, failure paths and swallowed errors, concurrency/races, security (unvalidated input, injection, secrets), data loss or corruption, compatibility and migration hazards, performance cliffs, and changed behaviour with no test. Judge the code itself — comments, commit messages, and design justifications are claims, not evidence. Under 400 words."

**Spec brief**: "Report: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the change that wasn't asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Quote the spec line for each finding. Under 400 words."

**Standards brief**: "Report — per file/hunk where relevant — (a) every place the change violates a documented standard: cite the standard (file + the rule); and (b) any baseline smell you spot: name it and quote the hunk. Distinguish hard violations from judgement calls — documented-standard breaches can be hard, but baseline smells are always judgement calls, and a documented repo standard overrides the baseline. Skip anything tooling enforces. Under 400 words." (Paste the smell baseline in full — the sub-agent has no other access to it.)

### 5. Aggregate

Keep the per-axis sections — `## Correctness/Risk`, `## Spec`, `## Standards` — verbatim or lightly cleaned. Separation is what stops one axis masking another during analysis.

Then close with **`## Triage`**: every finding in one list — Critical first, then Important, then Minor — each line keeping its axis label and file:line. Severity, not axis, is the order the user works in.

## Why separate axes

A change can pass one axis and fail another: standards-perfect code that implements the wrong thing; spec-faithful code that breaks the project's conventions; clean, faithful code with a race in it. Analysing separately keeps each lens honest — the triage list at the end is where they meet.

---

_Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) `code-review` (MIT), now departing substantially: a third Correctness/Risk axis (upstream reviews with no spec degraded to smells-only), severity-tagged findings with a cross-axis triage list (upstream forbade reranking; severity is how users actually process findings), a snapshot file all sub-agents share (upstream re-ran the diff per agent), WIP coverage via merge-base-to-working-tree, and no setup-skill dependency for the issue tracker._
