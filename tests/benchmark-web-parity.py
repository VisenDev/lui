"""Matched browser redraw workloads, independent of the Lisp implementation."""
import functools
import http.server
import json
import os
from pathlib import Path
import shutil
import statistics
import threading

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
FRAMES = int(os.environ.get("BENCH_FRAMES", 60))
WARMUP = int(os.environ.get("WARMUP", 20))
if FRAMES < 2 or WARMUP < 0:
    raise ValueError("BENCH_FRAMES must be >=2 and WARMUP must be >=0")
INSTRUMENT = """(() => {
  const raf = window.requestAnimationFrame.bind(window);
  const transform = CanvasRenderingContext2D.prototype.setTransform;
  let painted = false, run = null;
  CanvasRenderingContext2D.prototype.setTransform = function(...args) {
    if (this.canvas.closest('main')) painted = true;
    return transform.apply(this, args);
  };
  function wake() { window.dispatchEvent(new Event('resize')); }
  window.requestAnimationFrame = callback => raf(time => {
    painted = false;
    const start = performance.now();
    callback(time);
    if (run && painted) {
      document.querySelector('main').getBoundingClientRect();
      const end = performance.now();
      if (run.warmup-- <= 0) run.samples.push({start, ms:end-start});
      if (run.samples.length === run.count) {
        const finished = run; run = null; finished.resolve(finished.samples);
      } else wake();
    }
  });
  window.measureRedraws = (count, warmup) => new Promise(resolve => {
    run = {count, warmup, resolve, samples:[]}; wake();
  });
})();"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(
    ("127.0.0.1", 0), functools.partial(QuietHandler, directory=ROOT))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
results = []
try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            executable_path=shutil.which("chromium-browser") or shutil.which("chromium"),
            args=["--no-sandbox"])
        for backend, path in (("jscl", "examples/web.html"),
                              ("ecl", os.environ.get("ECL_PAGE", "build/web-ecl/index.html"))):
            page = browser.new_page(viewport={
                "width": int(os.environ.get("BENCH_WIDTH", 900)),
                "height": int(os.environ.get("BENCH_HEIGHT", 700))})
            page.set_default_timeout(180000)
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.add_init_script(INSTRUMENT)
            page.goto(f"http://127.0.0.1:{server.server_port}/{path}")
            page.get_by_role("button", name="Say hello", exact=True).wait_for(state="attached")
            for toolkit in os.environ.get("BENCH_TOOLKITS", "Qt").split(","):
                for _ in range(5):
                    if page.get_by_text("Toolkit: " + toolkit, exact=True).count():
                        break
                    page.get_by_role("button", name="Cycle toolkit", exact=True).evaluate("b => b.click()")
                    page.wait_for_timeout(300)
                assert page.get_by_text("Toolkit: " + toolkit, exact=True).count(), toolkit
                for name in os.environ.get("BENCH_PAGES", "Controls,Editing,Layout,Scroll,Styles").split(","):
                    for tab in (["7GUIs", name.split("/", 1)[1]] if "/" in name else [name]):
                        page.get_by_role("button", name=tab, exact=True).evaluate("b => b.click()")
                        page.wait_for_timeout(300)
                    profiler = None
                    if os.environ.get("PROFILE") == "1" and backend == "ecl":
                        profiler = page.context.new_cdp_session(page)
                        profiler.send("Profiler.enable")
                        profiler.send("Profiler.start")
                    samples = page.evaluate("([n,w]) => measureRedraws(n,w)",
                                            [FRAMES, WARMUP])
                    if profiler:
                        profile = profiler.send("Profiler.stop")["profile"]
                        (ROOT / "build/profiles").mkdir(parents=True, exist_ok=True)
                        filename = toolkit + "-" + name.replace("/", "-") + ".json"
                        (ROOT / "build/profiles" / filename).write_text(json.dumps(profile))
                        profiler.detach()
                    durations = sorted(sample["ms"] for sample in samples)
                    result = {"backend": backend, "toolkit": toolkit, "page": name,
                              "frames": len(samples), "warmup": WARMUP,
                              "viewport": page.viewport_size, "browser": browser.version, "median_ms": statistics.median(durations),
                              "p95_ms": durations[int(.95 * (len(durations)-1))],
                              "active_fps": 1000*(len(samples)-1)/(samples[-1]["start"]-samples[0]["start"])}
                    print(json.dumps(result), flush=True)
                    results.append(result)
            assert not errors, errors
            page.close()
        browser.close()
finally:
    server.shutdown()
    server.server_close()
    thread.join()
if os.environ.get("BENCH_OUTPUT"):
    output = Path(os.environ["BENCH_OUTPUT"])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(results, indent=2) + "\n")
