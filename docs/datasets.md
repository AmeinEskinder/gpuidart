# Retained table datasets

View snapshots describe controls and reference a dataset by ID. Rust retains records separately. Dart owns the application records and authors each transaction.

## API

```dart
final quotes = TableDataset(
  'quotes-data',
  columns: ['ID', 'Instrument', 'Price'],
  rows: List.generate(100000, (i) => ['$i', 'Instrument $i', '100.00']),
);
var count = 0;
UiNode build() => UiColumn('main', [
  UiText('count', 'Count: $count'),
  const UiTable('quotes', dataset: 'quotes-data'),
]);
final host = await GpuiHost.openView(build, datasets: [quotes]);

await host.editDataset(quotes, [const CellEdit(4, 2, '101.25')]);
assert(quotes.cell(4, 2) == '101.25');
assert(quotes.revision == 2);

count++;
await host.rebuild(); // No table records.

await host.editDataset(quotes, [
  RowEdit(4, ['4', 'Renamed instrument', '102.50']),
  const CellEdit(99999, 2, '99.25'),
]);

await host.replaceDataset(
  quotes,
  columns: ['ID', 'Instrument', 'Price'],
  rows: [['0', 'Replacement', '123.45']],
);
```

`columns` and the result of `row()` are immutable. Successful transactions commit values to the Dart dataset and advance its revision. Rejection leaves both sides unchanged. Await each transaction before starting another on the same dataset.

Cells and record IDs cross to native as UTF-8, so an unpaired UTF-16 surrogate has no wire form: in an edit it is an `ArgumentError` before anything is sent, in a packed slice it fails that upload (a failed upload during `open` closes the window), and in the JSON forms native rejects the message. The constructor does not scan for one, since a scan of a million records costs about a quarter of a second.

`TableDataset(..., retainRecords: false)` releases the Dart copy of the records once they are uploaded, so native holds the only one. `rowCount`, edits by index, structural edits and `replaceDataset` keep working; native validates record IDs on inserts, so a duplicate is a rejected transaction rather than an `ArgumentError`; `row`, `cell` and `rowId` throw a `StateError`. Read values back with the `cell` diagnostic when needed. At a million records this returns about 230 MiB of process memory once the collector has run ([measured](../reports/performance/datasets-1m-20260928/README.md)).

## Operations and lifetime

| Operation | Transfer and native work |
| --- | --- |
| `openView(..., datasets: [...])` | Upload and validate each initial dataset once. Records beyond about 4 MiB of encoded text go as a schema in the initial message and appended slices once the window is ready, one revision per slice, before `open` returns |
| `openView(..., deferDatasets: true)` | Upload only columns and formats before the first frame; the records follow as replacements once the window is ready, and `open` returns after they applied at revision 2 |
| `registerDataset(dataset)` | Upload a new dataset under an unused ID at revision 1; a large one sends its first slice as that upload and the rest appended |
| `TableDataset.generated(id, columns:, rowCount:, rowAt:, rowIdAt:)` | Records produced on demand and never held in the calling isolate: the schema uploads at revision 1 and a short-lived helper isolate generates, packs and submits the records one slice at a time, each slice a revision, then exits. `open` or `registerDataset` returns after the last slice applied. The generators must be sendable to an isolate (top-level or static functions, or closures over plain values); a repeated record ID is native's rejection, surfaced as the upload's error. Main-window datasets only |
| `publish` / `rebuild` | Send the whole view with dataset references, validate references and reconcile controls |
| `CellEdit` | Send row index, column index and value; replace one indexed string |
| `RowEdit` | Send row index and replacement values; replace one row |
| `InsertRow` | Send the index, values and record ID; insert one record and recompute views |
| `DeleteRow` | Send the index; drop one record and recompute views |
| `MoveRow` | Send the index and destination; reorder one record and recompute views |
| `replaceDataset` | Validate and replace the complete dataset and schema; a large replacement sends its first slice as the replacement and the rest appended, and the Dart records follow each acknowledgement |
| `releaseDataset` | Drop the host's reference to an unused dataset |

