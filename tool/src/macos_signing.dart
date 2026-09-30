import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

typedef MacosSigningRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

final class MacosSigning {
  MacosSigning._(this.identity, this.notaryProfile, this.keychain, this._run);

  factory MacosSigning.fromOptions({
    String? identity,
    String? notaryProfile,
    String? keychain,
    MacosSigningRunner? runner,
  }) {
    for (final option in [identity, notaryProfile, keychain]) {
      if (option != null && option.trim().isEmpty) {
        throw ArgumentError('macOS signing options must not be empty');
      }
    }
    final distribution = identity != null || notaryProfile != null;
    if ((distribution && (identity == null || notaryProfile == null)) ||
        (!distribution && keychain != null)) {
      throw ArgumentError(
        'Supply both --signing-identity and --notary-profile; '
        '--signing-keychain is optional',
      );
    }
    if (identity != null &&
        !identity.startsWith('Developer ID Application: ') &&
        !RegExp(r'^[0-9A-Fa-f]{40}$').hasMatch(identity)) {
      throw ArgumentError(
        '--signing-identity must be a Developer ID Application name or SHA-1 fingerprint',
      );
    }
    return MacosSigning._(
      identity,
      notaryProfile,
      keychain,
      runner ?? ((executable, arguments) => Process.run(executable, arguments)),
    );
  }

  static const _developerIdRequirement =
      'anchor apple generic and '
      'certificate 1[field.1.2.840.113635.100.6.2.6] exists and '
      'certificate leaf[field.1.2.840.113635.100.6.1.13] exists';

  final String? identity, notaryProfile, keychain;
  final MacosSigningRunner _run;
  bool get isDistribution => identity != null;

  Future<void> sign({
    required Directory stage,
    required Directory app,
    required List<File> binaries,
  }) async {
    _inside(stage, app.path);
    for (final binary in binaries) {
      _inside(stage, binary.path);
    }
    final evidence = <String, Object?>{
      'mode': isDistribution ? 'developer-id' : 'ad-hoc',
      'status': 'in-progress',
      'commands': <Map<String, Object?>>[],
    };
    final report = File(p.join(stage.path, 'macos-signing.json'));
    try {
      final options = [
        '--force',
        '--sign',
        identity ?? '-',
        if (isDistribution) ...['--options', 'runtime', '--timestamp'],
        if (keychain != null) ...['--keychain', keychain!],
      ];
      for (final binary in binaries) {
        if (!isDistribution &&
            !p.isWithin(app.absolute.path, binary.absolute.path)) {
          continue;
        }
        _requireSuccess(
          await _record(report, evidence, '/usr/bin/codesign', [
            ...options,
            binary.path,
          ]),
        );
      }
      _requireSuccess(
        await _record(report, evidence, '/usr/bin/codesign', [
          ...options,
          app.path,
        ]),
      );
      if (isDistribution) {
        for (final binary in binaries) {
          _requireSuccess(
            await _record(report, evidence, '/usr/bin/codesign', [
              '--verify',
              '--strict',
              '-R=$_developerIdRequirement',
              binary.path,
            ]),
          );
        }
      }
      _requireSuccess(
        await _record(report, evidence, '/usr/bin/codesign', [
          '--verify',
          '--deep',
          '--strict',
          if (isDistribution) '-R=$_developerIdRequirement',
          app.path,
        ]),
      );
      _requireSuccess(
        await _record(report, evidence, '/usr/bin/codesign', [
          '--display',
          '--verbose=4',
          app.path,
        ]),
      );
      evidence['status'] = 'verified';
      await _save(report, evidence);
    } catch (error) {
      evidence['status'] = 'failed';
      evidence['error'] = error.toString();
      await _save(report, evidence);
      rethrow;
    }
  }

