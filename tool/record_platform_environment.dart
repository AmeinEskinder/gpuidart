import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Usage: record_platform_environment.dart OUTPUT');
  }
  final commands = <List<String>>[
    ['git', 'rev-parse', 'HEAD'],
    ['rustc', '--version'],
    ['cargo', '--version'],
    ['uname', '-a'],
    if (Platform.isMacOS) ...[
      ['sw_vers'],
      ['xcodebuild', '-version'],
      ['xcrun', '--find', 'metal'],
      ['sysctl', 'hw.model', 'hw.machine', 'hw.physicalcpu', 'hw.memsize'],
      ['swift', 'tool/platform_probe/metal.swift'],
    ] else ...[
      ['cat', '/etc/os-release'],
      ['ldd', '--version'],
      ['lscpu'],
      ['vulkaninfo', '--summary'],
      ['xdpyinfo'],
    ],
  ];
  final results = <Map<String, Object>>[];
  for (final command in commands) {
    try {
      final result = await Process.run(
        command.first,
        command.skip(1).toList(),
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
