"""Open the standalone docs offline and drive its canvas with real input."""

from pathlib import Path
import shutil
import tempfile
import unittest

import web
from playwright.sync_api import sync_playwright


class DocsWebTests(unittest.TestCase):
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
                ui.click_widget(text="Cycle toolkit")
                ui.widget(text="Toolkit: Motif")
                ui.click_widget(text="Show debugger")
                ui.widget(text="Layout debugger")
                ui.click_widget(text="Close")
                ui.click_widget(text="Toolkits", kind="list-item")
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
