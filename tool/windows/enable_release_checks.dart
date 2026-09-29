import 'dart:io';

import '../src/windows_tool.dart';
import 'capability_state.dart';
import 'common.dart';

const japaneseCapabilities = [
  'Language.Basic~~~ja-JP~0.0.1.0',
  'Language.Fonts.Jpan~~~und-JPAN~0.0.1.0',
];

void requireDownload(Map<String, dynamic> environment) {
  final network = environment['network'] as Map;
  if (network['cost'] != 'Unrestricted' ||
      network['roaming'] == true ||
      network['over_data_limit'] == true) {
    throw StateError(
      'Windows download is blocked by this setup check: network cost is ${network['cost']}. Use an unmetered connection, or turn off Metered connection if you accept the data usage. No network settings were changed.',
    );
  }
}

Future<ProcessResult> dism(List<String> arguments) async {
  final result = await runTimed(
    '${Platform.environment['SystemRoot']}\\System32\\dism.exe',
    ['/English', '/Online', ...arguments],
    timeout: const Duration(hours: 1),
  );
  if (![0, 3010].contains(result.exitCode)) {
    throw StateError(
      'DISM failed (${result.exitCode}): ${result.stdout}\n${result.stderr}',
    );
  }
  return result;
}

String dismState(String output) {
  final value = RegExp(
    r'^State\s*:\s*(.+)$',
    multiLine: true,
  ).firstMatch(output)?[1]?.trim();
  if (value == null) throw StateError('DISM did not report a state: $output');
  return value.replaceAll(' ', '');
}

Future<List<Map<String, dynamic>>> capabilities() async => [
  for (final name in japaneseCapabilities)
    {
      'Name': name,
      'State': dismState(
        '${(await dism(['/Get-CapabilityInfo', '/CapabilityName:$name'])).stdout}',
      ),
    },
];

