import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import http_utils

spec = importlib.util.spec_from_file_location("manifest_updater", Path(__file__).resolve().parents[1] / "scripts/update-manifests.py")
manifest_updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest_updater)


class HTTPTests(unittest.TestCase):
    def test_large_release_repositories_use_single_latest_release(self):
        with patch.object(manifest_updater, "fetch_json", return_value={"tag_name": "20260901", "prerelease": False, "draft": False}) as fetch:
            release = manifest_updater.fetch_stable_release("https://api.github.com/repos/astral-sh/python-build-standalone/releases")
            self.assertEqual(release["tag_name"], "20260901")
            fetch.assert_called_once_with("https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest")

    def test_retries_504_then_succeeds(self):
        error = urllib.error.HTTPError("https://example.com", 504, "timeout", {}, io.BytesIO())
        with patch("http_utils.urllib.request.build_opener") as build, patch("http_utils.time.sleep") as sleep:
            build.return_value.open.side_effect = [error, io.BytesIO(b'{"ok":true}')]
            self.assertEqual(http_utils.fetch_json("https://example.com"), {"ok": True})
            self.assertEqual(sleep.call_count, 1)

    def test_permanent_failure_and_rate_limit_are_bounded(self):
        with patch("http_utils.urllib.request.build_opener") as build, patch("http_utils.time.sleep") as sleep:
            build.return_value.open.side_effect = urllib.error.URLError("offline")
            with self.assertRaises(urllib.error.URLError):
                http_utils.request("https://example.com")
            self.assertEqual(build.return_value.open.call_count, 4)
            self.assertEqual(sleep.call_count, 3)

    def test_token_is_never_sent_to_other_hosts(self):
        with patch.dict("os.environ", {"GH_TOKEN": "fixture"}), patch("http_utils.urllib.request.build_opener") as build:
            http_utils.request("https://registry.npmjs.org/package")
            self.assertIsNone(build.return_value.open.call_args.args[0].get_header("Authorization"))
            http_utils.request("https://api.github.com/repos/test/test")
            self.assertEqual(build.return_value.open.call_args.args[0].get_header("Authorization"), "Bearer fixture")

    def test_multi_file_failure_restores_prior_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            a, b, staged = root / "a", root / "b", root / "staged"
            a.write_text("old-a"); b.write_text("old-b"); staged.write_text("new-a")
            with self.assertRaises(OSError):
                http_utils.commit_files([(staged, a), (root / "missing", b)])
            self.assertEqual(a.read_text(), "old-a")
            self.assertEqual(b.read_text(), "old-b")


if __name__ == "__main__":
    unittest.main()
