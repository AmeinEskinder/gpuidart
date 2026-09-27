import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('chart wire carries bounded dataset/view references, never records', () {
    for (final kind in ChartKind.values) {
      final wire = UiChart(
        'prices',
        dataset: 'history',
        series: kind,
        labelColumn: 0,
        valueColumn: 1,
        view: const UiTableView(filter: [UiFilter(2, UiFilterOp.ge, '12')]),
        semantics: const UiSemantics(
          role: UiRole.chart,
          label: 'Price history',
        ),
      ).toJson();
      expect(wire['kind'], 'chart');
      expect((wire['chart'] as Map)['series'], kind.name);
      expect((wire['chart'] as Map)['view'], isNotNull);
      expect((wire['chart'] as Map).containsKey('rows'), false);
    }
    for (final node in [
      const UiChart(
        'a',
        dataset: '',
        series: ChartKind.line,
        labelColumn: 0,
        valueColumn: 1,
      ),
      const UiChart(
        'a',
        dataset: 'd',
        series: ChartKind.line,
        labelColumn: -1,
        valueColumn: 1,
      ),
      const UiChart(
        'a',
        dataset: 'd',
        series: ChartKind.line,
        labelColumn: 0,
        valueColumn: 64,
      ),
      const UiChart(
        'a',
        dataset: 'd',
        series: ChartKind.line,
        labelColumn: 0,
        valueColumn: 1,
        maxPoints: 0,
      ),
      const UiChart(
        'a',
        dataset: 'd',
        series: ChartKind.line,
        labelColumn: 0,
        valueColumn: 1,
        maxPoints: 513,
      ),
      const UiChart(
        'a',
        dataset: 'd',
        series: ChartKind.line,
        labelColumn: 0,
        valueColumn: 1,
        height: double.nan,
      ),
      const UiChart(
        'a',
        dataset: 'd',
        series: ChartKind.line,
        labelColumn: 0,
        valueColumn: 1,
        height: 1025,
      ),
      const UiChart(
        'a',
        dataset: 'd',
        series: ChartKind.line,
        labelColumn: 0,
        valueColumn: 1,
        semantics: UiSemantics(role: UiRole.button),
      ),
    ]) {
      expect(node.toJson, throwsArgumentError);
    }
  });
}
