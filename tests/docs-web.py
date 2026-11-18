"""Open the standalone docs offline and drive its canvas with real input."""

from pathlib import Path
import re
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
from playwright.sync_api import sync_playwright, expect


class DocsUI:
    def __init__(self, page):
        self.page = page

    def frames(self):
        self.page.evaluate("""() => new Promise(resolve =>
            requestAnimationFrame(() => requestAnimationFrame(resolve)))""")

    def widget(self, text):
        expect(self.page.get_by_text(text, exact=True).first).to_be_visible()

    def click_widget(self, text, kind=None):
        control = self.page.get_by_role("button", name=text, exact=True)
        box = control.bounding_box()
        self.page.mouse.click(box["x"] + box["width"] / 2,
                              box["y"] + box["height"] / 2)
        self.frames()

    def search(self, text):
        # The canvas field is between its visible caption and result count.
        caption = self.page.get_by_text("Search API", exact=True).bounding_box()
        count = self.page.get_by_text(re.compile(r"^\d+ API entries$")).bounding_box()
        self.page.mouse.click(caption["x"] + 30,
                              (caption["y"] + caption["height"] + count["y"]) / 2)
        self.frames()
        self.page.keyboard.press("Control+Shift+A")
        self.page.keyboard.insert_text(text)
        self.frames()


