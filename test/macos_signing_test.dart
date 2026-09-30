import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/src/macos_signing.dart';

void main() {
  const identity = 'Developer ID Application: Example (TEAMID)';
  late Directory stage, app;
  late List<File> binaries;
  setUp(() async {
    stage = await Directory.systemTemp.createTemp('gpuidart-signing-test-');
    app = Directory(p.join(stage.path, 'Example.app'));
    final payload = Directory(p.join(app.path, 'Contents', 'MacOS'));
    await payload.create(recursive: true);
    binaries = [
      for (final name in ['Example', 'libgpuidart.dylib', 'gpuidart-launcher'])
        File(p.join(payload.path, name)),
      File(p.join(stage.path, 'verify')),
    ];
    for (final file in binaries) {
      await file.writeAsString('fixture executable');
    }
  });
  tearDown(() => stage.delete(recursive: true));

  test('signing configuration requires a complete Developer ID pair', () {
    expect(MacosSigning.fromOptions().isDistribution, false);
    expect(
      () => MacosSigning.fromOptions(identity: identity),
      throwsArgumentError,
    );
    expect(
      () => MacosSigning.fromOptions(notaryProfile: 'profile'),
      throwsArgumentError,
    );
    expect(
      () => MacosSigning.fromOptions(keychain: 'keys'),
      throwsArgumentError,
    );
    expect(
      () => MacosSigning.fromOptions(identity: '', notaryProfile: 'profile'),
      throwsArgumentError,
    );
    expect(
      () => MacosSigning.fromOptions(identity: '-', notaryProfile: 'profile'),
      throwsArgumentError,
    );
    expect(
      MacosSigning.fromOptions(
        identity: identity,
        notaryProfile: 'profile',
        keychain: 'keys',
      ).isDistribution,
      true,
    );
  });

  test(
    'evaluation keeps app-only ad-hoc signing and does not submit',
    () async {
      final calls = <List<String>>[];
      final signing = MacosSigning.fromOptions(
        runner: (exe, args) async {
          calls.add([exe, ...args]);
          if (exe == '/usr/bin/ditto') {
            await File(args.last).writeAsString('notary-zip-fixture\n');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      await signing.sign(stage: stage, app: app, binaries: binaries);
      final signatures = calls.where((c) => c.contains('--sign')).toList();
      expect(signatures, hasLength(4));
      expect(signatures.every((c) => c[c.indexOf('--sign') + 1] == '-'), true);
      expect(signatures.any((c) => c.last == binaries.last.path), false);
      expect(await signing.notarize(stage: stage, app: app), isEmpty);
      expect(calls.every((c) => c.first == '/usr/bin/codesign'), true);
    },
  );

  test(
    'distribution signs verifier and nested code before outer app',
    () async {
      final calls = <List<String>>[];
      final signing = MacosSigning.fromOptions(
        identity: identity,
        notaryProfile: 'profile',
        keychain: 'keys',
        runner: (exe, args) async {
          calls.add([exe, ...args]);
          if (exe == '/usr/bin/ditto') {
            await File(args.last).writeAsString('notary-zip-fixture\n');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      await signing.sign(stage: stage, app: app, binaries: binaries);
      final signatures = calls.where((c) => c.contains('--sign')).toList();
      expect(signatures.map((c) => c.last), [
        ...binaries.map((f) => f.path),
        app.path,
      ]);
      for (final call in signatures) {
        expect(
          call,
          containsAll([
            '--timestamp',
            '--options',
            'runtime',
            identity,
            '--keychain',
            'keys',
          ]),
        );
        expect(call, isNot(contains('--deep')));
        expect(call, isNot(contains('--entitlements')));
      }
    },
  );

  for (final status in ['Invalid', 'In Progress']) {
    test('$status retains Apple log and cannot reach stapling', () async {
      final calls = <List<String>>[];
      final signing = MacosSigning.fromOptions(
        identity: identity,
        notaryProfile: 'profile',
        runner: (exe, args) async {
          calls.add([exe, ...args]);
          if (exe == '/usr/bin/ditto') {
            await File(args.last).writeAsString('notary-zip-fixture\n');
          }
          if (args.contains('submit')) {
            return ProcessResult(
              0,
              status == 'Invalid' ? 1 : 0,
              jsonEncode({'id': 'submission', 'status': status}),
              '',
            );
          }
          if (args.contains('log')) {
            await File(args.last).writeAsString(
              jsonEncode({
                'status': status,
                'jobId': 'submission',
                'issues': [
                  {'severity': 'error', 'message': 'fixture rejection'},
                ],
              }),
            );
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      await expectLater(
        signing.notarize(stage: stage, app: app),
        throwsStateError,
      );
      expect(calls.any((c) => c.contains('log')), true);
      expect(calls.any((c) => c.contains('stapler')), false);
      final report = jsonDecode(
        await File(p.join(stage.path, 'macos-notarization.json'))
            .readAsString(),
      ) as Map;
      expect(report['status'], 'failed');
      expect(report['notarized'], false);
      expect(report['apple_status'], status);
      expect(
        File(p.join(stage.path, 'macos-notary-log.json')).existsSync(),
        true,
      );
    });
  }

  for (final failure in [null, 'staple', 'ticket']) {
    test('Accepted requires all ticket checks: failure=$failure', () async {
      final calls = <List<String>>[];
      final signing = MacosSigning.fromOptions(
        identity: identity,
        notaryProfile: 'profile',
        runner: (exe, args) async {
          calls.add([exe, ...args]);
          if (exe == '/usr/bin/ditto') {
            await File(args.last).writeAsString('notary-zip-fixture\n');
          }
          if (args.contains('submit')) {
            final beforeUpload = jsonDecode(
              await File(p.join(stage.path, 'macos-notarization.json'))
                  .readAsString(),
            ) as Map;
            expect(beforeUpload['submitted_archive'], {
              'bytes': 19,
              'sha256': '57018e30d202fa644c6485edbb23537a94bb426fef700c1a9e7dd6948ab97db7',
            });
            return ProcessResult(
              0,
              0,
              jsonEncode({'id': 'submission', 'status': 'Accepted'}),
              '',
            );
          }
          if (args.contains('log')) {
            await File(args.last).writeAsString(
              '{"status":"Accepted","jobId":"SUBMISSION","issues":null}',
            );
          }
          if (failure == 'staple' && args.contains('validate')) {
            return ProcessResult(0, 65, '', 'ticket validation failed');
          }
          if (failure == 'ticket' && args.contains('--check-notarization')) {
            return ProcessResult(
              0,
              1,
              '',
              'standalone notarization ticket missing',
            );
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      if (failure != null) {
        await expectLater(
          signing.notarize(stage: stage, app: app),
          throwsStateError,
        );
      } else {
        final result = await signing.notarize(stage: stage, app: app);
        expect(result['notarized'], true);
        expect(result['status'], 'Accepted');
        expect(result['standalone_ticket_verified'], true);
        expect((result['notary_log'] as Map)['issues'], isEmpty);
        final submission = calls.singleWhere((c) => c.contains('submit'));
        expect(File(submission[3]).existsSync(), false);
        expect(result['submitted_archive'], {
          'bytes': 19,
          'sha256': '57018e30d202fa644c6485edbb23537a94bb426fef700c1a9e7dd6948ab97db7',
        });
        expect(calls.last, [
          '/usr/bin/syspolicy_check',
          'distribution',
          app.path,
        ]);
        final ticket = calls.singleWhere(
          (c) => c.contains('--check-notarization'),
        );
        expect(ticket, [
          '/usr/bin/codesign',
          '--verify',
          '--verbose=4',
          '--check-notarization',
          '-R=notarized',
          binaries.last.path,
        ]);
      }
      final report = jsonDecode(
        await File(p.join(stage.path, 'macos-notarization.json'))
            .readAsString(),
      ) as Map;
      expect(report['notarized'], failure == null);
      expect(calls.any((c) => c.contains('validate')), true);
      if (failure != null) {
        expect(calls.any((c) => c.first == '/usr/bin/syspolicy_check'), false);
      }
    });
  }

  test('SHA-1 certificate identities are supported', () {
    expect(
      MacosSigning.fromOptions(
        identity: '0123456789abcdef0123456789abcdef01234567',
        notaryProfile: 'profile',
      ).isDistribution,
      true,
    );
  });

  test(
    'distribution verifies Developer ID certificate chain after signing',
    () async {
      final signing = MacosSigning.fromOptions(
        identity: identity,
        notaryProfile: 'profile',
        runner: (exe, args) async {
          if (args.any((arg) => arg.contains('1.2.840.113635.100.6.1.13'))) {
            return ProcessResult(0, 1, '', 'certificate requirement failed');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      await expectLater(
        signing.sign(stage: stage, app: app, binaries: binaries),
        throwsStateError,
      );
      final evidence = jsonDecode(
        await File(p.join(stage.path, 'macos-signing.json')).readAsString(),
      ) as Map;
      expect(evidence['status'], 'failed');
    },
  );
  for (final scenario in [
    'mismatched-id',
    'invalid-log',
    'error-issue',
    'warning-issue',
  ]) {
    test('Apple log verification: $scenario', () async {
      final calls = <List<String>>[];
      final expected = scenario == 'warning-issue';
      final issues = [
        if (scenario == 'error-issue' || scenario == 'warning-issue')
          {
            'severity': scenario == 'error-issue' ? 'error' : 'warning',
            'message': 'fixture issue',
          },
      ];
      final signing = MacosSigning.fromOptions(
        identity: identity,
        notaryProfile: 'profile',
        runner: (exe, args) async {
          calls.add([exe, ...args]);
          if (exe == '/usr/bin/ditto') {
            await File(args.last).writeAsString('notary-zip-fixture\n');
          }
          if (args.contains('submit')) {
            return ProcessResult(
              0,
              0,
              '{"id":"submission","status":"Accepted"}',
              '',
            );
          }
          if (args.contains('log')) {
            await File(args.last).writeAsString(
              jsonEncode({
                'jobId': scenario == 'mismatched-id'
                    ? 'other-submission'
                    : 'SuBmIsSiOn',
                'status': scenario == 'invalid-log' ? 'Invalid' : 'Accepted',
                'issues': issues,
              }),
            );
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      if (expected) {
        expect(
          (await signing.notarize(stage: stage, app: app))['status'],
          'Accepted',
        );
      } else {
        await expectLater(
          signing.notarize(stage: stage, app: app),
          throwsStateError,
        );
      }
      final report = jsonDecode(
        await File(p.join(stage.path, 'macos-notarization.json'))
            .readAsString(),
      ) as Map;
      final log = report['notary_log'] as Map;
      expect(report['notarized'], expected);
      expect(calls.any((c) => c.contains('stapler')), expected);
      expect(log['issues'], issues);
      expect(log['issue_count'], issues.length);
      expect(log['error_count'], scenario == 'error-issue' ? 1 : 0);
      expect(log['warning_count'], scenario == 'warning-issue' ? 1 : 0);
    });
  }
}
