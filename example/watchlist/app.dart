import 'package:gpuidart/gpuidart.dart';

class Instrument {
  Instrument(this.symbol, this.company, this.cents);
  final String symbol;
  final String company;
  int cents;
  bool shortlisted = false;
  String get price => (cents / 100).toStringAsFixed(2);
  List<String> get cells => [
    symbol,
    company,
    price,
    shortlisted ? 'Saved' : '',
  ];
}

/// Application state is independent of native input, focus and scroll state.
class WatchlistApplication {
  WatchlistApplication() {
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
    instruments = List.generate(1000, (index) {
      final company = companies[index % companies.length];
      return Instrument(
        '${company.$1}${index.toString().padLeft(4, '0')}',
        company.$2,
        10000 + index * 7,
      );
    });
    visible = List.of(instruments);
    dataset = TableDataset(
      'instruments',
      columns: columns,
      rows: visible.map((item) => item.cells).toList(),
    );
  }

  static const columns = ['Symbol', 'Company', 'Sample price', 'Shortlist'];
  late final List<Instrument> instruments;
  late final TableDataset dataset;
  late List<Instrument> visible;
  String query = '';
  bool shortlistOnly = false;
  String? selectedSymbol;
  int ticks = 0;
  String status =
      'Select a row to update its sample price or save it to your shortlist.';

  String get heading => 'Market watch';
  int? get selectedRow {
    final index = visible.indexWhere((item) => item.symbol == selectedSymbol);
    return index < 0 ? null : index;
  }

  UiNode build() {
    final row = selectedRow;
    final selected = row == null ? null : visible[row];
    return UiColumn('watchlist-screen', [
      UiText('title', heading),
      const UiText(
        'source',
        'Sample instruments and prices. No live market feed.',
      ),
      const UiInput('search', placeholder: 'Search by symbol or company'),
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
      ]),
      UiText(
        'summary',
        '${visible.length} ${visible.length == 1 ? 'instrument' : 'instruments'} shown · ${instruments.where((item) => item.shortlisted).length} saved',
      ),
      const UiTable('watchlist', dataset: 'instruments'),
      UiText(
        'selection',
        selected == null
            ? 'No instrument selected'
            : '${selected.symbol} · ${selected.company} · ${selected.price}',
      ),
      UiText(
        'status',
        visible.isEmpty
            ? 'No instruments match. Edit the search or show all instruments.'
            : status,
      ),
    ]);
  }

  Future<void> filter(
    GpuiHost host, {
    String? query,
    bool? shortlistOnly,
  }) async {
    final nextQuery = query ?? this.query;
    final nextShortlist = shortlistOnly ?? this.shortlistOnly;
    final normalized = nextQuery.trim().toLowerCase();
    final next = instruments
        .where(
          (item) =>
              (!nextShortlist || item.shortlisted) &&
              ('${item.symbol} ${item.company}'.toLowerCase().contains(
                normalized,
              )),
        )
        .toList();
    await host.replaceDataset(
      dataset,
      columns: columns,
      rows: next.map((item) => item.cells).toList(),
    );
    this.query = nextQuery;
    this.shortlistOnly = nextShortlist;
    visible = next;
    selectedSymbol = null;
    await host.rebuild();
  }

  Future<void> select(GpuiHost host, int? row) async {
    if (row != null) RangeError.checkValidIndex(row, visible, 'row');
    selectedSymbol = row == null ? null : visible[row].symbol;
    await host.rebuild();
  }

  Future<void> tick(GpuiHost host) async {
    final row = selectedRow;
    if (row == null) {
      status = 'Select an instrument first.';
    } else {
      final item = visible[row];
      final cents = item.cents + 7;
      await host.editDataset(dataset, [
        CellEdit(row, 2, (cents / 100).toStringAsFixed(2)),
      ]);
      item.cents = cents;
      ticks++;
      status = 'Updated ${item.symbol} to ${item.price}.';
    }
    await host.rebuild();
  }

  Future<void> toggleShortlist(GpuiHost host) async {
    final row = selectedRow;
    if (row == null) {
      status = 'Select an instrument first.';
      await host.rebuild();
      return;
    }
    final item = visible[row];
    final saved = !item.shortlisted;
    await host.editDataset(dataset, [CellEdit(row, 3, saved ? 'Saved' : '')]);
    item.shortlisted = saved;
    status = '${item.symbol} ${saved ? 'added to' : 'removed from'} shortlist.';
    if (shortlistOnly && !saved) {
      await filter(host);
    } else {
      await host.rebuild();
    }
  }
}
