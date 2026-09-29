import 'dart:async';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';

import '../watchlist/app.dart';

/// One window with in-memory sample data and application-owned navigation/drafts.
final class TerminalApplication {
  TerminalApplication._(int count)
    : market = WatchlistApplication(count: count);
  final WatchlistApplication market;
  final history = TableDataset(
    'history',
    columns: ['Day', 'Close', 'Volume', 'Index'],
    rows: [],
    rowIds: [],
  );
  late final GpuiHost host;
  late final StreamSubscription<GpuiEvent> _subscription;
  Future<void> _pending = Future.value();
  final _inputStates = <String, UiInputState>{};
  bool _closing = false;
  Object? failure;
  String page = 'watchlist';
  String period = '20';
  UiThemeMode mode = UiThemeMode.light;
  bool customAccent = false;
  String displayName = 'Dart user';
  String notice = 'Select an instrument to inspect its sample history.';
  bool helpOpen = false;
  final eventCounts = <String, int>{};
  String get heading => 'Market terminal';
  Future<void> get idle => _pending;

  static Future<TerminalApplication> open({int rows = 1000}) async {
    if (rows < 26 || rows > 100000) {
      throw ArgumentError('Rows must be 26..100000');
    }
    final app = TerminalApplication._(rows);
    app.host = await GpuiHost.openView(
      app.build,
      datasets: [app.market.dataset, app.history],
      theme: () => app.theme,
      menus: app.menus,
      actions: actions,
      window: const GpuiWindowOptions(
        title: 'Market terminal',
        width: 1000,
        height: 760,
      ),
    );
    app._subscription = app.host.events.listen((event) {
      if (event.type == 'closed') {
        app._closing = true;
        return;
      }
      if (event.type == 'error') {
        app.failure = StateError(event.toString());
        return;
      }
      if (![
        'input',
        'click',
        'tab_change',
        'radio_change',
        'checkbox_change',
        'table_selection',
        'row_action',
        'action',
        'tree_select',
        'sheet_close',
        'select_change',
      ].contains(event.type)) {
        return;
      }
      app.eventCounts.update(event.type, (n) => n + 1, ifAbsent: () => 1);
      app._pending = app._pending
          .then((_) async {
            if (!app._closing) await app._handle(event);
          })
          .catchError((Object error) {
            app.failure = error;
          });
    });
    return app;
  }

  static List<UiAction> get actions {
    final mod = Platform.isMacOS ? 'meta' : 'ctrl';
    return [
      UiAction(name: 'app.watchlist', keys: '$mod+1'),
      UiAction(name: 'app.instrument', keys: '$mod+2'),
      UiAction(name: 'app.settings', keys: '$mod+,'),
      UiAction(name: 'app.quit', keys: '$mod+q'),
      UiAction(name: 'data.tick', keys: '$mod+r'),
      UiAction(name: 'data.shortlist', keys: '$mod+b'),
      UiAction(name: 'app.search', keys: '$mod+f'),
    ];
  }

  UiTheme get theme => UiTheme(
    mode: mode,
    overrides: {
      if (customAccent) ...{
        ThemeToken.primary: mode == UiThemeMode.light ? '#2563EB' : '#93C5FD',
        ThemeToken.primaryForeground: mode == UiThemeMode.light
            ? '#FFFFFF'
            : '#111827',
      },
    },
  );

  List<UiMenu> menus() => [
    UiMenu('terminal', 'Terminal', [
      const UiMenuAction('settings', 'Settings', action: 'app.settings'),
      const UiMenuSeparator(),
      const UiMenuAction('quit', 'Quit terminal', action: 'app.quit'),
    ]),
    UiMenu('view', 'View', [
      UiMenuAction(
        'watchlist',
        'Watchlist',
        action: 'app.watchlist',
        checked: page == 'watchlist',
      ),
      UiMenuAction(
        'instrument',
        'Instrument detail',
        action: 'app.instrument',
        checked: page == 'instrument',
      ),
      const UiMenuAction('search', 'Search instruments', action: 'app.search'),
    ]),
    UiMenu('data', 'Data', [
      UiMenuAction(
        'tick',
        'Simulate price update',
        action: 'data.tick',
        disabled: market.selectedSymbol == null,
      ),
      UiMenuAction(
        'shortlist',
        'Toggle shortlist',
        action: 'data.shortlist',
        disabled: market.selectedSymbol == null,
      ),
    ]),
  ];

