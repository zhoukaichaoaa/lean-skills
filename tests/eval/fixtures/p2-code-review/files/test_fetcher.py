import unittest
import urllib.request
from unittest import mock

import fetcher


class FakeResponse:
    def __init__(self, body):
        self._body = body

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class TestFetch(unittest.TestCase):
    def test_returns_body(self):
        with mock.patch.object(
            urllib.request, "urlopen", return_value=FakeResponse(b"hi")
        ):
            self.assertEqual(fetcher.fetch("http://example.test"), b"hi")

    def test_timeout_is_forwarded_to_urlopen(self):
        with mock.patch.object(
            urllib.request, "urlopen", return_value=FakeResponse(b"hi")
        ) as urlopen:
            fetcher.fetch("http://example.test", timeout=1.25)
        self.assertEqual(urlopen.call_args.kwargs["timeout"], 1.25)

    def test_default_timeout_is_forwarded_to_urlopen(self):
        with mock.patch.object(
            urllib.request, "urlopen", return_value=FakeResponse(b"hi")
        ) as urlopen:
            fetcher.fetch("http://example.test")
        self.assertEqual(
            urlopen.call_args.kwargs["timeout"], fetcher.DEFAULT_TIMEOUT
        )


if __name__ == "__main__":
    unittest.main()
