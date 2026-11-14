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
                ui.click_widget("Full demo")
                ui.widget("LUI feature gallery")
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
                page.get_by_role("button", name="Show debugger", exact=True).evaluate("el => el.click()")
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
                ui.click_widget(text="Cycle toolkit")
                ui.widget(text="Toolkit: Glass")
                for toolkit in ("Motif", "Garnet", "macOS", "Qt", "Glass"):
                    ui.click_widget(text="Cycle toolkit")
                    ui.widget(text="Toolkit: " + toolkit)
                for palette in ("Light", "Dark", "Ocean", "Forest", "Default"):
                    ui.click_widget(text="Cycle palette")
                    ui.widget(text="Palette: " + palette)
                ui.click_widget(text="Show debugger")
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
