# Feature stack design: styles, actions, record identity, cell formatting

This specifies roadmap steps 3–4 as concrete wire types and semantics. It is a design contract for implementation, not evidence of shipped behavior. Every new field is optional; existing snapshots, datasets and ABI 1 behavior are unchanged when they are absent. All types use `deny_unknown_fields` on the Rust side, matching `native/src/protocol.rs`.

## 1. Typed styles

### Wire type

Every node gains an optional `"style"` member:

```json
{
  "kind": "column", "id": "root",
  "style": {"gap": 12, "padding": [16, 16, 16, 16], "background": "token:muted"},
  "children": []
}
```

```rust
pub struct Style {
    pub padding: Option<[f32; 4]>,      // logical px: top, right, bottom, left
    pub gap: Option<f32>,               // logical px
    pub width: Option<Size>,            // { "px": 320 } | "full" | "fit"
    pub height: Option<Size>,
    pub align: Option<Align>,           // start | center | end | stretch
    pub justify: Option<Justify>,       // start | center | end | space_between
    pub background: Option<Color>,
    pub foreground: Option<Color>,
    pub border_color: Option<Color>,
    pub border_radius: Option<f32>,
    pub font_size: Option<f32>,         // logical px; text nodes only
    pub font_weight: Option<FontWeight> // normal | medium | semibold | bold
}
```

`Color` is `"token:<name>"` or `"#RRGGBB"` / `"#RRGGBBAA"`. Raw hex is allowed so apps are not blocked on token coverage, but tokens are the documented default so theme switching keeps working. The token enum is closed and contains only roles that exist in gpui-kit's `ThemeColor` at the pinned revision: `background`, `foreground`, `primary`, `primary_foreground`, `secondary`, `secondary_foreground`, `muted`, `muted_foreground`, `accent`, `accent_foreground`, `danger`, `danger_foreground`, `border`, `success`, `warning`, `info`. (An earlier draft of this list assumed `panel`; gpui-kit has no such role, so it was dropped, and the foreground/secondary/success/warning/info roles that do exist were added.) Setting `border_color` implies a 1 px border; there is no border-width field in this milestone.

### Boundaries

- Units are logical pixels only. No percentages, no `em`, no viewport units. Scale-factor conversion stays in GPUI.
- Numeric bounds: padding/gap/radius 0–512 px, font size 8–96 px, fixed width/height 0–8192 px, flex not supported in this milestone. Out-of-range values are validation rejections, not clamps.
- **No inheritance or cascade.** A style applies to exactly its node. Text color/size on a container does not propagate to children in this milestone; this is deliberate to keep precedence trivially defined: node style wins over the gpui-kit theme default, nothing else competes.
- `font_size`/`font_weight` on non-text nodes are validation errors. Unknown token names are validation errors.
- Validation happens in `Snapshot::validate`, so malformed styles reject before any retained state changes — same discipline as existing node validation.

## 2. Actions and scoped keymaps

### Wire type

Snapshots gain an optional top-level member:

```json
{
  "revision": 4,
  "actions": [
    {"name": "app.search", "keys": "ctrl+f", "context": "global"},
    {"name": "watchlist.add", "keys": "ctrl+enter", "context": "quotes-table"}
  ],
  "root": { ... }
}
```

Native dispatch produces a new event: `{ "type": "action", "revision": N, "name": "watchlist.add", "context": "quotes-table" }`. Buttons keep emitting `click`; actions are a separate channel so existing apps are unaffected.

### Boundaries

- `context` is `"global"` or the ID of a node present in the same snapshot. Dispatch walks from the focused node up the snapshot tree; the first binding whose context contains the focus wins. `global` bindings match last.
- Duplicate `name`+`context` pairs, or two different actions bound to the same `keys`+`context`, are validation rejections. Conflicts across nested contexts are legal (innermost wins) and tested.
- Key grammar is a closed subset: `ctrl|alt|shift|meta` modifiers plus one key from a named set (letters, digits, f1–f12, enter, escape, space, tab, arrows, home/end/pageup/pagedown, delete, backspace). Anything else rejects. This keeps parsing total and avoids promising IME-adjacent key handling we have not verified.
- At most 256 bindings per snapshot.
- Text editing and IME composition shortcuts are owned by the native input and are never intercepted: a binding whose single key is printable text (a bare letter/digit with no modifier) is rejected. Human IME verification remains an open release gate; this design must not change the input's composition path.
- Actions with no matching binding do nothing silently; a binding whose `name` no Dart listener handles is still delivered as an event. There is no native-side command execution in this milestone.

### Dispatch implementation (as shipped)

