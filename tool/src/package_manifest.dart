import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'commands.dart';
import 'toolchain.dart';

void validatePackageName(String name) {
  const payloadNames = {'verify', 'gpuidart-windows-tool', 'gpuidart-launcher'};
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name) ||
      payloadNames.contains(name.toLowerCase()) ||
      RegExp(
        r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$',
        caseSensitive: false,
      ).hasMatch(name)) {
    throw ArgumentError('Invalid or reserved package name: $name');
  }
}

Future<String> fileHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<Map<String, Object>> sourceManifest(String entry) async {
  const sourcePaths = [
    'LICENSE',
    'bin',
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
  ];
  final sources =
      (await command('git', [
            'ls-files',
            '-z',
            '--cached',
            '--others',
            '--exclude-standard',
            '--',
            ...sourcePaths,
          ]))
          .split('\u0000')
          .where((path) => path.isNotEmpty && File(path).existsSync())
          .toSet();
  final absolute = File(entry).absolute.path;
  final inside = p.isWithin(Directory.current.path, absolute);
  final entryPath = inside
      ? p.relative(absolute).replaceAll('\\', '/')
      : absolute;
  final tracked =
      inside &&
      (await command('git', [
        'ls-files',
        '--cached',
        '--',
        entryPath,
      ])).isNotEmpty;
  sources.add(entryPath);
  final sorted = sources.toList()..sort();
  final hashes = [
    for (final path in sorted)
      {'path': path, 'sha256': await fileHash(File(path))},
  ];
  return {
    'git_commit': await command('git', ['rev-parse', 'HEAD']),
    'source_dirty':
        !tracked ||
        (await command('git', [
          'status',
          '--porcelain',
          '--',
          ...sourcePaths,
          entryPath,
        ])).isNotEmpty,
    'source_files': hashes,
    'source_sha256': sha256
        .convert(
          utf8.encode(
            hashes.map((f) => '${f['path']}:${f['sha256']}').join('\n'),
          ),
        )
        .toString(),
    'application_entry': {
      'path': entryPath,
      'tracked_in_sdk_repository': tracked,
      'sha256': await fileHash(File(absolute)),
    },
    'dart': await command(dartExecutable, ['--version']),
    'rustc': await command('rustc', ['--version']),
    'cargo': await command('cargo', ['--version']),
    'built_at_utc': DateTime.now().toUtc().toIso8601String(),
  };
}
