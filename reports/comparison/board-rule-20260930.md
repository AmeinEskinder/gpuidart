# The rule for the latency rows of the board, stated before it is run

Written on 2026-09-30 before any run of the adaptive repaint exists, so
that the rule cannot move after the results.

The exit line said "Dart at or below Flutter". The two fixtures' display
figures come from two instruments (the Dart fixture's swap chain statistics,
PresentMon for the Flutter fixture) on a 59 Hz panel whose presents are
16.1 to 17.1 ms apart, which gives about 3 ms of resolution between them.
The rule for the board is therefore:

1. **Every latency cell within 3 ms of Flutter or better.** The cells are
   input to present and input to display, on the cell, burst and scroll
   workloads, at the median and at the 95th percentile. Each figure is the
   median over six counting runs of that run's own median or 95th
   percentile, from the moment the injection completed.
2. **The cell input-to-display median at least 10 ms better than
   Flutter's**, with the adaptive repaint as shipped.
3. **A cell counts only with six counting runs per fixture**: equal work,
   and the instrument answering at least 98 percent of the inputs for both
   the present and the display figure. A cell with fewer is reported as not
   claimed, whatever its figures.

4. **Scroll at a cadence both fixtures can hold, if sixty a second fails
   to count.** If the Flutter fixture is still short of six counting scroll
   runs at sixty wheel events a second after five rounds of added runs (it
   loses runs to driver deadlines missed by one to five events in 600),
   the scroll workload is run for both fixtures at thirty wheel events a
   second, six counting runs each, and the scroll cells are claimed at that
   cadence and stated as such. The sixty-a-second runs stay in the record
   with their counts.

The adaptive repaint itself is accepted into the default on its own A/B,
six runs a side, before the board: the cell workload within the figures of
the repaint firing on every update (input to display about 26 ms at the
median, about 34 at the 95th percentile), the burst workload within the
figures of the repaint off on presents made (about 597 in ten seconds),
and scroll unchanged, which holds by construction since a wheel event sends
no update through the repaint.

The evidence this rule was written against is the board on the switch-off
build, [board-switch-off-20260930.md](board-switch-off-20260930.md), where
every latency cell was already within this rule's 3 ms except the cell
display median, 3.4 ms behind.
