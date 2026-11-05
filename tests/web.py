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
        expect(page.get_by_text("Hello Common Lisp (1)", exact=True).filter(visible=True)).to_be_visible()
        page.get_by_role("textbox").fill("Ada")
        expect(page.get_by_text("Hello Ada (1)", exact=True).filter(visible=True)).to_be_visible()
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
        expect(page.get_by_text("Hello Ada (0)", exact=True).filter(visible=True)).to_be_visible()

    def test_gallery_pages_persist_inputs_and_switch_collection(self):
        tabs = self.page.get_by_role("tab")
        expect(tabs).to_have_count(5)
        expect(self.page.get_by_role("tab", name="Controls")).to_have_attribute(
            "aria-selected", "true")
        self.page.get_by_role("textbox").fill("Persistent name")
        self.page.get_by_role("tab", name="Editing", exact=True).click()
        expect(self.page.get_by_role("textbox")).to_have_value(
            "The quick brown fox jumps over the lazy dog.")
        self.page.get_by_role("textbox").fill("Persistent editor")
        for name in ("Layout", "Scroll", "Styles"):
            self.page.get_by_role("tab", name=name, exact=True).click()
            expect(self.page.get_by_role("tab", name=name, exact=True)).to_have_attribute(
                "aria-selected", "true")
        self.page.get_by_role("tab", name="Controls", exact=True).click()
        expect(self.page.get_by_role("textbox")).to_have_value("Persistent name")
        self.assertTrue(self.page.locator("main button").evaluate_all(
            "nodes => nodes.every(n => getComputedStyle(n).borderTopLeftRadius !== '0px')"))
        self.page.get_by_role("button", name="Glass", exact=True).click()
        expect(self.page.get_by_role("button", name="Motif", exact=True)).to_be_visible()
        self.assertTrue(self.page.locator("main button").evaluate_all(
            "nodes => nodes.every(n => getComputedStyle(n).borderTopLeftRadius === '0px')"))
        self.page.get_by_role("tab", name="Editing", exact=True).click()
        expect(self.page.get_by_role("textbox")).to_have_value("Persistent editor")
        expect(self.page.locator("canvas")).to_have_count(0)

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

    def test_readline_native_text_selection_unicode_and_composition(self):
        self.fixture()
        control = self.page.locator("#test-host input")
        control.fill("one two three")
        control.press("Control+a")
        self.assertEqual(control.evaluate("n => n.selectionStart"), 0)
        expect(control).to_have_value("one two three")
        control.press("Control+e")
        self.assertEqual(control.evaluate("n => n.selectionStart"), 13)
        control.press("Control+w")
        expect(control).to_have_value("one two ")
        control.press("Control+y")
        expect(control).to_have_value("one two three")
        control.press("Control+a")
        control.press("Alt+f")
        self.assertEqual(control.evaluate("n => n.selectionStart"), 3)
        control.press("Control+f")
        control.press("Control+k")
        expect(control).to_have_value("one ")
        control.press("Control+y")
        expect(control).to_have_value("one two three")
        control.press("Control+e")
        control.press("Control+u")
        expect(control).to_have_value("")
        control.press("Control+y")
        expect(control).to_have_value("one two three")
        control.press("Control+Shift+a")
        self.assertEqual(control.evaluate("n => [n.selectionStart,n.selectionEnd]"),
                         [0, 13])
        control.fill("ab")
        control.press("Control+t")
        expect(control).to_have_value("ba")
        control.fill("A😀B")
        control.press("Control+b")
        self.assertEqual(control.evaluate("n => n.selectionStart"), 3)
        control.press("Control+b")
        self.assertEqual(control.evaluate("n => n.selectionStart"), 1)
        control.press("Control+d")
        expect(control).to_have_value("AB")
        control.fill("abcde")
        control.evaluate("n => n.setSelectionRange(1,4,'backward')")
        control.press("Control+Shift+f")
        self.assertEqual(control.evaluate(
            "n => [n.selectionStart,n.selectionEnd,n.selectionDirection]"),
            [2, 4, "backward"])
        control.fill("alpha beta gamma")
        control.press("Control+w")
        control.press("Control+w")
        control.press("Control+y")
        expect(control).to_have_value("alpha beta gamma")
        control.press("Control+w")
        self.page.keyboard.insert_text("z")
        control.press("Control+w")
        control.press("Control+y")
        expect(control).to_have_value("alpha beta z")
        for modifiers in ({"ctrlKey": True, "key": "c"},
                          {"metaKey": True, "key": "a"},
                          {"ctrlKey": True, "key": "a", "isComposing": True}):
            self.assertTrue(control.evaluate("""(n, options) =>
                n.dispatchEvent(new KeyboardEvent('keydown',
                    {...options, bubbles:true, cancelable:true}))""", modifiers))
        control.evaluate("""n => n.dispatchEvent(new CompositionEvent(
            'compositionstart', {bubbles:true}))""")
        self.assertTrue(control.evaluate("""n => n.dispatchEvent(
            new KeyboardEvent('keydown', {key:'a', ctrlKey:true,
                bubbles:true, cancelable:true}))"""))
        control.evaluate("""n => n.dispatchEvent(new CompositionEvent(
            'compositionend', {bubbles:true}))""")
        self.frames()
        expect(control).to_have_value("alpha beta z")

    def test_native_tabs_hover_pressed_and_keyboard_focus(self):
        self.lisp('''(defvar *tab-test-page* :first)
          (defvar *tab-test-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *tab-test-host* "id") #j"tab-host"
                (jscl/ffi:oget *tab-test-host* "style" "width") #j"500px"
                (jscl/ffi:oget *tab-test-host* "style" "height") #j"150px")
          (#j:document:body:appendChild *tab-test-host*)
          (defvar *tab-test-app*
            (lui.web:mount *tab-test-host*
              (lambda ()
                (lui.frame:row (:gap 8)
                  (when (lui.glass:tab :first "First"
                          :selected-p (eq *tab-test-page* :first))
                    (setf *tab-test-page* :first))
                  (lui.glass:tab :disabled "Disabled" :disabled-p t)
                  (when (lui.glass:tab :second "Second"
                          :selected-p (eq *tab-test-page* :second))
                    (setf *tab-test-page* :second))))))''')
        first = self.page.get_by_role("tab", name="First", exact=True)
        second = self.page.get_by_role("tab", name="Second", exact=True)
        disabled = self.page.get_by_role("tab", name="Disabled", exact=True)
        expect(self.page.locator("#tab-host [role=tablist]")).to_have_count(1)
        expect(first).to_have_attribute("aria-selected", "true")
        expect(second).to_have_attribute("tabindex", "-1")
        first.hover()
        self.page.wait_for_function("""() => getComputedStyle(
            document.querySelector('#tab-host button')).filter.includes('1.2')""")
        self.page.mouse.down()
        self.page.wait_for_function("""() => getComputedStyle(
            document.querySelector('#tab-host button')).transform !== 'none'""")
        self.page.mouse.up()
        self.frames()
        self.assertFalse(first.evaluate("n => n.matches(':focus-visible')"))
        first.focus()
        first.press("ArrowRight")
        expect(second).to_be_focused()
        expect(second).to_have_attribute("aria-selected", "true")
        expect(first).to_have_attribute("aria-selected", "false")
        self.assertTrue(second.evaluate("n => n.matches(':focus-visible')"))
        second.press("Home")
        expect(first).to_be_focused()
        first.press("End")
        expect(second).to_be_focused()
        expect(disabled).to_be_disabled()
        disabled.hover(force=True)
        self.assertEqual(disabled.evaluate("n => getComputedStyle(n).filter"), "none")
        self.page.locator("#tab-host").dispatch_event("pointerleave")
        self.frames()
        self.assertEqual(self.number(
            '(if (lui.frame:context-hover (lui.web::web-app-context *tab-test-app*)) 1 0)'), 0)
        self.lisp('(lui.web:unmount *tab-test-app*)')

    def test_removed_replaced_and_unmounted_controls_release_listeners(self):
        self.fixture()
        baseline = self.number('(length (lui.web::web-app-listeners *web-test-app*))')
        self.page.locator("#test-host input").evaluate("node => window.detachedControl = node")
        self.lisp('(setf *web-test-show* nil) (lui.web:refresh *web-test-app*)')
        self.frames()
        expect(self.page.locator("#test-host input")).to_have_count(0)
        self.assertEqual(self.number('(length (lui.web::web-app-listeners *web-test-app*))'), 3)
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
        self.assertEqual(self.number('(length (lui.web::web-app-listeners *web-test-app*))'), 6)
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
