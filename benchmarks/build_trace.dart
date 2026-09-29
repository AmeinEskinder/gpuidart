import 'dart:io';

import 'src/common.dart';
import 'src/process.dart';
import '../tool/src/toolchain.dart';

Future<void> main(List<String> args) => guarded(() async {
  Options(args).done();
  final root = repositoryRoot();
  try {
    await execute('cargo', [
      'build',
      '--locked',
      '--release',
      '-p',
      'gpuidart',
      '-p',
      'gpui-native-comparison',
      '--features',
      'gpuidart/benchmark-trace,gpui-native-comparison/benchmark-trace',
    ]);
    Directory('$root/build/comparison-trace').createSync(recursive: true);
    for (final name in ['gpuidart.dll', 'gpui-native-comparison.exe']) {
      File('$root/target/release/$name')
          .copySync('$root/build/comparison-trace/$name');
    }
    File('$root/build/comparison/rust/vcruntime140.dll')
        .copySync('$root/build/comparison-trace/vcruntime140.dll');
  } finally {
    await execute('cargo', [
      'build',
      '--locked',
      '--release',
      '-p',
      'gpuidart',
      '-p',
      'gpui-native-comparison',
    ]);
  }
  await execute(dartExecutable, [
    'compile',
    'exe',
    'benchmarks/dart/main.dart',
    '-o',
    'build/gpui-dart-comparison.exe',
  ]);
});
