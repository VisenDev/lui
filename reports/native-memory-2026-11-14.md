# Native demo memory and per frame work

Measured on November 14, 2026, on branch `codex/performance-optimizations`, against baseline commit `2424184`.

The native demo's high memory use comes from the saved Lisp runtime, graphics libraries, and a large allowance for temporary allocations before garbage collection. The largest avoidable source of those allocations was rebuilding rounded shapes before looking up their already-cached OpenGL geometry.

The implemented surface cache cuts Qt Controls allocation by **76%**, reduces complete offscreen frame time by **23%**, and lowers sampled resident memory from **187.0 to 176.3 MiB** at the existing GC setting. Combining that change with a tested 16 MiB nursery lowers resident memory to **136.8 MiB**, about **50.2 MiB or 27% below the original**, while remaining **21% faster than the original**. A smaller nursery alone is not free: it increases collection frequency and some frame timings.

**The rendering improvement is implemented. The application GC default is unchanged.** The 16 MiB setting remains an explicit experiment, not a change to the host Lisp's global policy. Restarting a rebuilt demo uses the rendering improvement; an already-running executable keeps its old code.

## What the reported 191 MiB contains

The original `demo-wayland` process from the screenshot had 192.0 MiB RSS and 143.3 MiB PSS when inspected. RSS counts resident shared pages in every process using them; PSS divides those pages among their users. Neither is a measurement of live widgets alone.

| Mapping group | Resident MiB | Meaning |
| --- | ---: | --- |
| Anonymous mappings | 74.2 | Mostly SBCL dynamic heap, plus other anonymous allocations |
| Saved executable mappings | 40.9 | Lisp runtime and loaded code/data, including dependencies |
| LLVM | 33.4 | Graphics stack library pages |
| Mesa Gallium | 16.5 | Graphics driver library pages |
| Native C heap | 9.7 | Native libraries and rendering resources |
| Other mappings | 17.3 | Other libraries, stacks, caches and mappings |

The largest anonymous mapping alone held 56.9 MiB. The loaded LLVM library does **not** establish software rendering: the offscreen probe identified the Radeon `radeonsi` driver on the Ryzen 7 7800X3D's integrated GPU.

A separate baseline probe forced a full collection while the renderer, window context, font caches and completed layout were still alive. Dynamic Lisp usage fell from **75.95 to 27.15 MiB**, reclaiming **48.80 MiB**. The improved renderer's corresponding live value was **26.93 MiB after collection**. These probes establish substantial temporary allocation; they are not a long-duration leak test. Collector heap usage, RSS, and GPU memory are different quantities and should not be added together.

## Measurement method

Hardware and software: AMD Ryzen 7 7800X3D, Linux `7.3.0-202.nobara.fc44.x86_64`, SBCL `2.6.9-1.fc44-linux-x64`, Mesa `26.2.6`, LLVM `22.1`. Logical viewport: **720 by 520**. Scenes: Qt Controls, Qt 7GUIs Cells, and Glass Controls. All used their ordinary gallery code and the default palette, without user input injection or the debugger.

Each timing run used **300 warmup frames and 1800 measured frames** in a fresh saved executable. The GC matrix and the renderer comparison each used three repetitions per configuration; the order was reversed in the middle repetition. They were separate experiments, with no overlapping benchmark processes. The before/after comparison alternated original and improved renderers to reduce ordering bias.

Tables report the **median of three run means**, the **median of three run p95 values**, and the **median of three run median memory samples**. They are not pooled-frame percentiles or confidence intervals. Process memory was sampled externally from `/proc/PID/smaps_rollup` every 50 ms; offscreen samples before 0.5 seconds were excluded. Individual-run maxima and CPU measurements are preserved in the accompanying JSON.

The offscreen benchmark includes construction, layout, painting, presentation to its offscreen surface, and `glFinish`, so submitted GPU work completes before the frame timing ends. It does not measure interactive input latency or compositor presentation. The window benchmark requested 240 FPS but normally followed the display at about 170 FPS. Tabbing away caused long presentation stalls; the window timings are therefore retained as evidence but excluded from the performance recommendation. Thirteen window runs completed before that matrix was stopped; all 54 offscreen runs completed.

SBCL allocation counters are process-wide and exclude foreign/GPU allocations. GC times are CPU time, not a distribution of wall-clock pauses. The allocation call profiler was run separately because instrumentation raised frame time drastically; its allocation attribution and call counts are used below, not its timing as a performance result. A separate light wrapper probe measured phase times. Counter granularity makes tiny per-phase allocation estimates approximate.

