# Evidence: the board on the switch-off build (night of 2026-09-30)

This is not the board. It is the full set of board runs made on the night
of 2026-09-30 against the release library at `08fcac8`, where the repaint
on update was off, retained as evidence after the owner ruled that the
default should be adaptive instead and that the board runs once, on the
shipped default. It shows where every row stood without the repaint, and
what a board run on a shared desktop costs.

How the rows were counted:

- **A capture cell counts a run** when it is equal work (every planned
  input injected on time, every check passed) and its instrument answers at
  least 98 percent of the inputs for both the present and the display
  figure. The counts below are what the data holds; a cell with fewer than
  six counting runs is not claimed.
- **The two display halves come from different instruments with the same
  meaning.** The Flutter fixture's input to display is PresentMon's
  `MsUntilDisplayed`. The Dart fixture's is read from its own swap chain's
  DXGI frame statistics after every Present, because PresentMon follows
  almost none of its `Composed: Flip` presents to the display
  ([present report](present-20260929.md)). Both are the vertical blank at
  which the first present after the input was shown, from the moment the
  injection completed.
- **The desktop was shared.** A second agent (Zed's Codex agent, with
  computer-use runtimes) ran verifiers and opened windows on the same
  desktop. The driver stopped ten runs of the first pass whose window lost
  the foreground, and trace sessions orphaned by those stops cost the first
  pass every Flutter capture (PresentMon reported 135,908 lost events and
  wrote no file). Those slots were rerun under fresh indices, the startup
  series was rerun in full, and the runner now stops its own session
  (`119a846`). What the other agent's load did to the runs it did not stop
  cannot be separated out; the per-run ranges carry it.

Series: `startup-0-20260930c` and `startup-100000-20260930c` (six runs each;
the disturbed first pass `startup-*-20260930b` is retained),
`present-20260930b-0` to `-37` (capture; indices 0 to 5 are the first pass,
the rest are reruns of single cells), `view-jank-20260930b-0` to `-5` and
`view-jank-isolate-20260930b-0` to `-5`, and the floor records
`reports/performance/floor-20260929/aot-*-20260930b.json`.
`present-20260930b-board.json` retains the input rows per run.

Figures are the median over the counting runs with the range of the runs
in brackets; for the input rows, "median / 95th percentile" of each run.

| Row | gpuidart | Flutter Windows | Counting runs | Reading |
| --- | --- | --- | --- | --- |
| Launch to first painted content, no records | 492 ms by the driver's probe [265, 815], 446 ms by the fixture's clock | 2,410 ms [2,017, 7,021] and 2,383 ms | 6 and 6 | Five times sooner; both fixtures slower and noisier than the day before (240 against 1,510) |
| Working set at 100,000 records | 159 MiB on cell, 166 on burst and scroll [159, 168] | 178, 183 and 185 MiB [177, 216] | 6 to 8 and 12 to 14 | 19 MiB lower on every workload |
| Working set at a million records | 374 MiB [358, 380], 396 at the peak, no collection forced | 470 MiB [455, 487], 531 at the peak | 6 and 6 | 96 MiB lower |
| Memory floor of an almost empty host | 76.5 to 76.6 MiB working set, 92.3 MiB private commit | not measured | 3 | Working set under the 85 MB line, private commit 7 MiB above it |
| View change over a million records, longest gap | 17.6 to 17.8 ms median per stage, 33.7 ms worst, 2 of 72 changes over 33 ms | 926 to 1,412 ms on the UI isolate, 2,368 worst; 34 ms median and 72.8 worst with a worker isolate | 6 and 6 (and 6) | No gap over two frame intervals |
| View change over a million records, time to the result | 189 ms sort [153, 264], 198 with a filter, 561 grouped [410, 778] | 901 ms [586, 1,375], 980 and 1,404 on the UI isolate; 1,001, 1,115 and 1,270 with a worker isolate | 6 and 6 (and 6) | 2.5 to 5 times sooner, not ten |
| Input to present, cell | 13.6 [4.7, 17.7] / 19.0 [17.6, 21.3] ms | 14.9 [10.1, 16.7] / 20.8 [19.9, 26.4] | 6 of 6 and 6 of 6 | Parity |
| Input to display, cell | 42.4 [37.8, 46.6] / 48.3 [45.1, 96.3] ms | 39.0 [35.8, 45.1] / 53.6 [44.9, 57.6] | 6 of 6 and 6 of 6 | Parity; 3 ms behind at the median, 5 ahead at the 95th percentile |
| Input to present, burst | 11.2 [6.7, 16.6] / 15.7 [11.2, 24.7] ms | 15.8 [7.9, 17.2] / 20.5 [19.5, 21.9] | 6 of 8 and 7 of 8 | Parity or better |
| Input to display, burst | 39.7 [34.8, 44.3] / 44.5 [38.7, 60.3] ms | 38.9 [29.7, 41.2] / 51.1 [42.6, 57.5] | 6 of 8 and 7 of 8 | Parity |
| Input to present, scroll | 8.3 [2.9, 12.9] / 15.9 [10.9, 17.3] ms | 6.9 [3.4, 12.5] / 15.3 [7.2, 16.9] | 6 of 6 and 5 of 10 | Not claimed: Flutter has five counting runs |
| Input to display, scroll | 34.0 [30.5, 41.2] / 44.0 [35.9, 45.8] ms | 32.2 [27.0, 36.0] / 45.7 [40.7, 49.4] | 6 of 6 and 5 of 10 | Not claimed: Flutter has five counting runs |
| Scroll displacement | exact in 6 of 6 runs | exact in 14 of 14 runs | all completed scroll runs | Exact on both |

The runs that do not count: two Dart burst runs and one Flutter burst run
missed one to four driver deadlines; five Flutter scroll runs missed one to
five. They are in the same folders, and `present-20260930b-board.json`
names each with its reason.

What this evidence says for the board to come: with the repaint off, the
launch, memory and jank rows are held and every latency cell is a draw.
The lone-click row is where the adaptive repaint is expected to move: the
cell A/B with the repaint firing on every update read 25.9 ms to the
display at the median against 44.9 without it
([click tail](click-tail-20260930.md)).
