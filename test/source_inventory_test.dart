import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'source inventory measures Git blobs and rejects maintained legacy code',
    () async {
      final root = Directory.current;
      final fixture = Directory.systemTemp.createTempSync(
        'gpuidart-source-inventory-',
      );
      final script = File('${root.path}/tool/source_inventory.dart')
          .absolute
          .path;
      try {
        Future<void> git(List<String> args) async {
          final result = await Process.run(
            'git',
            args,
            workingDirectory: fixture.path,
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
        }

        void source(String path, String content) {
          File('${fixture.path}/$path')
            ..createSync(recursive: true)
            ..writeAsStringSync(content);
        }

        Future<Map<String, dynamic>> measure(int expectedExit) async {
          final result = await Process.run(Platform.resolvedExecutable, [
            '--packages=${root.path}/.dart_tool/package_config.json',
            script,
            '--report=${fixture.path}/report.json',
          ], workingDirectory: fixture.path);
          expect(result.exitCode, expectedExit, reason: '${result.stderr}');
          return jsonDecode(
            File('${fixture.path}/report.json').readAsStringSync(),
          ) as Map<String, dynamic>;
        }

        Future<void> commit() async {
          await git(['add', 'lib', 'native', 'benchmarks', 'tool']);
          await git([
            '-c',
            'user.name=Inventory Test',
            '-c',
            'user.email=inventory@example.invalid',
            'commit',
            '--quiet',
            '-m',
            'Fixture',
          ]);
        }

        await git(['init', '--quiet']);
        await git(['config', 'core.autocrlf', 'false']);
        const dart = "// 日本語\nvoid main() {}\n";
        source('lib/main.dart', dart);
        source('native/main.rs', 'fn main() {}\n');
        source('native/include/gpuidart.h', 'void gd_close(void);\n');
        source('native/vendor/example/build.py', 'print("vendor")\n');
        source('benchmarks/shell/main.js', 'console.log("comparison");\n');
        Directory('${fixture.path}/tool').createSync();
        await commit();
        source('tool/untracked.ps1', 'Write-Output untracked\n');
        final measured = await measure(0);
        expect(measured['passed'], isTrue);
        expect(measured['violations'], isEmpty);
        final files = measured['files'] as List;
        final dartFile = files.singleWhere((f) => f['path'] == 'lib/main.dart');
        expect(dartFile['bytes'], utf8.encode(dart).length);
        expect(dartFile['lines'], 2);
        expect(files.any((f) => f['path'] == 'tool/untracked.ps1'), isFalse);
        expect(
          (measured['by_scope']['maintained']['languages'] as Map).keys.toSet(),
          {'Dart', 'Rust'},
        );
        await commit();
        final rejected = await measure(1);
        expect(rejected['passed'], isFalse);
        expect(
          (rejected['violations'] as List).single['path'],
          'tool/untracked.ps1',
        );
      } finally {
        fixture.deleteSync(recursive: true);
      }
    },
  );
}
