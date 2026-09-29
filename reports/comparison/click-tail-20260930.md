# The click tail: from an injected click to the changed frame on the display

Cell workload, 100,000 records, five clicks a second for ten seconds, the
Dart fixture with `retainRecords: false`. Every run here used the trace
build of the native library, which stamps the QPC clock at each stage of the
round trip (`benchmarks/native/src/input_trace.rs`), and the swap-chain
feedback of the vendored renderer (`GPUI_PRESENT_FEEDBACK`), which records
every Present call and the DXGI frame statistics after it: which present the
display last showed and at which vertical blank. The two files sit beside
`run.json` in every run folder as `native-input-trace.json` and
`present-feedback.csv`.

Two anchors are used, and the tables say which:

- **from the driver's timestamp**, taken before the driver positions the
  cursor and injects (the chain tables); the driver's own positioning is the
  `inject->down` stage;
- **from the injection completed**, the moment the click entered the system
  (the feedback tables), which is the anchor of the board's input-to-present
  row and the one comparable with the Flutter fixture's PresentMon record.

The display time of an input is the vertical blank of the first present at
or after its first present that the swap chain reports shown. A present the
display never took was superseded by the next before the vertical blank, and
that next present carries the change too, so no input is dropped from the
display figure for that reason. `.cache/click_chain.py` and
`.cache/feedback_analysis.py` compute the tables; the JSON beside each series
retains every number.

## The round trip per stage

Series [click-chain-20260929-0](click-chain-20260929-0) to
[-5](click-chain-20260929-5) traced the chain with drawing left to the vsync
tick and found one stage worth a frame: the wait from the edit applied
natively to the frame that renders it, 8.4 ms at the median and 15 ms at the
95th percentile, against a Dart round trip (click handler to edit applied)
of 0.3 ms. Everything else is under a millisecond except the driver's own
cursor positioning before the injection (up to 20 ms at the 95th percentile
of a run, charged to no fixture).

