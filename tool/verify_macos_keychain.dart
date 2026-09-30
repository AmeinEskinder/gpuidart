import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> args) async {
  if (!Platform.isMacOS || args.length > 1) {
    stderr.writeln(
      'Usage on macOS: dart run tool/verify_macos_keychain.dart [REPORT]',
    );
    exitCode = 64;
    return;
  }
  final destination = File(
    args.isEmpty ? 'build/package-evidence/keychain-lifecycle.json' : args[0],
  );
  final steps = <Map<String, Object>>[];
  final report = <String, Object>{
    'passed': false,
    'tested_at_utc': DateTime.now().toUtc().toIso8601String(),
    'os': Platform.operatingSystemVersion,
    'scope':
        'Temporary keychain creation/deletion only; no certificate, '
        'private key, signing identity, notarization credential or user '
        'credential is imported; no command explicitly sets user keychain settings.',
    'steps': steps,
  };

  Future<ProcessResult> run(
    String label,
    List<String> arguments, {
    bool snapshot = false,
  }) async {
    // Do not log arguments or credential-command output: create-keychain
    // receives the random disposable password through its argument vector.
    ProcessResult result;
    try {
      result = await Process.run('/usr/bin/security', arguments);
    } on ProcessException {
      throw StateError('$label could not start');
    }
    steps.add({
      'step': label,
      'exit_code': result.exitCode,
      if (snapshot) 'stdout': '${result.stdout}',
      if (snapshot) 'stderr': '${result.stderr}',
    });
    if (result.exitCode != 0) {
      throw StateError('$label failed with exit code ${result.exitCode}');
    }
    return result;
  }

  Future<Map<String, String>> snapshot(String label) async => {
    'search_list':
        '${(await run('$label search list', ['list-keychains', '-d', 'user'], snapshot: true)).stdout}',
    'default_keychain':
        '${(await run('$label default keychain', ['default-keychain', '-d', 'user'], snapshot: true)).stdout}',
  };

  bool same(Map<String, String> left, Map<String, String> right) =>
      left['search_list'] == right['search_list'] &&
      left['default_keychain'] == right['default_keychain'];

  Directory? temporary;
  String? keychain;
  Map<String, String>? before;
  var afterCreateUnchanged = false;
  var afterDeleteUnchanged = false;
  var cleanupPassed = true;
  try {
    before = await snapshot('before');
    report['before'] = before;
    temporary = await Directory.systemTemp.createTemp(
      'gpuidart-keychain-probe-',
    );
    keychain = '${temporary.path}/release.keychain-db';
    final random = Random.secure();
    final password = base64Url.encode(
      List.generate(32, (_) => random.nextInt(256)),
    );
    await run('create isolated keychain', [
      'create-keychain',
      '-p',
      password,
      keychain,
    ]);
    final keychainExists = File(keychain).existsSync();
    report['created_keychain_exists'] = keychainExists;
    if (!keychainExists) {
      throw StateError('Created keychain does not exist at its requested path');
    }
    final afterCreate = await snapshot('after create');
    report['after_create'] = afterCreate;
    afterCreateUnchanged = same(before, afterCreate);
    report['unchanged_after_create'] = afterCreateUnchanged;
  } catch (error) {
    report['error'] = '$error';
  } finally {
    if (keychain != null && File(keychain).existsSync()) {
      try {
        await run('delete isolated keychain', ['delete-keychain', keychain]);
      } catch (error) {
        cleanupPassed = false;
        report['delete_error'] = '$error';
      }
    }
    if (temporary != null) {
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException {
        cleanupPassed = false;
        report['cleanup_error'] = 'Could not remove owned temporary directory';
      }
    }
    if (before != null) {
      try {
        final afterDelete = await snapshot('after delete');
        report['after_delete'] = afterDelete;
        afterDeleteUnchanged = same(before, afterDelete);
        report['unchanged_after_delete'] = afterDeleteUnchanged;
      } catch (error) {
        report['final_snapshot_error'] = '$error';
      }
    }
    final passed =
        afterCreateUnchanged && afterDeleteUnchanged && cleanupPassed;
    report['passed'] = passed;
    await destination.parent.create(recursive: true);
    await destination.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    stdout.writeln(
      '${passed ? 'PASS' : 'FAIL'}: temporary keychain lifecycle; '
      'report ${destination.path}',
    );
    if (!passed) exitCode = 1;
  }
}
