import 'dart:io';

import 'package:gpuidart/src/platform.dart';

import 'src/commands.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) throw ArgumentError('Usage: build_test_fixtures.dart');
  Directory('.cache').createSync(recursive: true);
  await command('rustc', [
    '--edition=2024',
    '--crate-type',
    'cdylib',
    '-A',
    'private_interfaces',
    'test/fixtures/fault_host.rs',
    '-o',
    '.cache/${nativeLibraryName('fault_host')}',
  ]);
}
