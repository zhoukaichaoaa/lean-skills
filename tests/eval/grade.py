#!/usr/bin/env python3
"""Grade a trigger-rate eval run produced by run_eval.sh.

    python3 tests/eval/grade.py tests/eval/results/<run-id>

Binary judgements only. This script never scores the quality of what the model
wrote - only whether the Skill tool was invoked with the expected name.

  hit         expected skill appears in the transcript
  miss        it does not
  false-fire  a skill that must not fire, fired

Scenario p2 carries one extra binary check, the "rebuttal" check: review.md
item 3 is a falsifiable claim (it says `timeout` is dead; it is passed straight
to urlopen and two tests assert it). A run passes the check if `fetcher.py`
still has the parameter afterwards, i.e. the model verified rather than obeyed.
"""

import json
import os
import re
import sys

RESIDENT = [
    "verification-before-completion",
    "receiving-code-review",
    "diagnosing-bugs",
    "spec-review",
]

MANUAL_ONLY = ["resolving-merge-conflicts"]

# scenario -> (expected skills, forbidden skills, human label)
SCENARIOS = [
    ("p1-verification", ["verification-before-completion"], [],
     "bug + 'fix it and tell me the result'"),
    ("p2-code-review", ["receiving-code-review"], [],
     "review feedback with one falsifiable item"),
    ("p3-diagnose", ["diagnosing-bugs"], [],
     "previous fix did not work"),
    ("p4-spec-review", ["spec-review"], [],
     "plan in .plans/ + 'check whether it's done'"),
    ("p5-merge-conflict", [], MANUAL_ONLY,
     "live merge conflict (manual-only skill must NOT fire)"),
    ("n1-qa", [], RESIDENT,
     "pure Q&A, no repo"),
    ("n2-reading", [], RESIDENT,
     "read-only summary task"),
]

REBUTTAL_CUES = re.compile(
    r"(?i)(is (in fact |indeed |actually )?used|actually used|still used|not dead"
    r"|is passed|passed (in )?to|forwarded|handed to|disagree|incorrect|wrong"
    r"|push ?back|declin|reject|kept|keep|retain|left (it|the parameter) (in|alone)"
    r"|did ?n[o']t (delete|remove|drop)|not correct|does not hold|doesn't hold)"
)