class DocsWebTests(unittest.TestCase):
    def test_dialogs(self):
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                executable_path=shutil.which("chromium-browser") or shutil.which("chromium"),
                args=["--no-sandbox"])
            page = browser.new_page(viewport={"width": 1100, "height": 820})
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            try:
                page.goto((ROOT / "build/docs.html").as_uri())
                ui = DocsUI(page)
                ui.search("popup")
                ui.click_widget("lui:POPUP")
                toolkit = page.get_by_role("button", name="Cycle Toolkit", exact=True)
                toolkit_handle = toolkit.element_handle()
                ui.click_widget("Show error")
                expect(page.get_by_text("Could not save the file.", exact=True)).to_be_visible()
                # Background accessibility activation cannot replace the preview.
                expect(toolkit).to_have_count(0)
                toolkit_handle.evaluate("el => el.click()")
                ui.frames()
                page.set_viewport_size({"width": 900, "height": 700})
                ui.frames()
                expect(page.get_by_text("Could not save the file.", exact=True)).to_be_visible()
                ui.click_widget("OK")
                ui.widget("Toolkit: Qt")
                expect(page.get_by_text("Could not save the file.", exact=True)).to_be_hidden()
                ui.search("confirm")
                ui.click_widget("lui:CONFIRM")
                ui.click_widget("Delete example")
                page.keyboard.press("Escape")
                ui.frames()
                ui.widget("Confirmed: 0")
                ui.click_widget("Delete example")
                ui.click_widget("Delete")
                ui.widget("Confirmed: 1")
                self.assertEqual(errors, [])
            finally:
                browser.close()

    def test_shared_gallery_offline(self):
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                executable_path=shutil.which("chromium-browser") or shutil.which("chromium"),
                args=["--no-sandbox"])
            page = browser.new_page(viewport={"width": 1400, "height": 1000})
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            try:
                page.goto((ROOT / "build/docs.html").as_uri())
                ui = DocsUI(page)
                ui.click_widget("View Full Demo")
                ui.widget("LUI feature gallery")
                # Uncovered space beside the back button follows Qt's palette.
                pixel = page.locator("main canvas").evaluate("""canvas =>
                    Array.from(canvas.getContext('2d').getImageData(
                        canvas.width - 2, 2, 1, 1).data)""")
                self.assertEqual(pixel, [239, 239, 239, 255])
                for name in ["Editing", "Layout", "Scroll", "Styles", "Menus", "7GUIs"]:
                    ui.click_widget(name)
                    ui.frames()
                for name in ["Temperature", "Flight", "Timer", "CRUD", "Circles", "Cells", "Counter"]:
                    ui.click_widget(name)
                    ui.frames()
                ui.click_widget("Count")
                ui.frames()
                ui.click_widget("Back to documentation")
                ui.widget("Getting started")
                self.assertEqual(errors, [])
            finally:
                browser.close()

    def test_menu_hover_keeps_label_baseline(self):
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                executable_path=shutil.which("chromium-browser") or shutil.which("chromium"),
                args=["--no-sandbox"])
            page = browser.new_page(viewport={"width": 1050, "height": 760})
            try:
                page.goto((ROOT / "build/docs.html").as_uri())
                ui = DocsUI(page)
                ui.click_widget("View Full Demo")
                ui.click_widget("Menus")
                label_text = "Choose a menu action"
                label = page.get_by_text(label_text, exact=True)
                expect(label).to_be_visible()
                dom_baseline = label.evaluate("""el => {
                    const marker = document.createElement("span");
                    marker.style = "display:inline-block;width:0;height:0";
                    el.prepend(marker);
                    const y = marker.getBoundingClientRect().y;
                    marker.remove();
                    return y;
                }""")
                page.evaluate("""label => {
                    const fillText = CanvasRenderingContext2D.prototype.fillText;
                    CanvasRenderingContext2D.prototype.fillText = function (text, x, y, ...args) {
                        if (text === label) {
                            window.menuLabelBaseline = this.canvas.getBoundingClientRect().y + y;
                        }
                        return fillText.call(this, text, x, y, ...args);
                    };
                }""", label_text)
                for name in ("File", "Edit"):
                    trigger = page.get_by_role("button", name=name, exact=True)
                    trigger.hover(force=True)
                    expect(trigger).to_have_attribute("aria-expanded", "true")
                    expect(label).to_be_hidden()
                    ui.frames()
                    canvas_baseline = page.evaluate("window.menuLabelBaseline")
                    self.assertAlmostEqual(dom_baseline, canvas_baseline, delta=0.5)
            finally:
                browser.close()

    def test_mobile_debugger_uses_viewport(self):
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                executable_path=shutil.which("chromium-browser") or shutil.which("chromium"),
                args=["--no-sandbox"])
            page = browser.new_page(viewport={"width": 412, "height": 700},
                                    is_mobile=True, has_touch=True, device_scale_factor=2)
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            try:
                page.goto((ROOT / "build/docs.html").as_uri())
                page.get_by_role("button", name="Browse symbols", exact=True).evaluate("el => el.click()")
                page.get_by_role("button", name="Show Debugger", exact=True).evaluate("el => el.click()")
                ui = DocsUI(page)
                ui.frames()
                page.evaluate("window.scrollTo(0, 500)")
                page.wait_for_function("document.querySelector('main canvas').luiViewportOffset >= 500")
                ui.frames()
                # Exact debugger/resize geometry is covered by test-page-viewport
                # in tests/debug.lisp; check the compiled page's visible controls.
                expect(page.get_by_text("Layout debugger", exact=True)).to_be_visible()
                # A close action remains accessible after scrolling the page.
                close = page.get_by_role("button", name="Close", exact=True)
                bounds = close.bounding_box()
                self.assertGreaterEqual(bounds["y"], 0)
                self.assertLess(bounds["y"] + bounds["height"], 700)
                close.evaluate("el => el.click()")
                ui.frames()
                self.assertEqual(page.get_by_role("button", name="Close", exact=True).count(), 0)
                self.assertEqual(errors, [])
            finally:
                browser.close()

    def test_mobile_symbol_list_uses_page_scroll(self):
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                executable_path=shutil.which("chromium-browser") or shutil.which("chromium"),
                args=["--no-sandbox"])
            try:
                page = browser.new_page(viewport={"width": 412, "height": 700},
                                        is_mobile=True, has_touch=True, device_scale_factor=2)
                errors = []
                page.on("pageerror", lambda error: errors.append(str(error)))
                page.goto((ROOT / "build/docs.html").as_uri())
                browse = page.get_by_role("button", name="Browse symbols", exact=True)
                browse.wait_for()
                ui = DocsUI(page)
                self.assertGreater(page.evaluate("document.documentElement.scrollHeight"), 700)
                browse.evaluate("el => el.click()")
                page.wait_for_function("document.documentElement.scrollHeight > innerHeight * 5")
                entries = page.locator('button[aria-label*=":"]:visible')
                first = entries.evaluate_all("els => els.map(el => el.getAttribute('aria-label'))")
                page.evaluate("window.scrollTo(0, document.documentElement.scrollHeight)")
                page.wait_for_function("""first => [...document.querySelectorAll('button[aria-label*=":"]')]
                    .some(el => getComputedStyle(el).visibility === 'visible' &&
                          !first.includes(el.getAttribute('aria-label')))""", arg=first)
                self.assertLess(entries.count(), 100)
                self.assertEqual(page.locator("main canvas").evaluate("c => c.height"), 1400)
                entries.last.evaluate("el => el.click()")
                page.wait_for_function("window.scrollY === 0")
                self.assertEqual(errors, [])
            finally:
                browser.close()

    def test_offline_navigation_widgets_and_debugger(self):
        with tempfile.TemporaryDirectory() as tmp, sync_playwright() as pw:
            path = Path(tmp) / "index.html"
            shutil.copyfile(ROOT / "build/docs.html", path)
            browser = pw.chromium.launch(
                executable_path=shutil.which("chromium-browser")
                or shutil.which("chromium"), args=["--no-sandbox"])
            ui = DocsUI(browser.new_page(viewport={"width": 1100, "height": 820}))
            requests, errors = [], []
            ui.page.on("request", lambda request: requests.append(request.url))
            ui.page.on("pageerror", lambda error: errors.append(str(error)))
            try:
                ui.page.goto(path.as_uri())
                ui.page.wait_for_selector("main canvas", timeout=60000)
                ui.frames()
                self.assertEqual(ui.page.locator("main canvas").count(), 1)
                self.assertTrue(ui.page.evaluate("typeof jscl === 'undefined'"))
                expect(ui.page.get_by_text(re.compile(
                    r" FPS · .*ms/frame \(layout\)"))).to_be_visible()
                ui.widget(text="Toolkit: Qt")
                ui.click_widget(text="Cycle Toolkit")
                ui.widget(text="Toolkit: Glass")
                for toolkit in ("Motif", "Garnet", "macOS", "Qt", "Glass"):
                    ui.click_widget(text="Cycle Toolkit")
                    ui.widget(text="Toolkit: " + toolkit)
                for palette in ("Light", "Dark", "Ocean", "Forest", "Default"):
                    ui.click_widget(text="Cycle Palette")
                    ui.widget(text="Palette: " + palette)
                ui.click_widget(text="Show Debugger")
                ui.widget(text="Layout debugger")
                ui.click_widget(text="Close")
                ui.click_widget(text="Toolkits", kind="list-item")
                for toolkit in ("macOS", "Qt", "Glass"):
                    ui.click_widget(text=toolkit, kind="tab")
                ui.click_widget(text="Try this button")
                ui.widget(text="Button clicks: 1")
                ui.search("checkbox")
                ui.click_widget(text="lui:CHECKBOX")
                expect(ui.page.get_by_role("checkbox", name="Enable the example", exact=True)).to_be_visible()
                ui.search("date-picker")
                ui.click_widget(text="lui:DATE-PICKER")
                caption = ui.page.get_by_text("Live preview: date-picker", exact=True)
                box = caption.bounding_box()
                ui.page.mouse.click(box["x"] + 40,
                                   box["y"] + box["height"] + 20)
                ui.frames()
                expect(ui.page.get_by_role("button", name="Today", exact=True)).to_be_visible()
                ui.click_widget(text="Today")
                ui.search("spinner")
                ui.click_widget(text="lui:SPINNER")
                expect(ui.page.get_by_role("status", name="Loading")
                       ).to_have_count(1)
                ui.search("menu-bar")
                ui.click_widget(text="lui:MENU-BAR")
                menu = ui.page.get_by_role("button", name="File", exact=True)
                box = menu.bounding_box()
                ui.page.mouse.move(box["x"] + box["width"] / 2,
                                   box["y"] + box["height"] / 2)
                ui.frames()
                expect(menu).to_have_attribute("aria-expanded", "true")
                ui.click_widget(text="New")
                ui.widget(text="Actions: 1")
                ui.page.set_viewport_size({"width": 540, "height": 500})
                ui.frames()
                expect(ui.page.get_by_role("button", name=re.compile(r"^(Browse symbols|Read selected)$"))).to_be_visible()
                self.assertEqual(errors, [])
                self.assertEqual(requests, [path.as_uri()])
            finally:
                browser.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
