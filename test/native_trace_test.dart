@TestOn('windows || linux || mac-os')
@Tags(['live-window'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/tracing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'real requests correlate across the bridge without recording UI values',
    () async {
      final trace = GpuiTrace();
      final data = TableDataset(
        'private-dataset',
        columns: ['secret-column'],
        rows: [
          ['secret-value'],
        ],
      );
      UiNode build() => UiColumn('private-root', [
        const UiText('private-label', 'secret-label'),
        const UiInput('private-input', placeholder: 'secret-placeholder'),
        const UiTable('private-table', dataset: 'private-dataset'),
      ]);
      final host = await GpuiHost.openView(
        build,
        datasets: [data],
        trace: trace,
      );
      try {
        expect((trace.toJson()['metadata'] as Map)['finalized'], false);
        await host.diagnose('repaint', {'frames': 1});
        await host.editDataset(data, [const CellEdit(0, 0, 'secret-update')]);
        await host.rebuild();
        await expectLater(
          host.publish(const UiTable('invalid', dataset: 'missing')),
          throwsStateError,
        );
        expect(
          (await host.diagnose('cell', {
            'dataset': data.id,
            'row': 0,
            'column': 0,
          }))['value'],
          'secret-update',
        );
      } finally {
        await host.close();
      }
      final capture = trace.toJson();
      final metadata = capture['metadata'] as Map;
      expect(metadata['capture_complete'], true);
      expect(metadata['frequency'], greaterThan(0));
      final records = (capture['records'] as List).cast<Map>();
      Map record(String operation, int request, String name) =>
          records.singleWhere(
            (r) =>
                r['operation'] == operation &&
                r['request'] == request &&
                r['name'] == name,
          );
      for (final key in [
        ('snapshot', 2),
        ('snapshot', 3),
        ('dataset', 2),
        ('diagnostic', 3),
      ]) {
        final operation = key.$1, request = key.$2;
        final encoded = record(operation, request, 'dart.encode');
        final parsed = record(operation, request, 'native.parse');
        expect(encoded['bytes'], parsed['bytes']);
        expect(encoded['bytes'], greaterThan(0));
        final stages = [
          'dart.request',
          'dart.encode',
          'native.parse',
          'native.enqueue_attempt',
          'native.dequeue',
          'native.dispatch',
          'native.emit',
          'dart.receive',
          'dart.ack',
        ];
        for (var i = 1; i < stages.length; i++) {
          final before = record(operation, request, stages[i - 1]);
          final after = record(operation, request, stages[i]);
          expect(
            (after['start'] as int) - (before['start'] as int),
            greaterThanOrEqualTo(Platform.isWindows ? -1 : 0),
            reason: '${stages[i - 1]} -> ${stages[i]}',
          );
        }
        expect(record(operation, request, 'native.submit_return')['status'], 0);
        final dispatch = record(operation, request, 'native.dispatch');
        final emitted = record(operation, request, 'native.emit');
        expect(dispatch['thread'], emitted['thread']);
        expect(dispatch['end'], greaterThanOrEqualTo(emitted['start'] as int));
        expect(parsed['thread'], isNot(dispatch['thread']));
      }
      expect(record('snapshot', 3, 'dart.ack')['status'], 1);
      expect(record('snapshot', 1, 'dart.ack')['status'], 0);
      expect(record('initial', 1, 'dart.ack')['status'], 0);
      expect(
        record('dataset', 2, 'dart.ack')['native_apply_us'],
        isNonNegative,
      );
      expect(
        record('dataset', 2, 'dart.commit')['start'],
        greaterThanOrEqualTo(record('dataset', 2, 'dart.ack')['start'] as int),
      );
      final decoded = record('initial', 1, 'native.initial_decode');
      final validated = record('initial', 1, 'native.initial_validate');
      expect(decoded['bytes'], record('initial', 1, 'dart.encode')['bytes']);
      expect(validated['start'], greaterThanOrEqualTo(decoded['end'] as int));
      expect(
        record('initial', 1, 'native.first_content_paint')['process'],
        greaterThan(0),
      );
      for (final name in ['dart.json', 'dart.utf8', 'dart.ffi_copy']) {
        final stage = record('initial', 1, name);
        expect(stage['end'], greaterThanOrEqualTo(stage['start'] as int));
      }
      if (Platform.isMacOS ||
          Platform.environment['GPUIDART_COMPANION'] == '1') {
        final sent = record('initial', 1, 'native.companion_write');
        final received = record('initial', 1, 'native.companion_receive');
        final decoded = record('initial', 1, 'native.companion_decode');
        expect(sent['bytes'], received['bytes']);
        expect(received['bytes'], decoded['bytes']);
        expect(sent['process'], isNot(received['process']));
        expect(decoded['start'], greaterThanOrEqualTo(received['end'] as int));
      }
      final encoded = jsonEncode(capture);
      expect(encoded, isNot(contains('secret-')));
      expect(encoded, isNot(contains('private-')));
      expect(capture['traceEvents'], hasLength(records.length));
    },
  );

  test(
    'overflow is explicit and does not prevent updates or shutdown',
    () async {
      final trace = GpuiTrace(capacity: 2);
      final host = await GpuiHost.open(
        const UiText('text', 'initial'),
        trace: trace,
      );
      try {
        await host.publish(const UiText('text', 'updated'));
      } finally {
        await host.close();
      }
      final capture = trace.toJson();
      final metadata = capture['metadata'] as Map;
      expect(metadata['finalized'], true);
      expect(metadata['capture_complete'], false);
      expect(metadata['native_read_failed'], false);
      expect(metadata['dart_dropped'], greaterThan(0));
      expect(metadata['native_dropped'], greaterThan(0));
      expect(capture['records'], hasLength(4));
    },
  );
}
