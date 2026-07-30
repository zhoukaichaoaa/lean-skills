"""Small HTTP fetch helper with retries."""

import time
import urllib.request

DEFAULT_TIMEOUT = 5.0


def fetch(url, timeout=DEFAULT_TIMEOUT, retries=3):
    """Fetch `url` and return the response body as bytes.

    timeout: seconds to wait on the socket before giving up on an attempt.
    """
    last_error = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as resp:
                return resp.read()
        except OSError as exc:
            last_error = exc
            time.sleep(0.1 * (attempt + 1))
    raise last_error
