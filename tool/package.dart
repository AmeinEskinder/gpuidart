import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gpuidart/src/platform.dart';

import 'src/commands.dart';

Future<void> main(List<String> args) async {
  var name = 'gpuidart';
  var entry = 'example/watchlist/main.dart';
  for (final arg in args) {
    if (arg.startsWith('--name=')) {
      name = arg.substring(7);
    } else if (arg.startsWith('--entry=')) {
      entry = arg.substring(8);
    } else {
      throw ArgumentError('Usage: package.dart [--name=NAME] [--entry=FILE]');
    }
  }
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) {
    throw ArgumentError('Invalid package name');
  }
  if (Platform.isWindows) {
    stdout.writeln(
      await command('powershell.exe', [
        '-NoProfile',
        '-File',
        'tool/package.ps1',
        '-Name',
        name,
        '-EntryPoint',
        entry,
      ]),
    );
    return;
  }
  final target = switch (Abi.current()) {
    Abi.linuxX64 => 'linux-x64',
    Abi.macosArm64 => 'macos-arm64',
    _ => throw UnsupportedError(
      'Packaging currently targets Windows x64, Ubuntu 24.04 x64 and macOS 15 ARM64',
    ),
  };
  if (!File(entry).existsSync()) throw ArgumentError('Missing entry: $entry');
  await buildNative(release: true);
  // A fresh staging directory cannot carry stale files into a later package.
  final build = Directory('build')..createSync(recursive: true);
  final stage = await build.createTemp('$name-$target-');
  final payload = Platform.isMacOS
      ? Directory('${stage.path}/$name.app/Contents/MacOS')
      : stage;
  payload.createSync(recursive: true);
  final binary = '${payload.path}/$name';
  await command(Platform.resolvedExecutable, [
    'compile',
    'exe',
    '--define=gpuidart.packaged=true',
    entry,
    '-o',
    binary,
  ]);
  await File('target/release/${nativeLibraryName('gpuidart')}')
      .copy('${payload.path}/${nativeLibraryName('gpuidart')}');
  await File('target/release/gpuidart-launcher')
      .copy('${payload.path}/gpuidart-launcher');
  await command('chmod', ['755', binary, '${payload.path}/gpuidart-launcher']);
  await command(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'tool/unix/verify.dart',
    '-o',
    '${stage.path}/verify',
  ]);
  if (Platform.isMacOS) {
    await File('${stage.path}/$name.app/Contents/Info.plist')
        .writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.gpuidart.${name.toLowerCase().replaceAll('_', '-')}</string>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
''');
    for (final file in [
      nativeLibraryName('gpuidart'),
      'gpuidart-launcher',
      name,
    ]) {
      await command('codesign', [
        '--force',
        '--sign',
        '-',
        '${payload.path}/$file',
      ]);
    }
    await command('codesign', [
      '--force',
      '--sign',
      '-',
      '${stage.path}/$name.app',
    ]);
    await command('codesign', [
      '--verify',
      '--deep',
      '--strict',
      '${stage.path}/$name.app',
    ]);
  }
  final metadata = jsonDecode(
    await command('cargo', [
      'metadata',
      '--locked',
      '--offline',
      '--format-version',
      '1',
    ]),
  ) as Map;
  final packages = metadata['packages'] as List;
  final kit = packages.singleWhere((p) => p['name'] == 'gpui-kit');
  final kitRoot = File(kit['manifest_path'] as String).parent.parent.parent;
  await File('${kitRoot.path}/LICENSE-APACHE')
      .copy('${stage.path}/GPUI-Kit-LICENSE.txt');
  await File.fromUri(
    File(Platform.resolvedExecutable).parent.parent.uri.resolve('LICENSE'),
  ).copy('${stage.path}/Dart-LICENSE.txt');
  await File('${stage.path}/THIRD-PARTY.json').writeAsString(
    jsonEncode(
      packages
          .map(
            (p) => {
              'name': p['name'],
              'version': p['version'],
              'license': p['license'],
              'repository': p['repository'],
            },
          )
          .toList(),
    ),
  );
  await File('docs/unix-release-checks.md')
      .copy('${stage.path}/RELEASE-CHECKS.md');
  await File('${stage.path}/README.txt')
      .writeAsString('''GPUI-Dart $target evaluation package
Run ${Platform.isMacOS ? '$name.app/Contents/MacOS/$name or open $name.app' : './$name'}.
Keep the complete package together. No Dart/Rust SDK is needed to run it.
Run ./verify --report=verification.json to check hashes, dependencies, loaded libraries and the application's self-test.
See RELEASE-CHECKS.md for OS prerequisites and human checks.
${Platform.isMacOS ? 'This app has an ad-hoc signature. Developer ID distribution and notarization are unverified.' : 'Requires Ubuntu 24.04 x64, X11 and the documented system runtime libraries.'}
The project owner has not selected a project license. This is a private evaluation artifact.
''');
  final files = await stage
      .list(recursive: true, followLinks: false)
      .where((f) => f is File)
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  final prefix = '${stage.absolute.path}/';
  final sources = (await command('git', [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    'lib',
    'native',
    'launcher',
    'example',
    'tool',
    'pubspec.yaml',
    'pubspec.lock',
    'Cargo.toml',
    'Cargo.lock',
    'rust-toolchain.toml',
  ])).split('\n').where((p) => p.isNotEmpty).toSet().toList()..sort();
  if (!sources.contains(entry)) sources.add(entry);
  final manifest = {
    'target': target,
    'native_abi': 1,
    'companion_extension': 2,
    'executable': File(binary).absolute.path.substring(prefix.length),
    'library':
        '${Platform.isMacOS ? '$name.app/Contents/MacOS/' : ''}${nativeLibraryName('gpuidart')}',
    'minimum_os': Platform.isMacOS
        ? 'macOS 15 ARM64'
        : 'Ubuntu 24.04 x64, glibc 2.39, X11',
    'signing': Platform.isMacOS
        ? 'ad-hoc evaluation; not notarized'
        : 'unsigned evaluation archive',
    'build': {
      'git_commit': await command('git', ['rev-parse', 'HEAD']),
      'source_dirty': (await command('git', [
        'status',
        '--porcelain',
      ])).isNotEmpty,
      'source_files': [
        for (final source in sources)
          {
            'path': source,
            'sha256': sha256
                .convert(await File(source).readAsBytes())
                .toString(),
          },
      ],
      'dart': Platform.version,
      'rustc': await command('rustc', ['--version']),
      'built_at_utc': DateTime.now().toUtc().toIso8601String(),
    },
    'files': [
      for (final file in files)
        {
          'name': file.absolute.path.substring(prefix.length),
          'bytes': await file.length(),
          'sha256': sha256.convert(await file.readAsBytes()).toString(),
        },
    ],
  };
  await File(
    '${stage.path}/manifest.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  final archive = '${build.absolute.path}/$name-$target.tar.gz';
  await command('tar', ['-czf', archive, '-C', stage.path, '.']);
  stdout.writeln(
    jsonEncode({
      'package': archive,
      'sha256': sha256.convert(await File(archive).readAsBytes()).toString(),
      'staging_directory': stage.absolute.path,
    }),
  );
}
