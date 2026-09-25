# Hosted Windows CI

The first hosted-execution gate is complete. GitHub Actions reports success for
both recorded Windows Server 2022 jobs:

| Source | Run | Result |
| --- | --- | --- |
| `9c88cd6` | [36176207245](https://github.com/AmeinEskinder/gpuidart/actions/runs/36176207245) | Success, completed 2026-09-25 18:59:30 UTC |
| `d463696` | [36177754108](https://github.com/AmeinEskinder/gpuidart/actions/runs/36177754108) | Success, completed 2026-09-25 19:14:12 UTC |

The tracing revision passed 11 native tests, 22 Dart tests and analysis. The
workflow excludes the five Dart tests tagged `live-window`. Source SHAs, job
steps and timestamps are retained in [the first run metadata](run-36176207245.json)
and [the tracing run metadata](run-36177754108.json).

These jobs run `./tool/check.ps1 -Headless` with pinned toolchains and dependencies.
They do not verify GPU interaction, code reload, AOT packaging, clean-machine
launch or IME composition. The diagnostic preparation fix in `edffde4` was
verified locally and is newer than these hosted results.
