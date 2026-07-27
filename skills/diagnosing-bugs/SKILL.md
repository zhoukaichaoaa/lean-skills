---
name: diagnosing-bugs
description: Diagnosis loop for hard bugs and performance regressions. Use when a fix you already applied did not work, when the cause is not evident after a first look, when the failure is non-deterministic, or when the user says "diagnose". Obvious causes need no loop — fix those directly.
---

# Diagnosing Bugs

A discipline for hard bugs. Skip phases only when explicitly justified.

When exploring the codebase, read `CONTEXT.md` (if it exists) to get a clear mental model of the relevant modules, and check ADRs in the area you're touching.

**Second attempt rule.** If you already tried a fix and the symptom survived, your model of the bug is wrong. Return to Phase 1 and build the loop — a second guess from the same wrong model is the most expensive move available.

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. If you have a **tight** pass/fail signal for the bug — one that goes red on _this_ bug — you will find the cause; bisection, hypothesis-testing, and instrumentation all just consume it. If you don't have one, no amount of staring at code will save you.

Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**

### Ways to construct one — try them in roughly this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright / Puppeteer) — drives the UI, asserts on DOM/console/network.
5. **Replay a captured trace.** Save a real network request / payload / event log to disk; replay it through the code path in isolation.
6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so you can `git bisect run` it.
9. **Differential loop.** Run the same input through old-version vs new-version (or two configs) and diff outputs.
10. **Human-in-the-loop script.** Last resort. If a human must click, drive _them_ with a script that prints one instruction, waits, and captures the result — so the loop is still structured and its output still feeds back to you.

Build the right feedback loop, and the bug is 90% fixed.

### Tighten the loop

Treat the loop as a product. Once you have _a_ loop, **tighten** it:

- Can I make it faster? (Cache setup, skip unrelated init, narrow the test scope.)
- Can I make the signal sharper? (Assert on the specific symptom, not "didn't crash".)
- Can I make it more deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

A 30-second flaky loop is barely better than no loop; a 2-second deterministic one is tight — a debugging superpower.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not — keep raising the rate until it's debuggable.

### When the failure cannot be re-run: the artifact loop

Some real failures never rerun on your machine — a one-off production incident, a crash dump, a third-party outage that has passed. Only then, downgrade from a runnable loop to an **artifact loop**.

**Entry criterion — same standard of proof as the loop itself.** Write out constructions 1–10 above and, for each, one concrete sentence on why it cannot work for *this* failure. "It's a production incident" exempts nothing on its own: incidents are replayable from captured payloads (5), narrowable by differential runs against the last good deploy (9), and often reproducible under stress (7). If you can't produce ten reasons, you haven't exhausted the list — go back and build the loop.

With that written down: gather the evidence that exists (logs, traces, core dump, HAR, crash report, DB snapshot) and treat it as the loop. Phase 3 works the same — every hypothesis must predict something **checkable in the artifacts** ("if X is the cause, the log must show Y between T1 and T2") and dies when the artifacts contradict it. Phases 5–6 still apply in full: the fix still gets a regression test at a seam, and the report says plainly it was verified against artifacts, not a live reproduction.

