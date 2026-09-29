import 'dart:io';

import 'src/common.dart';
import 'src/process.dart';
import '../tool/src/toolchain.dart';

Future<void> packageBenchmarks({bool noFlutter = false}) async {
  final root = repositoryRoot(),
      packageRoot = '${repositoryRoot()}/build/comparison';
  Directory(packageRoot).createSync(recursive: true);
  final sources = {
    'rust': ['target/release/gpui-native-comparison.exe'],
    'dart': ['build/gpui-dart-comparison.exe', 'target/release/gpuidart.dll'],
    'solid': [
      'benchmarks/solid/dist/gpui-solid-comparison.exe',
      'benchmarks/solid/dist/gpuix-native.win32-x64-msvc.node',
    ],
    'shell': [
      'target/release/gpui-component-shell.exe',
      'benchmarks/shell/main.js',
    ],
    if (!noFlutter) 'flutter': <String>[],
  };
  String? driver;
  final packages = <Json>[];
  for (final entry in sources.entries) {
    final folder = '$packageRoot/${entry.key}';
    Directory(folder).createSync(recursive: true);
    for (final source in entry.value) {
      File('$root/$source').copySync('$folder/${source.split('/').last}');
    }
    if (entry.key == 'flutter') {
      copyTree(
        Directory('$root/benchmarks/flutter/build/windows/x64/runner/Release'),
        Directory(folder),
      );
    }
    if (File('$root/build/windows-x64/vcruntime140.dll').existsSync()) {
      File('$root/build/windows-x64/vcruntime140.dll')
          .copySync('$folder/vcruntime140.dll');
    } else {
      driver ??= await driverExecutable();
      await execute(driver, [
        '--extract-crt',
        '$root/.tools/downloads/Microsoft.VC.14.44.17.14.CRT.Redist.X64.base.vsix',
        '$folder/vcruntime140.dll',
      ]);
    }
    if (entry.key != 'flutter') {
      File('$root/.cache/gpui-kit/LICENSE-APACHE')
          .copySync('$folder/GPUI-Kit-LICENSE.txt');
    }
    final files =
        Directory(folder)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final inventory = <Json>[];
    for (final file in files) {
      inventory.add({
        'name': file.path.substring(folder.length + 1).replaceAll('\\', '/'),
        'bytes': file.lengthSync(),
        'sha256': await hash(file.path),
      });
    }
    packages.add({
      'implementation': entry.key,
      'files': inventory,
      'payload_bytes': inventory.fold<num>(
        0,
        (sum, f) => sum + number(f['bytes']),
      ),
      'closure_status': 'explicit runtime payload; PE direct imports checked; clean-machine launch pending',
    });
  }
  Future<String> version(String exe, List<String> args) async {
    final result = await execute(exe, args);
    return '${result.stdout}${result.stderr}'.trim();
  }

  final versions = {
    'rust': await version('rustc', ['--version']),
    'dart': await version(dartExecutable, ['--version']),
    'flutter': noFlutter
        ? 'not built'
        : (await version('flutter', ['--version'])).split('\n').first,
    'bun': await version('bun', ['--version']),
    'kit_revision': '0c830f4d257e69fdd17200650533ab4ca9a40cc0',
    'gpui_pre': '0.3.7',
    'gpui_shell': '0.7.0',
    'quickjs_jit_revision': '82d3808f3aa7d1c4ad2f360f5b3bd5979501d599',
    'quickjs_jit_stdlib_revision': '605da483611a3548edb8c33fdff602e3f5f42076',
    'gpuix_native': '0.10.0',
    'gpuix_solid': '0.10.0',
    'solid_js': '1.9.15',
    'gpuix_binary_provenance': 'published npm artifact pinned by bun.lock integrity; upstream does not publish gitHead for this artifact',
    'rust_build': 'cargo --release (optimized); profiler enabled for native reference and GPUI-Dart',
    'solid_build': 'Bun compile + minify + Solid production plugin; npm Windows native addon',
    'flutter_build': 'flutter build windows --release (AOT); engine DLL and data directory copied whole; CRT from the system',
    'presentmon': '2.6.0',
    'root_lock_sha256': (await hash('$root/Cargo.lock')).toUpperCase(),
    'shell_lock_sha256': (await hash('$root/.cache/gpui-kit/Cargo.lock'))
        .toUpperCase(),
    'solid_lock_sha256': (await hash('$root/benchmarks/solid/bun.lock'))
        .toUpperCase(),
  };
  writeJson('$root/reports/comparison/artifacts.json', {
    'versions': versions,
    'packages': packages,
    'captured_utc': DateTime.now().toUtc().toIso8601String(),
  });
  stdout.writeln('$root/reports/comparison/artifacts.json');
}

Future<void> main(List<String> args) => guarded(() async {
  final o = Options(args, flags: {'no-flutter'});
  final noFlutter = o.flag('no-flutter');
  o.done();
  await packageBenchmarks(noFlutter: noFlutter);
});
