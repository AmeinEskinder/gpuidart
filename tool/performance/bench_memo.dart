import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/tree_diff.dart';

/// Times describe and diff for one field change in a form of N memoized
/// rows, with the rows rebuilt fresh every time (today's cost) and with the
/// unchanged rows handed back as the same instances through [UiMemo]. Prints
/// medians in microseconds. Run with `dart run` for JIT figures or compile to
/// an executable for AOT figures.
void main(List<String> args) {
  final iterations = args.isEmpty ? 200 : int.parse(args.first);
  for (final fields in [128, 512, 2048]) {
    for (final reuse in [false, true]) {
      final values = List.generate(fields, (i) => 'value $i');
      final memos = List.generate(fields, (_) => UiMemo<UiNode>());
      UiNode row(int i) => UiRow('row$i', [
        UiText('label$i', 'Field $i'),
        UiInput('input$i', placeholder: values[i]),
      ]);
      UiNode build() => UiColumn('root', [
        for (var i = 0; i < fields; i++)
          if (reuse) memos[i].of([values[i]], () => row(i)) else row(i),
      ]);
      var baseline = DescribedNode.describe(build());
      final describe = <int>[];
      final diff = <int>[];
      var bytes = 0;
      for (var round = 0; round < iterations; round++) {
        values[round % fields] = 'value $round changed';
        final root = build();
        final timer = Stopwatch()..start();
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
        '$fields fields, ${reuse ? 'memoized rows' : 'fresh rows'}: '
        'describe ${describe[describe.length ~/ 2]} us, '
        'diff ${diff[diff.length ~/ 2]} us, ops $bytes bytes',
      );
    }
  }
}
