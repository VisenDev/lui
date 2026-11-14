"""Package the Emscripten single-file loader into a standalone HTML page."""
from pathlib import Path
import re
import argparse
import html as html_module

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--javascript", default="build/web-ecl/lui.js")
parser.add_argument("--output", default="build/web-ecl/index.html")
parser.add_argument("--title", default="LUI — ECL / WebAssembly")
args = parser.parse_args()
template = (ROOT / "examples/web-ecl.html").read_text()
javascript = (ROOT / args.javascript).read_text()
# HTML recognizes closing script tags even inside JavaScript string literals.
javascript = re.sub(r"</script", lambda match: r"<\/" + match[0][2:],
                    javascript, flags=re.IGNORECASE)
html, count = re.subn(
    r'<script src="\.\./build/web-ecl/lui\.js"\s+onerror="[^"]*"></script>',
    lambda match: "<script>\n" + javascript + "\n</script>", template)
if count != 1:
    raise SystemExit("Expected exactly one ECL loader script in the HTML template")
html = re.sub(r"<title>.*?</title>",
              lambda match: "<title>" + html_module.escape(args.title) + "</title>", html)
(ROOT / args.output).write_text(html)
