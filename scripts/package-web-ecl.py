"""Package the Emscripten single-file loader into a standalone HTML page."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
template = (ROOT / "examples/web-ecl.html").read_text()
javascript = (ROOT / "build/web-ecl/lui.js").read_text()
# HTML recognizes closing script tags even inside JavaScript string literals.
javascript = re.sub(r"</script", lambda match: r"<\/" + match[0][2:],
                    javascript, flags=re.IGNORECASE)
html, count = re.subn(
    r'<script src="\.\./build/web-ecl/lui\.js"\s+onerror="[^"]*"></script>',
    lambda match: "<script>\n" + javascript + "\n</script>", template)
if count != 1:
    raise SystemExit("Expected exactly one ECL loader script in the HTML template")
(ROOT / "build/web-ecl/index.html").write_text(html)
