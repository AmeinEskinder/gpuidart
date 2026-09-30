import 'dart:convert';
import 'dart:io';
import 'dart:math';

const requiredMacosReleaseSecrets = [
  'MACOS_CERTIFICATE_P12_BASE64',
  'MACOS_CERTIFICATE_PASSWORD',
  'MACOS_SIGNING_IDENTITY',
  'APPLE_NOTARY_KEY_ID',
  'APPLE_NOTARY_ISSUER_ID',
  'APPLE_NOTARY_KEY_P8',
];

Future<void> main(List<String> args) async {
  final secrets = {
    for (final name in requiredMacosReleaseSecrets)
      name: Platform.environment[name] ?? '',
  };
  final missing = secrets.entries
      .where((entry) => entry.value.trim().isEmpty)
      .map((entry) => entry.key)
      .toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing required GitHub secrets: ${missing.join(', ')}');
    exitCode = 78;
    return;
  }
  if (args.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/macos_release.dart');
    exitCode = 64;
    return;
  }
  if (!Platform.isMacOS) {
    stderr.writeln('Developer ID release requires macOS.');
    exitCode = 64;
    return;
  }

  final environment = Map<String, String>.of(Platform.environment)
    ..removeWhere((name, _) => requiredMacosReleaseSecrets.contains(name));
  final redactions = secrets.values.toSet();
  String redact(String text) {
    final values = redactions.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final value in values) {
      if (value.isNotEmpty) text = text.replaceAll(value, '<redacted>');
    }
    return text;
  }

  Future<ProcessResult> run(
    String step,
    String executable,
    List<String> arguments, {
    bool showOutput = false,
  }) async {
    stdout.writeln(step);
    ProcessResult result;
    try {
      result = await Process.run(
        executable,
        arguments,
        environment: environment,
        includeParentEnvironment: false,
      );
    } on ProcessException {
      throw StateError('$step could not start.');
    }
    // Credential commands can echo inputs on failure. Never relay their output.
    if (showOutput) {
      stdout.write(redact('${result.stdout}'));
      stderr.write(redact('${result.stderr}'));
    }
    if (result.exitCode != 0) {
      throw StateError('$step failed with exit code ${result.exitCode}.');
    }
    return result;
  }

  Future<String> keychainSetting(String command) async =>
      '${(await run('Read keychain configuration', '/usr/bin/security', [command, '-d', 'user'])).stdout}';

  Directory? temporary;
  String? keychain;
  String? originalSearchList;
  String? originalDefault;
  try {
    List<int> certificate;
    try {
      certificate = base64Decode(
        secrets['MACOS_CERTIFICATE_P12_BASE64']!.replaceAll(RegExp(r'\s'), ''),
      );
    } on FormatException {
      throw StateError('MACOS_CERTIFICATE_P12_BASE64 is not valid base64.');
    }
    if (certificate.isEmpty ||
        !secrets['APPLE_NOTARY_KEY_P8']!.contains(
          '-----BEGIN PRIVATE KEY-----',
        )) {
      throw StateError(
        'The certificate or App Store Connect private key is invalid.',
      );
    }
    final cli = File('build/bin/gpuidart').absolute;
    if (!cli.existsSync()) {
      throw StateError(
        'Build the compiled CLI before running the release wrapper.',
      );
    }
    originalSearchList = await keychainSetting('list-keychains');
    originalDefault = await keychainSetting('default-keychain');
    temporary = await Directory.systemTemp.createTemp('gpuidart-signing-');
    await run('Restrict credential directory', '/bin/chmod', [
      '700',
      temporary.path,
    ]);
    final certificateFile = File('${temporary.path}/certificate.p12');
    final notaryKey = File('${temporary.path}/AuthKey.p8');
    for (final file in [certificateFile, notaryKey]) {
      await file.create();
      await run('Restrict credential file', '/bin/chmod', ['600', file.path]);
    }
    await certificateFile.writeAsBytes(certificate, flush: true);
    await notaryKey.writeAsString(secrets['APPLE_NOTARY_KEY_P8']!, flush: true);
    final random = Random.secure();
    final password = base64Url.encode(
      List.generate(32, (_) => random.nextInt(256)),
    );
    redactions.add(password);
    keychain = '${temporary.path}/release.keychain-db';
    await run('Create temporary signing keychain', '/usr/bin/security', [
      'create-keychain',
      '-p',
      password,
      keychain,
    ]);
    if (await keychainSetting('list-keychains') != originalSearchList ||
        await keychainSetting('default-keychain') != originalDefault) {
      throw StateError(
        'Temporary keychain unexpectedly changed user keychain configuration.',
      );
    }
    await run('Restrict signing keychain', '/bin/chmod', ['600', keychain]);
    await run('Set temporary keychain timeout', '/usr/bin/security', [
      'set-keychain-settings',
      '-lut',
      '21600',
      keychain,
    ]);
    await run('Unlock temporary signing keychain', '/usr/bin/security', [
      'unlock-keychain',
      '-p',
      password,
      keychain,
    ]);
    await run('Import Developer ID identity', '/usr/bin/security', [
      'import',
      certificateFile.path,
      '-k',
      keychain,
      '-f',
      'pkcs12',
      '-P',
      secrets['MACOS_CERTIFICATE_PASSWORD']!,
      '-T',
      '/usr/bin/codesign',
    ]);
    await run('Authorize Apple signing tools', '/usr/bin/security', [
      'set-key-partition-list',
      '-S',
      'apple-tool:,apple:',
      '-s',
      '-k',
      password,
      keychain,
    ]);
    final identities = await run(
      'Check Developer ID identity and trust chain',
      '/usr/bin/security',
      ['find-identity', '-v', '-p', 'codesigning', keychain],
    );
    final requestedIdentity = secrets['MACOS_SIGNING_IDENTITY']!.trim();
    final matches =
        RegExp(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"]+)"', multiLine: true)
            .allMatches('${identities.stdout}')
            .where(
              (match) =>
                  match[2]!.startsWith('Developer ID Application:') &&
                  (match[1]!.toLowerCase() == requestedIdentity.toLowerCase() ||
                      match[2] == requestedIdentity),
            )
            .toList();
    if (matches.length != 1) {
      throw StateError(
        'Expected one valid Developer ID Application identity in the temporary keychain. '
        'Use the full certificate name or SHA-1; export its private key and certificate chain, and check expiry.',
      );
    }
    final identity = matches.single[1]!;
    redactions.addAll([identity, matches.single[2]!]);
    await run(
      'Store notarization credentials in temporary keychain',
      '/usr/bin/xcrun',
      [
        'notarytool',
        'store-credentials',
        'gpuidart-release',
        '--key',
        notaryKey.path,
        '--key-id',
        secrets['APPLE_NOTARY_KEY_ID']!,
        '--issuer',
        secrets['APPLE_NOTARY_ISSUER_ID']!,
        '--keychain',
        keychain,
      ],
    );
    await certificateFile.delete();
    await notaryKey.delete();
    await run('Build, sign, and notarize macOS package', cli.path, [
      'package',
      '--name=Watchlist',
      '--signing-identity=$identity',
      '--notary-profile=gpuidart-release',
      '--signing-keychain=$keychain',
    ], showOutput: true);
    await run('Verify the delivered notarized package', cli.path, [
      'verify',
      'build/Watchlist-macos-arm64.tar.gz',
      'build/package-evidence/notarized-verification.json',
      '--require-notarized',
    ], showOutput: true);
    stdout.writeln('Notarized package build and verification passed.');
  } catch (error) {
    stderr.writeln(redact('$error'));
    exitCode = 1;
  } finally {
    if (keychain != null && File(keychain).existsSync()) {
      try {
        await run('Delete temporary signing keychain', '/usr/bin/security', [
          'delete-keychain',
          keychain,
        ]);
      } catch (_) {
        stderr.writeln(
          'Could not delete temporary keychain through Security; removing its isolated directory.',
        );
        exitCode = 1;
      }
    }
    if (temporary != null) {
      try {
        await temporary.delete(recursive: true);
      } catch (_) {
        stderr.writeln('Could not remove the temporary credential directory.');
        exitCode = 1;
      }
    }
    if (originalSearchList != null && originalDefault != null) {
      try {
        if (await keychainSetting('list-keychains') != originalSearchList ||
            await keychainSetting('default-keychain') != originalDefault) {
          stderr.writeln(
            'User keychain configuration differs from its initial state.',
          );
          exitCode = 1;
        }
      } catch (_) {
        stderr.writeln(
          'Could not verify the final user keychain configuration.',
        );
        exitCode = 1;
      }
    }
  }
}
