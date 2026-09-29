import 'dart:io';

import 'src/toolchain.dart';
import 'src/windows_tool.dart';
import 'windows/capability_state.dart';
import 'windows/common.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final pending = await readJson(
    'reports/mvp/prerequisites/japanese-install-pending.json',
  );
  final step = (pending['steps'] as List).firstWhere(
    (step) => step['name'] == 'Japanese',
  ) as Map;
  require(
    capabilityInstallStatus(
          (step['capabilities_after'] as List).cast<Map<String, dynamic>>(),
          step['restart_needed'] == true,
        ) ==
        'restart_required',
    'The recorded staged Japanese installation must be awaiting restart.',
  );
  final parent = await Directory('.cache').create(recursive: true);
  final directory = await parent.createTemp('prerequisite-check-');
  try {
    final path = '${directory.path}/inspection.json';
    await File(path).writeAsString(
      '{"passed":false,"error":"preserve the earlier installation failure"}',
    );
    final previousHash = await fileHash(File(path));
    final installed = File('build/windows-prerequisites.json');
    final before = await installed.exists() ? await fileHash(installed) : null;
    Future<Map<String, dynamic>> inspect(
      String reportPath, {
      required bool sandbox,
    }) async {
      final result = await runTimed(dartExecutable, [
        'run',
        'tool/windows/enable_release_checks.dart',
        '--japanese',
        '--check-only',
        if (sandbox) '--sandbox',
        '--report=$reportPath',
      ]);
      require(
        result.exitCode == 0,
        'Read-only prerequisite inspection failed: ${result.stderr}',
      );
      final report = await readJson(reportPath);
      require(
        report['mode'] == 'inspection' &&
            report['passed'] == null &&
            (report['steps'] as List).isEmpty,
        'Inspection must not claim an installation pass or run installation steps.',
      );
      return report;
    }

    final report = await inspect(path, sandbox: true);
    require(
      await fileHash(File(report['previous_report'] as String)) == previousHash,
      'The previous failure report was not preserved byte-for-byte.',
    );
    final environment =
        await windowsQuery(['setup-environment']) as Map<String, dynamic>;
    require(
      (report['environment_before'] as Map).keys.toSet().difference({
        'restart_pending',
        'restart_reasons',
        'network',
      }).isEmpty,
      'Setup inspection must not require firmware, OS branding or installed-language inventory.',
    );
    final restart = environment['restart_pending'] == true;
    require(
      report['restart_needed'] == restart &&
          (!restart || '${report['blockers']}'.contains('Restart Windows')),
      'Pending Windows servicing was not reported as requiring restart.',
    );
    final network = environment['network'] as Map;
    if (network['cost'] != 'Unrestricted' ||
        network['roaming'] == true ||
        network['over_data_limit'] == true) {
      require(
        '${report['blockers']}'.contains('network cost'),
        'Metered network was not reported before installation.',
      );
    }
    final after = await installed.exists() ? await fileHash(installed) : null;
    require(before == after, 'Inspection changed the installation report.');
    final japanese = await inspect(
      '${directory.path}/japanese-inspection.json',
      sandbox: false,
    );
    require(
      !RegExp(
        'restart|servicing',
        caseSensitive: false,
      ).hasMatch('${japanese['blockers']}'),
      'An unrelated pending restart must not preempt the Japanese-only DISM attempt.',
    );
    require(
      !restart ||
          (japanese['restart_needed'] == true &&
              '${japanese['notes']}'.contains('restart')),
      'Japanese-only inspection must retain and explain the pending Windows restart.',
    );
    await writeJson('reports/mvp/prerequisites/inspection-check.json', {
      'tested_at_utc': timestamp(),
      'passed': true,
      'scope': 'Read-only setup inspection and report preservation; no Windows installation or release-gate pass',
      'inspection': report,
      'japanese_only_inspection': japanese,
      'capability_states': 'Recorded InstallPending classified as restart_required; all states covered by windows_preparation_test.dart',
    });
    stdout.writeln(
      'PASS: restart/network inspection, preserved failure report, no installation result claimed.',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}
