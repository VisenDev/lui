"""Measure actual Lisp/layout/DOM work on actively refreshed gallery frames."""

import json
import math
import os
from pathlib import Path
import statistics

from web import WebTests
from playwright.sync_api import expect

toolkits = tuple(os.environ.get("BENCH_TOOLKITS", "Glass,Motif,Garnet").split(","))
pages = ("Controls", "Editing", "Layout", "Scroll", "Styles") + tuple(
    "7GUIs/" + task for task in
    ("Counter", "Temperature", "Flight", "Timer", "CRUD", "Circles", "Cells")
)
case_count = len(toolkits) * len(pages)
frames = int(os.environ.get("BENCH_FRAMES", "240"))
warmup = int(os.environ.get("WARMUP", "30"))
if frames < case_count or warmup < 0:
    raise ValueError(f"BENCH_FRAMES must be >={case_count} and WARMUP >=0")

RAW_PROFILE = r"""({count, warmup}) => new Promise(resolve => {
    const original = jscl.evaluateString("(symbol-function 'lui.web::draw-frame)");
    const refresh = jscl.evaluateString("(symbol-function 'lui.web:refresh)");
    const samples = [];
    let completed = 0;
    window.__luiBenchmarkFunction = function(...args) {
        window.__luiBenchmarkApp = args[0];
        const start = performance.now();
        const result = original(...args);
        const drawn = performance.now();
        document.querySelector('main').getBoundingClientRect();
        const finished = performance.now();
        if (completed++ >= warmup) samples.push({start,
            draw_ms:drawn-start, work_ms:finished-start});
        if (samples.length === count) {
            window.__luiBenchmarkFunction = original;
            jscl.evaluateString(`(setf (symbol-function 'lui.web::draw-frame)
                #j:window:__luiBenchmarkFunction)`);
            delete window.__luiBenchmarkFunction;
            resolve(samples);
        } else refresh(...args);
        return result;
    };
    jscl.evaluateString(`(setf (symbol-function 'lui.web::draw-frame)
        #j:window:__luiBenchmarkFunction)`);
    window.dispatchEvent(new Event('resize'));
})"""

PROFILE = r"""({count, warmup}) => new Promise(resolve => {
    const names = ['draw-frame', 'measure-widget', 'update-node'];
    const original = Object.fromEntries(names.map(name => [name,
        jscl.evaluateString(`(symbol-function 'lui.web::${name})`)]));
    const refresh = jscl.evaluateString("(symbol-function 'lui.web:refresh)");
    const setProperty = CSSStyleDeclaration.prototype.setProperty;
    const rect = Element.prototype.getBoundingClientRect;
    let current, completed = 0;
    const samples = [];
    CSSStyleDeclaration.prototype.setProperty = function(...args) {
        if (current) current.style_writes++;
        return setProperty.apply(this, args);
    };
    Element.prototype.getBoundingClientRect = function(...args) {
        if (current) current.layout_reads++;
        return rect.apply(this, args);
    };
    function patch(name, fn) {
        window.__luiBenchmarkFunction = fn;
        jscl.evaluateString(`(setf (symbol-function 'lui.web::${name})
            #j:window:__luiBenchmarkFunction)`);
    }
    for (const [name, metric] of [['measure-widget','measure_ms'],
                                ['update-node','dom_ms']]) {
        patch(name, function(...args) {
            const start = performance.now();
            const result = original[name](...args);
            if (current) {
                current[metric] += performance.now() - start;
                if (name === 'measure-widget') current.measure_calls++;
            }
            return result;
        });
    }
    patch('draw-frame', function(...args) {
        window.__luiBenchmarkApp = args[0];
        current = {measure_ms:0, dom_ms:0, measure_calls:0,
                   style_writes:0, layout_reads:0, start:performance.now()};
        const result = original['draw-frame'](...args);
        current.draw_ms = performance.now() - current.start;
        // Include deferred browser style/layout cost, but not GPU raster time.
        document.querySelector('main').getBoundingClientRect();
        current.work_ms = performance.now() - current.start;
        if (completed++ >= warmup) samples.push(current);
        current = undefined;
        if (samples.length === count) {
            for (const name of names) patch(name, original[name]);
            CSSStyleDeclaration.prototype.setProperty = setProperty;
            Element.prototype.getBoundingClientRect = rect;
            delete window.__luiBenchmarkFunction;
            resolve(samples);
        } else {
            // Drive real application work. An idle rAF interval is not a frame.
            refresh(...args);
        }
        return result;
    });
    window.dispatchEvent(new Event('resize'));
})"""

