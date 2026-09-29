# The board against Flutter Windows (2026-09-29)

Every row the order of play asked to be measured, with the figure, the
evidence and the verdict. One machine (`reports/environment.json`), the
Dart fixture ahead-of-time compiled against the release library, the
Flutter fixture a release build on the same machine. The verdicts are
the measurements', not a claim of a finished comparison: two rows are
half filled and one move is not played.

| Row | gpuidart | Flutter Windows | Verdict | Evidence |
| --- | --- | --- | --- | --- |
| Launch to first painted content, no records | 240 ms by the driver's content probe, 194 ms by the fixture's clock | 1,510 ms and 1,504 ms | Met: six times sooner on this GPU, where Flutter compiles its shaders per process | [startup](startup-20260929.md) |
| Open a million records | 1.15 to 1.86 s, two view recomputes | not measured | Met on quiet runs against the 1.5 s line, missed by up to 0.4 s on loaded ones | [one million records](../performance/datasets-1m-20260929/README.md) |
| Working set at 100,000 records, while clicking and scrolling | 142 to 167 MiB with the Dart copy released | 177 to 185 MiB | Met: 18 to 36 MiB lower | [input to present](present-20260929.md) |
| Working set at a million records | 656 to 666 MiB during a run in either records mode; 393 to 414 MiB after a major collection with the records released | 455 to 495 MiB | Half met: lower once collected, higher while the VM still holds the freed pages | [jank](view-jank-20260929.md) |
| Memory floor of an almost empty host | 74 to 77 MiB working set, 91.5 to 92.2 MiB private commit; 34.7 MiB of the resident pages inside shared images, 39 MiB private heap | not measured | Half met: the working set is under the 85 MB line, the private commit above it; attribution by resident pages done | [floor](../performance/floor-20260929/README.md) |
| A view change over a million records: longest gap between painted frames | 35 ms, two frame intervals (6 of 36 changes skipped one frame, none more) | 509 to 1,011 ms sorting on the UI isolate; 50 ms with a worker isolate, a frame skipped on 18 of 36 changes | Met as "no gap over two frame intervals"; the "zero over 33 ms" line is missed by those six changes at 33 to 35 ms | [jank](view-jank-20260929.md) |
| A view change over a million records: time to the result | 125 to 179 ms for a sort, 340 to 450 ms for a grouping | 506 to 707 ms and 754 to 998 ms on the UI isolate; 454 to 1,030 ms and 759 to 1,332 ms with a worker isolate | Two to five times sooner, not the order of magnitude the exit line asked for | [jank](view-jank-20260929.md), [throughput](view-1m-20260929.md) |
| Input to present | cell 15.7 to 15.8 ms median, 32.6 to 34.0 at the 95th percentile; scroll 9.5 to 13.8 and 14.0 to 16.8 | cell 9.8 to 19.7 and 20.4 to 27.2; scroll 3.6 to 12.0 and 11.5 to 16.9 | Parity within a frame; a click on the Dart fixture reaches the second frame more often | [input to present](present-20260929.md) |
| Input to display | followed for a few percent of the presents only: scroll 29.5 to 32.7 ms median over 15 to 76 samples a run | cell 33.0 to 53.8 ms median, scroll 23.8 to 32.3 | Half filled: a capture without elevation cannot follow the flip-model presents of the Dart fixture to the display | [input to present](present-20260929.md) |
| Scroll displacement under sustained wheel input | exact in eleven of twelve traced runs; the twelfth was a pointer moved by a person, and the table moved once per event it was given | exact | Met; the driver now stops a run whose pointer moved | [scroll cadence](scroll-cadence-20260929.md) |
| Catalog and a real application | 29 node kinds, the terminal rebuilt on panes, tree, popover, sheet, combobox and rich text, accessibility workflow green | the framework's own catalog | Met for the kinds named; every kind is bound by hand | [binding table](../../docs/binding-table.md) |
| Embedding spike | not played | | Waits on a machine that can afford the Dart SDK build | |

## What is left

- **Input to display for the Dart fixture** needs one capture from an
  elevated session; the harness and the analyzers are ready for it.
- **The private commit of an almost empty host** is 6 to 7 MiB above the
  line; 39 MiB of the floor are private heap of the Dart runtime, the
  window and the graphics driver, which is where a reduction would have
  to come from.
- **The working set at a million records** depends on the Dart VM
  returning freed pages; an application that allocates normally triggers
  the collection the fixture had to force.
- **The embedding spike** is the owner's move.

Not checkmate: the board is measured except for one half row that needs
elevation and one move that needs a machine, and two lines are met in a
weaker form than they were written (two frame intervals instead of 33 ms,
two to five times instead of ten).
