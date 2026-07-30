# Debug notes

## 2026-07-18 - retry.run_with_retries never makes the final attempt

Symptom: with `attempts=3` and a callable that succeeds on its third call,
`run_with_retries` raises instead of returning. Counting the calls shows only
two ever happen.

Tried: the loop header was `for i in range(attempts - 1)`, which looked like
the whole story. Changed it to `for i in range(attempts)`.

Result: no change. `test_retry.py::TestRunWithRetries::test_succeeds_on_final_attempt`
still fails, and the call count is still 2.
