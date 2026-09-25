@TestOn('linux || mac-os')
@Tags(['live-window'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/src/platform.dart';
import 'package:test/test.dart';

import '../tool/src/owned_process.dart';

void main() {
  for (final mode in ['exit', 'hung']) {
    test('companion $mode startup settles and reaps the owned child', () async {
      final directory = await Directory.systemTemp.createTemp(
        'gpuidart-companion-fault-',
      );
      final script = File('${directory.path}/launcher');
      final pidFile = File('${directory.path}/pid');
      await script.writeAsString(
        '#!/bin/sh\necho \$\$ > "${pidFile.path}"\n${mode == 'exit' ? 'exit 7' : 'exec /bin/sleep 60'}\n',
      );
      expect((await Process.run('chmod', ['700', script.path])).exitCode, 0);
      final process = await OwnedProcess.start(
        Platform.resolvedExecutable,
        ['run', 'test/fixtures/companion_client.dart', mode],
        launcherPath: resolveLauncher(),
        environment: {
          'GPUIDART_LAUNCHER': script.path,
          'GPUIDART_COMPANION': '1',
        },
      );
      final output = process.process.stdout.transform(utf8.decoder).join();
      final errors = process.process.stderr.transform(utf8.decoder).join();
      try {
        expect(
          await process.process.exitCode.timeout(const Duration(seconds: 12)),
          0,
          reason: await errors,
        );
        expect(await output, contains('EXPECTED:'));
        final child = (await pidFile.readAsString()).trim();
        final status = await Process.run('ps', ['-o', 'stat=', '-p', child]);
        expect(
          (status.stdout as String).trim(),
          anyOf(isEmpty, startsWith('Z')),
        );
      } finally {
        await process.stop();
        await directory.delete(recursive: true);
      }
    });
  }
}
