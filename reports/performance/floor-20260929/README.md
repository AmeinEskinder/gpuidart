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
image stays on disk.

## Resident pages by image

A later series ([aot-*-resident.json](.), same library with the working-set
walk added to the probe in `fef037d`) attributes the resident pages
themselves: `QueryWorkingSet` lists every page in memory with its shared
flag, and each page inside an image's mapping counts toward that image.
Three zero-row runs agree within 0.2 MiB:

| Resident pages, zero rows | MiB |
| --- | ---: |
| Working set at the settle | 73.7 to 73.8 |
| Pages inside mapped images | 34.7 |
| Pages outside every image (heaps, stacks, driver and GPU allocations, the Dart heap) | 39.3 to 39.4 |
| Shared with other processes | 34.0 |
| Private to the process | 40.1 to 40.2 |

The largest resident images, against their mapped size:

| Image | Mapped, MiB | Resident, MiB | Of which shared |
| --- | ---: | ---: | ---: |
| gpuidart.dll | 25.1 | 4.9 | 4.8 |
| igc64.dll | 82.7 | 3.5 | 2.8 |
| ntdll.dll | 2.4 | 1.9 | 1.9 |
| combase.dll | 3.5 | 1.9 | 1.8 |
| measure_floor.exe | 6.4 | 1.7 | 1.7 |
| igd10um64xe.DLL | 17.1 | 1.7 | 1.6 |
| igdgmm64.dll | 5.7 | 1.2 | 1.2 |
| KERNELBASE.dll, d3d11.dll, windows.storage.dll | 4.0, 2.4, 8.7 | 1.0 each | 1.0, 1.0, 0.9 |

So the native library's own touched code and data are 4.9 MiB of the
74 MiB floor, the graphics stack's images about 8 MiB, and the whole set of
69 images 34.7 MiB, almost all of it shared with other processes and so
not this process's cost on the machine. The other half, 39 MiB, is private
heap: what the Dart runtime, the GPUI window and the Direct3D driver
allocate for a window with one label. At 100,000 records the resident set
is 137.8 MiB: the images grow by 1.5 MiB (the library's touched pages, 6.3
against 4.9) and the pages outside them by 62 MiB, the records in both
copies and the table's working memory.

Attribution by resident pages replaces the mapped-size reading above:
mapped size said the graphics compiler was the largest image, resident
pages say it holds 3.5 MiB of the floor and the private heap holds 39.

## Limits

One machine, one day, three zero-row runs and one at 100,000 in each
series; a private commit of 91.5 MiB against a working set of 74 to 77
means about 15 MiB is committed but not resident at the reading, and the
private commit stays above the 85 MB line the order of play set even
though the working set is under it. `SizeOfImage` is mapped, not resident;
the working-set walk counts 4 KiB pages and attributes a page to an image
by address, so a page a driver allocated outside its image counts as heap. The Flutter fixture's zero-row floor was not measured here; the
[comparison series](../../comparison/README.md) has both fixtures at
100,000 rows (Dart 138 MiB against Flutter 173 MiB idle working set).