Future<void> main(List<String> arguments) async {
  final args = options(
    arguments,
    {'sandbox', 'japanese', 'check-only', 'report'},
    flags: {'sandbox', 'japanese', 'check-only'},
  );
  final sandbox = args.containsKey('sandbox');
  final japanese = args.containsKey('japanese');
  final inspect = args.containsKey('check-only');
  if (!sandbox && !japanese) {
    throw ArgumentError(
      'Specify --sandbox, --japanese, or both. No settings have changed.',
    );
  }
  final reportPath = File(
    args['report'] ??
        'build/windows-prerequisites${inspect ? '.inspection' : ''}.json',
  ).absolute.path;
  final before =
      await windowsQuery(['setup-environment']) as Map<String, dynamic>;
  final report = <String, dynamic>{
    'started_at_utc': timestamp(),
    'passed': inspect ? null : false,
    'steps': <Map<String, dynamic>>[],
    'mode': inspect ? 'inspection' : 'install',
    'environment_before': before,
    'restart_needed': before['restart_pending'],
  };
  if (await File(reportPath).exists()) {
    final previous =
        '$reportPath.${DateTime.now().microsecondsSinceEpoch}.json';
    await File(reportPath).copy(previous);
    report['previous_report'] = previous;
  }
  await writeJson(reportPath, report);
  if (inspect) {
    final blockers = <String>[];
    final notes = <String>[];
    if (before['restart_pending'] == true) {
      if (sandbox) {
        blockers.add(
          'Restart Windows to complete pending servicing before Sandbox setup.',
        );
      }
      if (japanese) {
        notes.add(
          'A Windows restart is pending. A Japanese-only installation can ask DISM whether the requested capabilities can be installed now; this inspection cannot establish that outcome.',
        );
      }
    }
    if (japanese) {
      try {
        requireDownload(before);
      } catch (error) {
        blockers.add('$error');
      }
    }
    report.addAll({
      'blockers': blockers,
      'notes': notes,
      'finished_at_utc': timestamp(),
    });
    await writeJson(reportPath, report);
    for (final message in [...blockers, ...notes]) {
      stdout.writeln(message);
    }
    stdout.writeln(
      'Inspection only; no installation attempted. Saved $reportPath',
    );
    return;
  }
  for (final name in [if (sandbox) 'Sandbox', if (japanese) 'Japanese']) {
    final step = <String, dynamic>{
      'name': name,
      'passed': false,
      'status': 'failed',
    };
    try {
      final environment =
          await windowsQuery(['setup-environment']) as Map<String, dynamic>;
      if (name == 'Sandbox') {
        if (environment['restart_pending'] == true ||
            report['restart_needed'] == true) {
          throw StateError(
            'Windows has pending servicing. Restart Windows before Sandbox setup, or use --japanese alone to attempt the independent language installation. Sandbox installation was not attempted.',
          );
        }
        Future<String> state() async => dismState(
          '${(await dism(['/Get-FeatureInfo', '/FeatureName:Containers-DisposableClientVM'])).stdout}',
        );
        final previous = await state();
        step['previous_state'] = previous;
        step['restart_needed'] = previous == 'EnablePending';
        if (!['Enabled', 'EnablePending'].contains(previous)) {
          final enabled = await dism([
            '/Enable-Feature',
            '/FeatureName:Containers-DisposableClientVM',
            '/All',
            '/NoRestart',
          ]);
          step['restart_needed'] = enabled.exitCode == 3010;
        }
        step['state'] = await state();
        if (!['Enabled', 'EnablePending'].contains(step['state'])) {
          throw StateError('Sandbox feature state is ${step['state']}');
        }
        step['restart_needed'] =
            step['restart_needed'] == true || step['state'] == 'EnablePending';
        step['status'] = step['restart_needed'] == true
            ? 'restart_required'
            : 'installed';
      } else {
        step['capabilities_before'] = await capabilities();
        step['restart_needed'] = false;
        for (final capability in step['capabilities_before'] as List) {
          if (capability['State'] == 'Installed') continue;
          if (capability['State'] == 'InstallPending') {
            step['restart_needed'] = true;
            break;
          }
          requireDownload(
            await windowsQuery(['setup-environment']) as Map<String, dynamic>,
          );
          stdout.writeln(
            'Installing ${capability['Name']}. Windows Update may take several minutes.',
          );
          final installed = await dism([
            '/Add-Capability',
            '/CapabilityName:${capability['Name']}',
            '/NoRestart',
          ]);
          if (installed.exitCode == 3010) {
            step['restart_needed'] = true;
            break;
          }
        }
        final after = await capabilities();
        step['capabilities_after'] = after;
        step['status'] = capabilityInstallStatus(
          after,
          step['restart_needed'] == true,
        );
        if (step['status'] == 'restart_required') step['restart_needed'] = true;
        if (step['status'] == 'incomplete') {
          throw StateError(
            'Japanese typing or fonts are not installed yet. See capability states in the report.',
          );
        }
        step['next_step'] = step['status'] == 'restart_required'
            ? 'Windows staged installation and requires a restart. Rerun --japanese after restarting to finish remaining capabilities.'
            : 'Add Japanese in Settings > Time & language > Language & region. Windows display language is unchanged.';
      }
      step['passed'] = step['status'] == 'installed';
    } catch (error) {
      step['status'] = 'failed';
      step['error'] = '$error';
      if (name == 'Japanese' && step.containsKey('capabilities_before')) {
        try {
          step['capabilities_after'] = await capabilities();
        } catch (inspectionError) {
          step['inspection_error'] = '$inspectionError';
        }
      }
      if ('$error'.contains('800f0908') || '$error'.contains('-2146498296')) {
        step['next_step'] = 'Windows refused a metered-network download. Use an unmetered connection before retrying.';
      }
      stderr.writeln('$name failed: $error');
    }
    if (step['restart_needed'] == true) report['restart_needed'] = true;
    (report['steps'] as List).add(step);
    await writeJson(reportPath, report);
  }
  final after =
      await windowsQuery(['setup-environment']) as Map<String, dynamic>;
  final steps = (report['steps'] as List).cast<Map<String, dynamic>>();
  final failed = steps.any((step) => step['status'] == 'failed');
  report['environment_after'] = after;
  report['restart_needed'] =
      report['restart_needed'] == true || after['restart_pending'] == true;
  report['installation_passed'] = steps.every((step) => step['passed'] == true);
  report['passed'] =
      report['installation_passed'] == true && report['restart_needed'] != true;
  report['status'] = failed
      ? 'failed'
      : report['restart_needed'] == true
      ? 'restart_required'
      : 'installed';
  report['finished_at_utc'] = timestamp();
  await writeJson(reportPath, report);
  stdout.writeln('Saved $reportPath. No restart was initiated.');
  if (failed) exitCode = 1;
}
