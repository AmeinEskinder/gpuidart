import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('column format serializes to the wire shape', () {
    final format = UiColumnFormat(
      decimals: 2,
      rules: [
        UiFormatRule(
          when: UiFormatCondition(UiFilterOp.lt, '0'),
          color: UiColor.token(ThemeToken.danger),
          icon: UiCellIcon.arrowDown,
        ),
        UiFormatRule(
          when: UiFormatCondition(UiFilterOp.gt, '0'),
          color: UiColor.hex('#16A34A'),
        ),
      ],
    );
    expect(jsonDecode(jsonEncode(format.toJson())), {
      'number': {'decimals': 2},
      'rules': [
        {
          'when': {'op': 'lt', 'value': '0'},
          'color': 'token:danger',
          'icon': 'arrow_down',
        },
        {
          'when': {'op': 'gt', 'value': '0'},
          'color': '#16A34A',
        },
      ],
    });
    expect(const UiColumnFormat().toJson(), <String, Object>{});
  });

  test('column format validates decimals and rule counts', () {
    expect(() => const UiColumnFormat(decimals: 7).toJson(), throwsRangeError);
    expect(() => const UiColumnFormat(decimals: -1).toJson(), throwsRangeError);
    expect(
      () => UiColumnFormat(
        rules: List.generate(
          17,
          (i) => UiFormatRule(when: UiFormatCondition(UiFilterOp.eq, '$i')),
        ),
      ).toJson(),
      throwsArgumentError,
    );
    expect(
      UiColumnFormat(
        rules: List.generate(
          16,
          (i) => UiFormatRule(when: UiFormatCondition(UiFilterOp.eq, '$i')),
        ),
      ).toJson()['rules'],
      hasLength(16),
    );
  });

  test('datasets validate format column indices against their width', () {
    expect(
      () => TableDataset(
        'records',
        columns: ['price'],
        rows: [
          ['1'],
        ],
        formats: const {1: UiColumnFormat(decimals: 2)},
      ),
      throwsRangeError,
    );
    expect(
      TableDataset(
        'records',
        columns: ['price'],
        rows: [
          ['1'],
        ],
        formats: const {0: UiColumnFormat(decimals: 2)},
      ).rowCount,
      1,
    );
  });
}
