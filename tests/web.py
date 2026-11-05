"""Native HTML integration tests. Build first with scripts/build-web.lisp.

Run: python tests/web.py (requires Playwright and Chromium).
"""

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


class WebTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(QuietHandler, directory=ROOT)
        )
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch(
            executable_path=shutil.which("chromium-browser") or shutil.which("chromium"),
            args=["--no-sandbox"],
        )

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.page = self.browser.new_page(viewport={"width": 900, "height": 700})
        self.errors = []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))
        self.page.goto(f"http://127.0.0.1:{self.server.server_port}/examples/web.html")
        expect(self.page.get_by_role("button", name="Say hello")).to_be_visible()

    def tearDown(self):
        self.page.close()
        self.assertEqual(self.errors, [])

    def lisp(self, source):
        self.page.evaluate("source => { jscl.evaluateString(source); }",
                           "(progn " + source + ")")

    def frames(self):
        self.page.evaluate("""() => new Promise(resolve =>
            requestAnimationFrame(() => requestAnimationFrame(resolve)))""")

    def fixture(self):
        self.lisp('''
          (defvar *web-test-value* "original")
          (defvar *web-test-show* t)
          (defvar *web-test-kind* :text)
          (defvar *web-test-draws* 0)
          (defvar *web-test-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *web-test-host* "id") #j"test-host"
                (jscl/ffi:oget *web-test-host* "style" "width") #j"500px"
                (jscl/ffi:oget *web-test-host* "style" "height") #j"300px")
          (#j:document:body:appendChild *web-test-host*)
          (defvar *web-test-app*
            (lui.web:mount *web-test-host*
              (lambda ()
                (incf *web-test-draws*)
                (lui.frame:column (:width (lui.layout:grow))
                  (when *web-test-show*
                    (if (eq *web-test-kind* :text)
                        (setf *web-test-value*
                          (lui.glass:text-field :fixture *web-test-value*
                            :width (lui.layout:grow)))
                        (lui.glass:button :fixture "Replacement")))))))
        ''')
        expect(self.page.locator("#test-host input")).to_be_visible()
        self.frames()

    def number(self, expression):
        self.lisp(f'(setf (jscl/ffi:oget #j:window "testNumber") {expression})')
        return self.page.evaluate("window.testNumber")

    def test_shared_demo_native_controls(self):
        page = self.page
        expect(page.locator("canvas")).to_have_count(0)
        expect(page.get_by_role("textbox")).to_have_value("Common Lisp")
        page.get_by_role("button", name="Say hello").click()
        expect(page.locator("main > div").filter(has_text="Hello Common Lisp (1)")).to_be_visible()
        page.get_by_role("textbox").fill("Ada")
        expect(page.locator("main > div").filter(has_text="Hello Ada (1)")).to_be_visible()
        checkbox = page.get_by_role("checkbox", name="Enabled")
        checkbox.uncheck()
        expect(checkbox).not_to_be_checked()
        slider = page.get_by_role("slider")
        slider.focus()
        slider.press("End")
        expect(slider).to_have_value("1")
        slider.press("Home")
        expect(slider).to_have_value("0")
        page.get_by_role("button", name="Reset", exact=True).click()
        expect(page.locator("main > div").filter(has_text="Hello Ada (0)")).to_be_visible()

    def test_identity_selection_composition_and_host_resize(self):
        self.fixture()
        control = self.page.locator("#test-host input")
        control.focus()
        control.evaluate("node => { window.originalControl = node; node.setSelectionRange(1, 4); }")
        self.lisp('(lui.web:refresh *web-test-app*)')
        self.frames()
        self.assertTrue(control.evaluate("node => node === window.originalControl && node === document.activeElement"))
        self.assertEqual(control.evaluate("node => [node.selectionStart, node.selectionEnd]"), [1, 4])
        control.evaluate('''node => {
            node.dispatchEvent(new CompositionEvent('compositionstart', {bubbles:true}));
            node.value = '日本';
            node.dispatchEvent(new InputEvent('input', {bubbles:true, isComposing:true}));
        }''')
        self.lisp('(lui.web:refresh *web-test-app*)')
        self.frames()
        expect(control).to_have_value("日本")
        self.assertEqual(self.number('(length *web-test-value*)'), 8)
        control.evaluate("node => node.dispatchEvent(new CompositionEvent('compositionend', {bubbles:true}))")
        self.frames()
        self.assertEqual(self.number('(length *web-test-value*)'), 2)
        before = control.bounding_box()["width"]
        self.page.locator("#test-host").evaluate("node => node.style.width = '350px'")
        self.page.wait_for_function("document.querySelector('#test-host input').getBoundingClientRect().width < 400")
        self.assertLess(control.bounding_box()["width"], before)
        self.assertTrue(control.evaluate("node => node === window.originalControl"))

    def test_removed_replaced_and_unmounted_controls_release_listeners(self):
        self.fixture()
        baseline = self.number('(length (lui.web::web-app-listeners *web-test-app*))')
        self.page.locator("#test-host input").evaluate("node => window.detachedControl = node")
        self.lisp('(setf *web-test-show* nil) (lui.web:refresh *web-test-app*)')
        self.frames()
        expect(self.page.locator("#test-host input")).to_have_count(0)
        self.assertEqual(self.number('(length (lui.web::web-app-listeners *web-test-app*))'), 1)
        draws = self.number('*web-test-draws*')
        self.page.evaluate("window.detachedControl.dispatchEvent(new Event('input'))")
        self.frames()
        self.assertEqual(self.number('*web-test-draws*'), draws)
        self.lisp('(setf *web-test-show* t) (lui.web:refresh *web-test-app*)')
        self.frames()
        self.assertEqual(self.number('(length (lui.web::web-app-listeners *web-test-app*))'), baseline)
        self.lisp('(setf *web-test-kind* :button) (lui.web:refresh *web-test-app*)')
        self.frames()
        expect(self.page.get_by_role("button", name="Replacement")).to_be_visible()
        expect(self.page.locator("#test-host input")).to_have_count(0)
        self.assertEqual(self.number('(length (lui.web::web-app-listeners *web-test-app*))'), 3)
        self.lisp('(lui.web:refresh *web-test-app*) (lui.web:unmount *web-test-app*)')
        self.frames()
        expect(self.page.locator("#test-host > *")).to_have_count(0)
        self.assertEqual(self.number('(length (lui.web::web-app-listeners *web-test-app*))'), 0)
        draws = self.number('*web-test-draws*')
        self.page.locator("#test-host").evaluate("node => {node.style.width = '250px'; node.dispatchEvent(new WheelEvent('wheel', {deltaY:20}));}")
        self.page.evaluate("window.dispatchEvent(new Event('resize'))")
        self.frames()
        self.assertEqual(self.number('*web-test-draws*'), draws)
        self.lisp('(lui.web:unmount *web-test-app*)')


if __name__ == "__main__":
    unittest.main(verbosity=2)