WebTests.setUpClass()
results = []
try:
    viewport = {"width": int(os.environ.get("BENCH_WIDTH", "900")),
                "height": int(os.environ.get("BENCH_HEIGHT", "700"))}
    if min(viewport.values()) <= 0:
        raise ValueError("BENCH_WIDTH and BENCH_HEIGHT must be positive")
    page = WebTests.browser.new_page(viewport=viewport)
    page.set_default_timeout(60000)
    if os.environ.get("BENCH_BUNDLE"):
        bundle = Path(os.environ["BENCH_BUNDLE"]).resolve()
        page.route("**/build/lui-web.js", lambda route: route.fulfill(
            path=str(bundle), content_type="text/javascript"))
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(f"http://127.0.0.1:{WebTests.server.server_port}/examples/web.html")
    page.get_by_role("tab", name="Controls", exact=True).wait_for()
    detail = bool(os.environ.get("BENCH_DETAIL"))
    print(f"Viewport: {viewport['width']}x{viewport['height']}")
    print("Active completed frames: Lisp/layout/DOM elapsed time + browser layout flush; excludes GPU raster")
    print("Diagnostic per-function instrumentation" if detail else
          "Raw timing: only draw entry/exit and one browser layout flush")
    print("toolkit page frames draw_mean_ms flush_mean_ms work_mean_ms "
          "work_p50_ms work_p95_ms work_max_ms active_fps scroll_delta_px")
    current_toolkit = "Glass"
    for case, (toolkit, name) in enumerate(
        (toolkit, name) for toolkit in toolkits for name in pages
    ):
        while current_toolkit != toolkit:
            page.get_by_role("button", name=current_toolkit, exact=True).click()
            current_toolkit = {"Glass": "Motif", "Motif": "Garnet",
                               "Garnet": "Glass"}[current_toolkit]
            expect(page.get_by_role("button", name=current_toolkit,
                                    exact=True)).to_be_visible()
        for tab_name in name.split("/"):
            tab = page.get_by_role("tab", name=tab_name, exact=True)
            tab.click()
            expect(tab).to_have_attribute("aria-selected", "true")
        samples = page.evaluate(PROFILE if detail else RAW_PROFILE, {
            "count": frames // case_count + (case < frames % case_count),
            "warmup": warmup // case_count + (case < warmup % case_count),
        })
        work = sorted(sample["work_ms"] for sample in samples)
        active_fps = (1000 * (len(samples) - 1) /
                      (samples[-1]["start"] - samples[0]["start"])
                      if len(samples) > 1 else None)
        scroll_delta = None
        if name == "Scroll":
            page.evaluate("""() => {
                window.__luiReadScroll = jscl.evaluateString(`(lambda ()
                    (let ((total 0))
                      (maphash (lambda (id offset) (declare (ignore id))
                                 (incf total (cdr offset)))
                               (lui.frame::context-scroll
                                (lui.web::web-app-context
                                 #j:window:__luiBenchmarkApp)))
                      total))`);
            }""")
            scroll_value = "() => window.__luiReadScroll()"
            visible_rows = """() => Array.from(document.querySelectorAll('main button'))
                .filter(n => n.textContent.startsWith('Item ') &&
                    getComputedStyle(n).display !== 'none' &&
                    (() => {const r=n.getBoundingClientRect();
                        return r.top>=0 && r.bottom<=innerHeight &&
                            document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)===n;})())
                .map(n => n.textContent).join('|')"""
            before = page.evaluate(scroll_value)
            rows_before = page.evaluate(visible_rows)
            row = page.get_by_role("button", name="Item 01 — selectable row", exact=True)
            row.hover()
            page.evaluate("""() => {window.__luiWheelStart = undefined;
                window.addEventListener('wheel', () => {
                    window.__luiWheelStart = performance.now();
                }, {capture:true, once:true});}""")
            page.mouse.wheel(0, 240)
            page.wait_for_function("before => window.__luiReadScroll()>before", arg=before)
            model_latency = page.evaluate("performance.now()-window.__luiWheelStart")
            page.wait_for_function("({read, before}) => (0,eval)('('+read+')')()!==before",
                                   arg={"read": visible_rows, "before": rows_before})
            visible_latency = page.evaluate("performance.now()-window.__luiWheelStart")
            scroll_delta = page.evaluate(scroll_value) - before
            if scroll_delta <= 0:
                raise AssertionError("Wheel over a row did not scroll the app")
        result = {"toolkit": toolkit, "page": name, "frames": len(samples),
                  "mean_ms": statistics.fmean(work),
                  "draw_ms": statistics.fmean(s["draw_ms"] for s in samples),
                  "flush_ms": statistics.fmean(s["work_ms"] - s["draw_ms"]
                                                 for s in samples),
                  "p50_ms": work[math.ceil(len(work) * .5) - 1],
                  "p95_ms": work[math.ceil(len(work) * .95) - 1],
                  "max_ms": max(work), "active_fps": active_fps,
                  "scroll_delta_px": scroll_delta,
                  "scroll_model_observed_ms": model_latency if name == "Scroll" else None,
                  "scroll_visible_observed_ms": visible_latency if name == "Scroll" else None}
        if detail:
            for metric in ("measure_ms", "dom_ms", "style_writes", "layout_reads"):
                result[metric] = statistics.fmean(sample[metric] for sample in samples)
        results.append(result)
        numbers = [result[key] for key in ("draw_ms", "flush_ms", "mean_ms", "p50_ms", "p95_ms", "max_ms",
                   "active_fps", "scroll_delta_px")]
        print(toolkit, name, len(samples),
              " ".join("-" if value is None else f"{value:.3f}" for value in numbers),
              flush=True)
    if errors:
        raise RuntimeError("; ".join(errors))
    if os.environ.get("BENCH_OUTPUT"):
        Path(os.environ["BENCH_OUTPUT"]).write_text(json.dumps(results, indent=2) + "\n")
    page.close()
finally:
    WebTests.tearDownClass()
