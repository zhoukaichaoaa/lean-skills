---
name: verification-before-completion
description: Use when about to write "fixed", "done", "passing", "should work", or any wording that implies success — before any commit, PR, or handoff, and whenever reporting a result you have not confirmed by running a command in this session.
---

# Verification Before Completion

A claim about the state of the code is worth exactly the **evidence** behind it. This skill turns every completion claim into one you have already proved.

## The gate

Before any wording that implies success:

1. **Name the command** that would prove the claim.
2. **Run it** — whole, fresh, in this session.
3. **Read the whole output** — exit code and failure count, not the last line.
4. **State the claim with its evidence attached**, or state the actual status instead.

Evidence is output produced after your last edit. A run from before it describes code that no longer exists.

## What proves what

| Claim | Evidence that proves it |
|---|---|
| Tests pass | Full test command output, 0 failures |
| Build succeeds | Build command, exit 0 — a green linter says nothing about compilation |
| Bug fixed | The user's original symptom re-tested, now absent |
| Regression test works | Red → green confirmed: revert the fix, watch it fail, restore |
| Requirements met | Line-by-line pass over the spec, each item matched to code |
| Subagent finished | The VCS diff, read by you |
| Lint clean | Linter output over the whole target, 0 errors |

## Completion criterion

You may make the claim once you can quote, in the same message, the command you ran and the span of output that proves it.

Until then, report the real state: what changed, what you have not run yet, what you expect to happen.

## When evidence is out of reach

Name the command you would run and why you can't (no network, needs a device, needs credentials), then report the work as unverified. An honest "unverified" costs the reader one command to settle; a confident guess costs them the whole debugging session that follows.

---

_Adapted from [obra/superpowers](https://github.com/obra/superpowers) `verification-before-completion` (MIT), rewritten to the positive-framing and pruning rules in [DOCTRINE.md](https://github.com/zhoukaichaoaa/lean-skills/blob/main/DOCTRINE.md)._
