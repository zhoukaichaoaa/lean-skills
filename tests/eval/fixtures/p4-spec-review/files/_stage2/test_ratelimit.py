import time
import unittest

from ratelimit import RateLimiter


class TestRateLimiter(unittest.TestCase):
    def test_unseen_key_is_allowed(self):
        rl = RateLimiter(limit=2, window_seconds=60)
        self.assertTrue(rl.allow("fresh"))

    def test_blocks_at_the_limit(self):
        rl = RateLimiter(limit=2, window_seconds=60)
        self.assertTrue(rl.allow("k"))
        self.assertTrue(rl.allow("k"))
        self.assertFalse(rl.allow("k"))

    def test_keys_are_independent(self):
        rl = RateLimiter(limit=1, window_seconds=60)
        self.assertTrue(rl.allow("a"))
        self.assertTrue(rl.allow("b"))
        self.assertFalse(rl.allow("a"))

    def test_window_resets(self):
        rl = RateLimiter(limit=1, window_seconds=0.05)
        self.assertTrue(rl.allow("k"))
        self.assertFalse(rl.allow("k"))
        time.sleep(0.06)
        self.assertTrue(rl.allow("k"))

    def test_reset_all(self):
        rl = RateLimiter(limit=1, window_seconds=60)
        self.assertTrue(rl.allow("k"))
        rl.reset_all()
        self.assertTrue(rl.allow("k"))


if __name__ == "__main__":
    unittest.main()
