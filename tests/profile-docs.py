"""Profile actual mobile docs scrolling, optionally against an older HTML build.

Example: python3 tests/profile-docs.py --output build/profiles/after
Use --bundle build/profiles/before.html for a saved baseline. Requires the same
Playwright/Chromium setup as tests/web.py. CPU slowdown is not a real phone.
"""

import argparse
import json
import math
from pathlib import Path
import shutil
import statistics

from playwright.sync_api import sync_playwright
from web import ROOT

PHASES = (
    "%lui.frame::begin-frame", "%lui.docs::draw-docs", "%lui.frame::end-frame",
    "%lui.layout:solve", "lui.draw::%measure-widget", "lui.draw::%paint-frame",
    "lui.web::sync-overlay", "lui.debug::snapshot", "lui.debug::draw-debugger",
    "%lui.web.input:update-accessibility",
)
INSTRUMENT = r"""({phases, detail}) => {
    window.samples = [];
    let current;
    function patch(name, fn) {
        window.profileFunction = fn;
        jscl.evaluateString(`(setf (symbol-function '${name}) #j:window:profileFunction)`);
    }
    if (detail) for (const name of phases) {
        const original = jscl.evaluateString(`(symbol-function '${name})`);
        patch(name, function(...args) {
            const start = performance.now();
            const result = original(...args);
            if (current) current[name] = (current[name] || 0) + performance.now() - start;
            return result;
        });
    }
    const draw = jscl.evaluateString("(symbol-function 'lui.web::draw-frame)");
    patch('lui.web::draw-frame', function(...args) {
        const start = performance.now();
        current = {start, scroll: scrollY};
        const result = draw(...args);
        current.draw = performance.now() - start;
        document.querySelector('main').getBoundingClientRect();
        current.work = performance.now() - start;
        window.samples.push(current);
        current = undefined;
        return result;
    });
}"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, default=ROOT / "build/docs.html")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rates", type=int, nargs="+", default=[1, 6])
    parser.add_argument("--debugger", choices=["both", "open", "closed"], default="both")
    parser.add_argument("--detail", choices=["both", "yes", "no"], default="both")
    parser.add_argument("--wheels", type=int)
    parser.add_argument("--warmup", type=int)
    args = parser.parse_args()
    if any(rate < 1 for rate in args.rates):
        parser.error("CPU rates must be at least 1")
    if args.wheels is not None and args.wheels < 1:
        parser.error("--wheels must be positive")
    if args.warmup is not None and args.warmup < 0:
        parser.error("--warmup must be nonnegative")
    args.output.mkdir(parents=True, exist_ok=True)
    debuggers = [False, True] if args.debugger == "both" else [args.debugger == "open"]
    details = [False, True] if args.detail == "both" else [args.detail == "yes"]
    results = []
    print("Active draw + layout flush; excludes GPU raster/presentation.")
    print("CPU sampling is enabled. Detail timings overlap; do not sum them.")
    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            executable_path=shutil.which("chromium-browser") or shutil.which("chromium"),
            args=["--no-sandbox"])
        try:
            for rate in args.rates:
                for debug in debuggers:
                    for detail in details:
                        # Match the original investigation's per-case workloads.
                        warmup = args.warmup if args.warmup is not None else (10 if rate == 6 and not debug else 20)
                        wheels = args.wheels if args.wheels is not None else (20 if debug else 40 if rate == 6 else 100)
                        name = f"r{rate}-d{int(debug)}-detail{int(detail)}"
                        print(f"Starting {name}: {warmup} warmup, {wheels} measured wheel steps", flush=True)
                        page = browser.new_page(
                            viewport={"width": 412, "height": 700},
                            is_mobile=True, has_touch=True, device_scale_factor=2)
                        page.set_default_timeout(60000)
                        errors = []
                        page.on("pageerror", lambda error: errors.append(str(error)))
                        page.goto(args.bundle.resolve().as_uri())
                        page.get_by_role("button", name="Browse symbols", exact=True).evaluate("el => el.click()")
                        if debug:
                            page.get_by_role("button", name="Show debugger", exact=True).evaluate("el => el.click()")
                        page.wait_for_timeout(500)
                        cdp = page.context.new_cdp_session(page)
                        cdp.send("Emulation.setCPUThrottlingRate", {"rate": rate})
                        page.evaluate(INSTRUMENT, {"phases": PHASES, "detail": detail})
                        page.mouse.move(20, 620)
                        for _ in range(warmup):
                            page.mouse.wheel(0, 24)
                            page.wait_for_timeout(25)
                        before = page.evaluate("scrollY")
                        page.evaluate("window.samples = []")
                        cdp.send("Profiler.enable")
                        cdp.send("Profiler.start")
                        for _ in range(wheels):
                            page.mouse.wheel(0, 24)
                            page.wait_for_timeout(25)
                        profile = cdp.send("Profiler.stop")["profile"]
                        samples = page.evaluate("window.samples")
                        after = page.evaluate("scrollY")
                        if errors or not samples or after <= before:
                            raise AssertionError(f"Invalid scrolling run: {errors}, {before} -> {after}")
                        offset = page.locator("main canvas").evaluate("c => c.luiViewportOffset")
                        if abs(offset - after) > 1:
                            raise AssertionError(f"Canvas offset {offset} does not match page {after}")
                        (args.output / f"{name}.cpuprofile").write_text(json.dumps(profile))
                        (args.output / f"{name}.json").write_text(json.dumps(samples))
                        metrics = set().union(*(sample.keys() for sample in samples)) - {"start", "scroll"}
                        work = sorted(sample["work"] for sample in samples)
                        result = {
                            "case": name, "frames": len(samples), "warmup_wheels": warmup,
                            "measured_wheels": wheels, "scroll_before": before, "scroll_after": after,
                            "mean_ms": {key: statistics.fmean(s.get(key, 0) for s in samples) for key in sorted(metrics)},
                            "p95_ms": work[math.ceil(.95 * len(work)) - 1],
                            "work_per_wheel_ms": sum(work) / wheels,
                        }
                        results.append(result)
                        (args.output / "summary.json").write_text(json.dumps({
                            "bundle": str(args.bundle.resolve()), "browser": browser.version,
                            "viewport": [412, 700], "device_scale_factor": 2,
                            "results": results}, indent=2) + "\n")
                        print(json.dumps(result), flush=True)
                        page.close()
        finally:
            browser.close()


if __name__ == "__main__":
    main()
