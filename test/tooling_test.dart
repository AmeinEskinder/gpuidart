import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

import '../tool/src/archives.dart';
import '../tool/src/toolchain.dart';
import '../tool/package.dart' as package;

void main() {
  test(
    'package names cannot overwrite bundled tools or Windows devices',
    () async {
      for (final name in [
        'verify',
        'VeRiFy',
        'gpuidart-windows-tool',
        'gpuidart-launcher',
        'NUL',
        'COM1',
      ]) {
        await expectLater(package.main(['--name=$name']), throwsArgumentError);
      }
    },
  );
  late Directory temporary;
  setUp(
    () => temporary = Directory.systemTemp.createTempSync('gpuidart tooling '),
  );
  tearDown(() => temporary.deleteSync(recursive: true));

  test(
    'ZIP packaging preserves nested Unicode files and binary content',
    () async {
      final source = Directory('${temporary.path}/source')..createSync();
      final nested = File('${source.path}/nested/日本語.txt')
        ..createSync(recursive: true);
      nested.writeAsStringSync('café 😀');
      File('${source.path}/binary.bin').writeAsBytesSync([0, 255, 1, 128]);
      final zip = File('${temporary.path}/package.zip');
      await createZip(source, zip);
      final destination = Directory('${temporary.path}/extracted');
      await extractZip(zip, destination);
      expect(
        File('${destination.path}/nested/日本語.txt').readAsStringSync(),
        'café 😀',
      );
      expect(File('${destination.path}/binary.bin').readAsBytesSync(), [
        0,
        255,
        1,
        128,
      ]);
    },
  );

  for (final path in [
    '../outside',
    r'..\outside',
    '/absolute',
    'C:/absolute',
    'file:stream',
  ]) {
    test('ZIP rejects $path before extracting any member', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('valid.txt', 4, utf8.encode('safe')))
        ..addFile(ArchiveFile(path, 3, utf8.encode('bad')));
      final zip = File('${temporary.path}/unsafe.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      final destination = Directory('${temporary.path}/extracted');
      await expectLater(extractZip(zip, destination), throwsFormatException);
      expect(File('${destination.path}/valid.txt').existsSync(), isFalse);
      expect(File('${temporary.path}/outside').existsSync(), isFalse);
    });
  }

  test(
    'toolchain lookup uses the requested environment and paths with spaces',
    () {
      final bin = Directory('${temporary.path}/custom bin')..createSync();
      final executable = File(
        '${bin.path}/my-tool${Platform.isWindows ? '.exe' : ''}',
      )..writeAsStringSync('fixture');
      expect(
        File(toolExecutable('my-tool', {'PATH': bin.path})).absolute.uri,
        executable.absolute.uri,
      );
    },
  );

  test(
    'toolchain environment preserves overrides without Windows duplicate keys',
    () {
      final environment = toolchainEnvironment(
        root: temporary.path,
        environment: {
          'GPUIDART_TEST_OVERRIDE': 'preserved',
          if (Platform.isWindows) 'Path': 'custom-environment-path',
        },
      );
      expect(environment['GPUIDART_TEST_OVERRIDE'], 'preserved');
      if (Platform.isWindows) {
        expect(environment.keys.where((key) => key.toUpperCase() == 'PATH'), [
          'PATH',
        ]);
        expect(environment['PATH'], endsWith('custom-environment-path'));
      }
    },
  );
}
