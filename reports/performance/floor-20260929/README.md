# The memory floor of an almost empty host (2026-09-29)

What a gpuidart process holds when it shows one window with one text node,
measured at the current head against the 85 MB line the order of play set,
and what the mapped images say about where it comes from.

## Method

[measure_floor.dart](../../../tool/performance/measure_floor.dart), compiled
ahead of time, opens a host over one `UiText` (`--rows=N` adds a table over
N records), reads the process counters when `open` returns, waits three
seconds with nothing to do, and reads them again beside every image mapped
into the process with its `SizeOfImage`, which the Windows runtime probe
now enumerates as the Unix probes do. It ran against the release library
built with link-time optimization (25,614 KiB on disk against 28,266 KiB
without) on the machine in `reports/environment.json`, three times at zero
rows and once at 100,000. The first series ([aot-*-lto.json](.)) churned
allocation before the settled reading, as the dataset tool does to provoke
the collector; in an idle process that only grew the Dart heap (settled
working set 131 to 148 MiB against 75 MiB right after opening), so the tool
lost that step and the quiet series ([aot-*-quiet.json](.)) is the one
reported. The 100,000-row figure comes from the tool's second quiet run;
its first quiet run at that size still carried the churn.

## Results

Process memory, MiB:

| Rows | After open, working set | Settled, working set | Settled, private commit | Lifetime peak working set |
| ---: | ---: | ---: | ---: | ---: |
| 0 (run 1) | 73.6 | 74.8 | 91.5 | 78.7 |
| 0 (run 2) | 75.5 | 76.8 | 91.5 | 80.9 |
| 0 (run 3) | 75.6 | 76.8 | 91.5 | 81.1 |
| 100,000 | 139.3 | 149.1 | 159.8 | 149.1 |

The zero-row floor is 75 to 77 MiB of working set and 91.5 MiB of private
commit, under the 85 MB line and level with the 75.87 and 94.57 MiB the
[baseline](../baselines/README.md) measured at `e9c0c27` before the catalog
grew from ten kinds to twenty-nine. The library's smaller image did not move
the resident floor, which is what mapped-but-untouched pages predict; it is
kept for the smaller artifact. At 100,000 records the process holds
149 MiB with the Dart copy of the records retained, against 129 MiB in the
baseline; the difference is inside the records' own memory (both copies)
and the settle wait, and the released-copy case is measured in the
[dataset report](../datasets-1m-20260929/README.md).

Images mapped into the zero-row process, 74 of them, 229.6 MiB of
`SizeOfImage` in total, the largest:

| Image | Mapped, MiB | What it is |
| --- | ---: | --- |
| igc64.dll | 82.7 | Intel's graphics shader compiler, loaded by the Direct3D 11 driver |
| gpuidart.dll | 25.0 | The native library (GPUI, Kit, the adapter) |
| igd10um64xe.DLL | 17.1 | The Intel Direct3D 11 user-mode driver |
| windows.storage.dll | 8.7 | Shell storage, through the file dialogs' dependencies |
| SHELL32.dll | 7.6 | Windows shell |
| measure_floor.exe | 6.4 | The Dart AOT executable with the runtime |
| igdgmm64.dll, igd10iumd64.dll | 5.7, 5.1 | Intel graphics memory management and driver |
| uiautomationcore.dll | 4.1 | UI Automation, for the accessibility tree |
| KERNELBASE.dll, combase.dll | 4.0, 3.5 | Windows base and COM |

Mapped size bounds what each library can contribute; the graphics driver's
compiler alone maps more than the whole resident floor, so most of every
image stays on disk. The floor is therefore not an adapter allocation but
the touched pages of the platform stack under a Direct3D window, the
native library's touched code and data, and the Dart runtime; a per-image
split of the resident pages needs a working-set walk the probe does not do
yet.

## Limits

One machine, one day, three zero-row runs and one at 100,000; a private
commit of 91.5 MiB against a working set of 76 means about 15 MiB is
committed but not resident at the reading. `SizeOfImage` is mapped, not
resident. The Flutter fixture's zero-row floor was not measured here; the
[comparison series](../../comparison/README.md) has both fixtures at
100,000 rows (Dart 138 MiB against Flutter 173 MiB idle working set).
