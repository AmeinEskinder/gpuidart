import 'package:gpuidart/gpuidart.dart';

import 'snapshot_fixture.dart';

/// Times publish-to-ack for one field change in the snapshot-gate fixture
/// through a full rebuild (build, describe, diff, one set operation) and
/// through a patch (one set operation, nothing else), against a live host.
/// Each operation is timed twice: back to back, where the acknowledgement
/// also waits for the previous frame to finish on the native thread, and
/// settled, after an inspect round trip has let that frame complete. Prints
/// medians in microseconds per size. Point GPUIDART_LIBRARY at a release
/// library for representative figures; `dart run` gives JIT figures, a
/// compiled executable AOT ones.
Future<void> main(List<String> args) async {
  final iterations = args.isEmpty ? 40 : int.parse(args.first);
  for (final fields in [128, 512, 2048]) {
    final fixture = SnapshotFixture(fields);
    final host = await GpuiHost.openView(
      fixture.build,
      datasets: [SnapshotFixture.dataset()],
    );
    try {
      UiNode patched(int field, int round) => UiText(
        'field-$field',
        'Device ${field ~/ 32} / property $field: patched $round',
        style: const UiStyle(
          fontSize: 12,
          foreground: UiColor.token(ThemeToken.foreground),
        ),
      );
      Future<int> timed(Future<void> Function() operation) async {
        final timer = Stopwatch()..start();
        await operation();
        return timer.elapsedMicroseconds;
      }

      final rebuildSettled = <int>[];
      final patchSettled = <int>[];
      final rebuildBackToBack = <int>[];
      final patchBackToBack = <int>[];
      for (var i = 0; i < iterations; i++) {
        final field = i % fields;
        await host.diagnose('inspect');
        fixture.change('property');
        rebuildSettled.add(await timed(host.rebuild));
        await host.diagnose('inspect');
        patchSettled.add(await timed(() => host.patch(patched(field, i))));
        fixture.change('property');
        rebuildBackToBack.add(await timed(host.rebuild));
        patchBackToBack.add(
          await timed(() => host.patch(patched(field, i + iterations))),
        );
      }
      int median(List<int> values) => (values..sort())[values.length ~/ 2];
      print(
        '$fields fields: settled rebuild ${median(rebuildSettled)} us, '
        'settled patch ${median(patchSettled)} us; back to back rebuild '
        '${median(rebuildBackToBack)} us, patch ${median(patchBackToBack)} us '
        '(${host.metrics.patches} patches)',
      );
    } finally {
      await host.close();
    }
  }
}