  UiNode build() => UiColumn('terminal', [
    UiText(
      'terminal-title',
      heading,
      semantics: const UiSemantics(role: UiRole.heading, headingLevel: 1),
      style: const UiStyle(fontSize: 24, fontWeight: UiFontWeight.semibold),
    ),
    const UiText(
      'sample-note',
      'Fictitious instruments and history. No live feed or trading.',
      style: UiStyle(foreground: UiColor.token(ThemeToken.mutedForeground)),
    ),
    // A navigation tree beside the pages, in resizable panes whose dragged
    // widths native keeps across publications.
    UiPanes(
      'shell',
      [
        _navigation(),
        UiColumn('content', [
          UiTabs(
            'pages',
            options: const [
              UiChoiceOption('watchlist', 'Watchlist'),
              UiChoiceOption('instrument', 'Instrument'),
              UiChoiceOption('settings', 'Settings'),
            ],
            selected: page,
            semantics: const UiSemantics(label: 'Terminal pages'),
          ),
          switch (page) {
            'instrument' => _instrument(),
            'settings' => _settings(),
            _ => _watchlist(),
          },
          UiText(
            'terminal-notice',
            notice,
            style: const UiStyle(
              foreground: UiColor.token(ThemeToken.mutedForeground),
            ),
          ),
        ], style: const UiStyle(gap: 8, padding: [0, 0, 0, 12])),
      ],
      panes: const [UiPane(size: 180, minSize: 140, maxSize: 320), UiPane()],
      style: const UiStyle(height: UiSize.px(600)),
    ),
    // The shortcuts sheet slides in from the right while help is open; its
    // close button reports back and the application publishes it closed.
    UiSheet(
      'help-sheet',
      'Keyboard shortcuts',
      [UiRichText('shortcuts', shortcutsMarkdown, selectable: true)],
      open: helpOpen,
      size: 380,
    ),
  ], style: const UiStyle(gap: 8));

  UiNode _navigation() => UiTree(
    'nav',
    items: const [
      UiTreeItem('watchlist', 'Watchlist'),
      UiTreeItem('instrument', 'Instrument'),
      UiTreeItem('settings', 'Settings'),
      UiTreeItem(
        'help',
        'Help',
        expanded: true,
        children: [UiTreeItem('shortcuts', 'Keyboard shortcuts')],
      ),
    ],
    selected: helpOpen ? 'shortcuts' : page,
    semantics: const UiSemantics(label: 'Terminal navigation'),
  );

  String get shortcutsMarkdown {
    final mod = Platform.isMacOS ? 'Command' : 'Control';
    return '''
# Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| $mod+1 / $mod+2 | Watchlist / Instrument |
| $mod+, | Settings |
| $mod+F | Search instruments |
| $mod+R | Simulate a price tick |
| $mod+B | Toggle the selected record's shortlist flag |
| $mod+Q | Close the terminal |

Right-click a watchlist row, or focus the table and press Shift+F10, for
record commands.
''';
  }

  /// The first two hundred instruments, for the find popover's combobox.
  List<UiSelectOption> get _jumpOptions => [
    for (final item in market.instruments.take(200))
      UiSelectOption(item.symbol, '${item.symbol} · ${item.company}'),
  ];

  String get _notesMarkdown {
    final selected = market.selected;
    if (selected == null) {
      return 'Select a row to see the instrument here, or use **Find** to jump to a symbol.';
    }
    return '''
## ${selected.symbol}

${selected.company}

| | |
| --- | --- |
| Price | ${selected.price} |
| Change | ${selected.changeRaw} % |
| Shortlist | ${selected.shortlisted ? 'saved' : 'not saved'} |
''';
  }

  UiNode _watchlist() => UiColumn('watchlist-page', [
    const UiInput(
      'search',
      controlled: true,
      placeholder: 'Search symbol',
      semantics: UiSemantics(label: 'Search instruments by symbol'),
    ),
    UiRow('watchlist-actions', [
      const UiButton(
        'tick',
        'Simulate price update',
        tooltip: 'Update the selected sample price by 0.07',
      ),
      const UiButton(
        'open-instrument',
        'Open instrument',
        tooltip: 'Show price and volume history for the selected instrument',
      ),
      UiButton(
        'shortlist-filter',
        market.shortlistOnly ? 'Show all instruments' : 'Show shortlist',
      ),
      UiButton('sort-price', market.sortLabel),
    ], style: const UiStyle(gap: 8)),
    // The table and the selected instrument's notes share the width.
    UiPanes(
      'watchlist-panes',
      [
        UiTable(
          'watchlist',
          dataset: market.dataset.id,
          view: market.view,
          semantics: const UiSemantics(label: 'Instruments'),
          style: const UiStyle(height: UiSize.px(330)),
          contextMenu: const [
            UiMenuAction('open', 'Open instrument', action: 'instrument.open'),
            UiMenuAction(
              'shortlist',
              'Toggle shortlist',
              action: 'instrument.shortlist',
            ),
          ],
        ),
        UiColumn('details', [
          // A popover holding a searchable select: type part of a symbol to
          // jump to that instrument.
          UiPopover('find', 'Find', [
            const UiText('find-hint', 'Jump to an instrument by symbol.'),
            UiSelect(
              'jump',
              options: _jumpOptions,
              selected:
                  market.instruments
                      .take(200)
                      .any((item) => item.symbol == market.selectedSymbol)
                  ? market.selectedSymbol
                  : null,
              placeholder: 'Symbol',
              searchable: true,
              semantics: const UiSemantics(label: 'Jump to instrument'),
            ),
          ]),
          UiRichText(
            'instrument-notes',
            _notesMarkdown,
            style: const UiStyle(padding: [0, 0, 0, 12]),
          ),
        ], style: const UiStyle(gap: 8)),
      ],
      panes: const [UiPane(size: 520, minSize: 360), UiPane(minSize: 180)],
      style: const UiStyle(height: UiSize.px(330)),
    ),
    UiText('selection', market.selectedSymbol ?? 'No instrument selected'),
  ], style: const UiStyle(gap: 8));

