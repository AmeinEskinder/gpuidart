# The board against Flutter Windows (2026-09-30)

Every row the order of play asked to be measured, run once on one evening
(19:19 to 20:11) with six repetitions per fixture and workload, on the
shipped default. One machine (`reports/environment.json`), the Dart fixture
ahead-of-time compiled against the release library at `173f383` (the
repaint on update adaptive, see [the click tail](click-tail-20260930.md)),
the Flutter fixture a release build on the same machine.

The latency rows are judged by [the rule](board-rule-20260930.md) committed
before any of these runs existed (`ea604d0`, `7d9d43a`): every latency cell
within 3 ms of Flutter or better, the cell input-to-display median at least
10 ms better, and a cell claimed only with six counting runs per fixture.

**The verdict on that rule: not met.** Ten of the twelve latency figures
are within 3 ms of Flutter or better, six of them better by 1 to 15 ms.
Two are not: the display median on burst, 5.5 ms behind, and on scroll,
3.8 ms behind. The cell display median is 9.5 ms better than Flutter's,
half a millisecond short of the 10 the rule asks. Every cell has its six
counting runs at sixty events a second, so the thirty-a-second scroll
fallback was not used.

How the rows were counted:

- **A capture cell counts a run** when it is equal work (every planned
  input injected on time, every check passed) and its instrument answers at
  least 98 percent of the inputs for both the present and the display
  figure. The chain added runs under fresh indices until each cell had six;
  the runs that do not count stay in the same folders, and
  `present-20260930g-board.json` names each with its reason.
- **The two display halves come from different instruments with the same
  meaning.** The Flutter fixture's input to display is PresentMon's
  `MsUntilDisplayed`. The Dart fixture's is read from its own swap chain's
  DXGI frame statistics after every Present (`GPUI_PRESENT_FEEDBACK`),
  because PresentMon follows almost none of its `Composed: Flip` presents
  to the display ([present report](present-20260929.md)). Both are the
  vertical blank at which the first present after the input was shown,
  from the moment the injection completed.
- **Ten Dart cell runs do not count for an instrument reason.** With the
  adaptive repaint a click makes exactly one present, and the swap chain
  names a present as shown only in the statistics read at the next present.
  The last click of a run is therefore confirmed only if something paints
  after the window; where nothing did, the run answers 48 of 50 inputs,
  under the 98 percent. Those ten runs are equal work and their other 48
  clicks read like the counting runs'. Whether a run counts depends on a
  stray paint after the window, not on its latency.

Series: `startup-0-20260930g` and `startup-100000-20260930g`,
`present-20260930g-0` to `-27`, `view-jank-20260930g-0` to `-5`,
`view-jank-isolate-20260930g-0` to `-5`, and the floor records
`reports/performance/floor-20260929/aot-*-20260930g.json`. One run was
stopped by the driver (the first startup slot, an editor window over the
click target) and rerun. `.cache/board_rows.py` and
`.cache/board_summary.py` compute every figure.

Figures are the median over the counting runs with the range of the runs
in brackets; the input rows give each run's median and 95th percentile.