Removing a table control does not release its dataset. Other tables can share it. Remove all references from the current view before release:

```dart
await host.publish(const UiText('empty', 'Table closed'));
await host.releaseDataset(quotes);
```

Released IDs cannot be reused within the same host, preventing delayed commands from addressing a new dataset under an old ID. Shutdown releases remaining native datasets. Dart can retain application records after native release.

Edits preserve table identity, selection and scroll position. Explicit replacement or binding an existing table to another dataset clears its selection and resets scrolling. Input controls retain their own state.

Rows use indices. `InsertRow`, `DeleteRow` and `MoveRow` change which records exist without a replacement:

```dart
await host.editDataset(quotes, [
  InsertRow(0, ['NEW', 'New instrument', '10.00'], id: 'NEW'),
  const DeleteRow(3),
  const MoveRow(0, 2),
]);
```

Steps in a batch apply in order, so each index refers to the records as the previous steps left them, and both sides validate the whole batch against that running shape before anything is written. An insert carries a record ID exactly when the dataset has record IDs; the ID must be nonempty and unused, and an ID deleted earlier in the same batch stays reserved until the next batch. A batch may not grow the dataset past 1,000,000 rows. Structural edits recompute every view over the dataset. With record IDs the selection follows its record, clears when the record is deleted, and the scroll keeps the first visible record anchored; without IDs the selected view row keeps its index.

## Stable record IDs

Pass `rowIds` to give each record a stable ID for its lifetime in one dataset. IDs must parallel the rows (same length, nonempty, unique).

```dart
final quotes = TableDataset(
  'quotes-data',
  columns: ['Symbol', 'Price'],
  rows: [['ACME', '100.0000'], ['BETA', '99.5000']],
  rowIds: ['ACME', 'BETA'],
);
```

With IDs present, native selection is stored as a record ID and survives sorting, filtering and cell edits; `TableSelection.record` carries it alongside the view `row` index (key on `record`; `row` is for debugging). If the selected record leaves the view — filtered out or removed by `replaceDataset` — selection clears and a selection event with both fields null is emitted; selection is never transferred to a neighbor. Row edits cannot change a record's ID; replacement may supply a new ID set. Without `rowIds`, index-based behavior is unchanged.

## Table views

`UiTable` accepts an optional `view` — a presentation-only filter/sort over the retained dataset. Views belong to tables, so two tables can view one dataset differently, and views never reorder the authoritative Dart records.

```dart
UiTable(
  'quotes',
  dataset: 'quotes-data',
  view: const UiTableView(
    sort: [UiSort(1, direction: UiSortDirection.desc)],
    filter: [UiFilter(0, UiFilterOp.contains, 'AC')],
  ),
)
```

