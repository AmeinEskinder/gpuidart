import 'dart:convert';
import 'dart:io';

import 'native_probe/client.dart';
import 'src/toolchain.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Usage: record_platform_environment.dart OUTPUT');
  }
  final commands = <List<String>>[
    ['git', 'rev-parse', 'HEAD'],
    ['rustc', '--version'],
    ['cargo', '--version'],
    if (!Platform.isWindows) ['uname', '-a'],
    if (Platform.isWindows) ...[
      ['gpuidart-native-probe', 'environment'],
    ] else if (Platform.isMacOS) ...[
      ['sw_vers'],
      ['xcodebuild', '-version'],
      ['xcrun', '--find', 'metal'],
      ['sysctl', 'hw.model', 'hw.machine', 'hw.physicalcpu', 'hw.memsize'],
      ['gpuidart-native-probe', 'metal'],
    ] else ...[
      ['cat', '/etc/os-release'],
      ['ldd', '--version'],
      ['lscpu'],
      ['vulkaninfo', '--summary'],
      ['xdpyinfo'],
    ],
  ];
  final results = <Map<String, Object>>[];
  final environment = toolchainEnvironment();
  for (final command in commands) {
    try {
      final result = await Process.run(
        command.first == 'gpuidart-native-probe'
            ? await nativeProbe()
            : toolExecutable(command.first, environment),
        command.skip(1).toList(),
        environment: environment,
        includeParentEnvironment: false,
      ).timeout(const Duration(seconds: 30));
      results.add({
        'command': command,
        'exit_code': result.exitCode,
        'stdout': '${result.stdout}',
        'stderr': '${result.stderr}',
      });
    } catch (error) {
      results.add({'command': command, 'error': '$error'});
    }
  }
  final output = File(args.single);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'recorded_at_utc': DateTime.now().toUtc().toIso8601String(),
      'dart': Platform.version,
      'display_environment': {
        for (final key in ['DISPLAY', 'WAYLAND_DISPLAY', 'XDG_SESSION_TYPE', 'XDG_CURRENT_DESKTOP', 'GDK_SCALE', 'GDK_DPI_SCALE', 'LIBGL_ALWAYS_SOFTWARE']) key: Platform.environment[key],
      },
      'commands': results,
      'scope': 'Runner/device enumeration. Does not establish physical GPU presentation or human interaction.',
    })}\n',
  );
}
