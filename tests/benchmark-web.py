"""Measure paced browser frames for the shared feature gallery."""

import math
import os
import statistics

from web import WebTests

frames = int(os.environ.get("BENCH_FRAMES", "240"))
warmup = int(os.environ.get("WARMUP", "30"))
if frames < 10 or warmup < 0:
    raise ValueError("BENCH_FRAMES must be >=10 and WARMUP >=0")

WebTests.setUpClass()
try:
    page = WebTests.browser.new_page(viewport={"width": 900, "height": 700})
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(f"http://127.0.0.1:{WebTests.server.server_port}/examples/web.html")
    page.get_by_role("tab", name="Controls", exact=True).wait_for()
    print("Browser rAF intervals: paced presentation throughput, not raw GPU speed")
    print("toolkit page frames elapsed_ms fps mean_ms p50_ms p95_ms max_ms")
    for case, (toolkit, name) in enumerate(
        (toolkit, name) for toolkit in ("Glass", "Motif")
        for name in ("Controls", "Editing", "Layout", "Scroll", "Styles")
    ):
        if case == 5:
            page.get_by_role("button", name="Glass", exact=True).click()
        page.get_by_role("tab", name=name, exact=True).click()
        samples = page.evaluate("""({count, warmup}) => new Promise(resolve => {
            let previous, skipped = 0;
            const samples = [];
            function frame(now) {
                if (previous !== undefined) {
                    if (skipped++ >= warmup) samples.push(now - previous);
                }
                previous = now;
                if (samples.length === count) resolve(samples);
                else requestAnimationFrame(frame);
            }
            requestAnimationFrame(frame);
        })""", {"count": frames // 10 + (case < frames % 10),
                 "warmup": warmup // 10 + (case < warmup % 10)})
        ordered = sorted(samples)
        elapsed = sum(samples)
        print(f"{toolkit} {name} {len(samples)} {elapsed:.3f} "
              f"{1000 * len(samples) / elapsed:.2f} {statistics.fmean(samples):.3f} "
              f"{ordered[math.ceil(len(samples) * .5) - 1]:.3f} "
              f"{ordered[math.ceil(len(samples) * .95) - 1]:.3f} {max(samples):.3f}",
              flush=True)
    if errors:
        raise RuntimeError("; ".join(errors))
    page.close()
finally:
    WebTests.tearDownClass()
