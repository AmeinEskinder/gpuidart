import 'package:gpuidart/gpuidart.dart';

class Instrument {
  Instrument(this.symbol, this.company, this.cents, this.changeBasisPoints);
  final String symbol;
  final String company;
  int cents;
  final int changeBasisPoints;
  bool shortlisted = false;

  /// Raw price carries four decimals; the table's number format renders two.
  String get priceRaw => (cents / 100).toStringAsFixed(4);
  String get changeRaw => (changeBasisPoints / 100).toStringAsFixed(4);
  String get price => (cents / 100).toStringAsFixed(2);
  List<String> get cells => [
    symbol,
    company,
    priceRaw,
    changeRaw,
    shortlisted ? 'Saved' : '',
  ];
}

/// Application state is independent of native input, focus and scroll state.
/// The dataset always holds all instruments; search, shortlist filtering and
/// sorting are a native view over it, so record selection survives them.
class WatchlistApplication {
  WatchlistApplication({this.count = 1000}) {
    const companies = [
      ('ALP', 'Alpine Research'),
      ('BRK', 'Brookfield Labs'),
      ('CED', 'Cedar Systems'),
      ('DLT', 'Delta Works'),
      ('ELM', 'Elm Networks'),
      ('FIR', 'Fir Energy'),
      ('GLN', 'Glen Robotics'),
      ('HBR', 'Harbor Design'),
    ];
    instruments = List.generate(count, (index) {
      final company = companies[index % companies.length];
      return Instrument(
        '${company.$1}${index.toString().padLeft(4, '0')}',
        company.$2,
        10000 + index * 7,
        (index * 13) % 41 - 20,
      );
    });
    dataset = TableDataset(
      'instruments',
      columns: columns,
      rows: instruments.map((item) => item.cells).toList(),
      rowIds: instruments.map((item) => item.symbol).toList(),
      formats: const {
        2: UiColumnFormat(decimals: 2),
        3: UiColumnFormat(
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
    );
  }

  static const columns = ['Symbol', 'Company', 'Price', 'Change', 'Shortlist'];
  final int count;
  late final List<Instrument> instruments;
  late final TableDataset dataset;
  String query = '';
  bool shortlistOnly = false;

  /// Sort state: null keeps dataset order; otherwise a column and direction.
  int? sortColumn;
  bool sortDescending = true;
  String? selectedSymbol;
  int ticks = 0;
  String status =
      'Select a row to update its sample price or save it to your shortlist.';

  String get heading => 'Market watch';

  /// The display-side mirror of the native view, for labels only.
  List<Instrument> get visible {
    final normalized = query.trim().toUpperCase();
    return instruments
        .where(
          (item) =>
              (!shortlistOnly || item.shortlisted) &&
              (normalized.isEmpty || item.symbol.contains(normalized)),
        )
        .toList();
  }

  Instrument? get selected {
    final symbol = selectedSymbol;
    if (symbol == null) return null;
    for (final item in instruments) {
      if (item.symbol == symbol) return item;
    }
    return null;
  }

  int get selectedSourceRow {
    final symbol = selectedSymbol;
    return symbol == null
        ? -1
        : instruments.indexWhere((item) => item.symbol == symbol);
  }

  UiTableView get view => UiTableView(
    sort: [
      if (sortColumn != null)
        UiSort(
          sortColumn!,
          direction: sortDescending
              ? UiSortDirection.desc
              : UiSortDirection.asc,
        ),
    ],
    filter: [
      if (query.trim().isNotEmpty)
        UiFilter(0, UiFilterOp.contains, query.trim().toUpperCase()),
      if (shortlistOnly) const UiFilter(4, UiFilterOp.eq, 'Saved'),
    ],
  );

  static const actions = [
    UiAction(name: 'app.search', keys: 'ctrl+f'),
    UiAction(
      name: 'watchlist.add',
      keys: 'ctrl+enter',
      context: UiActionContext.node('watchlist'),
    ),
  ];

  String get sortLabel => switch ((sortColumn, sortDescending)) {
    (2, true) => 'Price high → low',
    (2, false) => 'Price low → high',
    _ => 'Sort by price',
  };

  UiNode build() {
    final selected = this.selected;
    final shown = visible.length;
    final saved = instruments.where((item) => item.shortlisted).length;
    return UiColumn('watchlist-screen', [
      UiText(
        'title',
        heading,
        style: const UiStyle(fontSize: 22, fontWeight: UiFontWeight.semibold),
      ),
      const UiText(
        'source',
        'Sample instruments and prices. No live market feed.',
        style: UiStyle(foreground: UiColor.token(ThemeToken.mutedForeground)),
      ),
      const UiInput('search', placeholder: 'Search by symbol (Ctrl+F)'),
      UiRow('actions', [
        UiButton(
          'shortlist-filter',
          shortlistOnly ? 'Show all instruments' : 'Show shortlist',
        ),
        UiButton(
          'shortlist-toggle',
          selected?.shortlisted == true
              ? 'Remove from shortlist'
              : 'Add to shortlist',
        ),
        const UiButton('tick', 'Simulate price update'),
        UiButton('sort-price', sortLabel),
      ], style: const UiStyle(gap: 8)),
      UiText(
        'summary',
        '$shown ${shown == 1 ? 'instrument' : 'instruments'} shown · $saved saved',
        style: const UiStyle(fontWeight: UiFontWeight.medium),
      ),
      UiTable(
        'watchlist',
        dataset: 'instruments',
        view: view,
        style: const UiStyle(
          borderColor: UiColor.token(ThemeToken.border),
          borderRadius: 6,
        ),
      ),
      UiText(
        'selection',
        selected == null
            ? 'No instrument selected'
            : '${selected.symbol} · ${selected.company} · ${selected.price}',
      ),
      UiText(
        'status',
        shown == 0
            ? 'No instruments match. Edit the search or show all instruments.'
            : status,
        style: const UiStyle(
          foreground: UiColor.token(ThemeToken.mutedForeground),
          fontSize: 13,
        ),
      ),
    ], style: const UiStyle(gap: 12));
  }

  /// Search and shortlist filtering publish a view; the dataset is untouched
  /// and selection survives by record ID.
  Future<void> filter(
    GpuiHost host, {
    String? query,
    bool? shortlistOnly,
  }) async {
    this.query = query ?? this.query;
    this.shortlistOnly = shortlistOnly ?? this.shortlistOnly;
    await host.rebuild();
  }

  Future<void> cycleSort(GpuiHost host) async {
    switch ((sortColumn, sortDescending)) {
      case (null, _):
        sortColumn = 2;
        sortDescending = true;
      case (2, true):
        sortDescending = false;
      case (2, false):
        sortColumn = null;
    }
    await host.rebuild();
  }

  Future<void> select(GpuiHost host, String? symbol) async {
    selectedSymbol = symbol;
    await host.rebuild();
  }

  Future<void> focusSearch(GpuiHost host) async {
    await host.diagnose('focus', {'input': 'search'});
  }

  Future<void> tick(GpuiHost host) async {
    final row = selectedSourceRow;
    if (row < 0) {
      status = 'Select an instrument first.';
    } else {
      final item = instruments[row];
      final cents = item.cents + 7;
      await host.editDataset(dataset, [
        CellEdit(row, 2, (cents / 100).toStringAsFixed(4)),
      ]);
      item.cents = cents;
      ticks++;
      status = 'Updated ${item.symbol} to ${item.price}.';
    }
    await host.rebuild();
  }

  /// The ctrl+enter action: add only; removing stays on the button.
  Future<void> addSelectedToShortlist(GpuiHost host) async {
    final row = selectedSourceRow;
    if (row < 0 || instruments[row].shortlisted) {
      status = row < 0
          ? 'Select an instrument first.'
          : '${instruments[row].symbol} is already saved.';
      await host.rebuild();
      return;
    }
    await _setShortlisted(host, row, true);
  }

  Future<void> toggleShortlist(GpuiHost host) async {
    final row = selectedSourceRow;
    if (row < 0) {
      status = 'Select an instrument first.';
      await host.rebuild();
      return;
    }
    await _setShortlisted(host, row, !instruments[row].shortlisted);
  }

  Future<void> _setShortlisted(GpuiHost host, int row, bool saved) async {
    final item = instruments[row];
    await host.editDataset(dataset, [CellEdit(row, 4, saved ? 'Saved' : '')]);
    item.shortlisted = saved;
    status = '${item.symbol} ${saved ? 'added to' : 'removed from'} shortlist.';
    await host.rebuild();
  }
}
