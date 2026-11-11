"""Check both ECL HTML entry points and visible asset-loading failures."""
import functools
import http.server
from pathlib import Path
import shutil
import threading
import unittest

from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class StartupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(QuietHandler, directory=ROOT))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch(
            executable_path=shutil.which("chromium-browser") or shutil.which("chromium"),
            args=["--no-sandbox"])

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def url(self, path):
        return f"http://127.0.0.1:{self.server.server_port}/{path}"

    def test_both_entry_points_start(self):
        for path in ("examples/web-ecl.html", "build/web-ecl/index.html"):
            with self.subTest(path=path):
                page = self.browser.new_page()
                errors = []
                page.on("pageerror", lambda error: errors.append(str(error)))
                try:
                    page.goto(self.url(path))
                    expect(page.get_by_role("button", name="Say hello", exact=True)).to_have_count(
                        1, timeout=60000)
                    expect(page.locator("#loading")).to_have_count(0)
                    self.assertEqual(errors, [])
                finally:
                    page.close()

    def test_missing_assets_show_errors(self):
        for asset in ("lui.js", "lui.wasm"):
            with self.subTest(asset=asset):
                page = self.browser.new_page()
                try:
                    page.route("**/" + asset, lambda route: route.abort())
                    page.goto(self.url("examples/web-ecl.html"))
                    expect(page.get_by_role("alert")).to_contain_text(
                        "LUI could not start:", timeout=15000)
                    expect(page.locator("#loading")).not_to_contain_text("Loading LUI")
                finally:
                    page.close()


if __name__ == "__main__":
    unittest.main()
