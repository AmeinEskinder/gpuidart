@TestOn('windows || linux || mac-os')
@Tags(['live-window'])
library;

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/tracing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'real host acknowledges guarded Unicode writes without input echoes',
    () async {
      final tracing = GpuiTrace(capacity: 2048);
      final host = await GpuiHost.open(
        const UiInput('name', controlled: true),
        trace: tracing,
      );
      final events = <GpuiEvent>[];
      final subscription = host.events.listen(events.add);
      try {
        final initial = await host.readInput('name');
        expect(initial.controlled, true);
        expect(initial.value, '');
        final written = await host.writeInput(
          initial,
          text: 'A😀日本',
          selection: const UiTextSelection(1, 3),
        );
        expect(written.value, 'A😀日本');
        expect(written.selection.end, 3);
        expect(written.editRevision, greaterThan(initial.editRevision));
        await expectLater(
          host.writeInput(initial, text: 'stale'),
          throwsA(
            isA<InputWriteException>().having(
              (e) => e.reason,
              'reason',
              'stale',
            ),
          ),
        );
        final selected = await host.writeInput(
          written,
          selection: const UiTextSelection(0, 0),
        );
        expect(selected.value, written.value);
        expect(selected.selection.end, 0);
        await expectLater(
          host.writeInput(selected, selection: const UiTextSelection(2, 2)),
          throwsA(
            isA<InputWriteException>().having(
              (e) => e.reason,
              'reason',
              'invalid_selection',
            ),
          ),
        );
        await host.publish(
          const UiInput('name', controlled: true, placeholder: 'Changed'),
        );
        final retained = await host.readInput('name');
        expect(retained.generation, initial.generation);
        expect(retained.editRevision, selected.editRevision);
        await host.publish(const UiInput('name'));
        await expectLater(
          host.writeInput(retained, text: 'disabled'),
          throwsA(
            isA<InputWriteException>().having(
              (e) => e.reason,
              'reason',
              'not_controlled',
            ),
          ),
        );
        await host.publish(const UiText('gone', 'Removed'));
        await expectLater(
          host.readInput('name'),
          throwsA(
            isA<InputWriteException>().having(
              (e) => e.reason,
              'reason',
              'missing',
            ),
          ),
        );
        await host.publish(const UiInput('name', controlled: true));
        final recreated = await host.readInput('name');
        expect(recreated.generation, greaterThan(initial.generation));
        expect(recreated.value, '');
        await expectLater(
          host.writeInput(retained, text: 'ghost'),
          throwsA(
            isA<InputWriteException>().having(
              (e) => e.reason,
              'reason',
              'stale',
            ),
          ),
        );
        await host.diagnose('inspect');
        expect(events.where((e) => e.type == 'input'), isEmpty);
      } finally {
        await host.close();
        await subscription.cancel();
      }
      final trace = tracing.toJson();
      expect((trace['metadata'] as Map)['capture_complete'], true);
      final records = (trace['records'] as List).cast<Map<String, dynamic>>();
      expect(
        records.any(
          (r) =>
              r['operation'] == 'input_control' && r['name'] == 'native.emit',
        ),
        true,
      );
      expect(
        records.any(
          (r) => r['operation'] == 'input_control' && r['name'] == 'dart.ack',
        ),
        true,
      );
      expect(trace.toString(), isNot(contains('A😀日本')));
    },
  );
}
