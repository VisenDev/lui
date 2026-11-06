"""Exercise the standalone documentation artifact without a web server."""

from pathlib import Path
import re
import shutil
import tempfile
import unittest

from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]


class DocsWebTests(unittest.TestCase):
    def test_standalone_guides_search_reference_and_scroll(self):
        artifact = ROOT / "build/docs.html"
        self.assertTrue(artifact.is_file(), "Build docs with build-docs-web.lisp")
        with tempfile.TemporaryDirectory() as directory, sync_playwright() as pw:
            isolated = Path(directory) / "docs.html"
            shutil.copyfile(artifact, isolated)
            browser = pw.chromium.launch(
                executable_path=shutil.which("chromium-browser")
                or shutil.which("chromium"), args=["--no-sandbox"])
            page = browser.new_page(viewport={"width": 1000, "height": 760})
            errors, requests = [], []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("request", lambda request: requests.append(request.url))
            try:
                page.goto(isolated.as_uri())
                self.assertEqual(errors, [])
                self.assertEqual(page.locator("script").count(), 2)
                self.assertEqual(page.locator("script[src]").count(), 0)
                title = page.get_by_text("LUI documentation", exact=True)
                expect(title.filter(visible=True)).to_be_visible()
                page.screenshot(path=str(ROOT / "build/docs-web.png"))
                expect(page.get_by_role("option", name="Getting started",
                                        exact=True)).to_be_visible()
                page.get_by_role("option", name="Controls and options",
                                 exact=True).click()
                expect(page.get_by_text("Buttons return true when activated.",
                                        exact=False).filter(visible=True)).to_be_visible()
                page.get_by_role("option", name="All packages", exact=True).click()
                search = page.get_by_role("textbox")
                search.fill("button")
                expect(search).to_have_value("button")
                entries = page.get_by_role("option", name="lui:BUTTON", exact=True)
                expect(entries.first).to_be_visible()
                page.get_by_role("option", name="lui.garnet:BUTTON",
                                 exact=True).click()
                expect(page.locator("main > div[data-lui-style]").filter(
                    has_text=re.compile(r"^lui\.garnet:BUTTON$"))).to_be_visible()
                expect(page.get_by_text("Choose an API entry from the list.",
                                        exact=True)).to_have_count(0)
                search.fill("no-such-public-lui-entry-123")
                expect(page.get_by_text("No matching entries.", exact=True)
                       .filter(visible=True)).to_be_visible()
                search.fill("")
                page.set_viewport_size({"width": 1000, "height": 360})
                page.get_by_role("option", name="Getting started", exact=True).click()
                # Long guide content is clipped and scrolls inside its own pane.
                paragraph = page.get_by_text(
                    "LUI draws the same immediate-mode interface", exact=False
                ).filter(visible=True)
                before = paragraph.bounding_box()["y"]
                paragraph.hover()
                page.mouse.wheel(0, 240)
                page.wait_for_function("""old => {
                    const text = [...document.querySelectorAll('main > div')]
                        .find(n => n.textContent.startsWith('LUI draws the same'));
                    return text && text.getBoundingClientRect().y < old;
                }""", arg=before, timeout=5000)
                page.screenshot(path=str(ROOT / "build/docs-web-scrolled.png"))
                page.set_viewport_size({"width": 520, "height": 480})
                expect(search).to_be_visible()
                for name in ("Start", "Frames", "Controls"):
                    guide = page.get_by_role("option", name=name, exact=True)
                    self.assertTrue(guide.evaluate(
                        "node => node.scrollHeight <= node.clientHeight"), name)
                search.fill("checkbox")
                expect(page.get_by_role("option", name="lui:CHECKBOX", exact=True)
                       .first).to_be_visible()
                page.screenshot(path=str(ROOT / "build/docs-web-narrow.png"))
                self.assertEqual(errors, [])
                self.assertEqual(requests, [isolated.as_uri()])
            finally:
                browser.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
