"""Measure actual Lisp/layout/canvas work on active gallery frames."""

import json
import math
import os
from pathlib import Path
import statistics

from web import WebTests

toolkits = tuple(os.environ.get("BENCH_TOOLKITS", "Glass,Motif,Garnet").split(","))
pages = ("Controls", "Editing", "Layout", "Scroll", "Styles") + tuple(
    "7GUIs/" + task for task in
    ("Counter", "Temperature", "Flight", "Timer", "CRUD", "Circles", "Cells")
)
if os.environ.get("BENCH_PAGES"):
    pages = tuple(os.environ["BENCH_PAGES"].split(","))
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
    const names = ['lui.web::draw-frame', 'lui.layout:solve',
                   'lui.draw::measure-widget', 'lui.draw::paint-frame', 'lui.web::sync-overlay'];
    const original = Object.fromEntries(names.map(name => [name,
        jscl.evaluateString(`(symbol-function '${name})`)]));
    const refresh = jscl.evaluateString("(symbol-function 'lui.web:refresh)");
    let current, completed = 0;
    const samples = [];
    function patch(name, fn) {
        window.__luiBenchmarkFunction = fn;
        jscl.evaluateString(`(setf (symbol-function '${name})
            #j:window:__luiBenchmarkFunction)`);
    }
    for (const [name, metric] of [[names[1], 'layout_ms'],
                                [names[2], 'measure_ms'],
                                [names[3], 'paint_ms'], [names[4], 'overlay_ms']]) {
        patch(name, function(...args) {
            const start = performance.now();
            const result = original[name](...args);
            if (current) current[metric] += performance.now() - start;
            return result;
        });
    }
    patch(names[0], function(...args) {
        window.__luiBenchmarkApp = args[0];
        current = {layout_ms:0, measure_ms:0, paint_ms:0, overlay_ms:0,
                   start:performance.now()};
        const result = original[names[0]](...args);
        current.draw_ms = performance.now() - current.start;
        document.querySelector('main canvas').getBoundingClientRect();
        current.work_ms = performance.now() - current.start;
        if (completed++ >= warmup) samples.push(current);
        current = undefined;
        if (samples.length === count) {
            for (const name of names) patch(name, original[name]);
            delete window.__luiBenchmarkFunction;
            resolve(samples);
        } else refresh(...args);
        return result;
    });
    window.dispatchEvent(new Event('resize'));
})"""

def nodes(page):
    return page.evaluate("""() => {
        return jscl.evaluateString(`
          (let ((result (jscl/ffi:new #j:Array)))
            (lui.layout:walk-elements
             (lui.frame:context-root
              (lui.web::web-app-context
               (jscl/ffi:oget (#j:document:querySelector #j"main canvas")
                              "luiApp")))
             (lambda (node)
               (let ((widget (lui.layout:element-content node))
                     (box (lui.layout:element-box node))
                     (clip (lui.layout:element-clip node)))
                 (when (and (lui.widgets:widget-p widget)
                            (plusp (lui.layout:box-width clip))
                            (plusp (lui.layout:box-height clip)))
                   (let ((item (jscl/ffi:new #j:Object)))
                     (setf (jscl/ffi:oget item "text")
                           (jscl/ffi:jsstring (lui.widgets:widget-text widget))
                           (jscl/ffi:oget item "kind")
                           (jscl/ffi:jsstring
                            (symbol-name (lui.widgets:widget-kind widget)))
                           (jscl/ffi:oget item "x")
                           (+ (lui.layout:box-x clip)
                              (/ (lui.layout:box-width clip) 2))
                           (jscl/ffi:oget item "y")
                           (+ (lui.layout:box-y clip)
                              (/ (lui.layout:box-height clip) 2))
                           (jscl/ffi:oget item "top")
                           (lui.layout:box-y box))
                     ((jscl/ffi:oget result "push") item))))))
            result))`);
    }""")


def click(page, text, kind):
    item = next(n for n in nodes(page)
                if n["text"] == text and n["kind"] == kind.upper())
    page.mouse.click(item["x"], item["y"])
    page.evaluate("""() => new Promise(resolve =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)))""")


def has_text(page, text):
    return any(n["text"] == text for n in nodes(page))


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
    page.add_init_script("""(() => {
        const raf = window.requestAnimationFrame.bind(window);
        window.requestAnimationFrame = callback => raf(timestamp => {
            const start = performance.now();
            const result = callback(timestamp);
            const canvas = document.querySelector('main canvas');
            if (!window.__luiFirstFrame && canvas?.luiApp) {
                window.__luiFirstFrame = {
                    navigation_ms: performance.now(),
                    callback_ms: performance.now() - start};
            }
            return result;
        });
    })()""")
    page.goto(f"http://127.0.0.1:{WebTests.server.server_port}/examples/web.html")
    page.wait_for_function("document.querySelector('main canvas')?.luiApp")
    page.wait_for_function("window.__luiFirstFrame")
    cold_load = page.evaluate("window.__luiFirstFrame")
    detail = bool(os.environ.get("BENCH_DETAIL"))
    print("Cold first animation callback:", json.dumps(cold_load))
    print(f"Viewport: {viewport['width']}x{viewport['height']}")
    print("Active completed frames: Lisp/layout/canvas submission + browser layout flush; excludes GPU raster")
    print("Diagnostic per-function instrumentation" if detail else
          "Raw timing: only draw entry/exit and one browser layout flush")
    print("toolkit page frames draw_mean_ms flush_mean_ms work_mean_ms "
          "work_p50_ms work_p95_ms work_max_ms active_fps scroll_delta_px")
    current_toolkit = "Glass"
    assert has_text(page, "Toolkit: Glass")
    for case, (toolkit, name) in enumerate(
        (toolkit, name) for toolkit in toolkits for name in pages
    ):
        while current_toolkit != toolkit:
            click(page, "Cycle toolkit", "button")
            current_toolkit = {"Glass": "Motif", "Motif": "Garnet",
                               "Garnet": "Glass"}[current_toolkit]
            assert has_text(page, f"Toolkit: {current_toolkit}")
        for tab_name in name.split("/"):
            click(page, tab_name, "tab")
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
            before = page.evaluate(scroll_value)
            rows_before = [(n["text"], n["top"]) for n in nodes(page)
                           if n["text"].startswith("Item ")]
            row = next(n for n in nodes(page)
                       if n["text"] == "Item 01 — selectable row")
            page.mouse.move(row["x"], row["y"])
            page.evaluate("""() => {window.__luiWheelStart = undefined;
                window.addEventListener('wheel', () => {
                    window.__luiWheelStart = performance.now();
                }, {capture:true, once:true});}""")
            page.mouse.wheel(0, 240)
            page.wait_for_function("before => window.__luiReadScroll()>before", arg=before)
            model_latency = page.evaluate("performance.now()-window.__luiWheelStart")
            rows_after = [(n["text"], n["top"]) for n in nodes(page)
                          if n["text"].startswith("Item ")]
            if rows_after == rows_before:
                raise AssertionError("Wheel did not move painted row geometry")
            visible_latency = page.evaluate("performance.now()-window.__luiWheelStart")
            scroll_delta = page.evaluate(scroll_value) - before
            if scroll_delta <= 0:
                raise AssertionError("Wheel over a row did not scroll the app")
        result = {"toolkit": toolkit, "page": name, "frames": len(samples),
                  "cold_load": cold_load if case == 0 else None,
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
            for metric in ("layout_ms", "measure_ms", "paint_ms", "overlay_ms"):
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