- Dispatch is a manual match in a GPUI keystroke interceptor (`App::intercept_keystrokes`), not the GPUI keymap. The keymap's `Action` trait requires a `&'static str` name, so bindings cannot carry the dynamic wire `name`, and `bind_keys` has no removal API, so snapshot-driven refresh would leak stale bindings. The interceptor fires before all other key handling regardless of focus; a matched binding emits the event and consumes the keystroke via `stop_propagation` + `prevent_default`, an unmatched key passes through untouched, so text input and IME composition are unaffected (they never match, since bare printable keys are rejected).
- Modifier semantics are literal: `ctrl` is always the control key and `meta` is the platform meta key (cmd on macOS, windows key on Windows, super on Linux). There is no `secondary`/platform-primary alias; apps that want cmd-on-macOS/ctrl-elsewhere declare both bindings. The wire separator is `+` (`ctrl+enter`); GPUI's own `-` syntax is an internal detail.
- Focus tracking scope: inputs and tables resolve as their node IDs, so their contexts and ancestors apply. gpui-kit `Button` creates its focus handle internally and does not expose it, so a focused button currently resolves as *no focused node* — only `global` bindings match. This is a known limitation of the milestone, not a rule.
- On Windows, AltGr produces ctrl+alt; a `ctrl+alt+<key>` binding can therefore fire while typing national characters. This falls under the existing human IME release gate above.
- Held keys repeat: a held matched binding emits repeated `action` events.

## 3. Stable record identity and dataset views

### Record identity

`TableData` gains an optional member, parallel to `rows`:

```json
{"columns": ["sym", "price"], "rows": [["ACME", "10.5"]], "ids": ["ACME"]}
```

- When present, `ids` must have the same length as `rows`, all nonempty and unique. `RowEdit`/`CellEdit` stay index-based against the authoritative Dart dataset — Dart remains the source of truth and indices are unambiguous there.
- `RowEdit` cannot change identity; a record's ID is fixed for its lifetime in one dataset. `Replace` may supply a new ID set.
- `TableSelection` events gain `record: Option<String>` (the record ID) alongside the existing `row` index and `dataset_revision`. Consumers key on `record`; `row` remains for debugging.

### Views

The `table` node gains an optional member — views belong to tables, not datasets, because the dataset stays authoritative and two tables may view it differently:

```json
{
  "kind": "table", "id": "quotes-table", "dataset": "quotes",
  "view": {
    "sort": [{"column": 1, "direction": "desc"}],
    "filter": [{"column": 0, "op": "contains", "value": "AC"}]
  }
}
```

- Filter ops: `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `contains` — string comparison for `contains`, numeric comparison when both sides parse as finite `f64`, else lexical. At most 8 filter terms and 4 sort keys per table.
- Rust maintains a view index (`Vec<usize>` of source rows) per table, recomputed when the view spec or the dataset revision changes. Recompute cost at 100,000 records is measured and recorded; filter/sort terms on edited columns trigger recompute, other cell edits do not.
- The table renders and navigates the view order. Selection is stored as a record ID natively when `ids` exist: sorting, filtering or editing cells keeps the same record selected. Without `ids`, current index behavior is unchanged.
- **Disappearance rule:** if the selected record leaves the view (filtered out, or removed by `Replace`), selection clears and a `TableSelection` event with `row: null, record: null` is emitted. Selection is never transferred to a neighboring record implicitly.
- **Scroll anchor rule:** across view changes, the first fully visible record is kept anchored if it remains in the view; otherwise scroll resets to the top. `Replace` keeps its current unconditional reset (documented behavior, unchanged).
- `visible_rows` in diagnostics reports view coordinates; a new `view` field in the inspect payload reports source-row count, view-row count and the active spec hash.

### Views implementation (as shipped)

