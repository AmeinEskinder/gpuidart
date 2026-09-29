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

## The drift, traced (2026-09-29, later)

The fifth audit asked for the one-percent drift to be resolved or
explained. Nine more scroll runs of the Dart fixture ran the same day with
the trace library (`-TraceInput`), unattended, in three series:
[scroll-trace-20260929b-0](scroll-trace-20260929b-0) to [-2](scroll-trace-20260929b-2),
[c-0](scroll-trace-20260929c-0) to [c-2](scroll-trace-20260929c-2) and
[d-0](scroll-trace-20260929d-0) to [d-2](scroll-trace-20260929d-2). The
runner now tags each wheel packet with its sequence number as it does the
clicks (`e0075b3`), and the trace build records every wheel event GPUI
dispatches with its delta and line height and, at every painted frame,
the table's vertical offset.

Every one of the nine runs delivered its 600 wheel events (599 in c-0,
where the driver skipped one deadline) and ended with the table's offset
exactly 78 px per delivered event: the drift did not reproduce. The
per-frame offsets, recorded from the c series on (the b traces came out
empty because the trace kept its events in a thread-local list and saved
them from another thread, fixed in `8e3d764`), move by exactly 78 px in
every frame that moved, except for frames that absorbed two events and
moved 156 px: one such frame in c-0 and c-1, none in c-2, and 20 to 27 in
the d series, which ran at 22 to 26 percent of a core against 34 to 39 in
c. No frame moved by any other amount.

| Run | Wheel events delivered | Final offset, px | Frames painted | Frames moving 78 px | Frames moving 156 px |
| --- | ---: | ---: | ---: | ---: | ---: |
| c-0 | 599 | -46,722 | 606 | 597 | 1 |
| c-1 | 600 | -46,800 | 605 | 598 | 1 |
| c-2 | 600 | -46,800 | 606 | 600 | 0 |
| d-0 | 600 | -46,800 | 585 | 554 | 23 |
| d-1 | 600 | -46,800 | 579 | 546 | 27 |
| d-2 | 600 | -46,800 | 587 | 560 | 20 |

What the code says about the path: GPUI's Windows backend turns each
`WM_MOUSEWHEEL` into a line delta (`-120` wheel units times the system's
scroll-lines setting, 3), and the Kit table's scroll mask consumes the
vertical delta in the capture phase, converting lines to pixels with the
line height it captured at its paint (26 px, hence 78 px per event) and
clamping to the content. For the offset to drift, an event must be lost
before that handler or a handler must convert with another line height.

The wheel-event stage recorded nothing in the b, c and d runs because its
listener was registered after the content, whose scroll mask stops
propagation in the capture phase; the paint marker now registers it
first, and a fourth series ran with that build:
[scroll-trace-20260929e-0](scroll-trace-20260929e-0) to [e-2](scroll-trace-20260929e-2).

Run e-0 is the complete picture of a clean run: 600 wheel events injected,
600 received by GPUI with their sequence numbers, every one a line delta
of -3 at a line height of 26, one per painted frame, 600 frames moving
78 px, the offset -46,800.

Run e-1 is the drift, caught. Of 600 injected events GPUI received 409;
sequences 165 to 210 and 218 to 362 never arrived. The events that did
arrive carry the pointer position, and it moved: the first 164 sat at the
placed point (y = 269.6 in the table), sequences 211 to 217 arrived with
the pointer sweeping down to y = 656, below the table, and from 363 on it
came back to y = 401. Someone at the machine moved the mouse 2.7 s into
the run (the driver's clock puts sequence 165 at 2,734 ms). Windows
routes wheel input to the window under the cursor, so the 191 events
injected while the pointer was outside the window went to whatever was
under it, and the 7 that reached GPUI with the pointer below the table
found no scroll target: 402 events arrived over the table and the table
moved 402 times 78 px, to -31,356. The driver's focus check passed
throughout because no click changed the foreground window. Run e-2 then
failed activation with nothing under the activation point, the same
person having switched away.

That resolves the drift: it is foreign pointer input during a run, not
the table. The earlier "583 of 597 events applied" run is the same
mechanism, and a fractional excess such as the 276 px run matches a
notch of a real wheel with a high-resolution delta landing on the
window. The driver now checks before every wheel event that the cursor is
still where it placed it and stops the run otherwise, as it does on focus
loss, so a run with a moved pointer is an interrupted observation rather
than a drift charged to the fixture.