  Future<Map<String, Object?>> notarize({
    required Directory stage,
    required Directory app,
  }) async {
    if (!isDistribution) return {};
    _inside(stage, app.path);
    final evidence = <String, Object?>{
      'status': 'in-progress',
      'notarized': false,
      'commands': <Map<String, Object?>>[],
      'stapled_app': p.relative(app.path, from: stage.path),
      'standalone_binaries': 'Submitted to Apple; standalone binaries cannot carry stapled tickets',
    };
    final report = File(p.join(stage.path, 'macos-notarization.json'));
    final developerLog = File(p.join(stage.path, 'macos-notary-log.json'));
    final credentials = [
      '--keychain-profile',
      notaryProfile!,
      if (keychain != null) ...['--keychain', keychain!],
    ];
    final temporary = await Directory.systemTemp.createTemp('gpuidart-notary-');
    try {
      final zip = p.join(temporary.path, 'submission.zip');
      _requireSuccess(
        await _record(report, evidence, '/usr/bin/ditto', [
          '-c',
          '-k',
          '--keepParent',
          stage.absolute.path,
          zip,
        ]),
      );
      final archive = File(zip);
      evidence['submitted_archive'] = {
        'bytes': await archive.length(),
        'sha256': (await sha256.bind(archive.openRead()).first).toString(),
      };
      await _save(report, evidence);
      final submitted = await _record(report, evidence, '/usr/bin/xcrun', [
        'notarytool',
        'submit',
        zip,
        ...credentials,
        '--wait',
        '--output-format',
        'json',
      ]);
      final response = jsonDecode(submitted.stdout as String);
      if (response is! Map ||
          response['id'] is! String ||
          response['status'] is! String) {
        throw StateError(
          'Notary response lacks submission ID or status; see ${report.path}',
        );
      }
      final id = response['id'] as String;
      if (id.isEmpty) {
        throw StateError('Notary response has an empty submission ID');
      }
      evidence['submission_id'] = id;
      evidence['apple_status'] = response['status'];
      await _save(report, evidence);
      final log = await _record(report, evidence, '/usr/bin/xcrun', [
        'notarytool',
        'log',
        id,
        ...credentials,
        developerLog.path,
      ]);
      _requireSuccess(log);
      if (!developerLog.existsSync() || developerLog.lengthSync() == 0) {
        throw StateError('Apple notarization log was not retained');
      }
      final details = jsonDecode(await developerLog.readAsString());
      if (details is! Map ||
          details['status'] is! String ||
          details['jobId'] is! String) {
        throw StateError('Apple log lacks jobId or status');
      }
      final issues = details['issues'] ?? const <Object?>[];
      if (issues is! List || issues.any((issue) => issue is! Map)) {
        throw StateError('Apple log has malformed issues');
      }
      int count(String severity) => issues
          .where(
            (issue) =>
                (issue['severity'] as String?)?.toLowerCase() == severity,
          )
          .length;
      final errors = count('error');
      evidence['notary_log'] = {
        'job_id': details['jobId'],
        'status': details['status'],
        'issues': issues,
        'issue_count': issues.length,
        'warning_count': count('warning'),
        'error_count': errors,
      };
      await _save(report, evidence);
      _requireSuccess(submitted);
      if (response['status'] != 'Accepted' || details['status'] != 'Accepted') {
        throw StateError(
          'Apple notarization status is ${response['status']}, '
          'log status is ${details['status']}; see ${report.path}',
        );
      }
      if ((details['jobId'] as String).toLowerCase() != id.toLowerCase()) {
        throw StateError('Apple log jobId does not match the submission');
      }
      if (errors != 0) {
        throw StateError('Apple notarization log contains $errors errors');
      }
      _requireSuccess(
        await _record(report, evidence, '/usr/bin/xcrun', [
          'stapler',
          'staple',
          app.path,
        ]),
      );
      _requireSuccess(
        await _record(report, evidence, '/usr/bin/xcrun', [
          'stapler',
          'validate',
          app.path,
        ]),
      );
      _requireSuccess(
        await _record(report, evidence, '/usr/bin/codesign', [
          '--verify',
          '--verbose=4',
          '--check-notarization',
          '-R=notarized',
          p.join(stage.path, 'verify'),
        ]),
      );
      _requireSuccess(
        await _record(report, evidence, '/usr/bin/syspolicy_check', [
          'distribution',
          app.path,
        ]),
      );
      evidence['status'] = 'Accepted';
      evidence['stapled'] = true;
      evidence['standalone_ticket_verified'] = true;
      evidence['notarized'] = true;
      await _save(report, evidence);
      return evidence;
    } catch (error) {
      evidence['status'] = 'failed';
      evidence['error'] = error.toString();
      await _save(report, evidence);
      rethrow;
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<ProcessResult> _record(
    File report,
    Map<String, Object?> evidence,
    String executable,
    List<String> arguments,
  ) async {
    final record = <String, Object?>{
      'executable': executable,
      'arguments': arguments,
    };
    (evidence['commands'] as List<Map<String, Object?>>).add(record);
    try {
      final result = await _run(executable, arguments);
      record.addAll({
        'exit_code': result.exitCode,
        'stdout': result.stdout,
        'stderr': result.stderr,
      });
      await _save(report, evidence);
      return result;
    } catch (error) {
      record['error'] = error.toString();
      await _save(report, evidence);
      rethrow;
    }
  }

  static void _inside(Directory stage, String path) {
    if (!p.isWithin(stage.absolute.path, File(path).absolute.path)) {
      throw ArgumentError(
        'Signing target must be inside its staging directory: $path',
      );
    }
  }

  static void _requireSuccess(ProcessResult result) {
    if (result.exitCode != 0) {
      throw StateError(
        'Apple tool exited ${result.exitCode}: ${result.stderr}',
      );
    }
  }

  static Future<void> _save(File file, Map<String, Object?> value) => file
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(value)}\n');
}
