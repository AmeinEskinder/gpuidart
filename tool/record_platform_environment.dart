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
    if (!Platform.isWindows) ['uname', '-a'],
    if (Platform.isWindows) ...[
      [
        'powershell.exe',
        '-NoProfile',
        '-Command',
        'Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,TotalVisibleMemorySize | ConvertTo-Json',
      ],
      [
        'powershell.exe',
        '-NoProfile',
        '-Command',
        'Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors | ConvertTo-Json',
      ],
      [
        'powershell.exe',
        '-NoProfile',
        '-Command',
        'Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution | ConvertTo-Json',
      ],
    ] else if (Platform.isMacOS) ...[
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
