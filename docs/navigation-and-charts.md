# Themes, navigation and charts

Use the existing whole-view snapshot and retained datasets. The
[market terminal](../example/terminal/README.md) demonstrates these APIs together;
[the design](market-terminal.md) records the feature selection and native spike.
Build Dart and native code from the same revision.

## Theme replacement

`GpuiHost.open` and `publish` accept `theme: UiTheme(...)`. `openView` accepts a
theme builder, evaluated on rebuild and code reload. Every snapshot replaces the
complete descriptor. An omitted theme selects light; omitted overrides reset to
the chosen built-in palette. Keep the application's theme state outside `build`.

`UiTheme.light()` and `UiTheme.dark()` select the pinned Kit palettes. Overrides
map the 16 existing `ThemeToken` values to opaque `#RRGGBB` colors. Unknown tokens,
other color syntax and out-of-bound maps are rejected. This API cannot inject
arbitrary style code. Kit's component-specific palette entries remain built in.
Changing a theme preserves mounted control entities. Custom colors are not
automatically contrast-corrected; the terminal verifier checks two numeric token
pairs, which is not a full visual contrast audit.

## Tabs and radio groups

`UiTabs` and `UiRadioGroup` take 1..32 `UiChoiceOption(id, label, disabled: ...)`
values and a required enabled `selected` option ID. IDs are unique within the
group and occupy 1..256 UTF-8 bytes; labels occupy 1..1024 bytes. The group has one
Tab stop. Surviving option IDs preserve their native focus handles after reorders;
removing an option or changing control kind invalidates old callbacks.

Tabs use Left/Right/Home/End to move focus and Enter/Space to request activation.
Radio groups additionally accept Up/Down and request activation while moving.
Disabled options are skipped. `tab_change` and `radio_change` events carry the
selected ID. Dart accepts a request by publishing the new `selected` property.
Neither control stores child pages or retains unmounted page state for the app.

Their native accessibility roles are TabList/Tab and RadioGroup/RadioButton.
Selection comes from the accepted snapshot, and focus from the native handle.

## Application and row menus

Pass up to eight `UiMenu` values to the host's `menus` argument, or a menus builder
to `openView`. Each flat menu contains 1..64 `UiMenuAction` or `UiMenuSeparator`
entries. Menu/entry IDs are locally unique and bounded to 256 UTF-8 bytes; labels
to 1024 bytes. Application entries reference registered global `UiAction` names.
Checked and disabled states belong to the snapshot. Nested submenus are not bound.

Application menus use macOS's native menu bar and Kit's in-window menu bar on
Windows/Linux. Their shortcuts use the existing global/scoped action machinery;
an enabled inner scope retains priority. Unchanged descriptors preserve open
menus. Replacing a descriptor validates an invoked entry against current state.

`UiTable.contextMenu` uses the same flat entry types but emits `RowActionEvent`
with table ID, dataset ID/revision, captured record ID and action. Stable dataset
row IDs are required. Right-click captures the rendered record; Shift+F10 uses
the selected record and opens the menu near the window center. Sorting/filtering
does not retarget the command. Dataset replacement, table rebinding/removal and
entry changes reject stale callbacks. Applications must still validate event
dataset revisions before applying their own asynchronous work.

## Button help

`UiButton.tooltip` accepts 1..1024 UTF-8 bytes. Kit owns hover delay, placement and
dismissal. Accessible help augments the button name without replacing it.
Tooltips are currently bound on buttons only.

## Dataset charts

`UiChart` renders one `ChartKind.line` or `ChartKind.bar` series. It references an
existing dataset, label/value columns and an optional `UiTableView`. It has no
application paint callback, point event or interactive zoom. Charts and tables
can reference the same dataset independently.

`maxPoints` is 1..512, default 128. Height is 80..1024 logical pixels, default 220.
Columns must exist in the source, within the dataset's 64-column bound. Filtering
and sorting apply first; the chart takes the final `maxPoints` candidate rows.
The initial projection of a sorted/filtered view may examine the full source.
The point count bounds rendering, not view computation.

Non-numeric or non-finite values and magnitudes above 1e12 are omitted and counted,
without backfilling. Lines connect the remaining points across omissions. Labels
are capped at 128 Unicode scalars. Internal source identity keeps identical
display labels at distinct positions. Unchanged snapshots reuse cached points;
edits to referenced data/view columns recompute the projection. Unrelated edits
only advance the observed dataset revision.

Each chart exposes a Group with a summary and bounded point Label alternatives.
The pinned AccessKit version has no Chart role. Alternatives and native rendering
read the same cached projection, with stable record IDs where available. Dataset
replacement validates live chart references before mutation; releasing a
referenced dataset is rejected.

The [evidence report](../reports/market-terminal/README.md) records validation,
headless, live bridge and external platform checks, including failed attempts.
No chart visual-quality or human screen-reader claim follows from those checks.