| Row | gpuidart | Flutter Windows | Verdict | Evidence |
| --- | --- | --- | --- | --- |
| Launch to first painted content, no records | 307 ms by the driver's content probe [196, 747], 254 ms by the fixture's clock | 2,391 ms [1,568, 2,712] and 2,366 ms | Met: almost eight times sooner, six runs each | [startup runs](startup-0-20260930g-0) |
| Open a million records | 1.15 to 1.86 s, two view recomputes (not rerun on this board) | not measured | Met on quiet runs against the 1.5 s line, missed by up to 0.4 s on loaded ones | [one million records](../performance/datasets-1m-20260929/README.md) |
| Working set at 100,000 records, while clicking and scrolling | 159 MiB on cell, 165 on burst, 166 on scroll [159, 166] | 178, 182 and 182 MiB [177, 207] | Met: 16 to 19 MiB lower on every workload | [capture runs](present-20260930g-0) |
| Working set at a million records | 373 MiB [371, 374], 395 at the peak, no collection forced | 463 MiB [459, 467], 498 at the peak | Met: 90 MiB lower | [jank runs](view-jank-20260930g-0) |
| Memory floor of an almost empty host | 76.5 to 76.6 MiB working set, 92.0 to 92.4 MiB private commit; of 77.0 MiB resident, 37.4 inside shared images | not measured | Half met: the working set under the 85 MB line, the private commit 7 MiB above it | [floor](../performance/floor-20260929/README.md) |
| A view change over a million records: longest gap between painted frames | 17.3 to 17.6 ms at the median per stage, 33.4 ms at worst; 1 of 72 changes over 33 ms, none over two frame intervals | 650 to 898 ms on the UI isolate, 1,393 at worst, 56 of 72 over 33 ms; 30 to 34 ms median and 36.8 at worst with a worker isolate, 34 of 72 over 33 ms | Met as "no gap over two frame intervals"; the "zero over 33 ms" line missed by one change at 33.4 ms | [jank runs](view-jank-20260930g-0) |
| A view change over a million records: time to the result | 135 ms for a sort [126, 253], 145 with a filter, 364 for a grouping [330, 494] | 636 ms [463, 1,341], 635 and 885 [731, 1,391] on the UI isolate; 570, 586 and 703 with a worker isolate | 2.4 to 4.7 times sooner, not the order of magnitude the exit line asked for | [jank runs](view-jank-20260930g-0) |
| Input to present, cell | 2.6 [2.3, 4.4] / 4.6 [2.9, 8.2] ms | 11.5 [8.2, 19.0] / 19.8 [18.7, 23.5] | Better by 8.9 and 15.2 ms (6 of 16 and 6 of 6 runs count) | [board rows](present-20260930g-board.json) |
| Input to display, cell | 29.6 [25.5, 36.6] / 37.3 [30.0, 41.4] ms | 39.1 [31.2, 43.3] / 48.7 [46.2, 62.5] | Better by 9.5 and 11.4 ms; the rule's 10 ms at the median missed by 0.5 | [board rows](present-20260930g-board.json) |
| Input to present, burst | 15.0 [10.8, 19.4] / 20.1 [17.2, 23.9] ms | 12.4 [7.1, 14.0] / 19.9 [19.0, 22.4] | Within 3 ms: 2.6 and 0.2 behind (6 of 8 and 6 of 8) | [board rows](present-20260930g-board.json) |
| Input to display, burst | 43.3 [40.3, 44.6] / 45.9 [45.0, 59.9] ms | 37.8 [32.2, 42.8] / 49.0 [46.1, 54.1] | Median 5.5 ms behind, outside the rule; 95th percentile 3.1 better | [board rows](present-20260930g-board.json) |
| Input to present, scroll | 5.9 [3.7, 13.7] / 16.4 [9.7, 17.3] ms | 7.2 [3.4, 13.4] / 15.1 [11.9, 16.5] | Within 3 ms: 1.3 better and 1.3 behind (6 of 9 and 6 of 10) | [board rows](present-20260930g-board.json) |
| Input to display, scroll | 38.1 [32.8, 42.2] / 45.4 [37.1, 54.7] ms | 34.3 [29.1, 39.5] / 43.4 [39.7, 47.7] | Median 3.8 ms behind, outside the rule by 0.8; 95th percentile 2.0 behind, within | [board rows](present-20260930g-board.json) |
| Scroll displacement under sustained wheel input | exact in 9 of 9 runs | exact in 10 of 10 runs | Met | [capture runs](present-20260930g-0) |
| Catalog and a real application | 29 node kinds, the terminal rebuilt on panes, tree, popover, sheet, combobox and rich text, accessibility workflow green at `81126b9` | the framework's own catalog | Met for the kinds named; every kind is bound by hand | [binding table](../../docs/binding-table.md) |
| Embedding spike | not played | | Waits on a machine that can afford the Dart SDK build | |

## Reading the two display medians that miss

On burst and scroll the Dart fixture paints at the vsync tick, as it did
with the repaint off, and its presents are as prompt as Flutter's (input
to present within 3 ms on both). The display figure adds what happens
after Present, and there the two fixtures differ: 29.0 ms from present to
display at the median for the Dart fixture's composed flip on burst and
28.8 on scroll, against 26.2 and 26.3 for the Flutter fixture's composed
copy, over the counting runs of this sitting (on the cell workload, where
the Dart fixture presents off the tick, 26.0 against 26.9). The per-run ranges
overlap on scroll (32.8 to 42.2 against 29.1 to 39.5) and barely on burst
(40.3 to 44.6 against 32.2 to 42.8). The burst display median has also
moved by more than the rule's 3 ms between sittings on unchanged code
(39.7 ms on the switch-off board the night before, 43.2 with the repaint
off in this evening's A/B), so one board cannot say whether the 5.5 ms is
the presentation path or the sitting. It is reported as a miss because the
rule was written before the run.

## What changed since the board of 2026-09-29

- **The display half of the Dart fixture is measured**, from its swap
  chain, and every input row is filled on both sides with six counting
  runs.
- **The lone click leads.** With the adaptive repaint the cell row reads
  2.6 ms to the present and 29.6 to the display against Flutter's 11.5 and
  39.1; the day before, without it, 15.7 and no display figure.
- **The million-row working set** needs no forced collection: the records
  are built and packed in a helper isolate that exits.
- **Jank** is down to one change in 72 over 33 ms, by 0.4 ms.

## What is left

- **The display medians on burst and scroll**, 5.5 and 3.8 ms behind: a
  second sitting would say whether they are the presentation path; if
  they are, the lever is present to display, not the adapter.
- **The cell display lead**, half a millisecond short of the 10 ms asked.
- **The instrument's tail**: a paint after the measured window, or a
  statistics read at exit, would let every equal-work cell run count.
- **The private commit of an almost empty host**, 7 MiB above the line.
- **The embedding spike** is the owner's move.

The evidence from the night before, on the switch-off build, is
[retained](board-switch-off-20260930.md).
