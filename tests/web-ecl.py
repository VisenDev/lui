"""Exercise the compiled ECL gallery through real browser events."""
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


class ECLWebTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(
                QuietHandler, directory=ROOT / "build/web-ecl"))
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

    def setUp(self):
        self.page = self.browser.new_page(viewport={"width": 1000, "height": 800})
        self.errors = []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))
        suffix = "?fixture" if "fixture" in self._testMethodName else ""
        self.page.goto(f"http://127.0.0.1:{self.server.server_port}/{suffix}")
        self.page.wait_for_selector("main canvas", timeout=60000)
        name = "Increment" if suffix else "Say hello"
        expect(self.page.get_by_role("button", name=name, exact=True)).to_have_count(1)

    def tearDown(self):
        self.assertEqual(self.page.evaluate("LuiECL.frames.size"), 0)
        self.page.close()
        self.assertEqual(self.errors, [])

    def press(self, name):
        button = self.page.get_by_role("button", name=name, exact=True)
        box = button.bounding_box()
        self.page.mouse.click(box["x"] + box["width"] / 2,
                              box["y"] + box["height"] / 2)
        self.frames()

    def frames(self):
        self.page.evaluate("""() => new Promise(resolve =>
            requestAnimationFrame(() => requestAnimationFrame(resolve)))""")

    def test_compiled_gallery_input_and_resize(self):
        self.assertTrue(self.page.evaluate("typeof jscl === 'undefined'"))
        self.press("Say hello")
        expect(self.page.get_by_text("Hello Common Lisp (1)", exact=True)).to_have_count(1)
        # Assistive technology activation follows the shared :activate path.
        self.page.get_by_role("button", name="Reset", exact=True).evaluate("b => b.click()")
        expect(self.page.get_by_text("Hello Common Lisp (0)", exact=True)).to_have_count(1)
        self.page.set_viewport_size({"width": 760, "height": 600})
        self.frames()
        self.press("Say hello")
        expect(self.page.get_by_text("Hello Common Lisp (1)", exact=True)).to_have_count(1)
        self.assertGreater(self.page.locator("canvas").first.evaluate("c => c.width"), 0)

    def test_fixture_unicode_keyboard_gc_and_unmount(self):
        self.page.mouse.click(80, 12)
        self.page.keyboard.press("Control+Shift+A")
        value = 'café 漢字 😀 "quoted" \\ #.(error "never evaluated")'
        self.page.keyboard.insert_text(value)
        expect(self.page.get_by_text("Value: " + value, exact=True)).to_have_count(1)
        self.page.keyboard.press("Tab")
        self.page.keyboard.press("Space")
        expect(self.page.get_by_text("Count: 1", exact=True)).to_have_count(1)
        self.press("Collect garbage")
        self.page.wait_for_function("window.eclLiveRoots > 0")
        initial_roots = self.page.evaluate("window.eclLiveRoots")
        for _ in range(10):
            self.press("Collect garbage")
            self.press("Increment")
        expect(self.page.get_by_text("Count: 11", exact=True)).to_have_count(1)
        self.assertLessEqual(self.page.evaluate("window.eclLiveRoots"), initial_roots + 2)
        self.page.evaluate("window.eclUnmount()")
        expect(self.page.locator("main canvas")).to_have_count(0)
        # Only the fixture's explicit JavaScript test hook remains rooted.
        self.assertEqual(self.page.evaluate("window.eclRemainingRoots"), 1)
        self.page.wait_for_timeout(1100)


if __name__ == "__main__":
    unittest.main()
