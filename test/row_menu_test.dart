import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/native_event.dart';
import 'package:test/test.dart';

void main() {
  test(
    'table context menus carry bounded commands separately from records',
    () {
      final table = const UiTable(
        'table',
        dataset: 'records',
        contextMenu: [
          UiMenuAction('open', 'Open instrument', action: 'instrument.open'),
        ],
      );
      final wire = table.toJson();
      expect(wire['context_menu'], hasLength(1));
      expect(wire.containsKey('rows'), false);
      expect(
        () => UiTable(
          'table',
          dataset: 'records',
          contextMenu: List.filled(65, const UiMenuSeparator()),
        ).toJson(),
        throwsArgumentError,
      );
      final event = decodeNativeEvent(
        utf8.encode(
          jsonEncode({
            'type': 'row_action',
            'revision': 2,
            'id': 'table',
            'dataset': 'records',
            'dataset_revision': 5,
            'record': 'r17',
            'action': 'instrument.open',
          }),
        ),
      );
      expect(event['record'], 'r17');
      expect(event['dataset_revision'], 5);
      expect(
        () => decodeNativeEvent(
          utf8.encode('{"type":"row_action","revision":2,"id":"table"}'),
        ),
        throwsFormatException,
      );
    },
  );
}