## Before and after the rendering change

| Scene | Renderer and GC nursery | RSS MiB | PSS MiB | Mean ms | p95 ms | KiB allocated per frame |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Qt Controls | Original, 51.2 MiB | 187.0 | 137.9 | 1.980 | 2.581 | 905.9 |
| Qt Controls | Cached surfaces, 51.2 MiB | 176.3 | 127.1 | 1.533 | 1.842 | 217.0 |
| Qt Controls | Cached surfaces, 16 MiB | 136.8 | 87.6 | 1.558 | 1.942 | 217.0 |
| Qt Cells | Original, 51.2 MiB | 189.7 | 140.4 | 2.285 | 2.924 | 1210.7 |
| Qt Cells | Cached surfaces, 51.2 MiB | 172.8 | 123.5 | 1.865 | 2.512 | 477.3 |
| Qt Cells | Cached surfaces, 16 MiB | 142.9 | 93.7 | 1.871 | 2.540 | 477.0 |
| Glass Controls | Original, 51.2 MiB | 189.4 | 140.1 | 3.103 | 3.821 | 1080.3 |
| Glass Controls | Cached surfaces, 51.2 MiB | 177.1 | 127.7 | 2.655 | 3.350 | 355.5 |
| Glass Controls | Cached surfaces, 16 MiB | 141.1 | 91.7 | 2.697 | 3.383 | 355.2 |

At the unchanged nursery setting, allocation fell **76% on Qt Controls, 61% on Cells, and 67% on Glass Controls**. Mean frame times improved **23%, 18%, and 14%**, respectively. All three p95 comparisons also improved. The 16 MiB setting with the new renderer retained substantial advantages over the original renderer, although it was slightly slower than the new renderer at the original nursery size.

These are fixed-scene throughput results on this machine. They do not establish every platform's performance, input latency under every interaction, or behavior over hours. RSS also varies with shared-library residency and allocator high-water marks; a 16 MiB nursery is not a 16 MiB heap limit.

## Smaller GC thresholds

The observed default nursery allowance was **53,687,091 bytes, or 51.2 MiB**. The experiment set `sb-ext:bytes-consed-between-gcs` at executable startup, before creating the window. It did not force collection every frame. This distinction matters because SBCL's setting is not preserved merely by setting it before saving a core.

The following matrix uses the **original renderer**, isolating the GC-policy change:

| Scene | Nursery MiB | RSS MiB | Mean ms | p95 ms | GC CPU ms per 1800 frames |
| --- | ---: | ---: | ---: | ---: | ---: |
| Qt Controls | 51.2 | 189.0 | 1.971 | 2.560 | 21.8 |
| Qt Controls | 16 | 152.5 | 1.987 | 2.656 | 58.3 |
| Qt Controls | 8 | 145.1 | 2.011 | 2.783 | 110.8 |
| Qt Cells | 51.2 | 186.9 | 2.283 | 2.909 | 35.4 |
| Qt Cells | 16 | 156.3 | 2.341 | 3.191 | 96.5 |
| Qt Cells | 8 | 146.7 | 2.413 | 3.341 | 187.2 |
| Glass Controls | 51.2 | 187.3 | 3.082 | 3.788 | 30.8 |
| Glass Controls | 16 | 154.6 | 3.111 | 4.022 | 79.8 |
| Glass Controls | 8 | 148.8 | 3.183 | 4.150 | 149.0 |

With 16 MiB, median RSS fell by approximately **31–36 MiB** across these scenes. Mean time increased about **0.8–2.5%**, and p95 increased about **4–10%**. With 8 MiB, RSS fell another **6–10 MiB**, but GC CPU time rose substantially and p95 was about **9–15% above the default**. Eight MiB is therefore not the best default candidate from these results.

With cached surfaces, 16 MiB adds only about **0.3–1.6% to mean frame time** relative to the optimized renderer's default setting in this sample. Relative to the original application, the combination is both faster and about **47–50 MiB smaller**. Sixteen MiB is a reasonable application-launcher option to evaluate further. It should be set by the application at startup, not silently imposed on every Lisp image loading LUI. No claim of zero additional GC cost is warranted.

## Where temporary allocations went

The warmed Qt Controls call profile covered 600 measured frames. Its total was approximately 929 KB per frame, close to the uninstrumented allocation result. The following are exclusive allocation attributions, so the first two rows can be added:

