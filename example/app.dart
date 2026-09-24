import 'package:gpuidart/gpuidart.dart';

class DemoApplication {
  DemoApplication({int rowCount = 10000})
    : quotes = TableDataset(
        'quote-data',
        columns: ['ID', 'Instrument', 'Price'],
        rows: List.generate(
          rowCount,
          (i) => ['$i', 'Instrument $i', '${100 + i / 100}'],
        ),
      );

  int count = 0;
  String name = '';
  final TableDataset quotes;

  String get heading => 'Dart application · GPUI Kit controls';

  UiNode build() => UiColumn('main', [
    UiText('title', heading),
    UiText('count', 'Count: $count'),
    const UiButton('increment', 'Increment'),
    const UiInput('name', placeholder: 'Type here; state survives updates'),
    UiText('greeting', name.isEmpty ? 'Enter a name' : 'Hello, $name'),
    const UiTable('quotes', dataset: 'quote-data'),
  ]);
}