- Filter ops: `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `contains`. `contains` is a case-sensitive substring match; the rest compare numerically when both the cell and the filter value parse as finite doubles, lexically otherwise. All terms must match (AND).
- At most 8 filter terms and 4 sort keys per table; column indices must be below 64 and within the dataset's width (the host rejects wider references at publish). Sorting is stable.
- Rust keeps a view index per table and recomputes it when the view spec changes, on `replaceDataset`, or when an edit touches a sort/filter column; edits to unreferenced columns do not recompute it. Rendering and navigation follow the view order.
- A view over 10,000 records or more computes off the frame thread, over a snapshot of the records shared with the store. The publication or edit that changes it is acknowledged at once with the table listed in `pending_views`; the table keeps its last rows meanwhile (in dataset order after a replacement, with appended records behind them, following inserted, deleted and moved records), the window keeps painting and taking input, and a `table_view` event (`GpuiEvent.tableView`) reports the table, the dataset revision, the row and group counts and the compute time when the index swaps in with the selection and scroll anchor resolved. `GpuiHost.viewsSettled` completes when no view is pending, after the last `table_view` event has reached listeners; a verifier or test that inspects a table after a publication or edit awaits it first, since the acknowledgement arrives while the table still shows the previous index. Edits to a dataset a job is reading wait in arrival order and apply, with their acknowledgements, after the index lands; a second view change while a job runs supersedes it. Smaller views compute in place, and `table_view` still reports them.
- Selection by record ID follows the view; the scroll keeps the first visible record anchored across view changes when it remains in the view, and resets to the top otherwise. `replaceDataset` resets scroll unconditionally.
- `group: UiGroup(column, aggregates: [UiAggregate(column, UiAggregateOp.sum)])` groups the filtered, sorted records by one column in order of first appearance and inserts a header row per group. The header shows the key and count in the grouped column and each aggregate in its column, formatted with that column's format when it has one. `count` counts records; `sum`, `avg`, `min` and `max` run over the numeric cells and show nothing when none parse. At most 8 aggregates. Header rows are summaries: selecting one clears the selection and emits nothing, and edits to the grouped or aggregated columns recompute the view like sort and filter columns do. Diagnostics report the group count beside the view row count.
- Diagnostics report per-table source/view row counts, a spec hash, and the current selection.

## Lists

`UiList` shows one column of a dataset as a virtualized list, like Flutter's
`ListView.builder` over the same records a table can show.

```dart
UiList(
  'symbols',
  dataset: 'quotes-data',
  column: 0,
  view: const UiTableView(sort: [UiSort(0)]),
  selected: 'ACME',
)
```

- The dataset must carry record IDs; publishing a list over a dataset
  without them fails. `column` must be below the dataset's width.
- `view` accepts the table view's filter and sort; grouping is rejected.
  Rust keeps a view index per list and recomputes it under the same rules as
  a table's, and only the visible items are built.
- `selected` is a record ID owned by the application. Clicking an item
  reports `list_select` with the record ID, row and dataset revision; the
  item highlights at once and the next publication's `selected` is
  authoritative, like the other controls.
- The list's semantics role is `list`; its items are list items named by
  their text. Diagnostics report each list's dataset, revision, view row
  count and the selection shown.

## Declarative cell formatting

Datasets accept optional per-column formats at construction and on `replaceDataset` (edits cannot change them).

```dart
TableDataset(
  'quotes-data',
  columns: ['Symbol', 'Price', 'Change'],
  rows: rows,
  rowIds: ids,
  formats: const {
    1: UiColumnFormat(decimals: 2),
    2: UiColumnFormat(
      decimals: 2,
      rules: [
        UiFormatRule(
          when: UiFormatCondition(UiFilterOp.lt, '0'),
          color: UiColor.token(ThemeToken.danger),
          icon: UiCellIcon.arrowDown,
        ),
        UiFormatRule(
          when: UiFormatCondition(UiFilterOp.gt, '0'),
          color: UiColor.token(ThemeToken.success),
          icon: UiCellIcon.arrowUp,
        ),
      ],
    ),
  },
)
```

- `decimals` is fixed-point rendering with 0–6 decimals, no grouping, correctly rounded (ties to even). A non-numeric value in a number column renders the raw string unchanged.
- Rules use the same ops as view filters and evaluate against the raw cell string; the first matching rule wins, at most 16 per column. Rule colors are style colors (theme token or `#RRGGBB`/`#RRGGBBAA`); icons are `arrowUp`, `arrowDown`, `dot` and `warning`, rendered inline by the native toolkit.
- Formatting is evaluated for visible cells only, with no Dart callbacks in layout or paint.

## Transactions

Each message carries a request ID, dataset ID, expected base revision and next revision. Revisions start at 1 and advance by exactly one. Data commands and view snapshots share the native FIFO queue.

Rust checks the revision and validates every edit before applying any edit. Batch edits apply in list order; the last edit to a cell wins. Invalid indices, row widths or stale revisions reject the entire batch. Unknown dataset references reject view publication through a correlated completion, so the Dart future resolves with an error.

