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
        # The runtime compiler needs the special declarations when compiling
        # new fixture callbacks against an already compiled application.
        self.page.evaluate("""() => {jscl.evaluateString(`(declaim (special
            lui.frame:*context* lui.frame:*parent* lui:*unit*))`);}""")

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
        expect(page.locator("div").filter(has_text="Hello Common Lisp (1)").last.filter(visible=True)).to_be_visible()
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
        self.assertEqual(self.page.locator("main").evaluate(
            "n => [getComputedStyle(n).backgroundImage,getComputedStyle(n).backgroundColor]"),
            ["none", "rgb(184, 184, 184)"])
        self.assertTrue(self.page.locator("main button").evaluate_all(
            "nodes => nodes.every(n => getComputedStyle(n).borderTopLeftRadius === '0px')"))
        self.page.get_by_role("tab", name="Editing", exact=True).click()
        expect(self.page.get_by_role("textbox")).to_have_value("Persistent editor")
        expect(self.page.locator("canvas")).to_have_count(0)

    def test_native_shift_tab_order_and_stable_label_measurement(self):
        name = self.page.get_by_role("textbox")
        name.focus()
        name.press("Shift+Tab")
        expect(self.page.get_by_role("tab", name="Controls", exact=True)).to_be_focused()
        self.page.keyboard.press("Shift+Tab")
        expect(self.page.get_by_role("button", name="Glass", exact=True)).to_be_focused()
        self.page.keyboard.press("Tab")
        expect(self.page.get_by_role("tab", name="Controls", exact=True)).to_be_focused()
        self.page.keyboard.press("Tab")
        expect(name).to_be_focused()
        fps = self.page.get_by_text("FPS", exact=False).filter(visible=True)
        expect(fps).to_have_count(1)
        self.assertLess(fps.bounding_box()["height"], 30)
        before = self.page.get_by_role("checkbox", name="Enabled").bounding_box()["y"]
        self.page.get_by_role("checkbox", name="Enabled").hover()
        self.frames()
        self.assertEqual(self.page.get_by_role("checkbox", name="Enabled").bounding_box()["y"], before)

    def test_wheel_over_child_control_chains_and_capture_is_removed(self):
        self.lisp('''(defvar *scroll-test-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *scroll-test-host* "id") #j"scroll-host"
                (jscl/ffi:oget *scroll-test-host* "style" "width") #j"420px"
                (jscl/ffi:oget *scroll-test-host* "style" "height") #j"180px")
          (#j:document:body:appendChild *scroll-test-host*)
          (defvar *scroll-test-app*
            (lui.web:mount *scroll-test-host*
              (lambda ()
                (lui.frame:column (:id :outer :width (lui.layout:grow)
                                  :height (lui.layout:grow) :scroll-p t)
                  (lui.frame:column (:id :inner :width (lui.layout:grow)
                                    :height (lui.layout:fixed 80) :scroll-p t)
                    (lui.glass:button :wheel-row "Wheel over this row"
                      :height (lui.layout:fixed 32) :width (lui.layout:grow)))
                  (lui.glass:label "Outer scroll content"
                    :height (lui.layout:fixed 300))))))''')
        row = self.page.get_by_role("button", name="Wheel over this row")
        row.hover()
        before = row.evaluate("n => parseFloat(n.style.top)")
        row.evaluate("n => n.addEventListener('wheel', e => e.stopPropagation())")
        self.page.mouse.wheel(0, 30)
        self.page.wait_for_function("""before => parseFloat(
            document.querySelector('#scroll-host button').style.top)<before""", arg=before)
        self.assertEqual(self.number(
            '(round (cdr (gethash :outer (lui.frame::context-scroll (lui.web::web-app-context *scroll-test-app*)))))'), 30)
        self.assertEqual(self.number(
            '(round (cdr (gethash :inner (lui.frame::context-scroll (lui.web::web-app-context *scroll-test-app*)))))'), 0)
        self.lisp('(lui.web:unmount *scroll-test-app*)')
        prevented = self.page.locator("#scroll-host").evaluate("""n => {
            const event = new WheelEvent('wheel', {bubbles:true, cancelable:true});
            n.dispatchEvent(event); return event.defaultPrevented;
        }""")
        self.assertFalse(prevented)
        expect(self.page.locator("#scroll-host > *")).to_have_count(0)

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
        self.assertLess(second.evaluate(
            "n => parseFloat(getComputedStyle(n).outlineOffset)"), 0)
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


    def test_rejected_native_changes_restore_model(self):
        self.lisp('''
          (defvar *reject-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *reject-host* "id") #j"reject-host"
                (jscl/ffi:oget *reject-host* "style" "width") #j"500px"
                (jscl/ffi:oget *reject-host* "style" "height") #j"250px")
          (#j:document:body:appendChild *reject-host*)
          (defvar *reject-app*
            (lui.web:mount *reject-host*
              (lambda ()
                (lui.frame:column (:width (lui.layout:grow))
                  (lui.widgets:declare-widget :text-field :glass
                    :reject-text "" :value "Fixed")
                  (lui.widgets:declare-widget :checkbox :motif
                    :reject-check "Reject check" :value nil)
                  (lui.widgets:declare-widget :slider :glass
                    :reject-range "" :value 0.5 :width (lui.layout:grow))
                  (lui.widgets:declare-widget :slider :motif
                    :disabled-range "" :value 0.5 :disabled-p t
                    :width (lui.layout:grow))))))
        ''')
        host = self.page.locator("#reject-host")
        field = host.get_by_role("textbox")
        expect(field).to_have_value("Fixed")
        field.fill("Rejected")
        expect(field).to_have_value("Fixed")
        check = host.get_by_role("checkbox")
        check.click()
        expect(check).not_to_be_checked()
        slider = host.get_by_role("slider").first
        slider.evaluate("""n => {n.valueAsNumber = .9;
            n.dispatchEvent(new Event('input', {bubbles:true}));}""")
        expect(slider).to_have_value("0.5")
        disabled = host.get_by_role("slider").last
        self.assertEqual(disabled.evaluate(
            "n => getComputedStyle(n).getPropertyValue('--lui-accent')"),
            "#999999")
        self.lisp('(lui.web:unmount *reject-app*)')

    def test_checkbox_theme_keyboard_and_disabled_cursor(self):
        page = self.page
        page.get_by_role("button", name="Glass", exact=True).click()
        expect(page.get_by_role("button", name="Motif", exact=True)).to_be_visible()
        check = page.get_by_role("checkbox", name="Enabled", exact=True)
        expect(check).to_be_checked()
        self.assertEqual(check.evaluate("n => getComputedStyle(n).appearance"), "none")
        self.assertEqual(check.evaluate("n => getComputedStyle(n.parentNode).borderStyle"), "none")
        self.assertEqual(check.evaluate("n => getComputedStyle(n).borderTopStyle"), "inset")
        check.focus()
        check.press("Enter")
        expect(check).not_to_be_checked()
        check.press("Space")
        expect(check).to_be_checked()
        check.hover()
        self.frames()
        # The live FPS label can resize the page during the first hover frame.
        check.hover()
        page.wait_for_function("""() => getComputedStyle(
            document.querySelector('.lui-motif-check input')).filter === 'brightness(1.2)'""")
        disabled = page.get_by_role("button", name="Disabled", exact=True)
        expect(disabled).to_be_disabled()
        disabled.hover(force=True)
        self.assertEqual(disabled.evaluate("n => getComputedStyle(n).cursor"), "not-allowed")
        self.assertEqual(disabled.evaluate(
            "n => [getComputedStyle(n).opacity,getComputedStyle(n).color]"),
            ["1", "rgb(119, 119, 119)"])
        button = page.get_by_role("button", name="Say hello", exact=True)
        button.hover()
        self.assertEqual(button.evaluate("n => getComputedStyle(n).opacity"), "1")
        button.focus()
        button.press("Space")
        expect(page.locator("div").filter(has_text="Hello Common Lisp (1)").last).to_be_visible()
        button.press("Enter")
        expect(page.locator("div").filter(has_text="Hello Common Lisp (2)").last).to_be_visible()
        field = page.get_by_role("textbox")
        field.focus()
        field.press("End")
        field.press("Space")
        expect(field).to_have_value("Common Lisp ")


if __name__ == "__main__":
    unittest.main(verbosity=2)
