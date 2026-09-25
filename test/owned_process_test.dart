@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/owned_process.dart';

void main() {
  test(
    'cleanup kills a descendant that ignores TERM after its parent exits',
    () async {
      final owned = await OwnedProcess.start('/bin/sh', [
        '-c',
        "sh -c 'trap \"\" TERM; echo \$\$; while :; do sleep 1; done' & exit 0",
      ]);
      final lines = StreamIterator(
        owned.process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      owned.process.stderr.drain<void>();
      try {
        expect(
          await lines.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        final child = int.parse(lines.current);
        expect(await owned.process.exitCode, 0);
        await owned.stop().timeout(const Duration(seconds: 6));
        final state = await Process.run('ps', ['-o', 'stat=', '-p', '$child']);
        // A dead orphan can remain a zombie until the runner's init reaps it.
        expect(
          (state.stdout as String).trim(),
          anyOf(isEmpty, startsWith('Z')),
        );
        await owned.stop();
      } finally {
        await owned.stop();
        await lines.cancel();
      }
    },
  );

  test('an exec failure is bounded and releases its owned group', () async {
    final owned = await OwnedProcess.start('/gpuidart-missing-program', []);
    owned.process.stdout.drain<void>();
    owned.process.stderr.drain<void>();
    expect(
      await owned.process.exitCode.timeout(const Duration(seconds: 5)),
      isNot(0),
    );
    await owned.stop().timeout(const Duration(seconds: 5));
  });
}
