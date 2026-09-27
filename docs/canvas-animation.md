# Canvas and native animation

Both features keep frame work on the GPUI thread. The application describes
what to draw or how to move once; native paints and interpolates without a
publication per frame.

## Canvas

`UiCanvas(id, commands, style)` paints a retained list of commands inside the
node's bounds. Give the node a size through its style; coordinates are
logical pixels from the node's top left and may reach 8,192 px in either
direction. At most 4,096 commands per canvas.

| Command | Fields |
| --- | --- |
| `UiRect(x, y, width, height)` | `fill`, `stroke`, `strokeWidth` (0–512, default 1), `radius` |
| `UiCircle(cx, cy, radius)` | `fill`, `stroke`, `strokeWidth` |
| `UiLine(x1, y1, x2, y2, color)` | `width` |
| `UiPolyline(points)` | `stroke`, `width`, `fill`, `close`; 2 to 4,096 points, and a stroke or a fill |

Colors are theme tokens or hex like everywhere else, resolved against the
current theme when the frame is built. Filled rectangles and circles are GPU
quads; lines and polylines are tessellated paths. A canvas is a node like any
other: it can carry semantics with an `image` role, its command list is part
of the node's fields, and a change to the list sends one `set` operation for
that node.

Text, images and transforms are not in the draw list yet.

## Animation

`UiStyle(animation: UiAnimation(...))` wraps the node in a native timeline:

```dart
UiText(
  'toast',
  'Saved',
  style: UiStyle(
    animation: UiAnimation(
      duration: Duration(milliseconds: 250),
      easing: UiEasing.easeOutQuint,
      opacity: (0, 1),
      offset: ((0, 12), (0, 0)),
      key: 'saved-3',
    ),
  ),
)
```

- `opacity` runs from its first value to its second, 0 to 1.
- `offset` moves the node from its first point to its second, in logical
  pixels, relative to where it lays out.
- `duration` is 1 ms to 60 s; `easing` is `linear`, `easeInOut` (default),
  `easeOutQuint` or `bounce`; `repeat` loops.
- The timeline is keyed by node ID and `key`. A publication with the same key
  leaves a running or finished timeline alone; a new key restarts it. That
  is how an application replays an entrance without rebuilding the node.

GPUI requests a frame per tick, so an animation costs frames while it runs
and nothing afterwards. Animations do not affect layout of siblings; the
offset is a visual translation.
