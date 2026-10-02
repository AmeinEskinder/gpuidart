# The board against Flutter Windows (2026-10-02)

Run once, on the night of 2026-10-02 (23:54 to 00:42), six repetitions per
fixture and workload, on the shipped default at `c13d41f`: the adaptive
repaint on a lone update and the paced vsync tick. One machine
(`reports/environment.json`), the Dart fixture ahead-of-time compiled
against the release library, the Flutter fixture a release build.

The latency rows are judged by [the rule](board-rule-20260930.md), written
before the board of 2026-09-30 and extended, before this one, with the
three changes made since: the driver jitters every input over one refresh
interval, the instrument confirms a run's last present, and the tick is
paced.

**The verdict on that rule: met.** All twelve latency figures are within
3 ms of Flutter or better: eleven are better or equal, by up to 16 ms, and
one is 0.2 ms behind. The cell input-to-display median is 15.4 ms better
than Flutter's, where the rule asks for 10. Every cell has six counting
runs at sixty events a second; the thirty-a-second fallback was not used.

It is not a clean sweep of the board, and four things qualify it:

- **The paced tick drops frames while the capture runs.** On burst and
  scroll, 16 to 34 of about 600 presents per run (3 to 6 percent) were
  never shown, superseded before the display took them; unpaced, on the
  board of 2026-09-30, a typical run lost none or one. The pacing's own
  A/B, without PresentMon tracing the system, showed under 1 percent, and
  the sweep that chose the 5 ms margin rejected 4 ms for losing 2.5
  percent. Under the board's load the margin is too tight.
- **The jank row slipped.** A million-row view change still skips at most
  one frame, but with the tick's phase moving with its draw-time reserve
  the gap around a skipped frame now reaches 36.1 ms, and 12 of 72 changes
  exceed 33 ms where one did before.
- **One Dart scroll run was not exact**: 600 wheel events injected, the
  table one 78 px step short of 46,800. It does not count and a seventh
  run made the six; the cause is not established. With the jitter two
  wheel events can now arrive within a millisecond of each other.
- **One Flutter burst capture lost its presents** (68 recorded where the
  others have about 300), so that run reads 3.2 s at the median. It passes
  the counting rule; the median over the six does not move with it, and
  without it Flutter's burst display median is 43.5 ms instead of 44.1.

Figures from earlier boards are not comparable to the millisecond: the
jittered driver samples every phase of the refresh, and the Flutter
fixture's display medians read 2 to 6 ms higher under it than under the
cadence locked to the refresh.

How the rows were counted: a capture cell counts a run when it is equal
work and its instrument answers at least 98 percent of the inputs for both
figures. The Dart fixture's display half comes from its swap chain's DXGI
frame statistics and the Flutter fixture's from PresentMon's
`MsUntilDisplayed`: the same meaning, the vertical blank at which the first
present after the input was shown, from two instruments. Series:
`startup-0-20261002` and `startup-100000-20261002`, `present-20261002-0` to
`-22`, `view-jank-20261002-0` to `-5`, `view-jank-isolate-20261002-0` to
`-5`, and `reports/performance/floor-20260929/aot-*-20261002.json`;
`present-20261002-board.json` retains the input rows per run. One run was
stopped by the driver (a window over the click target) and rerun.

Figures are the median over the counting runs with the range of the runs
in brackets; the input rows give each run's median and 95th percentile.

