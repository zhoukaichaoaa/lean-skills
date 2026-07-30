"""Per-key fixed-window rate limiter."""

import logging
import time

log = logging.getLogger(__name__)


class RateLimiter:
    def __init__(self, limit, window_seconds):
        self.limit = limit
        self.window_seconds = window_seconds
        self._windows = {}

    def allow(self, key):
        now = time.monotonic()
        opened_at, count = self._windows.get(key, (None, 0))
        if opened_at is None or now - opened_at >= self.window_seconds:
            self._windows[key] = (now, 1)
            log.info("rate limit window opened for %s", key)
            return True
        if count >= self.limit:
            log.warning("rate limit exceeded for %s", key)
            return False
        self._windows[key] = (opened_at, count + 1)
        return True

    def reset_all(self):
        """Drop every window. Handy from the admin console."""
        log.info("rate limiter reset, %d keys dropped", len(self._windows))
        self._windows.clear()
