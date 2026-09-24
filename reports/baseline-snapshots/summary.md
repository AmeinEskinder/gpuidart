# Desktop prototype measurements

Generated from the adjacent JSON reports by `dart run tool/summarize.dart`.

## Packaged application

- ZIP: **10.88 MiB**. Payload files: **29.32 MiB**, excluding manifest/ZIP overhead.
- AOT launch and 120-update measurement passed after extracting the ZIP outside the repository, using an unrelated working directory and a Windows-only PATH.
- Loaded DLL paths confirm the packaged GPUI DLL, packaged CRT and Windows Common Controls v6. No loaded module came from the repository or a Dart/Flutter SDK directory.
- A clean machine without an installed SDK has not been tested.

## Local AOT sample

10000 records; 120 sequential updates, each changing a counter and one visible price, awaiting native application and then delaying 16 ms. This is not a fixed-rate load test. Native histograms cover startup, forced repaints and updates together.

| Metric | p50 | p95 | p99 |
| --- | ---: | ---: | ---: |
| Dart description build (includes immutable row copies) | 1.12 ms | 1.58 ms | 1.97 ms |
| Dart JSON encode, allocate and copy | 5.10 ms | 8.07 ms | 8.54 ms |
| Publish to applied acknowledgement (includes encoding) | 10.74 ms | 15.56 ms | 17.26 ms |
| Native draw | 1.88 ms | 2.86 ms | 3.17 ms |
| Native dirty to presentation submission | 8.19 ms | 16.83 ms | 19.01 ms |

RSS after the workload: **118.97 MiB**; process peak: **121.73 MiB**. These include the Dart runtime and native renderer.

The description and encoding samples include the first build. Native application acknowledgement and presentation submission are separate timestamps; neither measures the moment pixels become visible. No controlled OS input-to-present measurement has been made. Any input samples in the raw report are incidental window events.

## Unchanged repaint probe

The probe observed **30 native view materializations**. During that interval:

- Dart description builds: **0**.
- Dart snapshot encodes: **0**.
- Dart UI callbacks: **0**.
- Total FFI callbacks: **1**, the diagnostic completion itself.

These counters cover the registered builder and host callbacks. They do not claim the Dart runtime or unrelated application work stops executing.

## Viewport work

Ten warmed redraws per case, a fixed 860 × 650 window and a 320 px table. The allocator measures successful Rust allocation/reallocation requests on the headless UI thread during redraw. Data creation, publication, other threads and GPU allocations are excluded. Row/cell counts are construction calls, including layout measurement and overscan.

| Records | Row constructions | Cell constructions | Allocation calls | Bytes requested |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 110 | 290 | 20051 | 8366426 |
| 10000 | 110 | 290 | 20050 | 8366170 |
| 100000 | 110 | 290 | 20050 | 8366170 |

Rendering work stayed proportional to the viewport. Total data storage and snapshot copying still grow with record count.

## Actual Dart code reload

`DemoApplication.heading` changed in the same live process and isolate. The VM accepted the new source and the rebuilt native description contained the new heading. Counter, Dart text state, input entity/text/focus/selection and table entity/scroll offset remained equal. Reload plus reassembly to the applied acknowledgement took **87.43 ms** in this single development run. Invalid source was rejected and the previous code remained active.

The fixture seeds state through a development extension. Separate headless tests type Unicode, select by keyboard, navigate rows, dispatch wheel input, resize the window and verify retained state. The reload result establishes a component method edit; it does not establish arbitrary structural changes or AOT reload.

## Environment and outstanding checks

- Microsoft Windows 11 Pro 26200; 11th Gen Intel(R) Core(TM) i7-11850H @ 2.50GHz.
- Dart SDK version: 3.13.4 (stable) (Tue Sep 15 01:01:15 2026 -0700) on "windows_x64"; GPUI Kit `21622a70efd25219d26aa459164878c4da9e39f8`, GPUI 0.3.6, Rust 1.98.1, native release build with profiler enabled.
- Installed GPUs: NVIDIA T1200 Laptop GPU, Intel(R) UHD Graphics. The report does not identify which adapter rendered the window.
- Four native tests, one live Dart integration test and Dart analysis passed during this milestone.
- Human visual inspection is pending: the desktop automation connection was unavailable.
- GPUI Shell/QuickJS and GPUIX/Solid comparisons, controlled input latency and clean-machine installation verification remain outstanding. These local measurements establish no ranking against those runtimes.
