import 'dart:io';

import 'package:test/test.dart';

import '../tool/macos_release.dart';

void main() {
  final wrapper = File(
    Platform.environment['GPUIDART_RELEASE_WRAPPER'] ??
        'tool/macos_release.dart',
  ).absolute.path;
  Future<ProcessResult> invoke(Map<String, String> values) => Process.run(
    Platform.resolvedExecutable,
    [wrapper],
    environment: {
      for (final entry in Platform.environment.entries)
        if (!requiredMacosReleaseSecrets.contains(entry.key) &&
            !['PATH', 'Path'].contains(entry.key))
          entry.key: entry.value,
      'PATH': '',
      ...values,
    },
    includeParentEnvironment: false,
  );

  test('missing credentials fail before platform or tool checks', () async {
    final result = await invoke({});
    expect(result.exitCode, 78);
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('Missing required GitHub secrets:'));
    for (final name in requiredMacosReleaseSecrets) {
      expect(result.stderr, contains(name));
    }
    expect(result.stderr, isNot(contains('requires macOS')));
  });

  for (final missing in requiredMacosReleaseSecrets) {
    test('missing $missing cannot expose other credential values', () async {
      final values = {
        for (final name in requiredMacosReleaseSecrets)
          name: name == missing ? ' \n ' : 'sentinel-$name-private-value',
      };
      final result = await invoke(values);
      expect(result.exitCode, 78);
      expect(result.stdout, isEmpty);
      expect(result.stderr, 'Missing required GitHub secrets: $missing\n');
      for (final value in values.values.where(
        (value) => value.trim().isNotEmpty,
      )) {
        expect('${result.stdout}${result.stderr}', isNot(contains(value)));
      }
    });
  }
}
