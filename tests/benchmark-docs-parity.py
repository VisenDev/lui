"""Compare standalone ECL/MiriCL docs using identical real browser workloads.

Redraw timings include a layout flush, but exclude GPU raster/presentation.
Startup is local-file navigation to populated docs, with a fresh context.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import platform
import json
import math
from pathlib import Path
import shutil
import statistics

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
INSTRUMENT = """(() => {
  new MutationObserver((records, observer) => {
    const main = document.querySelector('main');
    if (main?.querySelector('canvas') && main.textContent.includes('Getting started')) {
      window.docsReadyMs = performance.now(); observer.disconnect();
    }
  }).observe(document, {childList:true, subtree:true});
  const raf = requestAnimationFrame.bind(window);
  const transform = CanvasRenderingContext2D.prototype.setTransform;
  let painted = false, run = null;
  CanvasRenderingContext2D.prototype.setTransform = function(...args) {
    if (this.canvas.closest('main')) painted = true;
    return transform.apply(this, args);
  };
  const wake = () => window.dispatchEvent(new Event('resize'));
  window.requestAnimationFrame = callback => raf(time => {
    painted = false;
    const start = performance.now();
    callback(time);
    if (run && painted) {
      document.querySelector('main').getBoundingClientRect();
      const ms = performance.now() - start;
      if (run.warmup-- <= 0) run.samples.push(ms);
      if (run.samples.length === run.count) {
        const finished = run; run = null; finished.resolve(finished.samples);
      } else wake();
    }
  });
  window.measureRedraws = (count, warmup) => new Promise(resolve => {
    run = {count, warmup, resolve, samples:[]}; wake();
  });
})();"""


def summary(samples):
    ordered = sorted(samples)
    return {"mean_ms": statistics.mean(samples),
            "median_ms": statistics.median(samples),
            "p95_ms": ordered[math.ceil(len(ordered) * .95) - 1],
            "samples": len(samples)}


def click(page, name):
    page.get_by_role("button", name=name, exact=True).evaluate("el => el.click()")
    page.wait_for_timeout(200)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=int, default=120)
    parser.add_argument("--warmup", type=int, default=30)
    parser.add_argument("--rounds", type=int, default=2)
    parser.add_argument("--output", type=Path,
                        default=ROOT / "build/miricl-docs-comparison.json")
    args = parser.parse_args()
    if args.frames < 2 or args.warmup < 0 or args.rounds < 1:
        parser.error("Need frames >= 2, warmup >= 0, rounds >= 1")
    pages = {"ecl": ROOT / "build/docs.html",
             "miricl": ROOT / "build/docs-miricl/index.html"}
    cpu = platform.processor()
    if Path("/proc/cpuinfo").exists():
        cpu = next((line.split(":", 1)[1].strip()
                    for line in Path("/proc/cpuinfo").read_text().splitlines()
                    if line.startswith("model name")), cpu)
    results = {"created_at": datetime.now(timezone.utc).isoformat(),
               "compile_policy": {"speed": 3, "safety": 2, "debug": 0, "space": 0},
               "settings": vars(args) | {"output": str(args.output)},
               "sizes": {}, "startup": {}, "redraws": [],
               "host": platform.platform(), "cpu": cpu}
    for name, path in pages.items():
        data = path.read_bytes()
        results["sizes"][name] = {"sha256": hashlib.sha256(data).hexdigest(),
                                   "html_bytes": len(data),
                                   "gzip_bytes": len(gzip.compress(data, mtime=0))}
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=shutil.which("chromium-browser")
                                   or shutil.which("chromium"), args=["--no-sandbox"])
        results["browser"] = browser.version
        for round_number in range(args.rounds):
            order = list(pages) if round_number % 2 == 0 else list(reversed(pages))
            for backend in order:
                for mobile in [False, True]:
                    context = browser.new_context(
                        viewport={"width": 412 if mobile else 1100,
                                  "height": 700 if mobile else 820},
                        is_mobile=mobile, has_touch=mobile,
                        device_scale_factor=2 if mobile else 1)
                    page = context.new_page()
                    page.set_default_timeout(120000)
                    errors = []
                    page.on("pageerror", lambda error: errors.append(str(error)))
                    page.add_init_script(INSTRUMENT)
                    page.goto(pages[backend].as_uri())
                    page.wait_for_function("window.docsReadyMs > 0")
                    results["startup"].setdefault(backend, []).append(
                        {"mobile": mobile, "round": round_number,
                         "ms": page.evaluate("docsReadyMs")})
                    if mobile:
                        click(page, "Browse symbols")
                        cases = ["symbols", "symbols-debugger"]
                    else:
                        cases = ["docs", "docs-debugger", "gallery-controls", "gallery-cells"]
                    for case in cases:
                        if case.endswith("debugger"):
                            click(page, "Show Debugger")
                        elif case == "gallery-controls":
                            click(page, "Close")
                            click(page, "View Full Demo")
                        elif case == "gallery-cells":
                            click(page, "7GUIs")
                            click(page, "Cells")
                        samples = page.evaluate("([n,w]) => measureRedraws(n,w)",
                                                [args.frames, args.warmup])
                        row = {"backend": backend, "case": case,
                               "round": round_number, "mobile": mobile,
                               **summary(samples), "raw_ms": samples}
                        results["redraws"].append(row)
                        print(backend, case, summary(samples), flush=True)
                    if errors:
                        raise AssertionError(errors)
                    context.close()
        browser.close()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps({"sizes": results["sizes"], "startup": results["startup"]}, indent=2))


if __name__ == "__main__":
    main()