No runnable loop **and** no artifacts? Stop and say so explicitly. List what you tried. Ask the user for: (a) access to whatever environment reproduces it, (b) captured artifacts (HAR file, log dump, core dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** hypothesise from nothing.

### Completion criterion — a tight loop that goes red

Phase 1 is done when the loop is **tight** and **red-capable**: you can name **one command** — a script path, a test invocation, a curl — that you have **already run at least once** (paste the invocation and its output), and that is:

- [ ] **Red-capable** — it drives the actual bug code path and asserts the **user's exact symptom**, so it can go red on this bug and green once fixed. Not "runs without erroring" — it must be able to _catch this specific bug_.
- [ ] **Deterministic** — same verdict every run (flaky bugs: a pinned, high reproduction rate, per above).
- [ ] **Fast** — seconds, not minutes.
- [ ] **Agent-runnable** — you can run it unattended.

If you catch yourself reading code to build a theory before this command exists, **stop — jumping straight to a hypothesis is the exact failure this skill prevents.** No red-capable command, no Phase 2. The one exception is the artifact loop above, and only once its entry criterion is met in writing.

## Phase 2 — Reproduce + minimise

Run the loop. Watch it go red — the bug appears.

Confirm:

- [ ] The loop produces the failure mode the **user** described — not a different failure that happens to be nearby. Wrong bug = wrong fix.
- [ ] The failure is reproducible across multiple runs (or, for non-deterministic bugs, reproducible at a high enough rate to debug against).
- [ ] You have captured the exact symptom (error message, wrong output, slow timing) so later phases can verify the fix actually addresses it.

### Minimise

Once it's red, shrink the repro to the **smallest scenario that still goes red**. Cut inputs, callers, config, data, and steps **one at a time**, re-running the loop after each cut — keep only what's load-bearing for the failure.

Why bother: a minimal repro shrinks the hypothesis space in Phase 3 (fewer moving parts left to suspect) and becomes the clean regression test in Phase 5.

Done when **every remaining element is load-bearing** — removing any one of them makes the loop go green.

Do not proceed until you have reproduced **and** minimised. On the artifact loop, this phase becomes: catalogue the evidence you hold, state the exact symptom it shows, and name what each artifact can and cannot settle — then proceed.

## Phase 3 — Hypothesise

Generate **3–5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea.

Each hypothesis must be **falsifiable**: state the prediction it makes.

> Format: "If \<X\> is the cause, then \<changing Y\> will make the bug disappear / \<changing Z\> will make it worse."

If you cannot state the prediction, the hypothesis is a vibe — discard or sharpen it.

**Show the ranked list to the user before testing.** They often have domain knowledge that re-ranks instantly ("we just deployed a change to #3"), or know hypotheses they've already ruled out. Cheap checkpoint, big time saver. Don't block on it — proceed with your ranking if the user is AFK.

## Phase 4 — Instrument

Each probe must map to a specific prediction from Phase 3. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if the env supports it. One breakpoint beats ten logs.
2. **Targeted logs** at the boundaries that distinguish hypotheses.
3. Never "log everything and grep".

**Tag every debug log** with a unique prefix, e.g. `[DEBUG-a4f2]`. Cleanup at the end becomes a single `grep -rF '[DEBUG-' .` — plain `grep` reads the brackets as an unterminated character class and exits **2** with `Unmatched [`, which in a checklist reads exactly like exit 1, "nothing left". Untagged logs survive; tagged logs die.

**Perf branch.** For performance regressions, logs are usually wrong. Instead: establish a baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

## Phase 5 — Fix + regression test

Write the regression test **before the fix** — but only if there is a **correct seam** for it.

A correct seam is one where the test exercises the **real bug pattern** as it occurs at the call site. If the only available seam is too shallow (single-caller test when the bug needs multiple callers, unit test that can't replicate the chain that triggered the bug), a regression test there gives false confidence.

**If no correct seam exists, that itself is the finding.** Note it. The codebase architecture is preventing the bug from being locked down. Flag this for the next phase.

If a correct seam exists:

1. Turn the minimised repro into a failing test at that seam.
2. Watch it fail.
3. Apply the fix.
4. Watch it pass.
5. Re-run the Phase 1 feedback loop against the original (un-minimised) scenario — on the artifact path, instead check the fix against every artifact that showed the symptom.

## Phase 6 — Cleanup + post-mortem

Required before declaring done:

- [ ] Original repro no longer reproduces (re-run the Phase 1 loop). **On the artifact path there is no loop to re-run** — instead: the regression test passes, the fix accounts for every symptom the artifacts show, and the report states plainly that the original incident was never reproduced live, so nobody reads this as confirmed-in-situ.
- [ ] Regression test passes (or absence of seam is documented)
- [ ] All `[DEBUG-...]` instrumentation removed — `grep -rF '[DEBUG-' .` exits 1. Exit 2 means the command itself failed; that is not a clean tree.
- [ ] Throwaway prototypes deleted (or moved to a clearly-marked debug location)
- [ ] The hypothesis that turned out correct is stated in the commit / PR message — or, when the work isn't being committed, in the handover report — so the next debugger learns

**Then ask: what would have prevented this bug?** If the answer involves architectural change (no good test seam, tangled callers, hidden coupling), report it to the user with the specifics. Make the recommendation **after** the fix is in, not before — you have more information now than when you started.

---

_Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) `diagnosing-bugs` (MIT). Changes: the second-attempt rule (idea from [obra/superpowers](https://github.com/obra/superpowers) `systematic-debugging`); the artifact loop for failures that cannot be re-run, gated on writing out why each of the ten constructions fails; description narrowed to hard bugs, performance regressions and surviving symptoms; dependencies on files outside this collection removed._
