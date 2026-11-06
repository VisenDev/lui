"""Canvas browser integration tests. Build with scripts/build-web.lisp first.

Geometry comes from the solved Lisp tree; interactions use real browser input.
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

    def setUp(self):
        self.page = self.browser.new_page(viewport={"width": 900, "height": 700})
        self.errors = []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))
        self.page.goto(f"http://127.0.0.1:{self.server.server_port}/examples/web.html")
        self.page.wait_for_function("""() => {
            const c = document.querySelector('main canvas');
            return c && c.luiApp && c.width > 0;
        }""")
        self.lisp('''(declaim (special lui.frame:*context* lui.frame:*parent*
          lui:*unit* lui::*toolkit* lui::*toolkit-definition*))''')
        self.frames()

    def tearDown(self):
        self.page.close()
        self.assertEqual(self.errors, [])

    def lisp(self, source):
        self.page.evaluate("source => { jscl.evaluateString(source); }",
                           "(progn " + source + ")")

    def number(self, expression):
        self.lisp(f'(setf (jscl/ffi:oget #j:window "testNumber") {expression})')
        return self.page.evaluate("window.testNumber")

    def frames(self):
        self.page.evaluate("""() => new Promise(resolve =>
            requestAnimationFrame(() => requestAnimationFrame(resolve)))""")

    def nodes(self, host="main"):
        """Snapshot solved widget geometry and model values, never widget DOM."""
        self.page.evaluate("s => {window.testCanvas = document.querySelector(s+' canvas');}", host)
        self.lisp('''
          (let* ((app (jscl/ffi:oget #j:window:testCanvas "luiApp"))
                 (context (lui.web::web-app-context app))
                 (result (jscl/ffi:new #j:Array)))
            (when (lui.frame:context-root context)
              (lui.layout:walk-elements (lui.frame:context-root context)
                (lambda (node)
                  (let ((widget (lui.layout:element-content node))
                        (box (lui.layout:element-box node))
                        (clip (lui.layout:element-clip node)))
                    (when (lui.widgets:widget-p widget)
                      (let ((item (jscl/ffi:new #j:Object)))
                        (setf
                          (jscl/ffi:oget item "id")
                          (jscl/ffi:jsstring
                            (prin1-to-string (lui.layout:element-id node)))
                          (jscl/ffi:oget item "kind")
                          (jscl/ffi:jsstring (string-downcase
                            (symbol-name (lui.widgets:widget-kind widget))))
                          (jscl/ffi:oget item "text")
                          (jscl/ffi:jsstring (lui.widgets:widget-text widget))
                          (jscl/ffi:oget item "value")
                          (jscl/ffi:jsstring (princ-to-string
                            (lui.widgets:widget-value widget)))
                          (jscl/ffi:oget item "x") (lui.layout:box-x box)
                          (jscl/ffi:oget item "y") (lui.layout:box-y box)
                          (jscl/ffi:oget item "width") (lui.layout:box-width box)
                          (jscl/ffi:oget item "height") (lui.layout:box-height box)
                          (jscl/ffi:oget item "clipX") (lui.layout:box-x clip)
                          (jscl/ffi:oget item "clipY") (lui.layout:box-y clip)
                          (jscl/ffi:oget item "clipWidth")
                          (lui.layout:box-width clip)
                          (jscl/ffi:oget item "clipHeight")
                          (lui.layout:box-height clip))
                        ((jscl/ffi:oget result "push") item)))))))
            (setf (jscl/ffi:oget #j:window "testNodes") result)))
        ''')
        return self.page.evaluate("window.testNodes")

    def widget(self, id=None, text=None, kind=None, host="main"):
        found = [n for n in self.nodes(host)
                 if (id is None or n["id"] == id)
                 and (text is None or n["text"] == text)
                 and (kind is None or n["kind"] == kind)]
        self.assertEqual(len(found), 1, f"Expected one widget {id, text, kind}; got {found}")
        return found[0]

    def point(self, node, host="main"):
        box = self.page.locator(host + " canvas").bounding_box()
        x1 = max(node["x"], node["clipX"])
        y1 = max(node["y"], node["clipY"])
        x2 = min(node["x"] + node["width"], node["clipX"] + node["clipWidth"])
        y2 = min(node["y"] + node["height"], node["clipY"] + node["clipHeight"])
        self.assertGreater(x2, x1, f"Widget clipped horizontally: {node}")
        self.assertGreater(y2, y1, f"Widget clipped vertically: {node}")
        return box["x"] + (x1+x2)/2, box["y"] + (y1+y2)/2

    def click_widget(self, id=None, text=None, kind=None, host="main"):
        self.page.mouse.click(*self.point(self.widget(id, text, kind, host), host))
        self.frames()

    def hover_widget(self, id=None, text=None, kind=None, host="main"):
        self.page.mouse.move(*self.point(self.widget(id, text, kind, host), host))
        self.frames()

    def text_value(self, id, host="main"):
        return self.widget(id=id, host=host)["value"]

    def replace_text(self, id, value, host="main"):
        self.click_widget(id=id, host=host)
        self.page.keyboard.press("Control+Shift+A")
        self.page.keyboard.insert_text(value)
        self.frames()

    def fixture(self, body=None, options=""):
        """Mount an isolated visible application; return its host selector."""
        body = body or '''
          (lui.frame:column (:width (lui.layout:grow) :gap 8)
            (setf *web-test-value*
              (lui.glass:text-field :fixture *web-test-value*
                (lui:opt :width (lui.layout:grow))))
            (when (lui.glass:button :push "Fixture push")
              (incf *web-test-clicks*)))'''
        self.lisp(f'''
          (defvar *web-test-value* "original")
          (defvar *web-test-clicks* 0)
          (defvar *web-test-draws* 0)
          (defvar *web-test-host* (#j:document:createElement #j"section"))
          (setf (jscl/ffi:oget *web-test-host* "id") #j"test-host"
                (jscl/ffi:oget *web-test-host* "style" "cssText")
                #j"position:fixed;left:0;top:0;width:500px;height:300px;z-index:10")
          (#j:document:body:appendChild *web-test-host*)
          (defvar *web-test-app*
            (lui.web:mount *web-test-host*
              (lambda () (incf *web-test-draws*) {body}) {options}))
        ''')
        self.frames()
        return "#test-host"

    def focus_id(self, app="*web-test-app*"):
        self.lisp(f'''(setf (jscl/ffi:oget #j:window "testFocus")
          (jscl/ffi:jsstring (prin1-to-string
            (lui.frame:context-focus (lui.web::web-app-context {app}))))))''')
        return self.page.evaluate("window.testFocus")

    def test_canvas_rendering_has_selectable_native_labels(self):
        expect(self.page.locator("main canvas")).to_have_count(1)
        expect(self.page.locator("main textarea")).to_have_count(1)
        # Labels are native, read-only DOM text layered over the canvas. They
        # expose the rendered content to accessibility APIs and browser text
        # selection while control graphics stay on the canvas.
        label = self.page.get_by_text("Toolkit: Glass", exact=True)
        expect(label).to_be_visible()
        self.assertTrue(label.evaluate("n => n.isContentEditable === false"))
        colors = self.page.locator("main canvas").evaluate("""c => {
          const p=c.getContext('2d').getImageData(0,0,c.width,c.height).data;
          const colors=new Set();
          for(let i=0;i<p.length;i+=16) colors.add(p.slice(i,i+4).join(','));
          return colors.size;
        }""")
        self.assertGreater(colors, 50)

    def test_screen_reader_activation_uses_toolkit_actions(self):
        button = self.page.get_by_role("button", name="Say hello", exact=True)
        button.evaluate("element => element.click()")
        expect(self.page.get_by_text("Hello Common Lisp (1)", exact=True)).to_be_visible()
        check = self.page.get_by_role("checkbox", name="Enabled")
        expect(check).to_have_attribute("aria-checked", "true")
        check.evaluate("element => element.click()")
        expect(check).to_have_attribute("aria-checked", "false")

    def test_native_label_selection_survives_frames_and_copies(self):
        host = self.fixture('''
          (lui.frame:column (:width (lui.layout:grow) :gap 8)
            (lui.glass:label "Selectable native label")
            (lui.glass:label "Read only and accessible"))''')
        label = self.page.get_by_text("Selectable native label", exact=True)
        expect(label).to_be_visible()
        expect(self.page.get_by_text("Read only and accessible", exact=True)).to_be_visible()
        self.assertFalse(label.evaluate("n => n.isContentEditable"))
        box = label.bounding_box()
        self.assertIsNotNone(box)
        # A native double-click selects the word under the pointer.
        label.dblclick(position={"x": box["width"] * 0.55,
                                 "y": box["height"] / 2})
        self.assertEqual(self.page.evaluate("getSelection().toString()"), "native")
        self.lisp('(lui.web:refresh *web-test-app*)')
        self.frames()
        self.assertEqual(self.page.evaluate("getSelection().toString()"), "native")
        self.page.context.grant_permissions(["clipboard-read", "clipboard-write"])
        self.page.keyboard.press("Control+c")
        copied = self.page.evaluate("navigator.clipboard.readText()")
        self.assertEqual(copied, "native")
        self.lisp('(lui.web:unmount *web-test-app*)')
        expect(self.page.locator(host + " > *")).to_have_count(0)

    def test_recently_hidden_native_label_reuses_its_dom_node(self):
        self.lisp('(defvar *web-test-show-label* t)')
        self.fixture('''
          (when *web-test-show-label*
            (lui.glass:label "Briefly hidden label"))''')
        label = self.page.get_by_text("Briefly hidden label", exact=True)
        expect(label).to_be_visible()
        label.evaluate("n => window.savedNativeLabel = n")
        self.lisp('(setf *web-test-show-label* nil) (lui.web:refresh *web-test-app*)')
        self.frames()
        self.assertEqual(self.page.evaluate("window.savedNativeLabel.style.visibility"), "hidden")
        self.lisp('(setf *web-test-show-label* t) (lui.web:refresh *web-test-app*)')
        self.frames()
        label = self.page.get_by_text("Briefly hidden label", exact=True)
        expect(label).to_be_visible()
        self.assertTrue(label.evaluate("n => n === window.savedNativeLabel"))

    def test_hiding_preceding_label_preserves_selection_and_sibling_node(self):
        self.lisp('(defvar *web-test-show-first-label* t)')
        self.fixture('''
          (when *web-test-show-first-label*
            (lui.widgets:declare-widget :label :glass :first "First label"))
          (lui.widgets:declare-widget :label :glass :second "Selected sibling")''')
        sibling = self.page.get_by_text("Selected sibling", exact=True)
        sibling.evaluate("""node => {
            window.savedSibling = node;
            const range = document.createRange();
            range.selectNodeContents(node);
            getSelection().addRange(range);
        }""")
        self.lisp('(setf *web-test-show-first-label* nil) (lui.web:refresh *web-test-app*)')
        self.frames()
        self.assertEqual(self.page.evaluate("getSelection().toString()"), "Selected sibling")
        self.assertTrue(sibling.evaluate("n => n === window.savedSibling"))

    def test_floating_control_covers_native_text(self):
        host = self.fixture('''
          (lui.frame:column (:width (lui.layout:fixed 240))
            (lui:label "Under the popup")
            (when (zerop *web-test-clicks*)
              (when (lui:button :popup "Dismiss"
                      (lui:opt :floating-p t :width (lui.layout:grow)))
                (incf *web-test-clicks*))))''')
        label = self.page.locator(host).get_by_text("Under the popup", exact=True)
        expect(label).to_have_count(0)
        self.click_widget(id=":POPUP", host=host)
        expect(label).to_be_visible()

    def test_mobile_long_press_selects_native_label(self):
        page = self.browser.new_page(viewport={"width": 390, "height": 844},
                                     device_scale_factor=2, is_mobile=True,
                                     has_touch=True)
        try:
            page.goto(f"http://127.0.0.1:{self.server.server_port}/examples/web.html")
            page.wait_for_function("""() => {
              const c=document.querySelector('main canvas');
              return c && c.luiApp && document.body.innerText.includes('Toolkit: Glass');
            }""")
            label = page.get_by_text("Toolkit: Glass", exact=True)
            expect(label).to_be_visible()
            cdp = page.context.new_cdp_session(page)
            def long_press(element):
                # Target an actual glyph, including when the label wraps.
                point = element.evaluate("""n => {
                  const r = document.createRange();
                  r.setStart(n.firstChild, 0); r.setEnd(n.firstChild, 1);
                  const b = r.getBoundingClientRect();
                  const x = b.x + b.width/2, y = b.y + b.height/2;
                  return {x, y, hit: document.elementFromPoint(x,y) === n};
                }""")
                self.assertTrue(point.pop("hit"))
                cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [point]})
                page.wait_for_timeout(850)
                cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
                return page.evaluate("getSelection().toString()")

            snapshot = label.aria_snapshot()
            self.assertIn("Toolkit: Glass", snapshot)
            self.assertEqual(label.evaluate("n => getComputedStyle(n).userSelect"), "text")
            # Some headless engines never synthesize Android's selection UI.
            # Check an ordinary paragraph before judging the mounted app.
            page.evaluate("""() => {
              const p = document.createElement('p'); p.id='long-press-control';
              p.style.cssText='position:fixed;bottom:10px;left:10px;background:white';
              p.textContent='Reference paragraph'; document.body.appendChild(p);
            }""")
            if not long_press(page.locator("#long-press-control")):
                self.skipTest("This engine does not select an ordinary HTML paragraph on long press")
            page.evaluate("() => { document.querySelector('#long-press-control').remove(); getSelection().removeAllRanges(); }")
            self.assertIn("Toolkit", long_press(label))
        finally:
            page.close()

    def test_mobile_mount_scroll_waits_for_painted_frame(self):
        page = self.browser.new_page(viewport={"width": 390, "height": 844},
                                     device_scale_factor=2, is_mobile=True,
                                     has_touch=True)
        page.on("pageerror", lambda error: self.errors.append(str(error)))
        try:
            # Gate application frame callbacks without freezing browser input or
            # scrolling, including callbacks already scheduled before the pause.
            page.add_init_script("""(() => {
                const raf = window.requestAnimationFrame.bind(window);
                window.pausedFrames = false;
                window.pendingFrames = [];
                window.requestAnimationFrame = callback => raf(time => {
                    if (window.pausedFrames) window.pendingFrames.push(callback);
                    else callback(time);
                });
                window.resumeFrames = () => {
                    window.pausedFrames = false;
                    window.pendingFrames.splice(0).forEach(callback => raf(callback));
                };
            })()""")
            page.goto(f"http://127.0.0.1:{self.server.server_port}/examples/web.html")
            page.wait_for_function("document.querySelector('main canvas')?.luiApp")
            ui = WebTests()
            ui.page = page
            ui.lisp('''
              (declaim (special lui.frame:*context* lui.frame:*parent* lui:*unit*))
              (lui.web:unmount (jscl/ffi:oget
                (#j:document:querySelector #j"main canvas") "luiApp"))
              ((jscl/ffi:oget (#j:document:querySelector #j"main") "remove"))
              (defvar *web-test-clicks* -1)
              (defvar *web-test-host* (#j:document:createElement #j"main"))
              (#j:document:body:appendChild *web-test-host*)
              (defvar *web-test-app*
                (lui.web:mount *web-test-host*
                  (lambda ()
                    (lui.frame:column (:width (lui.layout:grow))
                      (dotimes (i 60)
                        (when (lui.glass:button (list :row i)
                                (format nil "Row ~D" i)
                                (lui:opt :height (lui.layout:fixed 48)
                                         :width (lui.layout:grow)))
                          (setf *web-test-clicks* i)))))))''')
            ui.frames()
            page.wait_for_function("document.documentElement.scrollHeight > innerHeight * 2")
            canvas = page.locator("main canvas")
            painted = canvas.evaluate("c => c.toDataURL()")
            page.evaluate("window.pausedFrames = true")
            cdp = page.context.new_cdp_session(page)
            self.assertEqual(page.evaluate("document.elementFromPoint(190,700).tagName"),
                             "CANVAS")
            cdp.send("Input.dispatchTouchEvent", {
                "type": "touchStart", "touchPoints": [{"x": 190, "y": 700}]})
            for y in (620, 540, 460, 380):
                cdp.send("Input.dispatchTouchEvent", {
                    "type": "touchMove", "touchPoints": [{"x": 190, "y": y}]})
            page.wait_for_timeout(125)  # release at rest, without a fling
            cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            page.wait_for_timeout(150)
            self.assertEqual(page.evaluate("window.scrollY"), 0)
            self.assertEqual(canvas.evaluate("c => c.luiViewportOffset"), 0)
            self.assertEqual(canvas.evaluate("c => c.getBoundingClientRect().top"), 0)
            self.assertEqual(canvas.evaluate("c => c.toDataURL()"), painted)
            page.evaluate("window.resumeFrames()")
            page.wait_for_function("window.scrollY > 100")
            ui.frames()
            self.assertAlmostEqual(page.evaluate("window.scrollY"),
                                   canvas.evaluate("c => c.luiViewportOffset"), delta=1)
            self.assertAlmostEqual(canvas.evaluate("c => c.getBoundingClientRect().top"),
                                   0, delta=1)
            self.assertNotEqual(canvas.evaluate("c => c.toDataURL()"), painted)
            # A newly revealed row must receive a real canvas tap using its
            # page geometry, rather than an accessibility button activation.
            offset = page.evaluate("window.scrollY")
            visible = [node for node in ui.nodes()
                       if node["y"] > 844 and node["y"] >= offset
                       and node["y"] + node["height"] < offset + 844]
            self.assertTrue(visible)
            chosen = visible[0]
            x, y = ui.point(chosen)
            self.assertEqual(page.evaluate(
                "([x,y]) => document.elementFromPoint(x,y).tagName",
                [x, y - offset]), "CANVAS")
            page.touchscreen.tap(x, y - offset)
            ui.frames()
            self.assertEqual(ui.number("*web-test-clicks*"),
                             int(chosen["text"].split()[1]))
        finally:
            page.close()

    def test_mobile_embedded_scrollport_and_native_labels(self):
        page = self.browser.new_page(viewport={"width": 390, "height": 844},
                                     is_mobile=True, has_touch=True)
        page.on("pageerror", lambda error: self.errors.append(str(error)))
        try:
            page.goto(f"http://127.0.0.1:{self.server.server_port}/examples/web.html")
            page.wait_for_function("document.querySelector('main canvas')?.luiApp")
            ui = WebTests()
            ui.page = page
            ui.lisp('''
              (declaim (special lui.frame:*context* lui.frame:*parent* lui:*unit*))
              (defvar *mobile-port* (#j:document:createElement #j"section"))
              (setf (jscl/ffi:oget *mobile-port* "id") #j"mobile-port"
                    (jscl/ffi:oget *mobile-port* "style" "cssText")
                    #j"position:fixed;top:40px;left:0;width:300px;height:320px;overflow:auto")
              (#j:document:body:appendChild *mobile-port*)
              (lui.web:mount *mobile-port*
                (lambda ()
                  (lui.frame:column (:width (lui.layout:grow))
                    (dotimes (i 40)
                      (lui.glass:label (format nil "Embedded row ~D" i)
                        (lui:opt :width (lui.layout:grow) :height (lui.layout:fixed 48)))))))''')
            port = page.locator("#mobile-port")
            label = port.get_by_text("Embedded row 4", exact=True)
            expect(label).to_be_visible()
            box = label.bounding_box()
            x, y = box["x"] + 30, box["y"] + 12
            cdp = page.context.new_cdp_session(page)
            cdp.send("Input.dispatchTouchEvent", {
                "type": "touchStart", "touchPoints": [{"x": x, "y": y}]})
            for distance in (25, 70, 120):
                cdp.send("Input.dispatchTouchEvent", {
                    "type": "touchMove", "touchPoints": [{"x": x, "y": y - distance}]})
            page.wait_for_timeout(125)
            cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            page.wait_for_function("document.querySelector('#mobile-port').scrollTop >= 100")
            self.assertEqual(page.evaluate("window.scrollY"), 0)
            self.assertAlmostEqual(port.evaluate("el => el.scrollTop"),
                                   port.locator("canvas").evaluate("c => c.luiViewportOffset"), delta=1)
            label.evaluate("el => getSelection().selectAllChildren(el)")
            self.assertEqual(page.evaluate("getSelection().toString()"), "Embedded row 4")
        finally:
            page.close()

    def test_mobile_standalone_gallery_scrolls_on_canvas_swipe(self):
        page = self.browser.new_page(viewport={"width": 390, "height": 844},
                                     device_scale_factor=2, is_mobile=True,
                                     has_touch=True)
        try:
            page.goto(f"http://127.0.0.1:{self.server.server_port}/examples/web.html")
            page.wait_for_function("""() => {
              const c=document.querySelector('main canvas');
              return c && c.luiApp && c.width > 0 &&
                     document.body.innerText.includes('Toolkit: Glass');
            }""")
            def tap_button(name):
                bounds = page.get_by_role("button", name=name, exact=True).bounding_box()
                self.assertIsNotNone(bounds)
                page.touchscreen.tap(bounds["x"] + bounds["width"] / 2,
                                     bounds["y"] + bounds["height"] / 2)

            # Touch editing must keep the IME sink focused after the browser
            # finishes its compatibility mouse events.
            ui = WebTests()
            ui.page = page
            page.touchscreen.tap(*ui.point(ui.widget(id=":NAME")))
            expect(page.locator("main textarea")).to_be_focused()
            page.keyboard.insert_text("X")
            ui.frames()
            self.assertIn("X", ui.text_value(":NAME"))
            tap_button("Scroll")
            page.wait_for_function("document.documentElement.scrollHeight > innerHeight * 2")
            self.assertEqual(page.locator("main canvas").evaluate("c => c.clientHeight"),
                             page.evaluate("innerHeight"))
            cdp = page.context.new_cdp_session(page)
            # Start over a result button's canvas surface and drag vertically.
            x, y = 190, 700
            self.assertEqual(page.evaluate("([x,y]) => document.elementFromPoint(x,y).tagName",
                                           [x, y]), "CANVAS")
            cdp.send("Input.dispatchTouchEvent", {
                "type": "touchStart", "touchPoints": [{"x": x, "y": y}]})
            for y in (620, 540, 460, 380):
                cdp.send("Input.dispatchTouchEvent", {
                    "type": "touchMove", "touchPoints": [{"x": x, "y": y}]})
            cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            page.wait_for_function("window.scrollY > 100")
            # At the bottom, a real tap must hit the last item in page coordinates.
            page.evaluate("window.scrollTo(0, document.documentElement.scrollHeight)")
            last = "Item 60 — selectable row"
            page.wait_for_function("""() => {
                const c = document.querySelector('main canvas');
                return c.getBoundingClientRect().top < 1 && c.getBoundingClientRect().bottom > innerHeight - 1;
            }""")
            tap_button(last)
            expect(page.get_by_text("Selected item: 60", exact=True)).to_have_count(1)
            tap_position = page.evaluate("window.scrollY")
            self.assertGreater(tap_position, 100)
        finally:
            page.close()

    def test_demo_buttons_text_checkbox_and_slider(self):
        self.click_widget(text="Say hello")
        self.widget(text="Hello Common Lisp (1)")
        self.replace_text(":NAME", "Ada")
        self.widget(text="Hello Ada (1)")
        self.click_widget(id=":ENABLED")
        self.assertEqual(self.text_value(":ENABLED"), "NIL")
        self.click_widget(id=":NAME")
        self.page.keyboard.press("Tab")
        self.page.keyboard.press("End")
        self.frames()
        self.assertEqual(float(self.text_value(":VOLUME")), 1)
        self.page.keyboard.press("Home")
        self.frames()
        self.assertEqual(float(self.text_value(":VOLUME")), 0)
        self.click_widget(text="Reset")
        self.widget(text="Hello Ada (0)")

    def test_cells_edit_and_native_selection_during_scroll(self):
        self.click_widget(text="7GUIs", kind="tab")
        self.click_widget(text="Cells", kind="tab")
        first = "(:SEVEN-CELL 0)"
        self.page.mouse.dblclick(*self.point(self.widget(id=first)))
        self.frames()
        self.assertEqual(self.widget(id=first)["kind"], "text-field")
        self.page.keyboard.press("Control+a")
        self.page.keyboard.insert_text("42")
        self.page.keyboard.press("Enter")
        self.frames()
        self.widget(id=first, kind="cell", text="42")

        label = self.page.get_by_text("Selected: A0", exact=True)
        label.evaluate("el => getSelection().selectAllChildren(el)")
        self.page.mouse.move(*self.point(self.widget(id=":SEVEN-GRID")))
        self.page.mouse.wheel(0, 240)
        self.frames()
        grid_offset = self.page.evaluate("""() => jscl.evaluateString(`
          (let* ((app (jscl/ffi:oget (#j:document:querySelector #j"main canvas") "luiApp"))
                 (ids (lui.frame::context-ids (lui.web::web-app-context app))))
            (lui.layout:element-scroll-y (gethash :seven-grid ids)))`)""")
        self.assertGreater(grid_offset, 0)
        self.assertEqual(self.page.evaluate("getSelection().toString()"), "Selected: A0")

    def test_gallery_persistence_and_toolkit_pixels(self):
        self.replace_text(":NAME", "Persistent name")
        self.click_widget(text="Editing", kind="tab")
        self.replace_text(":EDITOR", "Persistent editor")
        for name in ("Layout", "Scroll", "Styles", "Controls"):
            self.click_widget(text=name, kind="tab")
        self.assertEqual(self.text_value(":NAME"), "Persistent name")
        shots = []
        for name in ("Motif", "Garnet", "Glass"):
            self.click_widget(text="Cycle toolkit")
            self.widget(text="Toolkit: " + name)
            shots.append(self.page.locator("main canvas").screenshot())
        self.assertEqual(len(set(shots)), 3)
        self.click_widget(text="Editing", kind="tab")
        self.assertEqual(self.text_value(":EDITOR"), "Persistent editor")

    def test_keyboard_focus_activation_and_readline(self):
        host = self.fixture()
        self.click_widget(id=":FIXTURE", host=host)
        self.page.keyboard.press("End")
        self.page.keyboard.type(" tail")
        self.frames()
        self.assertEqual(self.text_value(":FIXTURE", host), "original tail")
        self.page.keyboard.press("Control+a")
        self.page.keyboard.press("Control+k")
        self.frames()
        self.assertEqual(self.text_value(":FIXTURE", host), "")
        self.page.keyboard.press("Control+y")
        self.frames()
        self.assertEqual(self.text_value(":FIXTURE", host), "original tail")
        self.page.keyboard.press("Tab")
        self.frames()
        self.assertEqual(self.focus_id(), ":PUSH")
        self.page.keyboard.press("Space")
        self.frames()
        self.assertEqual(self.number("*web-test-clicks*"), 1)
        self.page.keyboard.press("Shift+Tab")
        self.frames()
        self.assertEqual(self.focus_id(), ":FIXTURE")

    def test_focused_control_accessible_name_and_value(self):
        host = self.fixture()
        self.click_widget(id=":FIXTURE", host=host)
        sink = self.page.locator(host + " textarea")
        expect(sink).to_have_attribute("aria-label", ":FIXTURE")
        expect(sink).to_have_attribute("aria-valuetext", "original")
        self.replace_text(":FIXTURE", "Updated value", host)
        expect(sink).to_have_attribute("aria-valuetext", "Updated value")
        self.page.keyboard.press("Tab")
        self.frames()
        expect(sink).to_have_attribute("aria-label", "Fixture push")

    def test_selection_delete_unicode_and_ime_commit(self):
        host = self.fixture()
        self.replace_text(":FIXTURE", "a😀日本z", host)
        self.assertEqual(self.text_value(":FIXTURE", host), "a😀日本z")
        self.page.keyboard.press("End")
        self.page.keyboard.press("Shift+ArrowLeft")
        self.page.keyboard.press("Backspace")
        self.frames()
        self.assertEqual(self.text_value(":FIXTURE", host), "a😀日本")
        sink = self.page.locator(host + " textarea")
        sink.evaluate("""n => {
          n.dispatchEvent(new CompositionEvent('compositionstart', {bubbles:true}));
          n.dispatchEvent(new InputEvent('beforeinput',
            {bubbles:true,cancelable:true,isComposing:true,data:'仮',inputType:'insertCompositionText'}));
        }""")
        self.frames()
        self.assertEqual(self.text_value(":FIXTURE", host), "a😀日本")
        sink.evaluate("""n => n.dispatchEvent(new CompositionEvent(
          'compositionend',{bubbles:true,data:'確定'}))""")
        self.frames()
        self.assertEqual(self.text_value(":FIXTURE", host), "a😀日本確定")

    def test_clipboard_paste_copy_cut_selection(self):
        host = self.fixture()
        self.replace_text(":FIXTURE", "copy this", host)
        self.page.keyboard.press("Control+Shift+A")
        self.frames()
        sink = self.page.locator(host + " textarea")
        copied = sink.evaluate("""n => {
          const data = new DataTransfer();
          n.dispatchEvent(new ClipboardEvent('copy',
            {bubbles:true,cancelable:true,clipboardData:data}));
          return data.getData('text/plain');
        }""")
        self.assertEqual(copied, "copy this")
        sink.evaluate("""n => n.dispatchEvent(new ClipboardEvent('cut',
          {bubbles:true,cancelable:true,clipboardData:new DataTransfer()}))""")
        self.frames()
        self.assertEqual(self.text_value(":FIXTURE", host), "")
        sink.evaluate("""n => {const data=new DataTransfer();
          data.setData('text/plain','pasted 日本');
          n.dispatchEvent(new ClipboardEvent('paste',
            {bubbles:true,cancelable:true,clipboardData:data}));}""")
        self.frames()
        self.assertEqual(self.text_value(":FIXTURE", host), "pasted 日本")

    def test_pointer_capture_release_outside_and_blur_cancel(self):
        host = self.fixture()
        point = self.point(self.widget(id=":PUSH", host=host), host)
        self.page.mouse.move(*point)
        self.page.mouse.down()
        self.frames()
        self.assertEqual(self.number('''(if (lui.frame:context-active
          (lui.web::web-app-context *web-test-app*)) 1 0)'''), 1)
        self.page.mouse.move(700, 500)
        self.page.mouse.up()
        self.frames()
        self.assertEqual(self.number("*web-test-clicks*"), 0)
        self.page.mouse.move(*point)
        self.page.mouse.down()
        self.page.evaluate("window.dispatchEvent(new Event('blur'))")
        self.page.mouse.up()
        self.frames()
        self.assertEqual(self.number("*web-test-clicks*"), 0)
        self.assertEqual(self.number('''(if (lui.frame:context-active
          (lui.web::web-app-context *web-test-app*)) 1 0)'''), 0)

    def test_cursor_feedback_disabled_and_text(self):
        self.hover_widget(text="Disabled")
        expect(self.page.locator("main canvas")).to_have_css("cursor", "not-allowed")
        self.hover_widget(id=":NAME")
        expect(self.page.locator("main canvas")).to_have_css("cursor", "text")
        self.hover_widget(text="Say hello")
        expect(self.page.locator("main canvas")).to_have_css("cursor", "pointer")
        self.click_widget(text="Disabled")
        self.widget(text="Hello Common Lisp (0)")

    def test_scroll_hit_testing_and_wheel(self):
        host = self.fixture('''
          (lui.frame:column (:id :scroll :width (lui.layout:grow)
                            :height (lui.layout:fixed 280) :scroll-p t)
            (dotimes (i 30)
              (when (lui.glass:button (list :row i)
                      (format nil "Row ~D" i)
                       (lui:opt :height (lui.layout:fixed 32)
                                :width (lui.layout:grow)))
                (setf *web-test-clicks* i))))''')
        before = self.widget(text="Row 1", host=host)["y"]
        self.hover_widget(text="Row 1", host=host)
        self.page.mouse.wheel(0, 180)
        self.page.wait_for_timeout(300)
        self.frames()
        self.assertLess(self.widget(text="Row 1", host=host)["y"], before-100)
        visible = [n for n in self.nodes(host) if n["text"].startswith("Row ")
                   and n["y"] >= 0 and n["y"]+n["height"] < 300]
        self.assertTrue(visible)
        chosen = visible[0]
        self.click_widget(text=chosen["text"], host=host)
        self.assertEqual(self.number("*web-test-clicks*"), int(chosen["text"].split()[1]))

    def test_resize_and_high_dpi_backing_store(self):
        host = self.fixture()
        before = self.widget(id=":FIXTURE", host=host)["width"]
        self.page.locator(host).evaluate("n => n.style.width='650px'")
        self.page.wait_for_timeout(80)
        self.frames()
        self.assertGreater(self.widget(id=":FIXTURE", host=host)["width"], before+100)
        self.assertTrue(self.page.locator(host+" canvas").evaluate("""c =>
          c.width===Math.round(c.clientWidth*devicePixelRatio) &&
          c.height===Math.round(c.clientHeight*devicePixelRatio)"""))

    def test_device_pixel_ratio_two(self):
        page = self.browser.new_page(viewport={"width": 640, "height": 480},
                                     device_scale_factor=2)
        try:
            page.goto(f"http://127.0.0.1:{self.server.server_port}/examples/web.html")
            page.wait_for_function("""() => {
              const c=document.querySelector('main canvas');
              return c && c.width===c.clientWidth*2 && c.height===c.clientHeight*2;
            }""")
        finally:
            page.close()

    def test_refresh_coalesces_and_unmount_stops_work(self):
        self.fixture(options=":min-fps 1 :max-fps 30")
        before = self.number("*web-test-draws*")
        self.lisp('(dotimes (i 100) (lui.web:refresh *web-test-app*))')
        self.page.wait_for_timeout(100)
        count = self.number("*web-test-draws*") - before
        self.assertGreaterEqual(count, 1)
        self.assertLessEqual(count, 4)
        before = self.number("*web-test-draws*")
        self.page.wait_for_timeout(1100)
        self.assertGreater(self.number("*web-test-draws*"), before)
        self.lisp('(lui.web:unmount *web-test-app*) (lui.web:unmount *web-test-app*)')
        before = self.number("*web-test-draws*")
        self.page.wait_for_timeout(1100)
        self.assertEqual(self.number("*web-test-draws*"), before)
        expect(self.page.locator("#test-host > *")).to_have_count(0)

    def test_native_label_color_updates_at_fixed_geometry(self):
        host = self.fixture('''
          (lui.widgets:declare-widget :label :glass :tint "Tinted"
            :foreground (if (zerop *web-test-clicks*) "#112233" "#445566"))''')
        label = self.page.locator(host).get_by_text("Tinted", exact=True)
        expect(label).to_have_css("color", "rgb(17, 34, 51)")
        before = label.bounding_box()
        self.lisp('(setf *web-test-clicks* 1) (lui.web:refresh *web-test-app*)')
        expect(label).to_have_css("color", "rgb(68, 85, 102)")
        self.assertEqual(label.bounding_box(), before)

    def test_font_measurement_changes_solved_geometry(self):
        host = self.fixture('''
          (lui.widgets:declare-widget :label :glass :font "iiiiiiii"
            :font-family (if (zerop *web-test-clicks*)
                             :sans-serif :monospace))''')
        narrow = self.widget(id=":FONT", host=host)["width"]
        self.lisp('(setf *web-test-clicks* 1) (lui.web:refresh *web-test-app*)')
        self.frames()
        self.assertGreater(self.widget(id=":FONT", host=host)["width"], narrow*1.4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