  UiNode _instrument() {
    final selected = market.selected;
    if (selected == null) {
      return const UiText(
        'empty-instrument',
        'Select an instrument in Watchlist first.',
      );
    }
    final view = UiTableView(
      filter: [UiFilter(3, UiFilterOp.ge, period == '20' ? '29' : '1')],
    );
    return UiColumn('instrument-page', [
      UiText(
        'instrument-title',
        '${selected.symbol} · ${selected.company}',
        semantics: const UiSemantics(role: UiRole.heading, headingLevel: 2),
        style: const UiStyle(fontSize: 20),
      ),
      UiRadioGroup(
        'period',
        options: const [
          UiChoiceOption('20', 'Recent 20 samples'),
          UiChoiceOption('48', 'All 48 samples'),
        ],
        selected: period,
        semantics: const UiSemantics(label: 'History range'),
      ),
      UiChart(
        'price-chart',
        dataset: 'history',
        series: ChartKind.line,
        labelColumn: 0,
        valueColumn: 1,
        view: view,
        maxPoints: 48,
        height: 150,
        semantics: const UiSemantics(label: 'Closing prices'),
      ),
      UiChart(
        'volume-chart',
        dataset: 'history',
        series: ChartKind.bar,
        labelColumn: 0,
        valueColumn: 2,
        view: view,
        maxPoints: 48,
        height: 110,
        semantics: const UiSemantics(label: 'Sample volumes'),
      ),
    ], style: const UiStyle(gap: 8));
  }

  UiNode _settings() => UiColumn('settings-page', [
    const UiText(
      'settings-title',
      'Workspace preferences',
      semantics: UiSemantics(role: UiRole.heading, headingLevel: 2),
      style: UiStyle(fontSize: 20),
    ),
    const UiInput(
      'display-name',
      controlled: true,
      placeholder: 'Display name',
      semantics: UiSemantics(label: 'Display name'),
    ),
    UiRadioGroup(
      'theme',
      options: const [
        UiChoiceOption('light', 'Light'),
        UiChoiceOption('dark', 'Dark'),
      ],
      selected: mode.name,
      semantics: const UiSemantics(label: 'Color theme'),
    ),
    UiCheckbox(
      'custom-accent',
      'Use custom blue accent',
      checked: customAccent,
    ),
    const UiText(
      'preferences-note',
      'Theme and draft survive code reload in this session. Preferences are not written to disk.',
    ),
  ], style: const UiStyle(gap: 12));

  Future<void> navigate(String target) async {
    if (target == page ||
        !['watchlist', 'instrument', 'settings'].contains(target)) {
      return;
    }
    final input = page == 'watchlist'
        ? 'search'
        : page == 'settings'
        ? 'display-name'
        : null;
    if (input != null) {
      final state = await host.readInput(input);
      if (state.composing) {
        notice = 'Finish text composition before changing tabs.';
        await host.rebuild();
        return;
      }
      _inputStates[input] = state;
      if (input == 'search') {
        market.query = state.value;
      } else {
        displayName = state.value;
      }
    }
    page = target;
    await host.rebuild();
    final mounted = page == 'watchlist'
        ? 'search'
        : page == 'settings'
        ? 'display-name'
        : null;
    if (mounted != null) {
      final value = mounted == 'search' ? market.query : displayName;
      _inputStates[mounted] = await host.writeInput(
        await host.readInput(mounted),
        text: value,
        selection: UiTextSelection(value.length, value.length),
      );
    }
  }

