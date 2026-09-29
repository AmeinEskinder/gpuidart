import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/prepare_windows_release_checks.dart';
import '../tool/src/toolchain.dart';
import '../tool/windows/capability_state.dart';
import '../tool/windows/common.dart';
import '../tool/windows/enable_release_checks.dart' as setup;

void main() {
  test(
    'setup rejects assigned boolean switches before system inspection',
    () async {
      for (final flag in ['sandbox', 'japanese', 'check-only']) {
        await expectLater(
          setup.main(['--japanese', '--$flag=false']),
          throwsArgumentError,
        );
        await expectLater(
          setup.main(['--japanese', '--$flag=true']),
          throwsArgumentError,
        );
      }
      expect(() => options(['--report'], {'report'}), throwsArgumentError);
      expect(() => options(['--report='], {'report'}), throwsArgumentError);
      expect(
        options(
          ['--japanese', '--report=out.json'],
          {'japanese', 'report'},
          flags: {'japanese'},
        ),
        {'japanese': 'true', 'report': 'out.json'},
      );
    },
  );

  test(
    'Sandbox preparation preserves graphics mode and isolated mappings',
    () async {
      final fixture = await Directory.systemTemp.createTemp(
        'sandbox-preparation-',
      );
      addTearDown(() => fixture.delete(recursive: true));
      final archive = File('${fixture.path}/empty.zip');
      await archive.writeAsBytes([
        0x50,
        0x4b,
        0x05,
        0x06,
        ...List.filled(18, 0),
      ]);
      for (final mode in ['Enable', 'Disable']) {
        final directory = await prepareWindowsReleaseChecks(
          archive: archive,
          vgpu: mode,
        );
        addTearDown(() => directory.delete(recursive: true));
        final configuration = await File('${directory.path}/check.wsb')
            .readAsString();
        expect(configuration, contains('<vGPU>$mode</vGPU>'));
        expect(configuration, isNot(contains('<VGpu>')));
        expect(configuration, contains('<Networking>Disable</Networking>'));
        expect(configuration, contains('<ReadOnly>true</ReadOnly>'));
        expect(
          configuration,
          contains(r'C:\GPUI-Input\sandbox_release_check.exe'),
        );
        expect(configuration.toLowerCase(), isNot(contains('powershell')));
        final identity = jsonDecode(
          await File('${directory.path}/input/candidate.json').readAsString(),
        ) as Map;
        expect(identity['vgpu'], mode);
        expect(identity['host_identity'], isNotEmpty);
        expect(
          await File('${directory.path}/input/sandbox_release_check.exe')
              .exists(),
          isTrue,
        );
        expect(
          await File('${directory.path}/input/gpuidart-windows-tool.exe')
              .exists(),
          isTrue,
        );
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('capability state keeps partial installation and restart distinct', () {
    List<Map<String, dynamic>> states(List<String> values) => [
      for (final value in values) {'State': value},
    ];
    expect(
      capabilityInstallStatus(states(['Installed', 'Installed']), false),
      'installed',
    );
    expect(
      capabilityInstallStatus(states(['Installed', 'Installed']), true),
      'restart_required',
    );
    expect(
      capabilityInstallStatus(states(['Installed', 'InstallPending']), false),
      'restart_required',
    );
    expect(
      capabilityInstallStatus(states(['Installed', 'NotPresent']), false),
      'incomplete',
    );
    expect(
      capabilityInstallStatus(
        states(['PartiallyInstalled', 'InstallPending']),
        true,
      ),
      'incomplete',
    );
    expect(capabilityInstallStatus([], false), 'incomplete');
  });

  test('Sandbox folder paths are escaped for XML', () {
    expect(xml('C:\\a&b<"x">'), 'C:\\a&amp;b&lt;&quot;x&quot;&gt;');
  });

  test(
    'packaged verifier replaces stale success when a file was changed',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'package-tamper-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final report = File('${directory.path}/verification.json');
      await report.writeAsString('{"passed":true}');
      await File('${directory.path}/manifest.json').writeAsString(
        jsonEncode({
          'files': [
            {'name': 'README.txt', 'sha256': 'invalid'},
          ],
          'executable': 'app.exe',
        }),
      );
      await File('${directory.path}/README.txt').writeAsString('changed');
      final result = await Process.run(dartExecutable, [
        'run',
        'tool/windows/verify.dart',
        '--package=${directory.path}',
      ]);
      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      final verification = jsonDecode(await report.readAsString()) as Map;
      expect(verification['passed'], isFalse);
      expect(
        verification['error'],
        contains('Package hash mismatch: README.txt'),
      );
    },
    skip: !Platform.isWindows,
  );
}