| Function or category | Bytes per frame | Calls per frame | Interpretation |
| --- | ---: | ---: | --- |
| `rounded-polygon` | 471,203 | 116 | Point pairs, vectors, intermediate lists and boxed arithmetic for fills and borders |
| `gl-shape` | 238,674 | 95 | Deep snapshots for backdrop tracking and translation to local contours |
| `toolkit-defaults` | 27,613 | 31 | Resolving and copying option and palette lists |
| `declare-widget` | 21,399 | 29 | Declaration bookkeeping outside its separately profiled callees |
| `make-geometry` | 12,758 | 110 | Toolkit text insets, minimum dimensions and alignment descriptions |
| `make-element` | 12,247 | 42 | New frame-local layout nodes |
| `%measure-widget` | 12,152 | 58 | Measurement keys and surrounding work, even when values are memoized |
| `wrap-text` | 10,913 | 28 | Native text wrapping during painting and cache misses |
| `make-widget` | 10,556 | 32 | Widget presentation records |
| `make-box` | 10,152 | 292 | Bounds, clips and intermediate geometry |
| `record-ink` | 9,543 | 122 | Drawing-command descriptions used to validate backdrop caches |

The first two functions account for **about 76% of all Lisp allocation**. The old geometry cache avoided repeated triangle generation, but callers still built and copied the input geometry before reaching the cache. Glyph outlines were already cached; the profile also observed roughly 314 glyph geometry draws per frame and repeated glyph/kerning lookups. Those lookup counts are CPU opportunities, not evidence that glyph outlines were repeatedly reloaded.

## Per frame phase measurements

These are separate wrapper measurements on Qt Controls, in the offscreen path. Times include instrumentation and are illustrative phase averages, not the timing comparison above. **Solve is contained in end-frame** and must not be added to it.

| Phase | Original KiB per frame | Cached surfaces KiB per frame | Original ms | Cached surfaces ms |
| --- | ---: | ---: | ---: | ---: |
| Begin frame and route inputs | 0.4 | 0.9 | 0.004 | 0.004 |
| Application callback and declarations | 99.6 | 98.6 | 0.043 | 0.052 |
| End frame including solve and reconciliation | 33.0 | 33.1 | 0.050 | 0.048 |
| Of which layout solve | 31.9 | 31.8 | 0.047 | 0.046 |
| Initialize GL frame state | 0.1 | 0.4 | 0.001 | 0.001 |
| Paint frame and selection | 771.9 | 82.5 | 1.239 | 0.934 |
| EGL presentation call | 0.1 | 0.6 | 0.005 | 0.005 |

The rest of complete frame time includes `glFinish`, benchmark bookkeeping and other unwrapped work. It is not an independent measurement of GPU time. Before the change, painting accounted for about **85% of allocations**, construction about **11%**, and layout about **3.5%**. After the change, construction is a much larger fraction of the remaining allocations.

## Does this work need to happen every frame

The audit follows the [Wayland frame loop](../src/backend-wayland.lisp), [frame lifecycle](../src/05-frame.lisp), [layout solver](../src/04-layout.lisp), [shared painter](../src/backend-common.lisp) and [GL renderer](../src/backend-common-gl.lisp). It covers the ordinary render path and its conditional branches; it does not imply that every optional feature runs in the measured scene.

