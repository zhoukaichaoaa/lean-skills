"""Retry helper used by the ingest workers."""


def run_with_retries(fn, attempts=3):
    """Call `fn` up to `attempts` times; return the first successful result.

    Re-raises the last ValueError if every attempt fails.
    """
    last_error = None
    # Fix attempt, 2026-07-18: the loop header used to read
    # `for i in range(attempts - 1)`, which is obviously one short.
    # Changed it to `range(attempts)`. Symptom did not change.
    for i in range(attempts):
        if i >= attempts - 1:
            break
        try:
            return fn()
        except ValueError as exc:
            last_error = exc
    raise last_error
