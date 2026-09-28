import 'package:gpuidart/gpuidart.dart';

import 'snapshot_fixture.dart';

/// Reads the native draw histogram after a run of property edits in the
/// snapshot-gate fixture, with plain sections and with cached sections, so
/// the per-frame cost of the two can be compared on the same machine. Each
/// edit is followed by an inspect round trip so its frame completes before
/// the next edit. Point GPUIDART_LIBRARY at a release library.
Future<void> main(List<String> args) async {
  final edits = args.isEmpty ? 30 : int.parse(args.first);
  for (final fields in [512, 2048]) {
    for (final cached in [false, true]) {
      final fixture = SnapshotFixture(
        fields,
        fixedParts: cached,
        cachedParts: cached,
      );
      final host = await GpuiHost.openView(
        fixture.build,
        datasets: [SnapshotFixture.dataset()],
      );
      try {
        final before = await host.diagnose('inspect');
        for (var i = 0; i < edits; i++) {
          fixture.change('property');
          await host.rebuild();
          await host.diagnose('inspect');
        }
        final after = await host.diagnose('inspect');
        final draw = after['draw'] as Map<String, dynamic>;
        final startup = before['draw'] as Map<String, dynamic>;
        final subtrees = after['subtrees'] as Map<String, dynamic>? ?? const {};
        final renders =
            subtrees.values
                .map((s) => (s as Map<String, dynamic>)['renders'] as int)
                .toList()
              ..sort();
        print(
          '$fields fields, ${cached ? 'cached' : 'plain'} sections: '
          'draw p50 ${draw['p50_us']} us over ${draw['samples']} frames '
          '(startup ${startup['samples']} frames at p50 ${startup['p50_us']} us); '
          'materializations ${after['native']?['materializations'] ?? after['materializations']}'
          '${renders.isEmpty ? '' : '; section renders min ${renders.first} median ${renders[renders.length ~/ 2]} max ${renders.last}'}',
        );
      } finally {
        await host.close();
      }
    }
  }
}
