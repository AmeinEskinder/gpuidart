import 'dart:convert';

import 'package:gpuidart/src/tree_diff.dart';

import 'snapshot_fixture.dart';

/// Times describe and diff for one property change in the snapshot-gate
/// fixture without a native host, the way the host runs them, so the
/// Dart-side cost can be iterated on alone. Prints medians in microseconds per size. Run with `dart run` for
/// JIT figures or compile to an executable for AOT figures.
void main(List<String> args) {
  final iterations = args.isEmpty ? 200 : int.parse(args.first);
  for (final fields in [128, 512, 2048]) {
    final fixture = SnapshotFixture(fields);
    var baseline = DescribedNode.describe(fixture.build());
    final describe = <int>[];
    final diff = <int>[];
    var bytes = 0;
    for (var i = 0; i < iterations; i++) {
      fixture.change('property');
      final root = fixture.build();
      final timer = Stopwatch()..start();
      // Like the host: describe against the previous description, then seal.
      final described = DescribedNode.describe(root, previous: baseline);
      describe.add(timer.elapsedMicroseconds);
      timer.reset();
      final ops = diffDescribed(baseline, described)!;
      diff.add(timer.elapsedMicroseconds);
      described.seal();
      bytes = utf8.encode(jsonEncode(ops)).length;
      baseline = described;
    }
    describe.sort();
    diff.sort();
    print(
      '$fields fields: describe ${describe[describe.length ~/ 2]} us, '
      'diff ${diff[diff.length ~/ 2]} us, ops $bytes bytes',
    );
  }
}
