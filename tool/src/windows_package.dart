import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'archives.dart';
import 'commands.dart';
import 'package_manifest.dart';
import 'toolchain.dart';

Future<void> packageWindows({
  required String name,
  required String entry,
  String? crtDirectory,
}) async {
  if (Abi.current() != Abi.windowsX64) {
    throw UnsupportedError('Windows packages currently target x64');
  }
  validatePackageName(name);
  if (!File(entry).existsSync()) {
    throw ArgumentError('Entry point not found: $entry');
  }
  await buildNative(release: true);
  final build = Directory('build')..createSync(recursive: true);
  final stage = await build.createTemp('$name-windows-x64-');
  await command(dartExecutable, [
    'compile',
    'exe',
    '--define=gpuidart.packaged=true',
    entry,
    '-o',
    '${stage.path}/$name.exe',
  ]);
  await command('mt.exe', [
    '-nologo',
    '-manifest',
    'tool/windows/app.manifest',
    '-outputresource:${stage.path}/$name.exe;#1',
  ]);
  await File('target/release/gpuidart.dll').copy('${stage.path}/gpuidart.dll');
  final crtArchive = File(
    '.tools/downloads/Microsoft.VC.14.44.17.14.CRT.Redist.X64.base.vsix',
  );
  final redist = toolchainEnvironment()['VCToolsRedistDir'];
  final crt =
      crtDirectory ??
      (redist == null ? null : '$redist/x64/Microsoft.VC143.CRT');
  if (crt != null) {
    await File('$crt/vcruntime140.dll').copy('${stage.path}/vcruntime140.dll');
  } else if (crtArchive.existsSync()) {
    await extractCrt(crtArchive, File('${stage.path}/vcruntime140.dll'));
  } else {
    throw StateError(
      'Supply --crt-directory with the Microsoft x64 redistributable directory.',
    );
  }
  await command('cargo', [
    'build',
    '--locked',
    '--release',
    '--manifest-path',
    'tool/windows/native/Cargo.toml',
  ]);
  await File('tool/windows/native/target/release/gpuidart-windows-tool.exe')
      .copy('${stage.path}/gpuidart-windows-tool.exe');
  await command(dartExecutable, [
    'compile',
    'exe',
    'tool/windows/verify.dart',
    '-o',
    '${stage.path}/verify.exe',
  ]);
  final metadata = jsonDecode(
    await command('cargo', [
      'metadata',
      '--locked',
      '--offline',
      '--filter-platform',
      'x86_64-pc-windows-msvc',
      '--format-version',
      '1',
    ]),
  ) as Map;
  final packages = metadata['packages'] as List;
  final kit = packages.singleWhere((package) => package['name'] == 'gpui-kit');
  final kitRoot = File(kit['manifest_path'] as String).parent.parent.parent;
  final dartSdk = await command(dartExecutable, [
    'run',
    'tool/src/dart_sdk.dart',
  ]);
  final licenses = {
    '${kitRoot.path}/LICENSE-APACHE': 'GPUI-Kit-LICENSE.txt',
    'LICENSE': 'LICENSE',
    'native/vendor/gpui-pre-0.3.7/LICENSE-APACHE': 'GPUI-LICENSE-APACHE.txt',
    'native/vendor/GPUI-NOTICE': 'GPUI-NOTICE.txt',
    'native/vendor/NOTICE': 'AccessKit-NOTICE.txt',
    'native/vendor/LICENSE-MIT': 'AccessKit-LICENSE-MIT.txt',
    'native/vendor/LICENSE-APACHE': 'AccessKit-LICENSE-APACHE.txt',
    '$dartSdk/LICENSE': 'Dart-LICENSE.txt',
  };
  for (final license in licenses.entries) {
    await File(license.key).copy('${stage.path}/${license.value}');
  }
  await _json(File('${stage.path}/THIRD-PARTY.json'), [
    for (final package in packages)
      {
        for (final key in ['name', 'version', 'license', 'repository'])
          key: package[key],
      },
  ]);
  final checks = await File('docs/windows-release-checks.md').readAsString();
  await File('${stage.path}/RELEASE-CHECKS.md').writeAsString(
    checks
        .replaceAll('gpuidart-windows-x64.zip', '$name-windows-x64.zip')
        .replaceAll('gpuidart.exe', '$name.exe'),
  );
  await File('${stage.path}/README.txt')
      .writeAsString('''GPUI-Dart Windows x64 evaluation package
Run $name.exe. Keep gpuidart.dll and vcruntime140.dll beside it.
No Dart SDK or Rust toolchain is needed to launch.
Run .\\verify.exe --report=verification.json to check hashes, loaded DLLs and display awareness.
For an independently provisioned VM, add --environment=clean_vm.
The application must implement --self-test and print one JSON object with mode aot and boolean passed true.
See RELEASE-CHECKS.md for desktop and input checks.

GPUI-Dart is MIT licensed. See LICENSE and the included dependency licenses.
vcruntime140.dll is from Microsoft's release x64 Visual C++ redistributable.
This is an evaluation ZIP, not a signed installer.
''');
  final files = stage.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  await _json(File('${stage.path}/manifest.json'), {
    'architecture': 'windows-x64',
    'target': 'windows-x64',
    'project_license': 'MIT',
    'executable': '$name.exe',
    'entry_point': entry,
    'dpi_awareness': 'PerMonitorV2',
    'native_abi': 1,
    'kit_revision': '0c830f4d257e69fdd17200650533ab4ca9a40cc0',
    'build': await sourceManifest(entry),
    'files': [
      for (final file in files)
        {
          'name': p.basename(file.path),
          'bytes': await file.length(),
          'sha256': await fileHash(file),
        },
    ],
  });
  final archive = File('${build.path}/$name-windows-x64.zip');
  await createZip(stage, archive);
  stdout.writeln(
    jsonEncode({
      'package': archive.absolute.path,
      'sha256': await fileHash(archive),
      'staging_directory': stage.absolute.path,
    }),
  );
}

Future<void> _json(File file, Object value) async {
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}
