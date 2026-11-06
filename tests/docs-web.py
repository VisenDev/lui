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
                page.get_by_role("button", name="Debug", exact=True).click()
                inspector = page.get_by_text("Layout inspector", exact=True)
                expect(inspector.filter(visible=True)).to_be_visible()
                page.get_by_role("button", name="Close", exact=True).click()
                expect(inspector.filter(visible=True)).to_have_count(0)
                page.get_by_role("option", name="Debugger", exact=True).click()
                page.get_by_role("button", name="Open inspector").click()
                expect(page.get_by_role("separator", name="Inspector width")
                       ).to_be_visible()
                root_row = page.get_by_role("option", name=re.compile(
                    r"^:?COLUMN$")).first
                root_row.click()
                page.get_by_role("button", name="Expand details").click()
                expect(root_row).to_have_count(0)
                page.get_by_role("button", name="Restore tree").click()
                expect(root_row).to_be_visible()
                root_row.click()
                expect(page.get_by_role("button", name="Close details",
                                        exact=True)).to_have_count(0)
                root_row.click()
                page.get_by_role("button", name="Expand details").click()
                page.get_by_role("button", name="Close details").click()
                expect(root_row).to_be_visible()
                expect(inspector.filter(visible=True)).to_be_visible()
                page.get_by_role("button", name="Close", exact=True).click()
                expect(inspector.filter(visible=True)).to_have_count(0)
                page.get_by_role("option", name="Getting started",
                                 exact=True).click()
                page.screenshot(path=str(ROOT / "build/docs-web.png"))
                expect(page.get_by_role("option", name="Getting started",
                                        exact=True)).to_be_visible()
                page.get_by_role("option", name="Controls and options",
                                 exact=True).click()
                expect(page.get_by_text("Buttons return true when activated.",
                                        exact=False).filter(visible=True)).to_be_visible()
                page.get_by_role("option", name="All packages", exact=True).click()
                search = page.get_by_role("textbox")
                # The reference has room for a full-height column of symbols.
                search_box = search.bounding_box()
                candidates = page.get_by_role("option").all()
                rows = [item.bounding_box() for item in candidates
                        if ":" in (item.text_content() or "")]
                visible = [box for box in rows if box and
                           search_box["y"] < box["y"] < 750]
                self.assertGreater(max(b["y"] for b in visible) -
                                   min(b["y"] for b in visible), 380)
                bars = page.get_by_role("scrollbar").all()
                symbol_bar = next(bar for bar in bars if
                                  search_box["x"] <= bar.bounding_box()["x"]
                                  <= search_box["x"] + search_box["width"])
                symbol_bar.press("End")
                expect(symbol_bar).to_have_attribute("aria-valuenow",
                    symbol_bar.get_attribute("aria-valuemax"))
                symbol_bar.press("Home")
                expect(symbol_bar).to_have_attribute("aria-valuenow", "0")
                # Hold the next draw to exercise two real clicks in one frame.
                page.evaluate("""() => {
                    const raf = window.requestAnimationFrame.bind(window);
                    const pending = [];
                    window.requestAnimationFrame = cb => pending.push(cb);
                    window.resumeDocs = () => {
                        window.requestAnimationFrame = raf;
                        pending.forEach(cb => raf(cb));
                    };
                }""")
                for symbol in ("lui:CHECKBOX", "lui:BUTTON"):
                    box = page.get_by_role("option", name=symbol,
                                           exact=True).bounding_box()
                    page.mouse.click(box["x"] + 15, box["y"] + 12)
                page.evaluate("window.resumeDocs()")
                expect(page.locator("main > div[data-lui-style]").filter(
                    has_text=re.compile(r"^lui:BUTTON$"))).to_be_visible()
                # Releasing over a different row cancels the click.
                check = page.get_by_role("option", name="lui:CHECKBOX",
                                         exact=True).bounding_box()
                cell = page.get_by_role("option", name="lui:CELL",
                                        exact=True).bounding_box()
                page.mouse.move(check["x"] + 15, check["y"] + 10)
                page.mouse.down()
                page.mouse.move(cell["x"] + 15, cell["y"] + 10)
                page.mouse.up()
                page.evaluate("""() => new Promise(resolve =>
                    requestAnimationFrame(() => requestAnimationFrame(resolve)))""")
                expect(page.locator("main > div[data-lui-style]").filter(
                    has_text=re.compile(r"^lui:BUTTON$"))).to_be_visible()
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
                search.fill("checkbox")
                page.get_by_role("option", name="lui:CHECKBOX",
                                 exact=True).click()
                preview = page.get_by_role("checkbox")
                expect(preview).to_have_count(1)
                for current, following in (("Glass", "Motif"),
                                           ("Motif", "Garnet"),
                                           ("Garnet", "Glass")):
                    checked = preview.is_checked()
                    preview.click()
                    self.assertNotEqual(preview.is_checked(), checked)
                    page.get_by_role("button", name=current, exact=True).click()
                    expect(page.get_by_role("button", name=following,
                                            exact=True)).to_be_visible()
                    self.assertNotEqual(preview.is_checked(), checked)
                self.assertEqual(page.get_by_role(
                    "option", name="lui.wayland-protocol", exact=True).count(), 0)
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
                for width in (520, 720, 1000):
                    page.set_viewport_size({"width": width, "height": 600})
                    search.fill("text-input-event")
                    full_name = "lui.interaction:TEXT-INPUT-EVENT"
                    wrapped = re.compile(r"\s*".join(map(re.escape, full_name)))
                    option = page.get_by_role("option", name=wrapped)
                    expect(option).to_be_visible()
                    self.assertTrue(option.evaluate(r"""node => {
                        const text = node.textContent.replace(/\s/g, '');
                        if (text.toLowerCase() !==
                            'lui.interaction:text-input-event') return false;
                        const box = node.getBoundingClientRect();
                        const range = document.createRange();
                        range.selectNodeContents(node);
                        return [...range.getClientRects()].every(r =>
                            r.left >= box.left - 1 && r.right <= box.right + 1
                            && r.top >= box.top - 1 && r.bottom <= box.bottom + 1);
                    }"""), width)
                page.get_by_role("button", name="Glass", exact=True).click()
                page.get_by_role("button", name="Motif", exact=True).click()
                guides = ("Controls and options", "Layout and scrolling",
                          "Input and inspection", "Backends and running")
                for name in guides:
                    guide = page.get_by_role("option", name=name, exact=True)
                    guide.click()
                    self.assertTrue(guide.evaluate("""node => {
                        const box = node.getBoundingClientRect();
                        const range = document.createRange();
                        range.selectNodeContents(node);
                        return [...range.getClientRects()].every(r =>
                            r.top >= box.top - 1 && r.bottom <= box.bottom + 1);
                    }"""), name)
                page.screenshot(path=str(ROOT / "build/docs-web-garnet.png"))
                self.assertEqual(errors, [])
                self.assertEqual(requests, [isolated.as_uri()])
            finally:
                browser.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
