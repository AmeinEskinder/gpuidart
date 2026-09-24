@TestOn('windows')
library;

import 'dart:async';

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Dart timers publish to the real GPUI loop and shutdown releases it',
    () async {
      final table = UiTable(
        'table',
        columns: ['ID', 'Value'],
        rows: List.generate(10000, (i) => ['$i', 'Row $i']),
      );
      UiNode build(String message) => UiColumn('root', [
        UiText('status', message),
        const UiButton('action', 'Action'),
        const UiInput('input', placeholder: 'Persistent input'),
        table,
      ]);
      final host = await GpuiHost.open(build('Starting'));
      final events = <GpuiEvent>[];
      final subscription = host.events.listen(events.add);
      try {
        final firstUpdate = Completer<void>();
        Timer(const Duration(milliseconds: 100), () async {
          try {
            await host.publish(build('Timer completed'));
            firstUpdate.complete();
          } catch (error, stack) {
            firstUpdate.completeError(error, stack);
          }
        });
        await firstUpdate.future.timeout(const Duration(seconds: 10));
        expect(
          () => host.publish(
            UiTable(
              'invalid',
              columns: ['A', 'B'],
              rows: [
                ['x'],
              ],
            ),
          ),
          throwsStateError,
        );
        await host.publish(build('Valid after rejected update'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          events.where((e) => e.type == 'applied').map((e) => e.revision),
          containsAllInOrder([2, 4]),
        );
        expect(events.where((e) => e.type == 'error'), isEmpty);
      } finally {
        await host.close().timeout(const Duration(seconds: 10));
        await subscription.cancel();
      }
      await host.close();
      expect(() => host.publish(build('After close')), throwsStateError);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
