"""Open the standalone docs offline and drive its canvas with real input."""

from pathlib import Path
import shutil
import tempfile
import unittest

import web
from playwright.sync_api import sync_playwright


class DocsWebTests(unittest.TestCase):
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
                page.goto((web.ROOT / "build/docs.html").as_uri())
                browse = page.get_by_role("button", name="Browse symbols", exact=True)
                browse.wait_for()
                ui = web.WebTests()
                ui.page = page
                self.assertGreater(page.evaluate("document.documentElement.scrollHeight"), 700)
                self.assertFalse(any(n["kind"] == "scrollbar" for n in ui.nodes()))
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
            shutil.copyfile(web.ROOT / "build/docs.html", path)
            browser = pw.chromium.launch(
                executable_path=shutil.which("chromium-browser")
                or shutil.which("chromium"), args=["--no-sandbox"])
            ui = web.WebTests()
            ui.page = browser.new_page(viewport={"width": 1100, "height": 820})
            requests, errors = [], []
            ui.page.on("request", lambda request: requests.append(request.url))
            ui.page.on("pageerror", lambda error: errors.append(str(error)))
            try:
                ui.page.goto(path.as_uri())
                ui.frames()
                self.assertEqual(ui.page.locator("main canvas").count(), 1)
                self.assertTrue(any("FPS" in n["text"] for n in ui.nodes()))
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
                ui.click_widget(id=":DOCS-SEARCH")
                ui.page.keyboard.insert_text("checkbox")
                ui.frames()
                ui.click_widget(text="lui:CHECKBOX", kind="list-item")
                self.assertTrue(any(n["kind"] == "checkbox" for n in ui.nodes()))
                ui.replace_text(":DOCS-SEARCH", "date-picker")
                ui.click_widget(text="lui:DATE-PICKER", kind="list-item")
                ui.click_widget(id="(:DOCS-DATE :INPUT)")
                ui.widget(text="Today", kind="list-item")
                ui.page.set_viewport_size({"width": 540, "height": 500})
                ui.frames()
                self.assertTrue(any(n["text"] in ("Browse symbols", "Read selected")
                                    for n in ui.nodes()))
                self.assertEqual(errors, [])
                self.assertEqual(requests, [path.as_uri()])
            finally:
                browser.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
