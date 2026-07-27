---
name: receiving-code-review
description: Use when review findings or reviewer feedback arrive — from the user, a PR thread, spec-review, or Claude Code's built-in /code-review — before implementing any of the suggestions.
---

# Receiving Code Review

Review feedback is a set of claims about the code. Each one is either true of this codebase or it isn't, and finding out is your job before you touch anything.

## The pass

1. **Read all of it** before acting on any of it.
2. **Restate each item** in your own words. An item you can't restate is an item you don't understand yet.
3. **Clarify every unclear item first** — before implementing the clear ones. Items interact; implementing 1, 2, 3 while 4 and 5 are still fuzzy usually means redoing 1, 2, 3.
4. **Check each claim against the codebase.** Does the suggestion hold on this stack, this version, these callers? Is there a reason the current code is the way it is?
5. **Work one item at a time** — act, then report that item: blocking issues first (breakage, security), then simple fixes, then the complex ones. Each item ends in one of three states: fixed and tested, disagreed with reasons, or waiting on your question.

## Responding

State the technical substance and let the code carry the rest:

- "Fixed — `parseConfig` now rejects the empty case at line 40."
- "Checked: build target is 10.15+, this API needs 13+, so the legacy path is load-bearing. Drop pre-13 support instead?"
- "I can't verify this without a staging database. Want me to investigate, or take it on faith?"

Agreement phrases ("you're absolutely right", "great catch") carry no information about the code. Replace each one with the fact it was standing in for.

## Disagreeing

Push back when the suggestion breaks existing behaviour, misses context the reviewer didn't have, or is wrong for this stack.

**YAGNI first.** When a reviewer asks you to "implement this properly", grep for callers before building anything: on an endpoint nothing calls, the honest answer is to delete it, not to flesh it out.

Push back with the specific evidence: the test that would break, the version constraint, the caller that depends on it.

If you pushed back and were wrong, say what you checked and what it showed, then implement. One sentence, no post-mortem.

## Completion criterion

Every item is either implemented and tested, answered with reasoning, or waiting on a clarification you asked for. None are silently skipped.

---

_Rewritten from [obra/superpowers](https://github.com/obra/superpowers) `receiving-code-review` (MIT), condensed and positively framed per [DOCTRINE.md](https://github.com/zhoukaichaoaa/lean-skills/blob/main/DOCTRINE.md)._