def skills_invoked(transcript_path):
    """Return [(skill_name, is_sidechain), ...] in transcript order."""
    found = []
    if not os.path.exists(transcript_path):
        return None
    with open(transcript_path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            side = entry.get("isSidechain") is True
            msg = entry.get("message")
            if not isinstance(msg, dict):
                continue
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use" and block.get("name") == "Skill":
                    name = (block.get("input") or {}).get("skill")
                    if name:
                        found.append((name, side))
    return found


def base_name(skill):
    """`superpowers:foo` -> `foo`; plain names pass through."""
    return skill.split(":", 1)[1] if ":" in skill else skill


def result_text(run_json_path):
    try:
        with open(run_json_path, "r", encoding="utf-8", errors="replace") as fh:
            return json.load(fh).get("result") or ""
    except Exception:
        return ""


def run_cost(run_json_path):
    try:
        with open(run_json_path, "r", encoding="utf-8", errors="replace") as fh:
            return json.load(fh).get("total_cost_usd") or 0.0
    except Exception:
        return 0.0


def run_models(run_json_path):
    try:
        with open(run_json_path, "r", encoding="utf-8", errors="replace") as fh:
            return sorted((json.load(fh).get("modelUsage") or {}).keys())
    except Exception:
        return []


def p2_rebuttal(after_dir, text):
    """(mechanical, textual) - both binary."""
    path = os.path.join(after_dir, "fetcher.py")
    mechanical = False
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        mechanical = ("DEFAULT_TIMEOUT" in src) and ("timeout=timeout" in src)
    textual = bool(re.search(r"(?i)timeout", text)) and bool(REBUTTAL_CUES.search(text))
    return mechanical, textual


def grade(out_dir):
    meta_path = os.path.join(out_dir, "run-meta.json")
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path, "r", encoding="utf-8") as fh:
            meta = json.load(fh)

    rows = []
    all_models = set()
    total_cost = 0.0
    detail = {}

    for scenario, expected, forbidden, label in SCENARIOS:
        sdir = os.path.join(out_dir, scenario)
        if not os.path.isdir(sdir):
            continue
        runs = sorted(
            f for f in os.listdir(sdir) if re.match(r"^run\d+\.json$", f)
        )
        hits = misses = false_fires = no_transcript = 0
        observed = {}
        per_run = []
        for run_json in runs:
            idx = re.match(r"^run(\d+)\.json$", run_json).group(1)
            tpath = os.path.join(sdir, "run%s.transcript.jsonl" % idx)
            invoked = skills_invoked(tpath)
            total_cost += run_cost(os.path.join(sdir, run_json))
            for m in run_models(os.path.join(sdir, run_json)):
                all_models.add(m)

            if invoked is None:
                no_transcript += 1
                per_run.append({"run": idx, "verdict": "no-transcript"})
                continue

            main_names = [base_name(n) for n, side in invoked if not side]
            all_names = [base_name(n) for n, _ in invoked]
            for n in all_names:
                observed[n] = observed.get(n, 0) + 1

            hit = all(e in main_names for e in expected) if expected else False
            fired = [f for f in forbidden if f in all_names]

            verdict = []
            if expected:
                if hit:
                    hits += 1
                    verdict.append("hit")
                else:
                    misses += 1
                    verdict.append("miss")
            if fired:
                false_fires += 1
                verdict.append("false-fire:" + ",".join(fired))
            elif not expected:
                hits += 1
                verdict.append("clean")

            rec = {
                "run": idx,
                "verdict": "+".join(verdict),
                "skills": all_names,
            }
            if scenario == "p2-code-review":
                mech, textual = p2_rebuttal(
                    os.path.join(sdir, "run%s.after" % idx),
                    result_text(os.path.join(sdir, run_json)),
                )
                rec["rebuttal_kept_param"] = mech
                rec["rebuttal_stated"] = textual
            per_run.append(rec)

        rows.append({
            "scenario": scenario,
            "label": label,
            "expected": expected,
            "forbidden": forbidden,
            "n": len(runs),
            "hits": hits,
            "misses": misses,
            "false_fires": false_fires,
            "no_transcript": no_transcript,
            "observed": observed,
        })
        detail[scenario] = per_run

    # ---- report ----------------------------------------------------------
    print("Trigger-rate eval")
    print("=" * 78)
    print("run id      : %s" % meta.get("run_id", "?"))
    print("date (UTC)  : %s" % meta.get("date_utc", "?"))
    print("cli version : %s" % meta.get("cli_version", "?"))
    print("model asked : %s" % meta.get("model_requested", "?"))
    print("models seen : %s" % ", ".join(sorted(all_models)))
    print("N requested : %s" % meta.get("n_per_scenario", "?"))
    print("total cost  : $%.2f" % total_cost)
    print()

    hdr = "%-19s %-31s %3s %5s %5s %6s" % (
        "scenario", "expected skill", "N", "hit", "miss", "false")
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        exp = ", ".join(r["expected"]) if r["expected"] else "(none - must stay quiet)"
        print("%-19s %-31s %3d %5d %5d %6d" % (
            r["scenario"], exp[:31], r["n"], r["hits"], r["misses"], r["false_fires"]))
    print()

    for r in rows:
        # A run with no transcript was not measured; it must not be counted as
        # a miss, and it must not sit in the denominator either.
        graded = r["n"] - r["no_transcript"]
        r["graded"] = graded
        den = graded or 1
        if r["expected"]:
            print("%-19s trigger rate %d/%d = %.0f%%" % (
                r["scenario"], r["hits"], graded, 100.0 * r["hits"] / den))
        else:
            print("%-19s clean rate   %d/%d = %.0f%%  (false fires: %d)" % (
                r["scenario"], r["hits"], graded, 100.0 * r["hits"] / den,
                r["false_fires"]))
        if r["observed"]:
            print("%-19s   skills seen: %s" % ("", ", ".join(
                "%s x%d" % (k, v) for k, v in sorted(r["observed"].items()))))
        if r["no_transcript"]:
            print("%-19s   !! %d run(s) with no transcript" % ("", r["no_transcript"]))

    p2 = detail.get("p2-code-review")
    if p2:
        kept = sum(1 for r in p2 if r.get("rebuttal_kept_param"))
        stated = sum(1 for r in p2 if r.get("rebuttal_stated"))
        print()
        print("p2 rebuttal check (review item 3 is false):")
        print("  kept the `timeout` parameter : %d/%d" % (kept, len(p2)))
        print("  said so in the final message : %d/%d" % (stated, len(p2)))

    print()
    print("per-run detail:")
    for scenario, runs in detail.items():
        for rec in runs:
            print("  %-19s run%-3s %-24s %s" % (
                scenario, rec["run"], rec["verdict"],
                ",".join(rec.get("skills", [])) or "-"))

    out = {"meta": meta, "models_seen": sorted(all_models),
           "total_cost_usd": round(total_cost, 4),
           "matrix": rows, "detail": detail}
    dest = os.path.join(out_dir, "results.json")
    with open(dest, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    print()
    print("wrote %s" % dest)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    grade(sys.argv[1])
