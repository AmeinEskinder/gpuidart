import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'common.dart';

Future<void> main(List<String> arguments) async {
  final args = options(arguments, {'report', 'environment', 'package'});
  final environment = args['environment'] ?? 'development_machine';
  if (![
    'development_machine',
    'clean_vm',
    'clean_machine',
  ].contains(environment)) {
    throw ArgumentError('Invalid environment: $environment');
  }
  final directory = Directory(
    args['package'] ?? File(Platform.resolvedExecutable).parent.path,
  ).absolute;
  final reportPath = args['report'] ?? '${directory.path}/verification.json';
  final report = <String, dynamic>{
    'tested_at_utc': timestamp(),
    'passed': false,
    'environment_declared_by_operator': environment,
    'package_path': directory.path,
  };
  await writeJson(reportPath, report);
  Process? process;
  Future<String>? output;
  Future<String>? errors;
  try {
    if (!Platform.isWindows) {
      throw UnsupportedError('This verifier requires Windows');
    }
    final manifest = await readJson('${directory.path}/manifest.json');
    for (final entry in manifest['files'] as List) {
      final name = entry['name'] as String;
      if (name.contains('..') ||
          name.contains('/') ||
          name.contains('\\') ||
          name.contains(':')) {
        throw StateError('Invalid package filename: $name');
      }
      final file = File('${directory.path}/$name');
      if (!await file.exists() || await fileHash(file) != entry['sha256']) {
        throw StateError('Package hash mismatch: $name');
      }
    }
    final executable = manifest['executable'] as String;
    if (!RegExp(r'^[a-zA-Z0-9_-]+\.exe$').hasMatch(executable)) {
      throw StateError('Invalid package executable: $executable');
    }
    final helper = '${directory.path}/gpuidart-windows-tool.exe';
    Future<Map<String, dynamic>> query(List<String> arguments) async {
      final result = await runTimed(helper, arguments);
      if (result.exitCode != 0) throw StateError('${result.stderr}');
      return jsonDecode('${result.stdout}') as Map<String, dynamic>;
    }

    final systemRoot = Platform.environment['SystemRoot']!;
    final childEnvironment = {...Platform.environment}
      ..removeWhere(
        (key, _) => RegExp(
          r'^(DART|FLUTTER|GPUIDART|CARGO|RUSTUP)',
          caseSensitive: false,
        ).hasMatch(key),
      )
      ..removeWhere((key, _) => key.toUpperCase() == 'PATH');
    childEnvironment['PATH'] = '$systemRoot\\System32;$systemRoot';
    process = await Process.start(
      '${directory.path}/$executable',
      ['--self-test'],
      workingDirectory: systemRoot,
      environment: childEnvironment,
      includeParentEnvironment: false,
    );
    output = process.stdout.transform(utf8.decoder).join();
    errors = process.stderr.transform(utf8.decoder).join();
    // Install error handlers immediately; strict UTF-8 errors are rethrown below.
    unawaited(output.catchError((Object _) => ''));
    unawaited(errors.catchError((Object _) => ''));
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var observation = <String, dynamic>{};
    while (!exited && DateTime.now().isBefore(deadline)) {
      try {
        observation = await query(['inspect-process', '${process.pid}']);
      } catch (_) {
        if (exited) break;
        rethrow;
      }
      final modules = (observation['loaded_modules'] as List).cast<String>();
      if (observation['window_dpi'] != 0 && modules.any(commonControls)) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final code = await process.exitCode.timeout(const Duration(seconds: 30));
    final stdoutText = await output;
    final stderrText = await errors;
    report['stderr'] = stderrText;
    if (code != 0) {
      throw StateError('Packaged self-test failed: $stderrText $stdoutText');
    }
    if (observation['per_monitor_v2'] != true ||
        observation['window_dpi'] == 0) {
      throw StateError('Window did not report PerMonitorV2 DPI awareness');
    }
    final modules = (observation['loaded_modules'] as List).cast<String>();
    for (final name in ['gpuidart.dll', 'vcruntime140.dll']) {
      final sibling = File('${directory.path}/$name').absolute.path
          .replaceAll('/', '\\')
          .toLowerCase();
      if (!modules.any((path) => path.toLowerCase() == sibling)) {
        throw StateError('Sibling $name was not loaded');
      }
    }
    if (!modules.any(commonControls)) {
      throw StateError('Common Controls v6 was not loaded');
    }
    if (modules.any(
      (path) => RegExp(
        r'\\(dart-sdk|flutter)\\',
        caseSensitive: false,
      ).hasMatch(path),
    )) {
      throw StateError('An SDK module was loaded');
    }
    final application = jsonDecode(stdoutText.trim());
    report['application'] = application;
    if (application is! Map ||
        application['mode'] != 'aot' ||
        application['passed'] != true) {
      throw StateError(
        'Application self-test must report mode aot and boolean passed true',
      );
    }
    report.addAll({
      'passed': true,
      'os': await query(['os']),
      'working_directory': systemRoot,
      'path': childEnvironment['PATH'],
      ...observation,
      'build': manifest['build'],
      'native_abi': manifest['native_abi'],
      'files': manifest['files'],
      'limitation': 'Machine cleanliness requires an independently provisioned machine or VM; this verifier checks launch, application checks, loaded modules and DPI.',
    });
    stdout.writeln(
      'PASS: packaged self-test, sibling DLLs, Common Controls v6 and PerMonitorV2 at DPI ${observation['window_dpi']}. Report: $reportPath',
    );
  } catch (error) {
    report['error'] = '$error';
    report['passed'] = false;
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    process?.kill();
    if (process != null) await process.exitCode;
    await writeJson(reportPath, report);
  }
}

bool commonControls(String path) => RegExp(
  r'\\WinSxS\\.*\\comctl32\.dll$',
  caseSensitive: false,
).hasMatch(path);
