"""Native HTML integration tests. Build first with scripts/build-web.lisp.

Run: python tests/web.py (requires Playwright and Chromium).
"""

import functools
import http.server
import re
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
            lui.frame:*context* lui.frame:*parent* lui:*unit*
            lui::*toolkit* lui::*toolkit-definition*))`);}""")

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

    def test_gallery_pages_persist_inputs_and_switch_toolkit(self):
        tabs = self.page.get_by_role("tab")
        expect(tabs).to_have_count(6)
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
        self.page.get_by_role("button", name="Cycle toolkit", exact=True).click()
        expect(self.page.get_by_text("Toolkit: Motif", exact=True).filter(visible=True)).to_be_visible()
        self.assertEqual(self.page.locator("main").evaluate(
            "n => [getComputedStyle(n).backgroundImage,getComputedStyle(n).backgroundColor]"),
            ["none", "rgb(184, 184, 184)"])
        self.assertTrue(self.page.locator("main button").evaluate_all(
            "nodes => nodes.every(n => getComputedStyle(n).borderTopLeftRadius === '0px')"))
        self.page.get_by_role("tab", name="Editing", exact=True).click()
        expect(self.page.get_by_role("textbox")).to_have_value("Persistent editor")
        self.page.get_by_role("button", name="Cycle toolkit", exact=True).click()
        expect(self.page.get_by_text("Toolkit: Garnet", exact=True).filter(visible=True)).to_be_visible()
        expect(self.page.get_by_role("textbox")).to_have_value("Persistent editor")
        self.assertEqual(self.page.locator("main").evaluate(
            "n => getComputedStyle(n).backgroundColor"), "rgb(255, 255, 255)")
        self.assertTrue(self.page.locator("main button").evaluate_all(
            "nodes => nodes.every(n => n.dataset.luiStyle === 'garnet' && getComputedStyle(n).fontWeight === '700')"))
        self.page.get_by_role("button", name="Cycle toolkit", exact=True).click()
        expect(self.page.get_by_text("Toolkit: Glass", exact=True).filter(visible=True)).to_be_visible()
        expect(self.page.get_by_role("textbox")).to_have_value("Persistent editor")
        expect(self.page.locator("canvas")).to_have_count(0)

    def test_native_shift_tab_order_and_stable_label_measurement(self):
        name = self.page.get_by_role("textbox")
        name.focus()
        name.press("Shift+Tab")
        expect(self.page.get_by_role("tab", name="Controls", exact=True)).to_be_focused()
        self.page.keyboard.press("Shift+Tab")
        expect(self.page.get_by_role("button", name="Show debugger", exact=True)).to_be_focused()
        self.page.keyboard.press("Shift+Tab")
        expect(self.page.get_by_role("button", name="Cycle toolkit", exact=True)).to_be_focused()
        self.page.keyboard.press("Tab")
        expect(self.page.get_by_role("button", name="Show debugger", exact=True)).to_be_focused()
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
            document.querySelector('#scroll-host button').style.top)<=before-29.99""", arg=before)
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
        self.assertEqual(self.number('(length (lui.web::web-app-listeners *web-test-app*))'), 4)
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
        self.assertEqual(self.number('(length (lui.web::web-app-listeners *web-test-app*))'), 8)
        self.lisp('(lui.web:refresh *web-test-app*) (lui.web:unmount *web-test-app*)')
        self.frames()
        expect(self.page.locator("#test-host > *")).to_have_count(0)
        self.assertEqual(self.number('(length (lui.web::web-app-listeners *web-test-app*))'), 0)
        draws = self.number('*web-test-draws*')
        self.page.locator("#test-host").evaluate("node => {node.style.width = '250px'; node.dispatchEvent(new WheelEvent('wheel', {deltaY:20}));}")
        self.page.evaluate("""() => {
            window.dispatchEvent(new Event('resize'));
            window.dispatchEvent(new Event('blur'));
        }""")
        self.frames()
        self.assertEqual(self.number('*web-test-draws*'), draws)
        self.lisp('(lui.web:unmount *web-test-app*)')


    def test_debugger_splitter_drag_keyboard_persistence_and_clamp(self):
        page = self.page
        page.get_by_role("button", name="Show debugger", exact=True).click()
        rail = page.get_by_role("separator", name="Debugger width")
        expect(rail).to_have_attribute("aria-orientation", "vertical")
        expect(rail).to_have_attribute("tabindex", "0")
        expect(rail).to_have_css("cursor", "ew-resize")
        before = float(rail.get_attribute("aria-valuenow"))
        rail.focus()
        rail.press("ArrowLeft")
        page.wait_for_function("""before => Number(document.querySelector(
            '[role=separator]').getAttribute('aria-valuenow')) > before""", arg=before)
        rail.press("ArrowRight")
        self.frames()
        self.assertAlmostEqual(float(rail.get_attribute("aria-valuenow")), before)
        rail.press("Home")
        page.wait_for_function("""() => Math.abs(Number(document.querySelector(
            '[role=separator]').getAttribute('aria-valuenow')) - 200/900) < .001""")
        rail.press("End")
        page.wait_for_function("""() => Math.abs(Number(document.querySelector(
            '[role=separator]').getAttribute('aria-valuenow')) - 804/900) < .001""")
        box = rail.bounding_box()
        page.mouse.move(box["x"] + box["width"] / 2, 100)
        page.mouse.down()
        self.frames()
        self.assertAlmostEqual(float(rail.get_attribute("aria-valuenow")), 804/900)
        page.mouse.move(400, 100, steps=8)
        page.wait_for_function("""() => Number(document.querySelector(
            '[role=separator]').getAttribute('aria-valuenow')) < .7""")
        # Continue the captured drag onto an app button, then release there.
        app_button = page.get_by_role("button", name="Say hello", exact=True).bounding_box()
        page.mouse.move(app_button["x"] + app_button["width"] / 2,
                        app_button["y"] + app_button["height"] / 2, steps=8)
        page.mouse.up()
        self.frames()
        expect(rail).to_be_focused()
        expect(page.get_by_text("Hello Common Lisp (0)", exact=True).filter(visible=True)).to_be_visible()
        width = float(rail.get_attribute("aria-valuenow"))
        page.get_by_role("button", name="Close", exact=True).click()
        expect(rail).to_have_count(0)
        page.get_by_role("button", name="Show debugger", exact=True).click()
        expect(rail).to_be_visible()
        self.assertAlmostEqual(float(rail.get_attribute("aria-valuenow")), width)
        page.set_viewport_size({"width": 320, "height": 480})
        page.wait_for_function("""() => Math.abs(Number(document.querySelector(
            '[role=separator]').getAttribute('aria-valuenow')) - .7) < .001""")
        close = page.get_by_role("button", name="Close", exact=True)
        expect(close).to_be_visible()
        box = close.bounding_box()
        self.assertLessEqual(box["x"] + box["width"], 320)
        close.click()
        expect(rail).to_have_count(0)

    def test_debugger_tree_select_collapse_highlight_and_close(self):
        page = self.page
        page.get_by_role("button", name="Show debugger", exact=True).click()
        expect(page.get_by_text("Layout debugger", exact=True).filter(visible=True)).to_be_visible()
        options = page.get_by_role("option").filter(has_not_text=re.compile(r"^[+-]$"))
        expect(options.first).to_be_visible()
        self.assertGreater(options.count(), 1)
        options.first.hover()
        expect(page.locator(".lui-highlight")).to_have_count(1)
        expect(page.locator(".lui-highlight")).to_have_css("pointer-events", "none")
        options.first.click()
        expect(options.first).to_have_attribute("aria-selected", "true")
        expect(page.get_by_text("Geometry", exact=True).filter(visible=True)).to_be_visible()
        expect(page.get_by_role("option", name="Layout debugger", exact=True)).to_have_count(0)
        page.get_by_role("option", name="-", exact=True).first.click()
        expect(options).to_have_count(1)
        page.get_by_role("option", name="+", exact=True).click()
        expect(options).not_to_have_count(1)
        page.get_by_role("tab", name="Controls", exact=True).focus()
        page.keyboard.press("ArrowRight")
        expect(page.get_by_role("tab", name="Editing", exact=True)).to_have_attribute("aria-selected", "true")
        expect(page.get_by_text("Layout debugger", exact=True).filter(visible=True)).to_be_visible()
        page.get_by_role("button", name="Close", exact=True).click()
        expect(page.get_by_text("Layout debugger", exact=True).filter(visible=True)).to_have_count(0)
        expect(page.locator(".lui-highlight")).to_have_count(0)
        page.get_by_role("tab", name="Controls", exact=True).click()
        page.get_by_role("button", name="Say hello", exact=True).click()
        expect(page.get_by_text("Hello Common Lisp (1)", exact=True).filter(visible=True)).to_be_visible()

    def test_debugger_divider_lost_release_and_capture(self):
        self.page.set_viewport_size({"width": 1100, "height": 900})
        self.lisp('''
          (defvar *capture-state*
            (lui.debug:make-state :open-p t :selected '(:id :target)))
          (defvar *capture-activations* 0)
          (defvar *capture-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *capture-host* "id") #j"capture-fixture"
                (jscl/ffi:oget *capture-host* "style" "width") #j"800px"
                (jscl/ffi:oget *capture-host* "style" "height") #j"520px")
          (#j:document:body:appendChild *capture-host*)
          (defvar *capture-app*
            (lui.web:mount *capture-host*
              (let ((first t))
                (lambda ()
                  (when first
                    (setf first nil)
                    (lui.debug:set-enabled t :state *capture-state*))
                  (when (lui.frame:activated-p
                         '(:lui.debug :details-resize nil))
                    (incf *capture-activations*))
                  (lui:button :target "Outside action"))))))
        ''')
        host = self.page.locator("#capture-fixture")
        divider = host.get_by_role("separator", name="Properties height")
        expect(divider).to_be_visible()
        divider.evaluate("""node => node.addEventListener('pointerdown',
            event => { window.capturePointer = event.pointerId; })""")

        def value():
            return float(divider.get_attribute("aria-valuenow"))

        def active():
            return self.number('''(if (lui.frame:context-active
              (lui.web::web-app-context *capture-app*)) 1 0)''')

        def start():
            divider.scroll_into_view_if_needed()
            box = divider.bounding_box()
            self.page.mouse.move(box["x"] + box["width"] / 2,
                                 box["y"] + box["height"] / 2)
            self.page.mouse.down()
            # Process pending pointer capture before testing real capture loss.
            self.page.mouse.move(box["x"] + box["width"] / 2 + 1,
                                 box["y"] + box["height"] / 2)
            self.frames()
            self.assertEqual(active(), 1)
            return box

        def cancelled():
            self.frames()
            self.assertEqual(active(), 0)
            self.assertFalse(divider.evaluate(
                "n => n.hasPointerCapture(window.capturePointer)"))
            old = value()
            # A later unpressed motion must not keep changing the divider.
            divider.evaluate("""n => n.dispatchEvent(new PointerEvent(
                'pointermove', {bubbles: true, buttons: 0,
                pointerId: window.capturePointer, clientX: 650,
                clientY: n.getBoundingClientRect().y - 20}))""")
            self.frames()
            self.assertEqual(value(), old)
            self.assertEqual(self.number("*capture-activations*"), 0)
            self.page.mouse.up()
            self.frames()
            self.assertEqual(self.number("*capture-activations*"), 0)

        # A missing pointerup is repaired by physical buttons=0 on motion.
        start()
        divider.evaluate("""n => n.dispatchEvent(new PointerEvent(
            'pointermove', {bubbles: true, buttons: 0,
            pointerId: window.capturePointer, clientX: 650,
            clientY: n.getBoundingClientRect().y}))""")
        cancelled()

        start()
        divider.evaluate("""n => n.dispatchEvent(new PointerEvent(
            'pointercancel', {bubbles: true, buttons: 0,
            pointerId: window.capturePointer}))""")
        cancelled()

        # Exercise the browser's actual lostpointercapture event.
        start()
        divider.evaluate("n => n.releasePointerCapture(window.capturePointer)")
        self.page.mouse.move(650, divider.bounding_box()["y"] - 2)
        cancelled()

        start()
        self.page.evaluate("window.dispatchEvent(new Event('blur'))")
        cancelled()

        # Leave/reenter with no button down must not resurrect a drag.
        start()
        divider.evaluate("""n => {
            const host = n.closest('#capture-fixture');
            for (const type of ['pointerleave', 'pointerenter'])
                host.dispatchEvent(new PointerEvent(type, {buttons: 0,
                    pointerId: window.capturePointer}));
        }""")
        cancelled()

        # Cancellation must leave the next real drag fully usable.
        box = start()
        old = value()
        self.page.mouse.move(box["x"] + box["width"] / 2, box["y"] - 20)
        self.frames()
        self.assertGreater(value(), old)
        self.page.mouse.up()
        self.frames()
        self.assertEqual(active(), 0)

    def test_motif_debugger_divider_drag_keyboard_and_close(self):
        self.page.set_viewport_size({"width": 1100, "height": 900})
        self.lisp('''
          (defvar *debugger-row-picked* nil)
          (defvar *debugger-row-clicks* 0)
          (defvar *debugger-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *debugger-host* "id") #j"debugger-fixture"
                (jscl/ffi:oget *debugger-host* "style" "width") #j"800px"
                (jscl/ffi:oget *debugger-host* "style" "height") #j"520px")
          (#j:document:body:appendChild *debugger-host*)
          (defvar *debugger-app*
            (lui.web:mount *debugger-host*
              (let ((first t))
                (lambda ()
                  (when first
                    (setf first nil)
                    (lui.debug:set-enabled t :toolkit :motif))
                  (lui:with-toolkit (:motif)
                    (lui:panel (lui:opt :id :inspected-app
                                        :width (lui.layout:grow)
                                        :height (lui.layout:grow) :padding 8)
                      (when (lui:list-item :inspected-row
                              "A Motif selected row with full content beyond forty characters"
                              (lui:opt :width (lui.layout:fixed 340)
                                       :selected-p *debugger-row-picked*))
                        (incf *debugger-row-clicks*)
                        (setf *debugger-row-picked* t))))))))
        ''')
        host = self.page.locator("#debugger-fixture")
        app_row = host.get_by_role("option", name=
            "A Motif selected row with full content beyond forty characters",
            exact=True)
        app_row.click()
        expect(app_row).to_have_attribute("aria-selected", "true")
        expect(app_row).to_have_css("background-color", "rgb(64, 80, 160)")
        expect(app_row).to_have_css("color", "rgb(255, 255, 255)")
        selected = host.get_by_role("option", name=re.compile(
            r"^:?LIST-ITEM .*INSPECTED-ROW"))
        selected.click()
        expect(selected).to_have_attribute("aria-selected", "true")
        selected.hover()
        expect(selected).to_have_css("background-color", "rgb(64, 80, 160)")
        expect(selected).to_have_css("color", "rgb(255, 255, 255)")
        expect(selected).to_have_css("border-top-style", "none")
        expect(selected).to_have_css("opacity", "1")
        host.screenshot(path=str(ROOT / "build/debugger-motif-selected.png"))
        divider = host.get_by_role("separator", name="Properties height")
        expect(divider).to_have_attribute("aria-orientation", "horizontal")
        expect(divider).to_have_attribute("tabindex", "0")
        expect(divider).to_have_css("cursor", "ns-resize")
        expect(host.get_by_role("separator", name="Debugger width")).to_have_attribute(
            "aria-orientation", "vertical")
        before = float(divider.get_attribute("aria-valuenow"))
        box, bounds = divider.bounding_box(), host.bounding_box()
        self.page.mouse.move(box["x"] + box["width"] / 2,
                             box["y"] + box["height"] / 2)
        self.page.mouse.down()
        self.page.mouse.move(bounds["x"] + 100, bounds["y"] + 20, steps=6)
        self.page.mouse.up()
        self.page.wait_for_function("""before => Number(document.querySelector(
            '#debugger-fixture [aria-label="Properties height"]')
                .getAttribute('aria-valuenow')) > before""", arg=before)
        self.assertEqual(self.number('*debugger-row-clicks*'), 1)
        expect(divider).to_be_focused()
        grown = float(divider.get_attribute("aria-valuenow"))
        divider.press("ArrowDown")
        self.page.wait_for_function("""before => Number(document.querySelector(
            '#debugger-fixture [aria-label="Properties height"]')
                .getAttribute('aria-valuenow')) < before""", arg=grown)
        shrunk = float(divider.get_attribute("aria-valuenow"))
        divider.press("ArrowUp")
        self.page.wait_for_function("""before => Number(document.querySelector(
            '#debugger-fixture [aria-label="Properties height"]')
                .getAttribute('aria-valuenow')) > before""", arg=shrunk)
        divider.press("ArrowDown")
        divider.press("Home")
        self.page.wait_for_function("""before => Number(document.querySelector(
            '#debugger-fixture [aria-label="Properties height"]')
                .getAttribute('aria-valuenow')) > before""", arg=shrunk)
        self.assertLessEqual(float(divider.get_attribute("aria-valuenow")), 1)
        close = host.get_by_role("button", name="Close", exact=True)
        self.assertTrue(close.evaluate("""node => {
            const range = document.createRange();
            range.selectNodeContents(node);
            const css = getComputedStyle(node);
            return range.getBoundingClientRect().height +
                parseFloat(css.paddingTop) + parseFloat(css.paddingBottom) +
                parseFloat(css.borderTopWidth) + parseFloat(css.borderBottomWidth)
                <= node.getBoundingClientRect().height + 1;
        }"""), "Maximized properties clipped the debugger Close button")
        close_details = host.get_by_role("button", name="Close details", exact=True)
        expect(close_details).to_have_text("×")
        expect(close_details).to_have_attribute("aria-label", "Close details")
        geometry = host.get_by_text("Geometry", exact=True).filter(visible=True)
        expect(geometry).to_be_visible()
        bar = host.get_by_role("scrollbar").last
        expect(bar).to_be_visible()
        self.assertGreater(float(bar.get_attribute("aria-valuemax")), 0)
        bar.press("Home")
        expect(bar).to_have_attribute("aria-valuenow", "0")
        labels_fit = host.evaluate("""host => [...host.querySelectorAll(
            'div[data-lui-style][data-lui-interactive=false]')].filter(node =>
                node.textContent && node.getBoundingClientRect().height > 0
                && !node.hasAttribute('role')).every(node => {
                    const range = document.createRange();
                    range.selectNodeContents(node);
                    return range.getBoundingClientRect().height <=
                        node.getBoundingClientRect().height + 1;
                })""")
        self.assertTrue(labels_fit, "Debugger property labels are clipped vertically")
        host.screenshot(path=str(ROOT / "build/debugger-motif-details.png"))
        bar.press("End")
        self.page.wait_for_function("""() => {
            const bar = [...document.querySelectorAll('#debugger-fixture [role=scrollbar]')].at(-1);
            return bar.getAttribute('aria-valuenow') === bar.getAttribute('aria-valuemax');
        }""")
        expect(host.get_by_text("Input", exact=True).filter(visible=True)).to_be_visible()
        self.assertTrue(host.evaluate("""host => [...host.querySelectorAll(
            'div[data-lui-style][data-lui-interactive=false]:not([role])')]
            .some(n => n.textContent.includes(
                'A Motif selected row with full content beyond forty characters'))"""))
        host.screenshot(path=str(ROOT / "build/debugger-motif-details-bottom.png"))
        for _ in range(10):
            divider.press("ArrowDown")
        expect(selected).to_be_visible()
        expect(selected).to_have_attribute("aria-selected", "true")
        selected.click()
        expect(selected).to_have_attribute("aria-selected", "false")
        expect(divider).to_have_count(0)
        expect(geometry).to_have_count(0)
        selected.click()
        expect(divider).to_be_visible()
        divider.press("End")
        expect(divider).to_have_count(0)
        expect(selected).to_have_attribute("aria-selected", "false")
        selected.click()
        expect(divider).to_be_visible()
        box, bounds = divider.bounding_box(), host.bounding_box()
        self.page.mouse.move(box["x"] + box["width"] / 2,
                             box["y"] + box["height"] / 2)
        self.page.mouse.down()
        self.page.mouse.move(box["x"] + box["width"] / 2,
                             bounds["y"] + bounds["height"] + 20, steps=8)
        self.page.mouse.up()
        expect(divider).to_have_count(0)
        expect(selected).to_have_attribute("aria-selected", "false")
        selected.click()
        expect(divider).to_be_visible()
        host.evaluate("node => {node.style.width = '360px';}")
        self.page.wait_for_function("""() => Math.abs(Number(
            document.querySelector('#debugger-fixture [aria-label="Debugger width"]')
                .getAttribute('aria-valuenow')) - 200/360) < .001""")
        close_details = host.get_by_role("button", name="Close details", exact=True)
        expect(close_details).to_be_visible()
        close_box, host_box = close_details.bounding_box(), host.bounding_box()
        self.assertLessEqual(close_box["x"] + close_box["width"],
                             host_box["x"] + host_box["width"])
        host.screenshot(path=str(ROOT / "build/debugger-motif-details-narrow.png"))
        close_details.press("Space")
        expect(divider).to_have_count(0)
        expect(selected).to_be_visible()
        expect(selected).to_have_attribute("aria-selected", "false")
        expect(host.get_by_text("Layout debugger", exact=True)
               .filter(visible=True)).to_be_visible()
        host.get_by_role("button", name="Close", exact=True).click()
        expect(divider).to_have_count(0)
        self.lisp('(lui.web:unmount *debugger-app*)')

    def test_debugger_narrow_style_close_and_disclosures(self):
        page = self.page
        page.set_viewport_size({"width": 320, "height": 480})
        previous = None
        for toolkit in ("Glass", "Motif", "Garnet"):
            if previous:
                page.get_by_role("button", name="Cycle toolkit", exact=True).click()
                expect(page.get_by_text("Toolkit: " + toolkit, exact=True).filter(visible=True)).to_be_visible()
            page.get_by_role("button", name="Show debugger", exact=True).click()
            close = page.get_by_role("button", name="Close", exact=True)
            expect(close).to_be_visible()
            box = close.bounding_box()
            self.assertGreaterEqual(box["x"], 0)
            self.assertGreaterEqual(box["y"], 0)
            self.assertLessEqual(box["x"] + box["width"], 320)
            self.assertLessEqual(box["y"] + box["height"], 480)
            minus = page.get_by_role("option", name="-", exact=True).first
            label_inside = """node => {
                const range = document.createRange();
                range.selectNodeContents(node);
                const text = range.getBoundingClientRect();
                const box = node.getBoundingClientRect();
                return text.left >= box.left && text.right <= box.right;
            }"""
            self.assertTrue(minus.evaluate(label_inside))
            minus.click()
            expect(page.get_by_role("option").filter(has_not_text=re.compile(r"^[+-]$"))).to_have_count(1)
            plus = page.get_by_role("option", name="+", exact=True)
            expect(plus).to_be_visible()
            self.assertGreaterEqual(plus.bounding_box()["width"], 20)
            self.assertTrue(plus.evaluate(label_inside))
            plus.click()
            close.click()
            expect(page.get_by_role("option")).to_have_count(0)
            previous = toolkit

    def test_highlight_overlay_preserves_pointer_and_text_selection(self):
        self.lisp('''
          (defvar *highlight-style* :glass)
          (defvar *highlight-opacity* 0.18)
          (defvar *highlight-clicks* 0)
          (defvar *highlight-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *highlight-host* "id") #j"highlight-host"
                (jscl/ffi:oget *highlight-host* "style" "width") #j"500px"
                (jscl/ffi:oget *highlight-host* "style" "height") #j"150px")
          (#j:document:body:appendChild *highlight-host*)
          (defvar *highlight-app*
            (lui.web:mount *highlight-host*
              (lambda ()
                (lui.frame:column (:gap 8)
                  (when (lui.glass:button :underlay "Under the overlay")
                    (incf *highlight-clicks*))
                  (lui.glass:label "Selectable beneath highlight")
                  (lui.frame:emit
                    (lui.layout:make-element :id :highlight
                      :floating-p t :interactive-p nil
                      :width (lui.layout:fixed 500)
                      :height (lui.layout:fixed 150)
                      :content (lui.widgets:make-widget :kind :highlight
                        :style *highlight-style* :background "#ffb347"
                        :accent "#ff8c00" :opacity *highlight-opacity*))))))))
        ''')
        host = self.page.locator("#highlight-host")
        overlay = host.locator(".lui-highlight")
        button = host.get_by_role("button", name="Under the overlay")
        expect(overlay).to_have_attribute("aria-hidden", "true")
        self.assertIsNone(overlay.get_attribute("tabindex"))
        for toolkit in ("glass", "motif", "garnet"):
            self.lisp(f'''(setf *highlight-style* :{toolkit})
                (lui.web:refresh *highlight-app*)''')
            expect(overlay).to_have_attribute("data-lui-style", toolkit)
            expect(overlay).to_have_css("pointer-events", "none")
            expect(overlay).to_have_css("border-top-width", "1px")
            expect(overlay).to_have_css("border-top-color", "rgb(255, 140, 0)")
            expect(overlay).to_have_css("border-radius", "0px")
            expect(overlay).to_have_css("box-shadow", "none")
            expect(overlay).to_have_css("background-image", "none")
            button.click()
        self.page.wait_for_function("jscl.evaluateString('*highlight-clicks*') === 3")
        button.focus()
        overlay.evaluate("node => node.focus()")
        expect(button).to_be_focused()
        label = host.get_by_text("Selectable beneath highlight", exact=True).filter(visible=True)
        label.scroll_into_view_if_needed()
        box = label.bounding_box()
        self.page.mouse.move(box["x"] + 1, box["y"] + box["height"] / 2)
        self.page.mouse.down()
        self.page.mouse.move(box["x"] + box["width"] - 1,
                             box["y"] + box["height"] / 2, steps=8)
        self.page.mouse.up()
        self.assertIn("Selectable beneath", self.page.evaluate("getSelection().toString()"))
        self.lisp('''(setf *highlight-opacity* 0)
          (lui.web:refresh *highlight-app*)''')
        self.page.wait_for_function("""() => getComputedStyle(document.querySelector(
            '#highlight-host .lui-highlight')).backgroundColor.endsWith('/ 0)')""")
        expect(overlay).to_have_css("border-top-color", "rgb(255, 140, 0)")
        self.lisp('(lui.web:unmount *highlight-app*)')
        expect(host.locator(".lui-highlight")).to_have_count(0)

    def test_crud_options_selection_keyboard_and_fields(self):
        self.page.get_by_role("tab", name="7GUIs", exact=True).click()
        self.page.get_by_role("tab", name="CRUD", exact=True).click()
        expect(self.page.get_by_role("listbox")).to_have_count(1)
        options = self.page.get_by_role("option")
        expect(options).to_have_count(3)
        options.first.click()
        expect(options.first).to_have_attribute("aria-selected", "true")
        expect(self.page.locator('[role=option][aria-selected=true]')).to_have_count(1)
        expect(self.page.get_by_role("textbox").nth(1)).to_have_value("Hans")
        expect(self.page.get_by_role("textbox").nth(2)).to_have_value("Emil")
        expect(options.first).to_be_focused()
        options.first.press("ArrowDown")
        expect(options.nth(1)).to_have_attribute("aria-selected", "true")
        expect(self.page.locator('[role=option][aria-selected=true]')).to_have_count(1)
        expect(self.page.get_by_role("textbox").nth(1)).to_have_value("Max")
        expect(self.page.get_by_role("textbox").nth(2)).to_have_value("Mustermann")
        expect(options.nth(1)).to_be_focused()
        options.nth(1).press("End")
        expect(options.last).to_have_attribute("aria-selected", "true")
        expect(self.page.get_by_role("textbox").nth(1)).to_have_value("Roman")
        expect(options.last).to_have_css("border-top-style", "none")
        self.page.screenshot(path=str(ROOT / "build/seven-crud.png"))

    def open_seven(self, name):
        self.page.get_by_role("tab", name="7GUIs", exact=True).click()
        self.page.get_by_role("tab", name=name, exact=True).click()
        self.frames()

    def cell(self, index):
        # Read existing DOM identities; all interactions still use the browser.
        self.page.locator("main [data-lui-interactive]").evaluate_all("""nodes => {
            window.testCellIndex ??= jscl.evaluateString(`(lambda (id)
                (if (and (consp id) (eq (first id) :seven-cell))
                    (second id) -1))`);
            for (const node of nodes) {
                const index = window.testCellIndex(node.luiId);
                if (index >= 0) node.dataset.testCell = index;
            }
        }""")
        return self.page.locator(f'[data-test-cell="{index}"]')

    def test_seven_temperature_flight_validation_and_booking(self):
        self.open_seven("Temperature")
        fields = self.page.get_by_role("textbox")
        fields.first.fill("100")
        expect(fields.nth(1)).to_have_value("212")
        fields.first.fill("invalid")
        expect(fields.nth(1)).to_have_value("212")
        expect(fields.first).to_have_css("background-color", "color(srgb 0.658824 0.196078 0.196078 / 0.35)")
        fields.nth(1).fill("32")
        expect(fields.first).to_have_value("0")
        self.page.get_by_role("tab", name="Flight", exact=True).click()
        fields = self.page.get_by_role("textbox")
        expect(fields.nth(1)).to_be_disabled()
        book = self.page.get_by_role("button", name="Book", exact=True)
        fields.first.fill("31.02.2024")
        expect(book).to_be_disabled()
        fields.first.fill("02.01.2024")
        expect(book).to_be_enabled()
        self.page.get_by_role("tab", name="Return flight", exact=True).click()
        expect(fields.nth(1)).to_be_enabled()
        fields.nth(1).fill("01.01.2024")
        expect(book).to_be_disabled()
        fields.nth(1).fill("03.01.2024")
        expect(book).to_be_enabled()
        book.click()
        expect(self.page.get_by_text(
            "Booked return flight: 02.01.2024 to 03.01.2024.", exact=True)
            .filter(visible=True)).to_be_visible()

    def test_seven_circle_modal_preview_cancel_apply_undo_redo(self):
        self.page.get_by_role("button", name="Cycle toolkit", exact=True).click()
        self.open_seven("Circles")
        canvas = self.page.locator("main svg")
        expect(canvas).to_be_visible()
        expect(self.page.get_by_role("button", name="Undo", exact=True)).to_be_disabled()
        canvas.click(position={"x": 80, "y": 70})
        expect(canvas.locator("circle")).to_have_count(1)
        expect(canvas.locator("circle")).to_have_attribute("r", "20px")
        canvas.hover(position={"x": 80, "y": 70})
        expect(canvas.locator("circle")).to_have_attribute("fill", "#c8c8c8")
        canvas.click(position={"x": 200, "y": 70})
        expect(canvas.locator("circle")).to_have_count(2)
        canvas.click(position={"x": 80, "y": 70}, button="right")
        slider = self.page.get_by_role("slider")
        expect(slider).to_be_visible()
        expect(slider).to_be_focused()
        expect(self.page.get_by_role("tab", name="Cells", exact=True)).to_be_disabled()
        expect(self.page.get_by_role("tab", name="Controls", exact=True)).to_be_disabled()
        expect(self.page.get_by_role("button", name="Undo", exact=True)).to_be_disabled()
        slider.press("End")
        expect(canvas.locator("circle").first).to_have_attribute("r", "80px")
        self.page.screenshot(path=str(ROOT / "build/seven-circle-dialog.png"))
        slider.press("Escape")
        expect(slider).to_have_count(0)
        expect(canvas.locator("circle").first).to_have_attribute("r", "20px")
        canvas.click(position={"x": 80, "y": 70}, button="right")
        slider.press("End")
        self.page.get_by_role("button", name="Apply", exact=True).click()
        expect(slider).to_have_count(0)
        expect(canvas.locator("circle").first).to_have_attribute("r", "80px")
        self.page.get_by_role("button", name="Undo", exact=True).click()
        expect(canvas.locator("circle").first).to_have_attribute("r", "20px")
        self.page.get_by_role("button", name="Redo", exact=True).click()
        expect(canvas.locator("circle").first).to_have_attribute("r", "80px")
        canvas.click(position={"x": 80, "y": 70}, button="right")
        slider.press("Home")
        self.page.get_by_role("button", name="Cancel", exact=True).click()
        expect(canvas.locator("circle").first).to_have_attribute("r", "80px")
        expect(self.page.get_by_role("tab", name="Controls", exact=True)).to_be_enabled()

    def test_seven_cells_real_editing_dependencies_cancel_and_navigation(self):
        self.open_seven("Cells")
        self.assertLess(self.page.get_by_role("gridcell").count(), 400)
        a0 = self.cell(0)
        a0.click()
        expect(self.page.get_by_role("textbox")).to_have_count(0)
        expect(a0).to_be_focused()
        a0.press("Enter")
        editor = self.page.get_by_role("textbox")
        expect(editor).to_be_focused()
        editor.fill("2")
        editor.press("Enter")
        expect(editor).to_have_count(0)
        expect(self.cell(0)).to_have_text("2")
        self.cell(1).dblclick()
        expect(editor).to_be_focused()
        editor.fill("3")
        editor.press("Enter")
        expect(editor).to_have_count(0)
        self.cell(2).dblclick()
        expect(editor).to_be_focused()
        editor.fill("=sum(A0:B0)")
        editor.press("Enter")
        expect(editor).to_have_count(0)
        expect(self.cell(2)).to_have_text("5")
        self.cell(2).dblclick()
        expect(editor).to_have_value("=sum(A0:B0)")
        editor.fill("=div(1,0)")
        editor.press("Escape")
        expect(editor).to_have_count(0)
        expect(self.cell(2)).to_have_text("5")
        # Real DOM blur commits the draft before selecting another cell.
        self.cell(1).dblclick()
        editor.fill("7")
        self.cell(0).click()
        expect(editor).to_have_count(0)
        expect(self.cell(2)).to_have_text("9")
        self.cell(2).click()
        expect(self.cell(2)).to_be_focused()
        self.page.keyboard.press("ArrowRight")
        expect(self.page.get_by_text("Selected: D0", exact=True)
               .filter(visible=True)).to_be_visible()
        expect(self.cell(3)).to_be_focused()
        self.page.keyboard.press("End")
        expect(self.page.get_by_text("Selected: Z99", exact=True)
               .filter(visible=True)).to_be_visible()
        expect(self.cell(2599)).to_be_focused()
        self.page.keyboard.press("Enter")
        expect(editor).to_be_focused()
        editor.fill("=sum(A0:C0)")
        editor.press("Enter")
        expect(editor).to_have_count(0)
        expect(self.cell(2599)).to_have_text("18")
        self.page.keyboard.press("Home")
        expect(self.page.get_by_text("Selected: A0", exact=True)
               .filter(visible=True)).to_be_visible()
        expect(self.cell(0)).to_be_focused()
        self.page.keyboard.type("4")
        expect(editor).to_have_value("4")
        editor.press("Enter")
        expect(editor).to_have_count(0)
        expect(self.cell(2)).to_have_text("11")
        self.page.screenshot(path=str(ROOT / "build/seven-cells.png"))

    def test_seven_cells_flat_readable_style_across_toolkits(self):
        self.open_seven("Cells")
        for name in ("Glass", "Motif", "Garnet"):
            expect(self.page.get_by_text("Toolkit: " + name, exact=True).filter(visible=True)).to_be_visible()
            normal = self.cell(1)
            selected = self.cell(0)
            expect(normal).to_have_attribute("role", "gridcell")
            expect(normal).to_have_attribute("aria-label", "Empty cell")
            expect(normal).to_have_attribute("aria-selected", "false")
            expect(normal).to_have_css("background-color", "rgb(255, 255, 255)")
            expect(normal).to_have_css("color", "rgb(32, 36, 48)")
            expect(normal).to_have_css("border-top-width", "1px")
            expect(normal).to_have_css("border-top-style", "solid")
            expect(normal).to_have_css("box-shadow", "none")
            expect(normal).to_have_css("background-image", "none")
            expect(selected).to_have_attribute("aria-selected", "true")
            expect(selected).to_have_css("color", "rgb(32, 36, 48)")
            expect(selected).to_have_css("background-color", "rgb(231, 239, 250)")
            expect(selected).to_have_css("outline-width", "2px")
            header = self.page.get_by_text("A", exact=True).filter(visible=True)
            expect(header).to_have_css("color", "rgb(32, 36, 48)")
            normal.hover()
            expect(normal).to_have_css("background-color", "rgb(255, 255, 255)")
            self.page.screenshot(path=str(ROOT / f"build/seven-cells-{name.lower()}.png"))
            self.page.get_by_role("button", name="Cycle toolkit", exact=True).click()

    def test_seven_cells_garnet_editor_identity_colors_and_readline(self):
        self.page.get_by_role("button", name="Cycle toolkit", exact=True).click()
        self.page.get_by_role("button", name="Cycle toolkit", exact=True).click()
        self.open_seven("Cells")
        self.cell(0).dblclick()
        editor = self.page.get_by_role("textbox")
        expect(editor).to_be_focused()
        editor.evaluate("n => window.cellEditor = n")
        for text in ("alpha", " beta", " gamma"):
            self.page.keyboard.type(text)
            self.frames()
            self.assertTrue(editor.evaluate("n => n === window.cellEditor"))
            expect(editor).to_have_css("background-color", "rgb(255, 255, 255)")
            expect(editor).to_have_css("color", "rgb(0, 0, 0)")
        expect(editor).to_have_value("alpha beta gamma")
        editor.press("Control+a")
        self.assertEqual(editor.evaluate("n => n.selectionStart"), 0)
        expect(editor).to_have_value("alpha beta gamma")
        self.page.keyboard.type("!")
        expect(editor).to_have_value("!alpha beta gamma")
        editor.press("Enter")
        expect(editor).to_have_count(0)
        expect(self.cell(0)).to_have_text("!alpha beta gamma")

    def test_seven_cells_trusted_entry_latency(self):
        self.open_seven("Counter")
        self.page.evaluate("""() => {
            document.addEventListener('click', event => {
                if (event.target.closest('[role=tab]')?.textContent !== 'Cells')
                    return;
                window.cellEntry = {start:event.timeStamp,
                                    trusted:event.isTrusted, elapsed:null};
                function visibleFrame() {
                    const cell = document.querySelector(
                        '[role=gridcell]:not([disabled])');
                    if (cell && cell.getBoundingClientRect().width > 0)
                        window.cellEntry.elapsed = performance.now() - window.cellEntry.start;
                    else requestAnimationFrame(visibleFrame);
                }
                requestAnimationFrame(visibleFrame);
            }, true);
        }""")
        timings = []
        for _ in range(2):
            self.page.get_by_role("tab", name="Cells", exact=True).click()
            self.page.wait_for_function("window.cellEntry?.elapsed !== null")
            entry = self.page.evaluate("window.cellEntry")
            self.assertTrue(entry["trusted"])
            timings.append(round(entry["elapsed"], 1))
            # Allows busy CI hosts while rejecting the former ~700ms path.
            self.assertLess(entry["elapsed"], 450, entry)
            self.page.get_by_role("tab", name="Counter", exact=True).click()
            expect(self.page.get_by_role("button", name="Count", exact=True)).to_be_visible()
        print(f"Cells trusted click-to-visible ms: cold={timings[0]}, warm={timings[1]}")

    def test_editor_enter_escape_and_native_clipboard(self):
        self.fixture()
        self.lisp('''
          (defvar *edit-keys* nil)
          (defvar *edit-original* (lui.web::web-app-callback *web-test-app*))
          (setf (lui.web::web-app-callback *web-test-app*)
            (lambda ()
              (setf *edit-keys* (append (lui.frame:events-for :fixture)
                                      *edit-keys*))
              (funcall *edit-original*)))
        ''')
        field = self.page.locator("#test-host input")
        field.press("Enter")
        self.frames()
        field.press("Escape")
        self.frames()
        self.assertEqual(self.number(
            "(count :activate *edit-keys* :key #'lui.frame:event-kind)"), 1)
        self.assertEqual(self.number('''(count-if (lambda (event)
            (and (eq :key (lui.frame:event-kind event))
                 (eq :escape (lui.frame:event-key event)))) *edit-keys*)'''), 1)
        self.page.context.grant_permissions(["clipboard-read", "clipboard-write"])
        field.evaluate("n => n.setSelectionRange(0,4)")
        field.press("Control+c")
        self.assertEqual(self.page.evaluate("navigator.clipboard.readText()"), "orig")
        expect(field).to_have_value("original")
        self.lisp('(lui.web:unmount *web-test-app*)')

    def test_seven_gui_timer_updates_progress_without_input(self):
        self.page.get_by_role("tab", name="7GUIs", exact=True).click()
        self.page.get_by_role("tab", name="Timer", exact=True).click()
        gauge = self.page.get_by_role("progressbar")
        expect(gauge).to_be_visible()
        before = float(gauge.get_attribute("aria-valuenow"))
        self.page.wait_for_function("""before => Number(document.querySelector(
            '[role=progressbar]').getAttribute('aria-valuenow')) > before + .005""",
            arg=before)
        self.page.get_by_role("slider").evaluate("""n => {
            n.value = '.2'; n.dispatchEvent(new Event('input', {bubbles:true}));
        }""")
        expect(gauge).to_have_attribute("aria-valuenow", "1")
        self.page.get_by_role("tab", name="Counter", exact=True).click()
        self.page.get_by_role("button", name="Count", exact=True).click()
        expect(self.page.get_by_text("1", exact=True).filter(visible=True)).to_be_visible()

    def test_visible_label_selection_and_native_copy_survive_refresh(self):
        self.page.context.grant_permissions(["clipboard-read", "clipboard-write"])
        label = self.page.get_by_text("Hello Common Lisp (0)", exact=True).filter(visible=True)
        label.evaluate("""node => {
            const range = document.createRange(); range.selectNodeContents(node);
            const selection = getSelection(); selection.removeAllRanges();
            selection.addRange(range);
        }""")
        self.page.evaluate("window.dispatchEvent(new Event('resize'))")
        self.frames()
        self.assertEqual(self.page.evaluate("getSelection().toString()"),
                         "Hello Common Lisp (0)")
        self.page.keyboard.press("Control+c")
        self.assertEqual(self.page.evaluate("navigator.clipboard.readText()"),
                         "Hello Common Lisp (0)")

    def test_requested_frames_deadlines_idle_and_unmount(self):
        self.lisp('''
          (defvar *clock-running* t)
          (defvar *clock-delay* 0.04)
          (defvar *clock-draws* 0)
          (defvar *clock-times* nil)
          (defvar *clock-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *clock-host* "style" "width") #j"300px"
                (jscl/ffi:oget *clock-host* "style" "height") #j"80px")
          (#j:document:body:appendChild *clock-host*)
          (defvar *clock-app*
            (lui.web:mount *clock-host*
              (lambda ()
                (incf *clock-draws*)
                (push (lui.frame:frame-time) *clock-times*)
                (lui.glass:label "Clock")
                (when *clock-running*
                  (lui.frame:request-frame *clock-delay*))))))
        ''')
        self.page.wait_for_function("""() => jscl.evaluateString(
            '*clock-draws*') >= 4""")
        self.assertGreater(self.number(
            '(- (first *clock-times*) (car (last *clock-times*)))'), 0.06)
        self.lisp('''(setf *clock-delay* 0.3)
          (lui.web:refresh *clock-app*)''')
        self.frames()
        self.lisp('''(setf *clock-running* nil)
          (dotimes (index 10) (lui.web:refresh *clock-app*))''')
        self.frames()
        stopped = self.number('*clock-draws*')
        self.page.wait_for_timeout(350)
        self.assertEqual(self.number('*clock-draws*'), stopped)
        self.assertEqual(self.number(
            '(if (lui.web::web-app-deadline-timer *clock-app*) 1 0)'), 0)
        self.lisp('''(setf *clock-running* t *clock-delay* 0.04)
          (lui.web:refresh *clock-app*)''')
        self.frames()
        self.lisp('(lui.web:unmount *clock-app*)')
        stopped = self.number('*clock-draws*')
        self.page.wait_for_timeout(100)
        self.assertEqual(self.number('*clock-draws*'), stopped)
        self.assertEqual(self.number(
            '(if (lui.web::web-app-deadline-timer *clock-app*) 1 0)'), 0)

    def test_svg_canvas_pointer_hover_secondary_doubleclick_and_gauge(self):
        self.lisp('''
          (defvar *canvas-log* nil)
          (defvar *canvas-hover* nil)
          (defvar *canvas-commands* '((:circle 50 50 20 "#000000" nil)))
          (defvar *canvas-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *canvas-host* "id") #j"canvas-host"
                (jscl/ffi:oget *canvas-host* "style" "width") #j"400px"
                (jscl/ffi:oget *canvas-host* "style" "height") #j"250px")
          (#j:document:body:appendChild *canvas-host*)
          (defvar *canvas-app*
            (lui.web:mount *canvas-host*
              (lambda ()
                (dolist (event (lui.frame:events-for :drawing))
                  (push event *canvas-log*)
                  (when (eq :move (lui.frame:event-kind event))
                    (setf *canvas-hover* (> (lui.frame:event-x event) 100))))
                (setf (sixth (first *canvas-commands*))
                      (when *canvas-hover* "#aabbcc"))
                (lui.frame:column (:gap 8)
                  (lui.garnet:canvas :drawing *canvas-commands*
                    :width (lui.layout:fixed 300)
                    :height (lui.layout:fixed 160))
                  (lui.motif:gauge :progress 0.25
                    :width (lui.layout:fixed 300)))))))
        ''')
        host = self.page.locator("#canvas-host")
        svg = host.locator("svg")
        circle = svg.locator("circle")
        expect(circle).to_have_attribute("cx", "50px")
        expect(circle).to_have_attribute("fill", "none")
        gauge = host.get_by_role("progressbar")
        expect(gauge).to_have_attribute("aria-valuenow", "0.25")
        self.assertAlmostEqual(gauge.locator("div").bounding_box()["width"],
                               (gauge.bounding_box()["width"] - 2) * .25, delta=1)
        svg.scroll_into_view_if_needed()
        box = svg.bounding_box()
        self.page.mouse.move(box["x"] + 30, box["y"] + 50)
        self.frames()
        first_moves = self.number("(count :move *canvas-log* :key #'lui.frame:event-kind)")
        self.page.mouse.move(box["x"] + 140, box["y"] + 50)
        expect(circle).to_have_attribute("fill", "#aabbcc")
        self.assertGreater(self.number(
            "(count :move *canvas-log* :key #'lui.frame:event-kind)"), first_moves)
        self.page.mouse.click(box["x"] + 50, box["y"] + 50, button="right")
        self.frames()
        self.assertGreater(self.number('''(count-if (lambda (event)
            (and (eq :press (lui.frame:event-kind event))
                 (eq :secondary (lui.frame:event-button event)))) *canvas-log*)'''), 0)
        self.page.mouse.dblclick(box["x"] + 60, box["y"] + 60)
        self.frames()
        self.assertGreater(self.number('''(count-if (lambda (event)
            (and (eq :press (lui.frame:event-kind event))
                 (= 2 (lui.frame:event-clicks event)))) *canvas-log*)'''), 0)
        self.page.mouse.move(box["x"] + 70, box["y"] + 70)
        self.page.mouse.down()
        self.page.mouse.move(box["x"] + 330, box["y"] + 70)
        self.page.mouse.up()
        self.frames()
        self.assertGreater(self.number('''(count-if (lambda (event)
            (and (eq :move (lui.frame:event-kind event))
                 (lui.frame:event-dragging-p event))) *canvas-log*)'''), 0)
        self.lisp('(lui.web:unmount *canvas-app*)')
        expect(host.locator("svg")).to_have_count(0)

    def test_motif_scroll_clips_rows_inside_panel_padding(self):
        self.lisp('''
          (defvar *clip-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *clip-host* "id") #j"clip-host"
                (jscl/ffi:oget *clip-host* "style" "width") #j"300px"
                (jscl/ffi:oget *clip-host* "style" "height") #j"120px")
          (#j:document:body:appendChild *clip-host*)
          (defvar *clip-app*
            (lui.web:mount *clip-host*
              (lambda ()
                (lui.motif:panel (:id :viewport :width (lui.layout:grow)
                                  :height (lui.layout:grow) :padding 8
                                  :scroll-p t)
                  (dotimes (index 8)
                    (lui.motif:button index (format nil "Row ~D" index)
                      :height (lui.layout:fixed 32))))))))
        ''')
        host = self.page.locator("#clip-host")
        row = host.get_by_role("button", name="Row 0", exact=True)
        row.hover()
        self.page.mouse.wheel(0, 20)
        self.page.wait_for_function("""() => parseFloat(
            document.querySelector('#clip-host button').style.top) < 0""")
        self.assertGreaterEqual(row.evaluate("""n => parseFloat(n.style.top) +
            parseFloat(getComputedStyle(n).clipPath.slice(6))"""), 7.99)
        box = host.bounding_box()
        self.assertFalse(self.page.evaluate("""({x,y}) =>
            !!document.elementFromPoint(x,y).closest('button')""",
            {"x": box["x"] + 20, "y": box["y"] + 2}))
        self.lisp('(lui.web:unmount *clip-app*)')

    def test_scrollbar_extent_drag_keyboard_paging_and_hiding(self):
        self.lisp('''
          (defvar *scrollbar-visible* t)
          (defvar *scrollbar-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *scrollbar-host* "id") #j"scrollbar-fixture"
                (jscl/ffi:oget *scrollbar-host* "style" "width") #j"300px"
                (jscl/ffi:oget *scrollbar-host* "style" "height") #j"220px")
          (#j:document:body:appendChild *scrollbar-host*)
          (defvar *scrollbar-app*
            (lui.web:mount *scrollbar-host*
              (lambda ()
                (lui:panel (lui:opt :id :scrollbar-viewport
                                    :width (lui.layout:grow)
                                    :height (lui.layout:fixed 180)
                                    :padding 8 :scroll-p t
                                    :scrollbar-p *scrollbar-visible*)
                  (dotimes (index 20)
                    (lui:button (list :scroll-row index) "Row"
                      (lui:opt :height (lui.layout:fixed 28)
                               :width (lui.layout:grow))))))))
        ''')
        host = self.page.locator("#scrollbar-fixture")
        bar = host.get_by_role("scrollbar")
        expect(bar).to_have_attribute("aria-valuemax", "396")
        expect(bar).to_have_attribute("aria-valuenow", "0")
        self.assertTrue(bar.evaluate("n => !!document.getElementById(n.getAttribute('aria-controls'))"))
        bar.scroll_into_view_if_needed()
        track = bar.bounding_box()
        thumb = bar.locator("div").bounding_box()
        self.assertAlmostEqual(thumb["height"] + 4,
                               track["height"] * 164 / 560, delta=1)
        self.page.mouse.move(track["x"] + 5, thumb["y"] + 5)
        self.page.mouse.down()
        self.page.mouse.move(track["x"] + 50, track["y"] + track["height"] + 40)
        self.page.mouse.up()
        expect(bar).to_have_attribute("aria-valuenow", "396")
        bar.press("Home")
        expect(bar).to_have_attribute("aria-valuenow", "0")
        bar.click(position={"x": 5, "y": track["height"] - 3})
        expect(bar).to_have_attribute("aria-valuenow", "164")
        bar.press("End")
        expect(bar).to_have_attribute("aria-valuenow", "396")
        self.lisp('''
          (let ((lui.frame:*context* (lui.web::web-app-context *scrollbar-app*)))
            (lui.frame:scroll-to :scrollbar-viewport 0 33))
          (lui.web:refresh *scrollbar-app*)
        ''')
        expect(bar).to_have_attribute("aria-valuenow", "33")
        self.lisp('''
          (setf *scrollbar-visible* nil)
          (lui.web:refresh *scrollbar-app*)
        ''')
        expect(bar).to_have_count(0)
        self.lisp('(lui.web:unmount *scrollbar-app*)')

    def test_scrollbar_toolkit_appearance_and_inheritance(self):
        self.lisp('''
          (lui:register-toolkit :garnet-scroll-child :parent :garnet)
          (defvar *scroll-style* :glass)
          (defvar *scroll-style-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *scroll-style-host* "id") #j"scroll-style-host"
                (jscl/ffi:oget *scroll-style-host* "style" "width") #j"280px"
                (jscl/ffi:oget *scroll-style-host* "style" "height") #j"200px")
          (#j:document:body:appendChild *scroll-style-host*)
          (defvar *scroll-style-app*
            (lui.web:mount *scroll-style-host*
              (lambda ()
                (lui:with-toolkit (*scroll-style*)
                  (lui:panel (lui:opt :id :style-viewport
                                      :width (lui.layout:grow)
                                      :height (lui.layout:grow)
                                      :padding 8 :scroll-p t)
                    (dotimes (index 15)
                      (lui:button (list :styled-row index) "Scrollbar sample"
                        (lui:opt :width (lui.layout:grow)
                                 :height (lui.layout:fixed 30)))))))))
        ''')
        host = self.page.locator("#scroll-style-host")
        bar = host.get_by_role("scrollbar")
        thumb = bar.locator("div")
        bar.scroll_into_view_if_needed()
        self.page.mouse.move(0, 0)
        expect(bar).to_have_css("background-color", re.compile(r" / 0\.08\)"))
        expect(thumb).to_have_css("background-color", re.compile(r" / 0\.32\)"))
        expect(thumb).to_have_css("border-radius", "4px")
        self.assertAlmostEqual(thumb.bounding_box()["width"],
                               bar.bounding_box()["width"] - 4)
        bar.hover()
        expect(thumb).to_have_css("background-color", re.compile(r" / 0\.5\)"))
        host.screenshot(path=str(ROOT / "build/web-glass-scrollbar.png"))
        self.lisp('''
          (setf *scroll-style* :garnet-scroll-child)
          (lui.web:refresh *scroll-style-app*)
        ''')
        expect(bar).to_have_attribute("data-lui-surface", "garnet")
        expect(bar).to_have_css("background-image", re.compile("conic-gradient"))
        expect(thumb).to_have_css("background-color", "rgb(255, 255, 255)")
        expect(thumb).to_have_css("border-radius", "0px")
        expect(thumb).to_have_css("border-top-color", "rgb(0, 0, 0)")
        expect(thumb).to_have_css("border-top-width", "1px")
        self.assertAlmostEqual(thumb.bounding_box()["width"],
                               bar.bounding_box()["width"] - 2)
        bar.press("End")
        self.page.wait_for_function("""() => {
            const bar = document.querySelector('#scroll-style-host [role=scrollbar]');
            return bar.getAttribute('aria-valuenow') === bar.getAttribute('aria-valuemax');
        }""")
        host.screenshot(path=str(ROOT / "build/web-garnet-scrollbar.png"))
        self.lisp('''
          (lui:register-toolkit :garnet-scroll-child :parent :garnet
            :defaults '(:background "#fff1c8"))
          (lui.web:refresh *scroll-style-app*)
        ''')
        expect(thumb).to_have_css("background-color", "rgb(255, 241, 200)")
        self.lisp('''
          (setf *scroll-style* :motif)
          (lui.web:refresh *scroll-style-app*)
        ''')
        expect(bar).to_have_attribute("data-lui-surface", "motif")
        expect(bar).to_have_css("background-image", "none")
        expect(thumb).to_have_css("border-top-width", "0px")
        expect(thumb).to_have_css("border-radius", "0px")
        self.assertAlmostEqual(thumb.bounding_box()["width"],
                               bar.bounding_box()["width"])
        self.lisp('(lui.web:unmount *scroll-style-app*)')

    def test_wrapped_list_rows_fit_content_across_toolkits(self):
        self.lisp('''
          (defvar *wrap-row-toolkit* :glass)
          (defvar *wrap-row-width* 120)
          (defvar *wrap-row-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *wrap-row-host* "id") #j"wrapped-rows"
                (jscl/ffi:oget *wrap-row-host* "style" "width") #j"260px"
                (jscl/ffi:oget *wrap-row-host* "style" "height") #j"420px")
          (#j:document:body:appendChild *wrap-row-host*)
          (defvar *wrap-row-app*
            (lui.web:mount *wrap-row-host*
              (lambda ()
                (lui:with-toolkit (*wrap-row-toolkit*)
                  (lui:panel (lui:opt :width (lui.layout:fixed *wrap-row-width*)
                                      :height (lui.layout:grow) :opacity 1)
                    (dolist (text '("Controls and options"
                                    "Layout and scrolling"
                                    "Input and inspection"
                                    "Backends and running"))
                      (lui:list-item text text
                        (lui:opt :width (lui.layout:grow))))
                    (lui:list-item :fixed "Explicitly fixed clipped row"
                      (lui:opt :width (lui.layout:grow)
                               :height (lui.layout:fixed 24))))))))
        ''')
        host = self.page.locator("#wrapped-rows")
        for toolkit in ("glass", "motif", "garnet"):
            self.lisp(f'''
              (setf *wrap-row-toolkit* :{toolkit} *wrap-row-width* 120)
              (lui.web:refresh *wrap-row-app*)
            ''')
            rows = host.get_by_role("option")
            expect(rows.first).to_have_attribute("data-lui-style", toolkit)
            expect(rows.first).to_have_css("width", "120px")
            narrow_heights = []
            for row in rows.all()[:-1]:
                metrics = row.evaluate("""node => {
                    const range = document.createRange();
                    range.selectNodeContents(node);
                    const css = getComputedStyle(node);
                    return {height:node.clientHeight, scroll:node.scrollHeight,
                        text:range.getBoundingClientRect().height,
                        padding:parseFloat(css.paddingTop)+parseFloat(css.paddingBottom)};
                }""")
                self.assertLessEqual(metrics["scroll"], metrics["height"])
                self.assertLessEqual(metrics["text"] + metrics["padding"],
                                     metrics["height"] + 1)
                self.assertGreater(metrics["text"], 25)
                narrow_heights.append(metrics["height"])
            fixed = rows.last
            expect(fixed).to_have_css("height", "24px")
            self.assertTrue(fixed.evaluate("n => n.scrollHeight > n.clientHeight"))
            if toolkit == "garnet":
                host.screenshot(
                    path=str(ROOT / "build/web-wrapped-list-rows.png"))
            self.lisp('''
              (setf *wrap-row-width* 240)
              (lui.web:refresh *wrap-row-app*)
            ''')
            expect(rows.first).to_have_css("width", "240px")
            for row, narrow in zip(rows.all()[:-1], narrow_heights):
                self.assertLess(row.bounding_box()["height"], narrow)
                self.assertTrue(row.evaluate("n => n.scrollHeight <= n.clientHeight"))
            expect(fixed).to_have_css("height", "24px")
        self.lisp('(lui.web:unmount *wrap-row-app*)')

    def test_date_time_picker_calendar_and_validation(self):
        self.lisp('''
          (defvar *picker-value* "2024-02-28T12:30")
          (defvar *picker-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *picker-host* "id") #j"picker-test"
                (jscl/ffi:oget *picker-host* "style" "width") #j"400px"
                (jscl/ffi:oget *picker-host* "style" "height") #j"700px")
          (#j:document:body:appendChild *picker-host*)
          (defvar *picker-app*
            (lui.web:mount *picker-host*
              (lambda ()
                (setf *picker-value*
                      (lui:date-time-picker :pick *picker-value*
                        (lui:opt :width (lui.layout:grow)))))))
        ''')
        host = self.page.locator("#picker-test")
        field = host.get_by_role("textbox", name="Date and time")
        field.fill("2024-02-30T12:30")
        expect(host.get_by_text("Use YYYY-MM-DDTHH:MM").filter(visible=True)).to_be_visible()
        field.fill("2024-02-28T12:30")
        host.get_by_role("button", name="Choose date").click()
        host.get_by_role("tab", name="29", exact=True).click()
        expect(field).to_have_value("2024-02-29T12:30")
        hour = host.get_by_role("slider", name="Hour", exact=True)
        hour.press("Home")
        for _ in range(18):
            hour.press("ArrowRight")
        expect(field).to_have_value("2024-02-29T18:30")
        self.lisp("(lui.web:unmount *picker-app*)")

    def test_wrapped_buttons_fit_content_across_toolkits(self):
        self.lisp('''
          (defvar *wrap-button-toolkit* :glass)
          (defvar *wrap-button-width* 120)
          (defvar *wrap-button-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *wrap-button-host* "id") #j"wrapped-buttons"
                (jscl/ffi:oget *wrap-button-host* "style" "width") #j"260px"
                (jscl/ffi:oget *wrap-button-host* "style" "height") #j"420px")
          (#j:document:body:appendChild *wrap-button-host*)
          (defvar *wrap-button-app*
            (lui.web:mount *wrap-button-host*
              (lambda ()
                (lui:with-toolkit (*wrap-button-toolkit*)
                  (lui:panel (lui:opt :width (lui.layout:fixed *wrap-button-width*)
                                      :height (lui.layout:grow) :opacity 1)
                    (dolist (text '("Controls and options"
                                    "Layout and scrolling"
                                    "Input and inspection"
                                    "Backends and running"))
                      (lui:button text text
                        (lui:opt :width (lui.layout:grow))))
                    (lui:button :fixed "Explicitly fixed clipped row"
                      (lui:opt :width (lui.layout:grow)
                               :height (lui.layout:fixed 24))))))))
        ''')
        host = self.page.locator("#wrapped-buttons")
        for toolkit in ("glass", "motif", "garnet"):
            self.lisp(f'''
              (setf *wrap-button-toolkit* :{toolkit} *wrap-button-width* 120)
              (lui.web:refresh *wrap-button-app*)
            ''')
            rows = host.get_by_role("button")
            expect(rows.first).to_have_attribute("data-lui-style", toolkit)
            self.assertLessEqual(rows.first.bounding_box()["width"], 120)
            narrow_heights = []
            for row in rows.all()[:-1]:
                metrics = row.evaluate("""node => {
                    const range = document.createRange();
                    range.selectNodeContents(node);
                    const css = getComputedStyle(node);
                    return {height:node.clientHeight, scroll:node.scrollHeight,
                        text:range.getBoundingClientRect().height,
                        padding:parseFloat(css.paddingTop)+parseFloat(css.paddingBottom)};
                }""")
                self.assertLessEqual(metrics["scroll"], metrics["height"])
                self.assertLessEqual(metrics["text"] + metrics["padding"],
                                     metrics["height"] + 1)
                self.assertGreater(metrics["text"], 25)
                narrow_heights.append(metrics["height"])
            fixed = rows.last
            self.assertAlmostEqual(fixed.bounding_box()["height"],
                                   20 if toolkit == "garnet" else 24, delta=1)
            self.assertTrue(fixed.evaluate("n => n.scrollHeight > n.clientHeight"))
            if toolkit == "garnet":
                host.screenshot(
                    path=str(ROOT / "build/web-wrapped-list-rows.png"))
            self.lisp('''
              (setf *wrap-button-width* 240)
              (lui.web:refresh *wrap-button-app*)
            ''')
            expect(rows.first).to_have_css(
                "width", "236px" if toolkit == "garnet" else "240px")
            for row, narrow in zip(rows.all()[:-1], narrow_heights):
                self.assertLess(row.bounding_box()["height"], narrow)
                self.assertTrue(row.evaluate("n => n.scrollHeight <= n.clientHeight"))
            self.assertAlmostEqual(fixed.bounding_box()["height"],
                                   20 if toolkit == "garnet" else 24, delta=1)
        self.lisp('(lui.web:unmount *wrap-button-app*)')

    def test_motif_text_fields_stay_recessed_while_buttons_are_raised(self):
        self.lisp('''
          (lui:register-toolkit :motif-field-child :parent :motif)
          (defvar *motif-field-value* "Recessed editor")
          (defvar *motif-field-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *motif-field-host* "id") #j"motif-field-host"
                (jscl/ffi:oget *motif-field-host* "style" "width") #j"320px"
                (jscl/ffi:oget *motif-field-host* "style" "height") #j"120px")
          (#j:document:body:appendChild *motif-field-host*)
          (defvar *motif-field-app*
            (lui.web:mount *motif-field-host*
              (lambda ()
                (lui:with-toolkit (:motif-field-child)
                  (lui.frame:column (:width (lui.layout:grow) :gap 8)
                    (setf *motif-field-value*
                          (lui:text-field :motif-editor *motif-field-value*
                            (lui:opt :width (lui.layout:grow))))
                    (lui:button :motif-raised "Raised button"))))))
        ''')
        host = self.page.locator("#motif-field-host")
        field = host.get_by_role("textbox")
        button = host.get_by_role("button", name="Raised button")
        expect(field).to_have_attribute("data-lui-surface", "motif")
        expect(field).to_have_css("border-top-style", "inset")
        expect(field).to_have_css("border-bottom-style", "inset")
        expect(field).to_have_css("border-top-width", "2px")
        expect(field).to_have_css("border-radius", "0px")
        field.hover()
        expect(field).to_have_css("border-top-style", "inset")
        expect(field).to_have_css("filter", "none")
        field.focus()
        expect(field).to_have_css("border-top-style", "inset")
        expect(field).to_have_css("outline-style", "solid")
        expect(field).to_have_css("outline-offset", "-3px")
        field.fill("Edited Motif field")
        expect(field).to_have_value("Edited Motif field")
        field.hover()
        self.page.mouse.down()
        expect(field).to_have_css("border-top-style", "inset")
        expect(field).to_have_css("transform", "none")
        self.page.mouse.up()
        expect(button).to_have_css("border-top-style", "outset")
        button.hover()
        expect(button).to_have_css("border-top-style", "outset")
        button.focus()
        expect(button).to_have_css("border-top-style", "outset")
        field.focus()
        host.screenshot(path=str(ROOT / "build/web-motif-recessed-field.png"))
        self.lisp('(lui.web:unmount *motif-field-app*)')

    def test_custom_toolkit_styles_inherit_and_widget_hook_runs_last(self):
        self.lisp('''
          (lui:register-toolkit :web-parent :parent :motif
            :defaults '(:foreground "#112233" :background "#334455")
            :web-style (lambda (dom widget element)
              (assert (eq :button (lui.widgets:widget-kind widget)))
              (assert (typep element 'lui.layout:element))
              (setf (jscl/ffi:oget dom "dataset" "order") #j"parent"
                    (jscl/ffi:oget dom "style" "borderColor") #j"#cc0000")))
          (lui:register-toolkit :web-child :parent :web-parent
            :web-style (lambda (dom widget element)
              (declare (ignore widget element))
              (setf (jscl/ffi:oget dom "dataset" "order")
                    ((jscl/ffi:oget (jscl/ffi:oget dom "dataset" "order")
                                   "concat") #j"-child")
                    (jscl/ffi:oget dom "style" "borderWidth") #j"3px")))
          (lui:register-toolkit :web-garnet :parent :garnet)
          (defvar *widget-style*
            (lambda (dom widget element)
              (declare (ignore widget element))
              (setf (jscl/ffi:oget dom "dataset" "order")
                    ((jscl/ffi:oget (jscl/ffi:oget dom "dataset" "order")
                                   "concat") #j"-widget")
                    (jscl/ffi:oget dom "style" "color") #j"#ff0000"
                    (jscl/ffi:oget dom "style" "letterSpacing") #j"2px")))
          (defvar *custom-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *custom-host* "id") #j"custom-host"
                (jscl/ffi:oget *custom-host* "style" "width") #j"500px"
                (jscl/ffi:oget *custom-host* "style" "height") #j"120px")
          (#j:document:body:appendChild *custom-host*)
          (defvar *custom-app*
            (lui.web:mount *custom-host*
              (lambda ()
                (lui:with-toolkit (:web-child)
                  (lui:button :custom "Custom style"
                    (lui:opt :web-style *widget-style*)))
                (lui:with-toolkit (:web-garnet)
                  (lui:button :inherited "Inherited Garnet")))))
        ''')
        custom = self.page.get_by_role("button", name="Custom style")
        expect(custom).to_have_attribute("data-order", "parent-child-widget")
        expect(custom).to_have_attribute("data-lui-surface", "motif")
        expect(custom).to_have_css("border-top-style", "outset")
        expect(custom).to_have_css("border-top-width", "3px")
        expect(custom).to_have_css("border-top-color", "rgb(204, 0, 0)")
        expect(custom).to_have_css("background-color", "rgb(51, 68, 85)")
        expect(custom).to_have_css("color", "rgb(255, 0, 0)")
        self.lisp('''
          (setf (lui:toolkit-web-style :web-parent)
            (lambda (dom widget element)
              (declare (ignore widget element))
              (setf (jscl/ffi:oget dom "dataset" "order") #j"replacement"
                    (jscl/ffi:oget dom "style" "borderColor") #j"#00aa00")))
          (lui.web:refresh *custom-app*)
        ''')
        expect(custom).to_have_attribute("data-order", "replacement-child-widget")
        expect(custom).to_have_css("border-top-color", "rgb(0, 170, 0)")
        self.lisp('''(setf *widget-style* nil)
          (lui.web:refresh *custom-app*)''')
        expect(custom).to_have_attribute("data-order", "replacement-child")
        expect(custom).to_have_css("color", "rgb(17, 34, 51)")
        expect(custom).to_have_css("letter-spacing", "normal")
        inherited = self.page.get_by_role("button", name="Inherited Garnet")
        expect(inherited).to_have_attribute("data-lui-surface", "garnet")
        expect(inherited).to_have_css("border-radius", "0px")
        self.assertIn("repeating-conic-gradient", inherited.evaluate(
            "n => getComputedStyle(n).backgroundImage"))
        inherited.hover()
        self.page.mouse.down()
        try:
            self.page.wait_for_function("""() => getComputedStyle(
                document.querySelector('#custom-host button:last-child'))
                .transform === 'matrix(1, 0, 0, 1, 4, 4)'""")
        finally:
            self.page.mouse.up()
        self.lisp('(lui.web:unmount *custom-app*)')
        expect(self.page.locator("#custom-host > *")).to_have_count(0)

    def test_garnet_checkbox_pressed_face_and_stationary_shadow(self):
        self.lisp('''
          (defvar *pressed-value* t)
          (defvar *pressed-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *pressed-host* "id") #j"pressed-host"
                (jscl/ffi:oget *pressed-host* "style" "width") #j"400px"
                (jscl/ffi:oget *pressed-host* "style" "height") #j"100px"
                (jscl/ffi:oget *pressed-host* "style" "background") #j"white")
          (#j:document:body:appendChild *pressed-host*)
          (defvar *pressed-app*
            (lui.web:mount *pressed-host*
              (lambda ()
                (setf *pressed-value*
                  (lui.garnet:checkbox :pressed *pressed-value* "Press square"))))))
        ''')
        check = self.page.locator("#pressed-host input")
        label = self.page.locator("#pressed-host label span")
        check.scroll_into_view_if_needed()

        def geometry():
            return check.evaluate(r"""n => {
                const face = n.getBoundingClientRect();
                const style = getComputedStyle(n);
                const offset = style.boxShadow.match(/-?[\d.]+px/g).map(parseFloat);
                const mark = getComputedStyle(n,'::after');
                return {x:face.x,y:face.y,shadowX:face.x+offset[0],
                    shadowY:face.y+offset[1],width:face.width,height:face.height,
                    markWidth:mark.width,markHeight:mark.height,
                    centered:style.placeContent,markTransform:mark.transform};
            }""")

        def pressed_matches(rest):
            active = geometry()
            self.assertAlmostEqual(active["x"] - rest["x"], 4)
            self.assertAlmostEqual(active["y"] - rest["y"], 4)
            self.assertAlmostEqual(active["shadowX"], rest["shadowX"])
            self.assertAlmostEqual(active["shadowY"], rest["shadowY"])
            self.assertEqual((active["width"], active["height"]), (20, 20))
            self.assertEqual(active["centered"], "center")
            if check.is_checked():
                self.assertEqual((active["markWidth"], active["markHeight"]),
                                 ("10px", "10px"))
                self.assertEqual(active["markTransform"], "none")

        for target in (check, label):
            rest = geometry()
            target.hover()
            self.page.mouse.down()
            try:
                pressed_matches(rest)
            finally:
                self.page.mouse.up()
            self.frames()
            self.assertAlmostEqual(geometry()["x"], rest["x"])
            self.assertAlmostEqual(geometry()["y"], rest["y"])
        # Space holds the same face down, then activates on release.
        for checked in (True, False):
            self.lisp(f'''(setf *pressed-value* {"t" if checked else "nil"})
              (lui.web:refresh *pressed-app*)''')
            expect(check).to_be_checked(checked=checked)
            check.focus()
            rest = geometry()
            self.page.keyboard.down("Space")
            try:
                pressed_matches(rest)
            finally:
                self.page.keyboard.up("Space")
            expect(check).to_be_checked(checked=not checked)
            self.assertAlmostEqual(geometry()["x"], rest["x"])
            self.assertAlmostEqual(geometry()["y"], rest["y"])
        self.lisp('(lui.web:unmount *pressed-app*)')

    def test_garnet_monochrome_controls_and_stipple(self):
        self.lisp('''
          (defvar *garnet-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *garnet-host* "id") #j"garnet-host"
                (jscl/ffi:oget *garnet-host* "style" "width") #j"550px"
                (jscl/ffi:oget *garnet-host* "style" "height") #j"300px")
          (#j:document:body:appendChild *garnet-host*)
          (defvar *garnet-app*
            (lui.web:mount *garnet-host*
              (lambda ()
                (flet ((g (kind id text &rest options)
                         (apply #'lui.widgets:declare-widget
                           kind :garnet id text
                           (append options '(:foreground "#000000"
                             :background "#ffffff" :accent "#000000"
                             :opacity 1 :radius 0 :frost 0
                             :font-family :monospace :font-weight :bold)))))
                  (lui.frame:column (:gap 8)
                    (g :button :push "Garnet button")
                    (g :checkbox :accept "Accept" :value t)
                    (g :slider :level "Level" :value 0.5)
                    (g :text-field :input "Input" :value "Type here")
                    (g :tab :tab "Selected" :value t)))))))
        ''')
        host = self.page.locator("#garnet-host")
        button = host.get_by_role("button", name="Garnet button")
        expect(button).to_be_visible()
        expect(button).to_have_css("font-weight", "700")
        expect(button).to_have_css("border-radius", "0px")
        self.assertIn("repeating-conic-gradient", button.evaluate(
            "n => getComputedStyle(n).backgroundImage"))
        self.assertIn("4px 4px", button.evaluate(
            "n => getComputedStyle(n).boxShadow"))
        button.hover()
        self.page.mouse.down()
        self.page.wait_for_function("""() => getComputedStyle(
          document.querySelector('#garnet-host button')).transform ===
          'matrix(1, 0, 0, 1, 4, 4)'""")
        self.page.mouse.up()
        check = host.get_by_role("checkbox", name="Accept")
        expect(check).to_be_checked()
        expect(check).to_have_css("width", "20px")
        expect(check).to_have_css("appearance", "none")
        expect(check.locator("..")).to_have_css("flex-direction", "row-reverse")
        self.assertIn("linear-gradient", check.evaluate(
            "n => getComputedStyle(n,'::after').backgroundImage"))
        expect(host.get_by_role("tab", name="Selected")).to_have_css(
            "background-color", "rgb(0, 0, 0)")
        expect(host.get_by_role("textbox")).to_have_css(
            "border-top-width", "1px")
        self.lisp('(lui.web:unmount *garnet-app*)')

    def test_widget_fonts_affect_measurement_and_refresh(self):
        self.lisp('''
          (defvar *font-family* :sans-serif)
          (defvar *font-weight* :normal)
          (defvar *font-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *font-host* "id") #j"font-host"
                (jscl/ffi:oget *font-host* "style" "width") #j"500px"
                (jscl/ffi:oget *font-host* "style" "height") #j"100px")
          (#j:document:body:appendChild *font-host*)
          (defvar *font-app*
            (lui.web:mount *font-host*
              (lambda ()
                (lui.widgets:declare-widget :label :glass :font "iiiiiiii"
                  :font-family *font-family* :font-weight *font-weight*)))))
        ''')
        label = self.page.locator("#font-host > div")
        expect(label).to_have_text("iiiiiiii")
        original_width = label.bounding_box()["width"]
        self.lisp('''(setf *font-family* :monospace *font-weight* :bold)
          (lui.web:refresh *font-app*)''')
        expect(label).to_have_css("font-weight", "700")
        self.assertIn("Liberation Mono", label.evaluate(
            "n => getComputedStyle(n).fontFamily"))
        self.assertGreater(label.bounding_box()["width"], original_width * 1.5)
        self.lisp('''(setf *font-family* :sans-serif *font-weight* :normal)
          (lui.web:refresh *font-app*)''')
        expect(label).to_have_css("font-weight", "400")
        self.assertEqual(label.bounding_box()["width"], original_width)
        self.lisp('(lui.web:unmount *font-app*)')

    def test_filtered_rows_restore_native_tab_order(self):
        self.lisp('''
          (defvar *order-show* t)
          (defvar *order-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *order-host* "id") #j"order-host"
                (jscl/ffi:oget *order-host* "style" "width") #j"500px"
                (jscl/ffi:oget *order-host* "style" "height") #j"200px")
          (#j:document:body:appendChild *order-host*)
          (defvar *order-app*
            (lui.web:mount *order-host*
              (lambda ()
                (lui.frame:column ()
                  (when *order-show* (lui.glass:button :one "Row one"))
                  (lui.glass:button :two "Row two")
                  (when *order-show* (lui.glass:button :three "Row three"))
                  (lui.glass:text-field :tail "Retained"))))))
        ''')
        host = self.page.locator("#order-host")
        tail = host.get_by_role("textbox")
        expect(tail).to_be_visible()
        tail.focus()
        tail.evaluate("n => n.setSelectionRange(1,4)")
        self.lisp('(setf *order-show* nil) (lui.web:refresh *order-app*)')
        expect(host.get_by_role("button")).to_have_count(1)
        self.lisp('(setf *order-show* t) (lui.web:refresh *order-app*)')
        expect(host.get_by_role("button")).to_have_count(3)
        expect(tail).to_be_focused()
        self.assertEqual(tail.evaluate("n => [n.selectionStart,n.selectionEnd]"), [1,4])
        tail.press("Shift+Tab")
        expect(host.get_by_role("button", name="Row three")).to_be_focused()
        self.page.keyboard.press("Shift+Tab")
        expect(host.get_by_role("button", name="Row two")).to_be_focused()
        self.page.keyboard.press("Shift+Tab")
        expect(host.get_by_role("button", name="Row one")).to_be_focused()
        self.page.keyboard.press("Tab")
        expect(host.get_by_role("button", name="Row two")).to_be_focused()
        self.lisp('(lui.web:unmount *order-app*)')

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
        page.get_by_role("button", name="Cycle toolkit", exact=True).click()
        expect(page.get_by_text("Toolkit: Motif", exact=True).filter(visible=True)).to_be_visible()
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