| Work | Current behavior | Needed every rendered frame |
| --- | --- | --- |
| Surface dimensions and display scaling | Checks logical/pixel sizes; sends scale/viewport/resize changes only when values differ | Cheap checks are appropriate. Native resize work is already conditional. |
| Input, key repetition and scroll animation | Drains queued input, resolves it against the previous layout, advances active scrolling | Process events/deadlines when present. Empty-input work can remain cheap; stale geometry cannot be reused after resize. |
| Previous hit regions and frame reset | Walks the old tree, clears declaration tables, allocates a new root and memo vector | Required by current identity/routing design. Table or buffer reuse is possible with careful ownership; completed frame objects must not be overwritten. |
| Application callback | Re-runs gallery logic, labels, scopes and controls exactly once | Yes under the immediate-mode contract. The application may change its model outside input handling. Skipping it requires an explicit invalidation contract. |
| Widget IDs, values and duplicate detection | Resolves scope/call-site IDs, captures controls and reads retained state | Yes for each declaration. Preserve duplicate errors, stable identity, focus/capture and disappearing-widget cleanup. |
| Toolkit defaults and palettes | Re-evaluates providers and assembles presentation lists | Dynamic providers must still run with correct scope. Static defaults could be cached only with toolkit revision and scope invalidation. |
| Widget and layout structures | Rebuilds widgets, elements, child vectors, boxes and sizing descriptions | The logical declarations are necessary; every allocation is not inherently necessary. Pooling is higher risk because callers/debuggers can retain completed layouts. |
| Floating overlays and debugger | Adds declared popups; debugger examines the previous frame when enabled | Only when present/enabled. The debugger was off in these measurements. |
| Width measurement and horizontal solve | Intrinsic measurement, table column work, width distribution | Necessary when constraints, content or geometry change. Current solver runs each frame; text-size results are already memoized, but keys and toolkit geometry are still constructed. |
| Height measurement and vertical solve | Measures wrapping at solved widths, distributes heights | Width-dependent measurement order is required. Cross-frame reuse would need reliable detection of all relevant changes. |
| Positioning, scroll bounds and clipping | Positions nodes, computes clips, clamps scrolling, places popups | Needed for changed layouts/scrolling. Potential incremental optimization, but smaller than the measured rendering waste. |
| Layout statistics and post-layout callbacks | Updates the 30-frame average/FPS counters; runs registered geometry callbacks | Statistics are cheap. Callbacks must preserve their declared semantics. The changing FPS label also causes genuine text changes. |
| State reconciliation | Removes absent values, clears invalid focus/capture, prunes floating paths, retains scroll positions and memo results | Required each completed declaration cycle; traversal organization can improve without changing behavior. |
| Pointer cursor | Hit-tests the completed tree and updates the native cursor only on a kind change | Native updates are already conditional. A stable pointer alone is insufficient to skip hit-testing if the layout moves beneath it. |
| GL frame setup and opaque clear | Sets viewport/matrices/blending/scissor and clears the surface | Required by the current full-frame presentation design. Partial redraw needs damage tracking and buffer preservation, not just removing the clear. |
| Visible widget traversal and painting | Visits the tree, rejects empty clips and invokes widget/toolkit painters in order | Needed for a full redraw. General custom painters may be dynamic. Dirty-region rendering is possible with an explicit correctness design. |
| Rounded surfaces and borders | Previously regenerated points and local copies before a cache lookup | **No. Fixed:** standard surfaces now look up immutable dimension/radius/thickness keys before generating contours. Positions use GL translation; color and clipping remain per draw. |
| Text wrapping and alignment | Painting wraps native text again and computes advances/kerning; measurement has a separate memo path | Unchanged font/text/width work could be reused. Cache keys must include font identity, size and mutable-string snapshots; bound retained memory. |
| Glyph outlines and GL geometry | Reuses font outlines and GL display lists; still emits glyph draws and transforms | Outline rebuilding is already avoided on hits. Whole text-run caching is a future CPU opportunity. |
| Color conversion | Parses hexadecimal colors and constructs RGBA vectors per draw | Unchanged color conversions could be reused or passed as scalars, with correct handling of mutable input strings. Small relative to the former contour cost. |
| Backdrop dependency tracking | Records earlier commands, compares regional dependencies, refreshes textures when needed | Needed when an effect can sample those commands. Do not skip it based on toolkit names: arbitrary custom painters can invoke backdrop effects. Surface records now store compact parameters instead of copied points. |
| Glass blur and refraction | Renders the shader when the painter requests it; source textures are cached and bounded | Needed for the visible requested effect. Source sampling is already reused when unchanged; shader execution is distinct from texture refresh. |
| Selection, caret and copying | Reconciles selection, draws highlights/caret and copies only when pending | Conditional and correctness-sensitive. Focused editors and animations require their scheduled updates. |
| Presentation and wait | Swaps the EGL surface, pumps input and waits for the next deadline | Present after actual drawing. Waiting is necessary pacing, not wasted rendering CPU. Hidden-window stalls should not be charged to GC. |

Normal interactive runners default to **1 idle FPS and at most 240 active FPS**, with input and animation deadlines waking them. They do not normally redraw an idle Controls page 240 times a second. At one idle frame per second, the measured original allocation rate would be about 0.93 MB/s versus about 0.22 MB/s after this change; those are derived rates, not an idle RSS experiment. Eliminating the idle polling callback entirely requires deciding how applications notify LUI about external model changes.

