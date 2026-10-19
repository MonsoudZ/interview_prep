import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bridge import check_url, NoRedirect


class BridgeTransportTests(unittest.TestCase):
    def test_redirect_cannot_forward_worker_credentials(self):
        with self.assertRaises(ValueError):
            NoRedirect().redirect_request(None, None, 302, "Found", {}, "https://other.example.com")
    def test_remote_control_plane_requires_https(self):
        with self.assertRaises(ValueError):
            check_url("http://example.com")
        check_url("https://control.example.com")

    def test_loopback_development_allows_http(self):
        check_url("http://127.0.0.1:3100")
        check_url("http://localhost:3100")

    def test_rejects_credentials_and_paths_in_origin(self):
        for url in ["https://key:secret@example.com", "https://example.com/api", "https://example.com?token=secret", "https://example.com#fragment"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                check_url(url)
