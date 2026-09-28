# Scroll cadence: making the 60-events-per-second runs eligible (2026-09-29)

Every earlier scroll run in the Dart and Flutter series missed at least one
driver deadline, so the scroll row of any comparison stayed outside the
equal-work subset. This directory pair records why and what changed.

## Where the misses came from

Six runs with the driver as it stood ([scroll-cadence-20260929-0](scroll-cadence-20260929-0)
through [-2](scroll-cadence-20260929-2), three per fixture) missed 3, 3 and 1
deadlines per repetition, the same counts for Dart and Flutter in each
repetition, and always at the same slots: the second input (scheduled at
17 ms) and one around the ninth (150 to 200 ms). A driver stall that lands
at the same slots for two different fixtures is the driver's own: Windows
PowerShell interprets a loop body until its sixteenth execution and then
compiles it to IL, and that compile stalled the input loop for 10 to 15 ms
inside the measured window. Raising the process to the high priority class
and reading the timer resolution (1.0 ms, recorded in `run.json`) did not
move those slots.

## What changed

`run.ps1` now executes the identical loop statement once as a dry phase at
the workload cadence, sending zero-length pointer moves, before it resets the
clocks and counters and runs the measured phase. The driver also stays at the
high priority class for the run, pays the first `SendInput` and timer wait
before the window, and keeps its 250 ms process sample out of the eight
milliseconds before an input deadline.

## Result

Runs with the warmed driver ([scroll-cadence-20260929b-0](scroll-cadence-20260929b-0)
through [-5](scroll-cadence-20260929b-5)):

| Fixture | Runs | Equal-work eligible | Driver deadline misses | Retained |
| --- | ---: | ---: | --- | --- |
| Flutter Windows | 3 | 3 | 0, 0, 0 | none |
| Dart AOT | 6 | 4 | 0, 1, 0, 0, 0, 0 | one correctness failure |

Flutter met the cadence in every run. Dart met it in four of six: one run
missed a single deadline mid-run at 4.5 s (the driver's send was one slot
late), and one run delivered all 600 inputs but the Kit table's scroll
offset ended at 47,075.68 px against the 46,800 px the wheel events add up
to, 276 px further than injected. Together with the earlier run that applied
583 of 597 wheel events, the Kit table's displacement under sustained wheel
input drifts by about one percent in either direction in one run out of
several; the Flutter list is exact in every run. That drift is retained as a
correctness failure and is a Dart-side finding to resolve before an
input-to-present row is claimed for scroll.

CPU during the eligible runs sat between 22 and 28 percent of one logical
core for both fixtures, within the earlier series' ranges. These runs
measure cadence only; memory and CPU rows still come from the rotated series.