  Future<void> _select(String? record) async {
    if (record == market.selectedSymbol) return;
    market.selectedSymbol = record;
    final selected = market.selected;
    await host.replaceDataset(
      history,
      columns: history.columns,
      rows: selected == null
          ? []
          : List.generate(
              48,
              (i) => [
                'D${(i + 1).toString().padLeft(2, '0')}',
                ((selected.cents - (47 - i) * 3 + (i % 5) * 2) / 100)
                    .toStringAsFixed(2),
                '${((i % 7) + 2) * 15000 + market.selectedSourceRow * 100}',
                '${i + 1}',
              ],
            ),
      rowIds: selected == null
          ? []
          : List.generate(48, (i) => '${selected.symbol}:day-${i + 1}'),
    );
    notice = selected == null
        ? 'No instrument selected.'
        : 'Selected ${selected.symbol}.';
    await host.rebuild();
  }

  Future<void> _command(String action) async {
    switch (action) {
      case 'app.watchlist':
        await navigate('watchlist');
      case 'app.instrument':
        await navigate('instrument');
      case 'app.settings':
        await navigate('settings');
      case 'app.search':
        await navigate('watchlist');
        if (page == 'watchlist') {
          await host.diagnose('focus', {'input': 'search'});
        }
      case 'app.quit':
        _closing = true;
        await host.close();
      case 'data.tick':
        await market.tick(host);
        if (market.selected != null && history.rowCount > 0) {
          await host.editDataset(history, [
            CellEdit(47, 1, market.selected!.price),
          ]);
        }
        notice = market.status;
        await host.rebuild();
      case 'data.shortlist':
        await market.toggleShortlist(host);
        notice = market.status;
        await host.rebuild();
    }
  }

  Future<void> _handle(GpuiEvent event) async {
    if (event.type == 'input' &&
        (event.id == 'search' || event.id == 'display-name')) {
      final state = event.inputState!;
      final previous = _inputStates[event.id];
      if (previous != null &&
          (state.generation < previous.generation ||
              (state.generation == previous.generation &&
                  state.editRevision < previous.editRevision))) {
        return;
      }
      if ((event.id == 'search' && page != 'watchlist') ||
          (event.id == 'display-name' && page != 'settings')) {
        return;
      }
      _inputStates[event.id!] = state;
      if (event.id == 'search') {
        if (!state.composing) await market.filter(host, query: state.value);
      } else {
        displayName = state.value;
      }
    } else if (event.tableSelection case final selection?) {
      if (page == 'watchlist' &&
          selection.dataset == market.dataset.id &&
          selection.datasetRevision == market.dataset.revision) {
        await _select(selection.record);
      }
    } else if (event.rowAction case final command?) {
      if (command.dataset == market.dataset.id &&
          command.datasetRevision == market.dataset.revision) {
        await _select(command.record);
        if (command.action == 'instrument.open') {
          await navigate('instrument');
        } else if (command.action == 'instrument.shortlist') {
          await _command('data.shortlist');
        }
      }
    } else if (event.action case final action?) {
      await _command(action.name);
    } else if (event.type == 'tab_change') {
      await navigate(event.selected!);
    } else if (event.type == 'tree_select') {
      switch (event.item) {
        case 'watchlist' || 'instrument' || 'settings':
          if (helpOpen) helpOpen = false;
          await navigate(event.item!);
          await host.rebuild();
        case 'shortcuts':
          helpOpen = true;
          await host.rebuild();
      }
    } else if (event.type == 'sheet_close' && event.id == 'help-sheet') {
      helpOpen = false;
      await host.rebuild();
    } else if (event.type == 'select_change' && event.id == 'jump') {
      if (event.selected case final symbol?) {
        await _select(symbol);
      }
    } else if (event.type == 'radio_change') {
      if (event.id == 'period') {
        period = event.selected!;
      }
      if (event.id == 'theme') {
        mode = UiThemeMode.values.byName(event.selected!);
      }
      await host.rebuild();
    } else if (event.type == 'checkbox_change' && event.id == 'custom-accent') {
      customAccent = event.checked!;
      await host.rebuild();
    } else if (event.type == 'click') {
      switch (event.id) {
        case 'tick':
          await _command('data.tick');
        case 'open-instrument':
          await navigate('instrument');
        case 'sort-price':
          await market.cycleSort(host);
        case 'shortlist-filter':
          await market.filter(host, shortlistOnly: !market.shortlistOnly);
      }
    }
  }

  Map<String, Object?> describe() => {
    'heading': heading,
    'page': page,
    'period': period,
    'theme': mode.name,
    'custom_accent': customAccent,
    'display_name': displayName,
    'help_open': helpOpen,
    'selected': market.selectedSymbol,
    'query': market.query,
    'ticks': market.ticks,
    'instruments_revision': market.dataset.revision,
    'history_revision': history.revision,
    'events': eventCounts,
    'failure': failure?.toString(),
  };

  Future<void> close() async {
    _closing = true;
    await host.close();
    await _subscription.cancel();
    await _pending;
  }
}
