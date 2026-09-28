# Windows baselines at 6731fca

Timing baselines captured on 2026-09-28 with the release library built from
this head (`windows-timing-command/` holds the build log, `windows-environment.json`
the machine record). Same cases, tool and repetitions as the
[September 26 baselines](../windows-e9c0c27/): `run_baselines.dart` full
mode, three repetitions, all 78 runs passed (`windows-timing-summary.json`,
raw captures in `windows-timing/`).

## Against September 26

| Case | Metric | e9c0c27 (Sep 26) | 6731fca (Sep 28) |
| --- | --- | ---: | ---: |
| AOT host, 0 rows | Host ready, ms | 221 | 450 |
| AOT host, 100k rows | Host ready, ms | 289 | 575 |
| AOT host, 0 rows, traced | First content paint, ms | 234 | 364 |
| AOT host, 100k rows, traced | First content paint, ms | 288 | 494 |
| JIT host, 100k rows, traced | First content paint, ms | 1,277 | 2,495 |
| AOT host, 0 rows | Private commit, MB | 98.7 | 99.3 |
| AOT host, 100k rows | Private commit, MB | 160.4 | 153.3 |

Memory is level or lower. Every startup figure is longer, so the question
was whether the code or the day changed.

## Same-day bisect across libraries

`bisect/` holds smoke baselines (AOT host, 0 and 100k rows, two repetitions)
taken one after the other on the same machine and the same Dart tree, each
with a different release library, so the Dart side and the day are held
constant and only the native library varies:

| Library | Host ready, 0 rows, ms | Host ready, 100k rows, ms |
| --- | ---: | ---: |
| e5345e5, original trunk | 447 | 472 |
| f5bc802, operation updates | 414 | 512 |
| da40c23, merge with main | 344 | 396 |
| 96de75f, in-place updates | 298 | 376 |

The oldest library is the slowest and the newest the fastest, and the
oldest already sits twice the September 26 figure. The startup difference
against September 26 is therefore the machine's state on the day, not the
code, while the in-place and merge changes shortened host-ready. Absolute
figures from the two days are not comparable; the relative order within one
day is.
