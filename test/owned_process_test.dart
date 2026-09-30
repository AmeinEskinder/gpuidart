@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/owned_process.dart';
import '../tool/src/toolchain.dart';

void main() {
  for (final duringStartup in [true, false]) {
    test(
      'CLI interrupt cleans up the app during ${duringStartup ? 'startup' : 'watching'}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'gpuidart-interrupt-',
        );
        final entry = File('${directory.path}/main.dart');
        await entry.writeAsString('''
import 'dart:async';
import 'dart:developer';
import 'dart:io';

Future<void> main() async {
  print('fixture-ready:\$pid');
  await Future<void>.delayed(const Duration(seconds: 2));
  final keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {});
  registerExtension('ext.gpuidart.reassemble', (_, _) async => ServiceExtensionResponse.result('{}'));
  registerExtension('ext.gpuidart.close', (_, _) async {
    keepAlive.cancel();
    return ServiceExtensionResponse.result('{}');
  });
}
''');
        final owned = await OwnedProcess.start(dartExecutable, [
          'run',
          'tool/dev.dart',
          entry.path,
        ]);
        final lines = StreamIterator(
          owned.process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );
        final errors = owned.process.stderr.transform(utf8.decoder).join();
        int? appPid;
        try {
          while (await lines.moveNext().timeout(const Duration(seconds: 10))) {
            final line = lines.current;
            if (line.startsWith('fixture-ready:')) {
              appPid = int.parse(line.substring('fixture-ready:'.length));
              if (duringStartup) break;
            }
            if (!duringStartup && line.startsWith('Watching ')) break;
          }
          expect(appPid, isNotNull);
          expect(owned.process.kill(ProcessSignal.sigint), isTrue);
          expect(
            await owned.process.exitCode.timeout(const Duration(seconds: 15)),
            0,
            reason: await errors,
          );
          final state = await Process.run('ps', [
            '-o',
            'stat=',
            '-p',
            '$appPid',
          ]);
          expect(
            (state.stdout as String).trim(),
            anyOf(isEmpty, startsWith('Z')),
          );
        } finally {
          if (appPid != null) Process.killPid(appPid, ProcessSignal.sigkill);
          await owned.stop();
          await lines.cancel();
          await directory.delete(recursive: true);
        }
      },
    );
  }

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
