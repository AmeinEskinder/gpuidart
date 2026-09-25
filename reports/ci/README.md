# Hosted Windows CI

The first hosted-execution gate is complete. GitHub Actions reports success for
the recorded Windows Server 2022 jobs:

| Source | Run | Result |
| --- | --- | --- |
| `9c88cd6` | [36176207245](https://github.com/AmeinEskinder/gpuidart/actions/runs/36176207245) | Success, completed 2026-09-25 18:59:30 UTC |
| `d463696` | [36177754108](https://github.com/AmeinEskinder/gpuidart/actions/runs/36177754108) | Success, completed 2026-09-25 19:14:12 UTC |
| `e8a176a` | [36179272099](https://github.com/AmeinEskinder/gpuidart/actions/runs/36179272099) | Success, completed 2026-09-25 19:29:07 UTC |

The tracing revision passed 11 native tests, 22 Dart tests and analysis. The
workflow excludes the five Dart tests tagged `live-window`. Source SHAs, job
steps and timestamps are retained in [the first run metadata](run-36176207245.json)
and [the tracing run metadata](run-36177754108.json). The diagnostic preparation
fix passed in [the reload investigation run](run-36179272099.json), with 12
native and 22 headless Dart tests.

These jobs run `./tool/check.ps1 -Headless` with pinned toolchains and dependencies.
They do not verify GPU interaction, code reload, AOT packaging, clean-machine
launch or IME composition.

The later probe commit `ac7aed4` failed [run 36181630592](https://github.com/AmeinEskinder/gpuidart/actions/runs/36181630592)
at Dart analysis because its Windows DPI helper used a relative `lib/` import.
The 12 native tests passed before that failure; Dart tests were not reached.
[Failure metadata](run-36181630592.json) is retained. The latest verified hosted
Windows source remains `e8a176a` until a corrected run succeeds.

The corrected source `8afcece` passed [36182707028](https://github.com/AmeinEskinder/gpuidart/actions/runs/36182707028),
including 12 native tests, 22 headless Dart tests and analysis. This is the latest
verified hosted Windows source. [Run metadata](run-36182707028.json) is retained.
