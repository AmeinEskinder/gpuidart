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

## Operations and lifetime

| Operation | Transfer and native work |
| --- | --- |
| `openView(..., datasets: [...])` | Upload and validate each initial dataset once |
| `registerDataset(dataset)` | Upload a new dataset under an unused ID at revision 1 |
| `publish` / `rebuild` | Send the whole view with dataset references, validate references and reconcile controls |
| `CellEdit` | Send row index, column index and value; replace one indexed string |
| `RowEdit` | Send row index and replacement values; replace one row |
| `replaceDataset` | Validate and replace the complete dataset and schema |
| `releaseDataset` | Drop the host's reference to an unused dataset |

Removing a table control does not release its dataset. Other tables can share it. Remove all references from the current view before release:

```dart
await host.publish(const UiText('empty', 'Table closed'));
await host.releaseDataset(quotes);
```

Released IDs cannot be reused within the same host, preventing delayed commands from addressing a new dataset under an old ID. Shutdown releases remaining native datasets. Dart can retain application records after native release.

Edits preserve table identity, selection and scroll position. Explicit replacement or binding an existing table to another dataset clears its selection and resets scrolling. Input controls retain their own state. Rows use indices; inserting, deleting or reordering records requires replacement.

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
- Selection by record ID follows the view; the scroll keeps the first visible record anchored across view changes when it remains in the view, and resets to the top otherwise. `replaceDataset` resets scroll unconditionally.
- Diagnostics report per-table source/view row counts, a spec hash, and the current selection.

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

- Initial upload, replacement and storage grow with total records. Messages are limited to 16 MiB, with at most 100,000 rows and 64 columns.
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
