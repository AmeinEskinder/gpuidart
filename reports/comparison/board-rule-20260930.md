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

## Changes made after the board of 2026-09-30, stated before the next one

The board of the evening of 2026-09-30 missed this rule on the burst and
scroll display medians and, by half a millisecond, on the cell display
lead. Its own records locate the two display misses in where the Dart
fixture presents within the refresh interval, 3.8 to 5.1 ms after the
vertical blank against the Flutter fixture's 7.2 to 7.6, with present to
display two intervals less that phase on both. Three changes follow, and
then one more board under this rule, unchanged:

1. **The driver jitters every injected input** by a seeded uniform draw
   over one refresh interval (16.67 ms, capped just under the input period
   so the order and the count hold), with the same seed for both fixtures'
   n-th attempt of a workload in a series, so that each run samples every
   phase of the refresh rather than the fraction a cadence locked to it
   samples. This changes the workload, not the rule. Figures from boards
   before it are not comparable to the millisecond.
2. **The instrument reads the swap chain's statistics once more** 60 ms
   after a present that nothing followed, so that a run's last click is
   confirmed shown and equal-work runs count. This changes which runs count,
   not a figure.
3. **The Dart fixture's library gains frame pacing in its vsync tick**: the
   invalidation waits until the next vertical blank less a margin for the
   compositor less the recent 99th percentile of the draw time, so the
   present lands late in the interval; the wait is zero when draws are
   long. The margin is found by sweeping it and keeping the largest wait at
   which at least 99 percent of frames are still shown at the second blank.
   The pacing's own acceptance, before the board: on burst and scroll, six
   runs a side, present to display at or below the Flutter fixture's 26 ms,
   no rise in frames shown a refresh late, scroll displacement exact; the
   immediate repaint on a lone click unchanged.
