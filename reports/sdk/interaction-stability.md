# Interaction and reload stability

The release-candidate interaction checks passed on the development machine:

- Keyboard Down changed the selected instrument, and wheel input advanced the table's visible rows.
- The native input and Dart both received 日本語😀 intact. Backspace removed the whole emoji. Clearing the remaining text restored all 1,000 instruments.
- A 400 by 360 logical window wrapped its toolbar controls. The screen scrolled to the footer, and enlarging it to 960 by 720 removed the obsolete scroll offset.
- Five batches of 100 price-button clicks produced exactly 500 application updates while retaining 1,000 records.
- Eleven successful source reloads preserved the application process, isolate, selected instrument, native input text/focus/selection, table identity, dataset revision and scroll position. A rejected source edit left the running code intact; ten subsequent edits reloaded successfully. Reload did not republish table records.

See [stability.json](stability.json), [reload.json](reload.json), [small-window screenshot](visual/watchlist-small.png) and [scrolled footer](visual/watchlist-footer.png). Both screenshots were visually inspected.

## Failures found and resolved

The new native narrow-window test initially failed because row controls extended beyond the right edge. Rows now wrap, and the native screen retains a scroll handle with a vertical scrollbar. A follow-up resize check found an obsolete 40-pixel offset after growing the window. Moving padding inside the scroll content fixed that layout error. The native test now checks both reaching the footer and removing obsolete scroll after resizing.

The first Unicode attempt sent characters before confirming input focus. The follow-up exposed an ANSI import in the Windows driver. PostMessageA reduced UTF-16 values to their low bytes, producing å,ž= instead of the intended text. The driver now calls PostMessageW explicitly, checks message-submission errors, and the test confirms focus before typing. The application then received the original Unicode string and deleted its emoji correctly.

Failed observations remain in [initial failure](stability-initial-failure.json), [focus observation](stability-unicode-failure.json), [ANSI-driver observation](stability-ansi-driver-failure.json) and [resize failure](stability-resize-failure.json).

These tests use posted Windows messages. They do not establish human IME behavior, physical input latency or presentation timing.