The adapter can ask Windows to repaint the window as soon as a publication,
an operation update or a dataset update is applied (`RedrawWindow` with an
invalidation, at most once every 4 ms, Windows only, on with
`GPUIDART_DRAW_ON_UPDATE=1`; see [the SDK guide](../../docs/sdk.md#frame-scheduling-on-windows)).
The A/B below was run with the switch on against off; the default is
decided at the end.
Six runs each side, run by the owner on 2026-09-30 in one session:
[click-a-20260930-0](click-a-20260930-0) to [-5](click-a-20260930-5) with the
switch off and [click-b-20260930-0](click-b-20260930-0) to
[-5](click-b-20260930-5) with it on. All twelve runs were equal work: 50 of
50 clicks injected on time, every check passed. Median over the six runs of
each run's p50 and p95, in ms, from the driver's timestamp:

| Stage | Off p50 | Off p95 | On p50 | On p95 |
| --- | ---: | ---: | ---: | ---: |
| Injection to GPUI mouse down (driver positioning included) | 1.9 | 18.1 | 1.7 | 14.5 |
| Mouse down to mouse up | 0.3 | 0.9 | 0.3 | 0.7 |
| Mouse up to the native click handler | 0.1 | 0.1 | 0.1 | 0.1 |
| Handler to the edit applied (through Dart) | 0.3 | 3.7 | 0.3 | 0.6 |
| Edit applied to the frame that renders it | 12.2 | 14.3 | 0.1 | 0.2 |
| That frame's render to its Present call | 2.7 | 4.5 | 2.2 | 3.2 |
| Injection to the changed frame's Present | 18.6 | 35.7 | 4.6 | 17.9 |
| Injection to the changed frame on the display | 47.1 | 64.3 | 27.6 | 45.0 |
| Clicks whose first present was the changed frame, of 50 | 42.5 | | 50 | |

The per-run ranges: injection to the changed frame on the display p50 38.0
to 47.4 off against 26.7 to 32.8 on, p95 55.6 to 66.3 against 42.2 to 48.4.
With the switch on, the frame that renders the edit starts within 0.2 ms of
the edit in every run, and the first present after every click is the
changed frame in four of the six runs (35 and 50 of 50 in the other two:
there the press state painted first).

## What the switch costs: presents the display never took, and CPU

From the injection completed, medians over the six eligible runs of each
side with the per-run range in brackets:

| | Off | On |
| --- | --- | --- |
| Input to present p50, ms | 15.3 [7.4, 16.1] | 3.2 [2.7, 3.5] |
| Input to present p95, ms | 18.4 [17.7, 19.5] | 4.5 [3.8, 5.1] |
| Input to display p50, ms | 44.9 [36.8, 45.4] | 25.9 [25.2, 30.7] |
| Input to display p95, ms | 48.0 [47.0, 48.8] | 33.7 [30.5, 39.3] |
| Presents in the window (50 clicks) | 57.5 [53, 58] | 50 [50, 65] |
| Presents the display never took | 7.5 [5, 10] | 0 [0, 15] |
| Fixture CPU over the 10 s window, ms | 383 [328, 531] | 375 [266, 484] |
| CPU as percent of one core | 3.8 [3.3, 5.3] | 3.7 [2.7, 4.8] |

A present the display never took is one superseded by the next present
before a vertical blank. With drawing left to the tick every run made 5 to
10 of them: the press state of the button painted at one tick and the edit
at the next, and the display skipped the first. With the switch on, four runs
made exactly one present per click and none were skipped; two runs made 62
and 65 presents, of which 12 and 15 were skipped, the press-state frame
painted by the tick just before the edit's own repaint. The worst run on
either side is therefore 65 presents against 58, and the median 50 against
57.5. CPU is the same within the run-to-run spread.

Two things the feedback does not measure: the vertical blank the statistics
report is when the composed desktop was scanned out, not the panel's own
response; and a present issued after the last present of the run has no
statistics reading after it, so the count of presents never taken can be one
high at the end of a window.

## Burst and scroll

The same A/B on the burst workload (thirty clicks a second, 300 in the
window) and the scroll workload (sixty wheel events a second, 600 in the
window), six runs a side, run unattended on 2026-09-30 at 02:13 to 02:20
([burst-a-20260930-0](burst-a-20260930-0) to [-5](burst-a-20260930-5) and
[burst-b-20260930-0](burst-b-20260930-0) to [-5](burst-b-20260930-5),
[scroll-a-20260930-0](scroll-a-20260930-0) to [-5](scroll-a-20260930-5) and
[scroll-b-20260930-0](scroll-b-20260930-0) to [-5](scroll-b-20260930-5)).
Three runs were stopped by the driver when the benchmark window lost the
foreground to a window of another session working on the same desktop
(burst off run 0, burst on run 5, scroll off run 4; their `failure.json`
names the window), and two burst runs with the switch off missed two and
three driver deadlines; those five do not count. Medians of the counting
runs with the per-run range, from the injection completed:

| Burst | Off (3 runs) | On (5 runs) |
| --- | --- | --- |
| Input to present p50 / p95, ms | 13.2 [8.3, 16.6] / 19.8 [19.2, 23.9] | 3.4 [3.2, 10.3] / 5.6 [5.1, 14.4] |
| Input to display p50 / p95, ms | 39.7 [34.5, 55.8] / 54.2 [46.2, 77.2] | 35.2 [28.2, 38.1] / 38.5 [32.0, 51.7] |
| Presents in the window (300 clicks) | 596 [596, 598] | 893 [888, 896] |
| Presents the display never took | 107 [3, 218] | 297 [292, 317] |
| CPU, percent of one core | 27.2 [21.2, 43.7] | 21.7 [17.7, 45.2] |

| Scroll | Off (5 runs) | On (6 runs) |
| --- | --- | --- |
| Input to present p50 / p95, ms | 10.4 [3.6, 14.5] / 16.6 [10.7, 17.2] | 10.8 [3.7, 13.2] / 16.8 [12.3, 17.2] |
| Input to display p50 / p95, ms | 38.7 [32.2, 41.7] / 44.6 [38.7, 45.7] | 39.4 [32.2, 41.9] / 45.1 [40.7, 45.6] |
| Presents in the window (600 events) | 599 [599, 600] | 599 [599, 600] |
| Presents the display never took | 0 [0, 4] | 0 [0, 0] |
| CPU, percent of one core | 23.6 [20.2, 29.7] | 22.3 [20.9, 23.4] |

Scroll is unchanged, as expected: a wheel event moves the table natively
and sends no update through Dart, so the switch never fires. Burst is
where the switch costs: at thirty clicks a second the window is dirty at
every vsync tick anyway, so the tick paints every frame with the switch
off (596 presents in ten seconds on a 60 Hz display) and the immediate
repaint adds one present per click that the tick's next present supersedes
before a vertical blank (893 presents, 597 of them shown, one per refresh).
The change still reaches the display sooner (4 ms at the median, 16 ms at
the 95th percentile over the counting runs), and CPU did not rise, but
a third of the frames rendered are never shown. Two caveats on this table:
the other session's fixtures were running on the same desktop during the
series, which is visible in the off runs 3 and 5 and the on run 4 (display
p95 of 77, 54 and 52 ms, CPU up to 45 percent) and widens every range; and
"presents the display never took" counts presents no statistics reading
reported shown, which at the display rate also misses a present shown
between two readings that straddled two vertical blanks, so the off side's
107 and 218 overstate, while the on side's 297 is arithmetic (893 presented,
597 shown).

## The default

Off. The rule for this A/B was that the default stays on only if neither
burst nor scroll regresses in presents never taken or in CPU; burst
regresses in presents never taken, by about one rendered and unshown
frame per click. The switch stays available as `GPUIDART_DRAW_ON_UPDATE=1`
for an application whose updates answer single inputs, where it takes the
changed frame to the display 19 ms sooner at the median on the cell
workload, and the SDK guide says what it costs under a burst. The board
of 2026-09-30 is measured with the default.

## Where the Dart fixture's display half comes from

The Flutter fixture's input-to-display row on the board comes from
PresentMon's `MsUntilDisplayed`, since PresentMon follows its
`Composed: Copy with GPU GDI` presents to the display. It follows almost none
of the Dart fixture's `Composed: Flip` presents, even elevated, and drops
presents from its record while the fixture renders every frame
([present report](present-20260929.md)). The Dart fixture's display half
therefore comes from the swap chain's own DXGI frame statistics, read after
every Present: the same meaning, the vertical blank at which the present was
shown, from a different instrument.
