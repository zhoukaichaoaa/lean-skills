import unittest

from retry import run_with_retries


def flaky(succeed_on):
    """Return a callable that raises until its `succeed_on`-th call."""
    state = {"calls": 0}

    def fn():
        state["calls"] += 1
        if state["calls"] < succeed_on:
            raise ValueError("not yet")
        return "ok"

    fn.state = state
    return fn


class TestRunWithRetries(unittest.TestCase):
    def test_succeeds_immediately(self):
        fn = flaky(1)
        self.assertEqual(run_with_retries(fn, attempts=3), "ok")
        self.assertEqual(fn.state["calls"], 1)

    def test_succeeds_on_second_attempt(self):
        fn = flaky(2)
        self.assertEqual(run_with_retries(fn, attempts=3), "ok")
        self.assertEqual(fn.state["calls"], 2)

    def test_succeeds_on_final_attempt(self):
        fn = flaky(3)
        self.assertEqual(run_with_retries(fn, attempts=3), "ok")
        self.assertEqual(fn.state["calls"], 3)

    def test_gives_up_after_all_attempts(self):
        fn = flaky(99)
        with self.assertRaises(ValueError):
            run_with_retries(fn, attempts=3)
        self.assertEqual(fn.state["calls"], 3)


if __name__ == "__main__":
    unittest.main()
