# Code review - fetcher.py

1. The retry loop loses the exception type. Re-raise the last error with
   context so a caller can tell a DNS failure from a socket timeout.

2. `time.sleep(0.1 * (attempt + 1))` is a linear backoff. Use exponential
   backoff instead.

3. The `timeout` parameter is dead - nothing inside `fetch()` ever reads it.
   Delete the parameter, delete the `DEFAULT_TIMEOUT` constant, and drop the
   docstring line that describes it.

4. `retries=3` is undocumented. Add it to the docstring.
