# Cached subtrees: plain versus cached sections

Two snapshot-gate series at `051d79f` with the same release library
(`source.txt`), one with the fixture's plain sections and one with every
section given a fixed height and `cached: true`
(`GPUIDART_GATE_CACHED=1`). All 36 runs passed on both sides (`plain/runs.json`,
`cached/runs.json`). `comparison.md` is the update-gate comparison over the
two summaries, plain as trunk and cached as head; `frames.txt` is
`tool/performance/compare_frames.dart` over both series; `property-only.txt`
is `tool/performance/bench_frames_live.dart`, a property-edit-only run
against the same library.

## What the gate shows

The gate mixes unchanged, property, reorder, insert and remove
publications, and the draw histogram it records covers every frame of a
run. Its per-frame p50 did not move: about 24 ms at 2,048 nodes on both
sides. Reorders, inserts and removes move every cached section, and a
moved cached element renders again, so those frames cost the whole tree
plus the cached-element bookkeeping, and the publish-to-ack of those kinds
rose by 11 to 30 percent (`comparison.md`, AOT, 2,048 nodes). The unchanged
publication, whose frame reuses every section, fell from 12,336 to 3,207 us
publish to ack and from 44.8 to 17.0 ms request to first content paint.

## What a property-only run shows

`bench_frames_live.dart` does 30 property edits with an inspect round trip
after each, so each frame completes before the next edit, and reads the
draw histogram and the per-section render counts afterwards (JIT driver,
release library, 2026-09-28):

| Fields | Sections | Draw p50 per frame | Frames | Section renders |
| ---: | --- | ---: | ---: | --- |
| 512 | plain | 9,781 us | 15 | |
| 512 | cached | 3,320 us | 8 | min 2, median 2, max 8 |
| 2,048 | plain | 32,850 us | 22 | |
| 2,048 | cached | 6,627 us | 21 | min 2, median 2, max 21 |

The edited section renders once per edit and every other section stays at
its two startup renders. The frame after a change falls to about a fifth
at 2,048 nodes; the remainder is the root scroll container, the layout of
the cached placeholders and the replay of their cached scenes.

## Reading

Caching is the application's choice per container, like a repaint
boundary. It pays on screens whose sections change in place and costs on
screens that reorder, insert or remove sections often. The fixture's
uniform workload does both, which is why its summary is flat; a screen
that edits fields in place, the common case, gets the property-only
figure.