- The view index lives in the `Rows` delegate as `Rc<RefCell<Vec<usize>>>` (view row → source row), shared with `DartView`, which owns the spec per table. `render_td` maps through it; `render_tr` keys row elements by source row so element identity survives reorders (filler rows past the view's end get a separate element ID namespace — gpui-kit renders them for short tables).
- **Recompute policy:** a spec change or a `Replace` always recomputes; an `Edit` recomputes only when its touched columns intersect the view's sort/filter columns (`Edit::Cell` carries the column; `Edit::Row` touches all columns). Measured at 100,000 records: filter+sort recompute ≈43 ms in a debug build (`view_recompute_at_100k_records_is_measured` prints/records it). A `view_recomputes` counter in diagnostics proves unreferenced edits skip recomputation.
- **Selection by ID:** `DartView` stores the selected record ID per table; `TableState` keeps its view-row index. The `TableEvent::SelectRow` subscription maps view row → source row → record ID through the view index. GPUI delivers emitted events deferred, so instead of a suppression flag the subscription dedupes against the last notified (row, record) pair: programmatic re-resolution to the same record does not re-emit, and the disappearance rule's null event fires exactly once.
- **Disappearance rule** applies as specified; in index mode there is one addition: a filter that shrinks the view below the selected view-row index clears the selection (with event) instead of leaving a dangling index — prior behavior never shrank row counts, so there is no behavior to preserve.
- **Scroll anchor:** the first visible view row's record (source row in index mode) is captured before recompute; if it remains in the view the table scrolls it to the top (`scroll_to_row`, non-strict: no-op when already visible), else the scroll offset resets to the top. The selection's deferred scroll-to-selection is cleared so the anchor/reset rule wins. `Replace` keeps its unconditional reset.
- View column indices are validated against the dataset's actual width at publish/creation time (`validate_views`), rejecting the publish; `Snapshot::validate` only bounds them below 64.

## 4. Declarative cell formatting

Datasets gain an optional registration-time member:

```json
{
  "format": {
    "columns": {
      "1": {
        "number": {"decimals": 2},
        "rules": [
          {"when": {"op": "lt", "value": "0"}, "color": "token:danger"},
          {"when": {"op": "gt", "value": "0"}, "color": "token:success"}
        ]
      }
    }
  }
}
```

- Per column: optional numeric rendering (`decimals` 0–6, grouping off in this milestone), optional color/icon rules. Rule conditions use the same closed op set as filters. At most 16 rules per column; first matching rule wins.
- Icons are a closed enum (`arrow_up`, `arrow_down`, `dot`, `warning`), rendered by gpui-kit natively. No image URLs, no custom glyphs.
- Formatting is evaluated in `render_td` for visible cells only — the same virtualization boundary as today. No Dart callbacks anywhere in layout or paint.
- Malformed input values (e.g. non-numeric text in a `number` column) render the raw string unformatted; this is a documented fallback, not an error, because Dart stays authoritative for data quality.
- Formatter cost is covered by the existing allocation/cell-construction probes: formatted rendering must keep construction counts constant across dataset sizes, and per-cell formatter CPU is measured in the 100,000-row smoke.

### Formatting implementation (as shipped)

- `format` is a member of `TableData`, so it is set at initial upload and may change on `Replace`; `Edit` messages cannot carry it. It is validated in `TableData::validate` (column < width, decimals 0–6, ≤16 rules; op/icon/color are closed serde types that reject at parse).
- Rules evaluate against the raw cell string with the same numeric-or-lexical comparison as view filters — including for non-numeric values, where lexical comparison may still match `lt`/`gt` rules. The raw-string fallback applies to number rendering only.
- Number rendering is Rust's fixed-precision float formatting: correctly rounded, ties to even, trailing zeros kept, no grouping.
- Icons render inline via gpui-kit's `Icon` (Lucide catalog: `arrow_up`/`arrow_down`/`dot`/`warning` → `ArrowUp`/`ArrowDown`/`Dot`/`TriangleAlert`) at the cell's text size, before the text, colored with the rule color. Icon-free cells keep the previous single-div structure.
- Diagnostics gains a `formatted_cell` op (table ID, view row, column) reporting the formatted text, color and icon — the same evaluation `render_td` paints.
- Measured: construction counts are identical at 100 / 10,000 / 100,000 records with formats on all columns (`formatted_cells_keep_viewport_constant_construction`), and pure formatter cost is ≈1.7 µs/cell in a debug build (`cell_formatter_cost_is_measured_at_100k_cells`).

## Compatibility and verification plan

- ABI stays at version 1; all additions are optional fields. An old DLL against a new Dart SDK rejects unknown fields — that is the existing `deny_unknown_fields` discipline and is acceptable because Dart and native ship pinned together.
- New tests: style validation bounds and type mismatches; keymap conflict/context resolution and printable-key rejection; record-identity selection through sort/filter/edit/reload at 100,000 records asserting no unchanged records are republished (existing `Work` counters); disappearance and scroll-anchor rules; formatter bounds, fallback and rule precedence; cell-construction constancy under formatting.
- The watchlist example migrates: search box drives a native `contains` filter view, price column uses number format + up/down color rules, columns sortable via header actions, `ctrl+f` focuses search, and selection survives re-sorting — demonstrated by the live-window test suite, not by inspection.
- `docs/sdk.md` and `docs/datasets.md` are updated with the shipped types and bounds; this design doc records intent where implementation differs.
