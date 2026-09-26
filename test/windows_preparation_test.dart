import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Sandbox preparation uses the case-sensitive vGPU element', () async {
    await Directory('.cache').create(recursive: true);
    final fixture = await Directory('.cache')
        .createTemp('sandbox-preparation-');
    final archive = File('${fixture.path}/empty.zip');
    await archive.writeAsBytes([0x50, 0x4b, 0x05, 0x06, ...List.filled(18, 0)]);
    for (final mode in ['Enable', 'Disable']) {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-File',
        'tool/prepare_windows_release_checks.ps1',
        '-Zip',
        archive.absolute.path,
        '-VGpu',
        mode,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final directory = Directory('${result.stdout}'.trim());
      final configuration = await File('${directory.path}/check.wsb')
          .readAsString();
      expect(configuration, contains('<vGPU>$mode</vGPU>'));
      expect(configuration, isNot(contains('<VGpu>')));
      expect(configuration, contains('<Networking>Disable</Networking>'));
      final identityText = await File('${directory.path}/input/candidate.json')
          .readAsString();
      final identity = jsonDecode(
        identityText.replaceFirst('\ufeff', ''),
      ) as Map<String, dynamic>;
      expect(identity['vgpu'], mode);
    }
  }, skip: !Platform.isWindows);
}