| Row | gpuidart | Flutter Windows | Verdict | Evidence |
| --- | --- | --- | --- | --- |
| Launch to first painted content, no records | 189 ms by the driver's content probe [156, 280], 138 ms by the fixture's clock | 1,394 ms [1,248, 1,799] and 1,390 ms | Met: seven times sooner, six runs each | [startup runs](startup-0-20261002-0) |
| Open a million records | 1.15 to 1.86 s, two view recomputes (not rerun on this board) | not measured | Met on quiet runs against the 1.5 s line, missed by up to 0.4 s on loaded ones | [one million records](../performance/datasets-1m-20260929/README.md) |
| Working set at 100,000 records, while clicking and scrolling | 159 MiB on cell, 166 on burst and scroll [159, 166] | 178, 182 and 182 MiB [177, 191] | Met: 16 to 19 MiB lower on every workload | [capture runs](present-20261002-0) |
| Working set at a million records | 372 MiB [352, 373], 395 at the peak, no collection forced | 460 MiB [453, 470], 494 at the peak | Met: 88 MiB lower | [jank runs](view-jank-20261002-0) |
| Memory floor of an almost empty host | 76.6 to 76.7 MiB working set, 92.3 MiB private commit | not measured | Half met: the working set under the 85 MB line, the private commit 7 MiB above it | [floor](../performance/floor-20260929/README.md) |
| A view change over a million records: longest gap between painted frames | 17.1 to 17.3 ms at the median per stage, 36.1 ms at worst; 12 of 72 changes over 33 ms, none skipping more than one frame | 553 to 812 ms on the UI isolate, 1,221 at worst; 20 to 34 ms median and 38.2 at worst with a worker isolate | One frame skipped at most, as before; the gap around it is up to 2.7 ms over two intervals with the paced tick | [jank runs](view-jank-20261002-0) |
| A view change over a million records: time to the result | 139 ms for a sort [120, 159], 144 with a filter, 361 for a grouping [309, 404] | 545 ms [460, 649], 573 and 799 [679, 1,197] on the UI isolate; 500, 548 and 608 with a worker isolate | 2.2 to 4.0 times sooner, not the order of magnitude the exit line asked for | [jank runs](view-jank-20261002-0) |
| Input to present, cell | 2.7 [2.6, 3.0] / 3.8 [3.7, 4.1] ms | 11.3 [11.0, 13.8] / 18.7 [17.6, 20.1] | Better by 8.6 and 14.9 ms | [board rows](present-20261002-board.json) |
| Input to display, cell | 29.8 [29.0, 31.1] / 36.5 [36.1, 37.3] ms | 45.2 [44.7, 47.3] / 52.5 [52.2, 53.2] | Better by 15.4 and 16.0 ms; the rule's 10 ms at the median met | [board rows](present-20261002-board.json) |
| Input to present, burst | 8.9 [8.1, 10.0] / 17.1 [16.5, 17.4] ms | 11.8 / 19.0 | Better by 2.9 and 1.9 ms | [board rows](present-20261002-board.json) |
| Input to display, burst | 32.8 [31.9, 34.4] / 45.4 [41.5, 47.3] ms | 44.1 / 52.5 | Better by 11.3 and 7.1 ms | [board rows](present-20261002-board.json) |
| Input to present, scroll | 8.7 [8.0, 9.4] / 16.4 [16.2, 17.6] ms | 8.7 [8.4, 9.0] / 16.2 [15.9, 16.6] | Equal at the median, 0.2 ms behind at the 95th percentile | [board rows](present-20261002-board.json) |
| Input to display, scroll | 32.3 [31.4, 32.5] / 41.2 [40.5, 43.9] ms | 36.3 [35.0, 41.0] / 48.7 [47.1, 49.7] | Better by 4.0 and 7.5 ms | [board rows](present-20261002-board.json) |
| Scroll displacement under sustained wheel input | exact in 6 of 7 runs; one run a 78 px step short | exact in 11 of 11 runs | Not clean: one Dart run lost one wheel step of 600 | [capture runs](present-20261002-0) |
| Catalog and a real application | 29 node kinds, the terminal rebuilt on panes, tree, popover, sheet, combobox and rich text, accessibility workflow green at `a7139f4` | the framework's own catalog | Met for the kinds named; every kind is bound by hand | [binding table](../../docs/binding-table.md) |
| Embedding spike | not played | | Waits on a machine that can afford the Dart SDK build | |

## What the pacing did

On burst and scroll the Dart fixture now presents about 10 ms after the
vertical blank instead of 4 to 5, and present to display is 22.8 to 24.6 ms
where it was 28 to 30 and the Flutter fixture's is about 26. Input to
display on those workloads went from 5.5 and 3.8 ms behind Flutter to 11.3
and 4.0 ahead. The lone click, which does not wait for the tick, is
unchanged for the Dart fixture at 29.8 ms.

## What is left

- **The pacing margin under load**: 5 ms drops 3 to 6 percent of frames
  while a system-wide trace runs. The sweep's own table says 6 ms lost
  none at a cost of half a millisecond; it should be re-chosen under the
  board's conditions, or made to back off when presents go unshown.
- **The gap around a skipped frame** on a million-row view change, back
  over 33 ms on 12 of 72 changes.
- **The Dart scroll run one step short**, to be reproduced with the trace
  build and the jittered driver.
- **The private commit of an almost empty host**, 7 MiB above the line.
- **The embedding spike**, the owner's move.

Earlier boards: [2026-09-30 on the adaptive default](exit-table-20260930.md),
which missed the rule by three cells, and
[the switch-off build](board-switch-off-20260930.md) before it.
