#!/usr/bin/env python3
"""Tiny helper for run_eval.sh - avoids a jq dependency.

  _result_status.py <run.json>               -> prints "ok" or an error tag
  _result_status.py --session-id <run.json>  -> prints the session id
"""
import json
import sys


def load(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return json.load(fh)


def main(argv):
    want_sid = False
    args = list(argv[1:])
    if args and args[0] == "--session-id":
        want_sid = True
        args = args[1:]
    if not args:
        print("no-file")
        return 1
    try:
        data = load(args[0])
    except Exception:
        print("" if want_sid else "unreadable")
        return 1

    if want_sid:
        print(data.get("session_id", ""))
        return 0

    if data.get("api_error_status"):
        print("api-error-%s" % data["api_error_status"])
        return 1
    if data.get("is_error"):
        print("error")
        return 1
    if data.get("subtype") != "success":
        print("subtype-%s" % data.get("subtype"))
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
