import 'dart:io';

import 'src/commands.dart';
import 'src/toolchain.dart';
import 'windows/common.dart';

Future<void> main(List<String> arguments) async {
  final name = options(arguments, {'name'})['name'] ?? 'WatchlistMvp';
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) {
    throw ArgumentError('Invalid application name');
  }
  final status = await command('git', [
    'status',
    '--porcelain',
    '--untracked-files=normal',
    '--',
    'bin',
    'lib',
    'native',
    'example',
    'tool',
    'test',
    'pubspec.yaml',
    'pubspec.lock',
    'Cargo.toml',
    'Cargo.lock',
    'rust-toolchain.toml',
  ]);
  if (status.isNotEmpty) {
    throw StateError(
      'Commit the MVP source and test changes before running release acceptance.',
    );
  }
  final commit = await command('git', ['rev-parse', 'HEAD']);
  const path = 'reports/mvp/acceptance.json';
  final checks = <Map<String, dynamic>>[];
  final report = <String, dynamic>{
    'started_at_utc': timestamp(),
    'source_commit': commit,
    'local_acceptance_passed': false,
    'release_status': 'candidate_pending_external_checks',
    'external_checks': {
      'clean_windows_launch': 'pending',
      'human_ime': 'pending',
      'mixed_monitor_dpi': 'pending',
    },
    'checks': checks,
  };
  await writeJson(path, report);
  final commands = <String, List<String>>{
    'native-and-dart': ['tool/check.dart'],
    'watchlist-ui': ['tool/verify_watchlist_ui.dart'],
    'watchlist-stability': ['tool/verify_watchlist_stability.dart'],
    'code-reload': ['tool/verify_watchlist_reload.dart'],
    'development-launcher': ['tool/verify_dev_launcher.dart'],
    'development-failures': ['tool/verify_dev_failures.dart'],
    'aot-package': ['tool/package.dart', '--name=$name'],
    'aot-launch': [
      'tool/verify_package.dart',
      'build/$name-windows-x64.zip',
      'reports/mvp/package.json',
    ],
    'package-failures': [
      'tool/verify_package_failures.dart',
      '--zip=build/$name-windows-x64.zip',
    ],
  };
  try {
    for (final entry in commands.entries) {
      stdout.writeln('Starting ${entry.key}');
      final timer = Stopwatch()..start();
      final result = await runTimed(dartExecutable, [
        'run',
        ...entry.value,
      ], timeout: const Duration(minutes: 15));
      await File('reports/mvp/${entry.key}.stdout.log')
          .writeAsString('${result.stdout}');
      await File('reports/mvp/${entry.key}.stderr.log')
          .writeAsString('${result.stderr}');
      checks.add({
        'name': entry.key,
        'exit_code': result.exitCode,
        'elapsed_ms': timer.elapsedMilliseconds,
      });
      await writeJson(path, report);
      if (result.exitCode != 0) {
        throw StateError(
          '${entry.key} failed. See reports/mvp/${entry.key}.stderr.log and stdout.log',
        );
      }
      stdout.writeln('Passed ${entry.key}');
    }
    // The verifier records the exact manifest from the generated package.
    final verification = await readJson('reports/mvp/package.json');
    final build = verification['build'] as Map;
    if (build['source_dirty'] != false || build['git_commit'] != commit) {
      throw StateError(
        'Package source identity does not match the committed acceptance source.',
      );
    }
    final archive = File('build/$name-windows-x64.zip');
    report['package'] = {
      'path': archive.path,
      'bytes': await archive.length(),
      'sha256': await fileHash(archive),
      'source_sha256': build['source_sha256'],
      'native_abi': verification['native_abi'],
    };
    report['local_acceptance_passed'] = true;
    stdout.writeln(
      'PASS: local MVP acceptance. Clean Windows, human IME and mixed-monitor checks remain pending. Report: $path',
    );
  } catch (error) {
    report['error'] = '$error';
    rethrow;
  } finally {
    report['finished_at_utc'] = timestamp();
    await writeJson(path, report);
  }
}