A data batch is atomic on the UI thread. A data transaction and a subsequent view snapshot have separate acknowledgements and may appear in different frames.

Data acknowledgements report native parsing time, application time, records checked and cells written. View acknowledgements report application time separately. Neither measures displayed pixels. The benchmark times each complete Dart API call separately and does not add percentiles from different intervals.

## Cost and limits

- A dataset built with `TableDataset.generated` costs the process native's copy of the records and one slice in flight (about 4 MiB of packed text plus the rows of that slice) rather than a Dart copy of every record, and nothing waits for a collection: the helper isolate's rows are short-lived and the calling isolate never held them. This is the SDK's path for a million records.
- Initial upload, replacement and storage grow with total records. Messages are limited to 16 MiB; datasets have at most 1,000,000 rows and 64 columns, and records that would exceed one message travel as appended slices of about 4 MiB each, so a large upload costs one transaction per slice. A slice is a framed message: the `GDP1` prefix, the length of a JSON `append` header, that header, then the records as length-prefixed UTF-8 cells row by row and the record IDs the same way, which spares both sides the JSON quoting of every cell. Native stores and acknowledges every slice but recomputes the views, notifies the tables and updates the charts once, at the last one (`more` in the header marks the others), checks appended record IDs against a sorted index of their hashes (eight bytes per record), and Dart packs each slice while native applies the previous one. Descriptions and edits stay JSON. [One million records](../reports/performance/datasets-1m-20260929/README.md) upload in 13 slices in 1.15 to 1.86 s depending on the machine's load (about 3 s [before](../reports/performance/datasets-1m-20260928/README.md) the packed slices) and sort in 120 to 160 ms, holding roughly 345 MiB in Dart and 250 MiB natively; with `retainRecords: false` the Dart share is released after the upload, about 230 MiB of process memory once collected.
- Snapshots contain no records; their cost grows with view size.
- Batches visit only their edits. Dart copies one immutable row when committing a cell, at most 64 columns. Rust replaces the indexed string directly.
- Rust's shared dataset belongs to the UI thread. `TableData` has no `Clone` or `PartialEq` implementation, preventing accidental full-data cloning or comparison in reconciliation.
- Notification work grows with the number of table controls using a dataset. Rendering remains virtualized.
- The initial FFI message now contains `snapshot` and `datasets`. Inline records have been removed from the view protocol. Build Dart and the native DLL together.

## Verification

```powershell
./tool/check.ps1
./tool/package.ps1
dart run tool/measure_data.dart
$env:GPUIDART_LIBRARY = "$PWD/target/release/gpuidart.dll"
dart run tool/verify_reload.dart
```

See [publication measurements](../reports/data-publication.md), [native allocations](../reports/data-allocations.json), and [the previous full-data baseline](../reports/baseline-snapshots/summary.md). The live acceptance test measures one cell, one row, ten cells and an unrelated counter at 100, 10,000 and 100,000 records. It checks transferred bytes, record work, retained identity, actual stored values and subsequent rendering. The reload fixture also checks an edited dataset value and revision across a real code change.

## Remaining desktop evidence

Windows Sandbox is not installed on this machine; a fresh Windows VM or clean machine is still needed. The computer-use helper failed after retry and reset, so visual IME composition, selection, scrolling and resizing remain unverified. Headless tests do not establish visual IME behavior.

Controlled OS input-to-present measurement and matched GPUI Shell/QuickJS and GPUIX/Solid workloads remain outstanding. Current measurements establish no ranking against those runtimes.


## Chart consumers

`UiChart` shares retained datasets and `UiTableView` with tables. It validates
label/value/view columns before accepting a snapshot or dataset replacement.
A dataset referenced by a mounted chart cannot be released. The chart caches its
bounded projection and reuses it through unchanged snapshots; relevant edits
recompute it. See [chart limits and omission rules](navigation-and-charts.md#dataset-charts).
Record IDs supply stable point alternatives, while chart rendering remains bounded
to at most 512 candidate rows. Filtering/sorting may still examine the full source.