The Cells example already restricts declarations to nearby visible rows and updates formula dependencies incrementally. It does not recalculate every spreadsheet formula each frame. The debugger already uses virtualized rows and is optional. Neither is the explanation for the default Controls page's largest allocation source.

## Implemented change and validation

`gl-surface` uses the existing toolkit-independent `renderer-surface` callback. Cache keys contain width, height, radius and optional border thickness. On a hit, it draws the display list under a translation instead of generating world-space points, deep-copying them for backdrop tracking and translating them back to local coordinates. Surface color and position remain part of the backdrop dependency snapshot. Arbitrary polygon painters keep the existing path. The shared geometry cache retains its 512-entry bound and existing cleanup.

No application API, dependency, toolkit dispatch rule, or GC default was added. The shared GL change applies to backends using that renderer; runtime validation here was Linux EGL/Wayland, not macOS or Windows.

Validation includes strict `make lint`, `make test-core test-native`, the OpenGL suite, fractional-scale and fill/border/translation pixel parity against the old polygon path, cached-versus-fresh Glass pages, mutable backdrop inputs, cache bounds, and a rebuilt saved Wayland executable's `--smoke-test`.

The existing blur test originally failed on both original and changed renderers because `%paint-frame` cleared the stripe pattern it was supposed to blur. Its pattern now draws from the test painter after that clear, and the blur assertions pass. The Wayland suite still fails the unrelated `test-batched-focus` assertion expecting `:EDIT` focus; this was reproduced with the original renderer. The full Wayland suite is therefore **not** reported as passing. `make docs-pages` completed and refreshed `docs/index.html`; `make test-docs` passed extraction, application checks, and all four offline browser tests.

## Work that is not repeated every frame

Loading the Lisp runtime and dependencies, connecting to Wayland, initializing EGL, compiling the blur shader, opening font files and discovering font faces are startup or lazy-initialization work. Font outlines and GL geometry are reused after their first use. Their retained storage contributes to memory even when the application is idle, but it is not evidence of repeated per-frame loading.

The remaining fixed footprint cannot be eliminated by reducing allocation alone. A leaner saved Lisp image is a separate possible investigation; removing build-only dependencies would require checking runtime references and saved foreign-function behavior. No savings from runtime stripping were measured here. Likewise, Mesa/LLVM residency is graphics-stack overhead, not a large widget model. Backdrop textures have their existing 32 MiB-or-one-region policy; GPU/foreign storage is outside SBCL's allocation counters.

## Recommended next work

1. Keep the surface-cache change: it removes the measured dominant allocation source and improves mean and p95 timing in all three tested scenes.
2. Consider 16 MiB as an application-level launch option, then test typing, scrolling, resizing and longer runs before changing a default. Eight MiB has a less attractive tradeoff. Never collect on every frame.
3. Profile the remaining construction cost: static toolkit/palette list assembly, widget records and memo-key construction. Preserve dynamic providers and immutable completed frames.
4. Evaluate a bounded native text wrapping or text-run cache, measuring retained memory as well as allocation. Font size, face, text mutation and width changes are essential invalidation cases.
5. Treat incremental layout, dirty-region painting and zero-idle polling as separate architectural projects. They require explicit invalidation and custom-painter contracts and are not prerequisites for the proven improvement here.

## Reproduction and evidence

The adjacent [run summary JSON](native-memory-2026-11-14.json) contains all 67 completed benchmark runs. Detailed logs, memory time series, the original GL source and executable-build/profiling probes are in `build/profiles/memory/`; a ZIP of these text artifacts is delivered with this report. Saved executables are excluded from the ZIP.

The probes load `scripts/benchmark.lisp` in library mode, save a native executable, and set GC policy in its entry point. The comparison executable called `demo-baseline` reloads the GL source from baseline `2424184` before saving; `demo-optimized` uses the changed source. The archive contains the exact driver files and runner settings. Reproduction builds must run from the repository root with the same dependencies and display environment.

For a quick source-loaded check of the final renderer, the existing benchmark can also be run with the setting applied before loading it:

```sh
PLATFORM=gl BENCH_CASE=qt/controls BENCH_FRAMES=1800 WARMUP=300 \
  sbcl --noinform --non-interactive \
  --eval '(setf (sb-ext:bytes-consed-between-gcs) (* 16 1024 1024))' \
  --load scripts/benchmark.lisp
```

This quick command is not a substitute for the saved-executable memory comparison: source loading and compilation can change process residency. The delivered probes use a saved image precisely to avoid attributing compilation garbage to the demo.
