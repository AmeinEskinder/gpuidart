import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../src/owned_process.dart';

Future<void> main(List<String> args) async {
  final root = File(Platform.resolvedExecutable).parent;
  var reportFile = File('${root.path}/verification.json');
  var environmentKind = 'development_machine';
  var runtimeOnly = false;
  for (final arg in args) {
    if (arg.startsWith('--report=')) {
      reportFile = File(arg.substring(9)).absolute;
    } else if (arg.startsWith('--environment=')) {
      environmentKind = arg.substring(14);
    } else if (arg == '--runtime-only') {
      runtimeOnly = true;
    } else {
      throw ArgumentError(
        'Usage: ./verify [--runtime-only] [--report=FILE] [--environment=development_machine|clean_vm|clean_machine|clean_container]',
      );
    }
  }
  if (!const [
    'development_machine',
    'clean_vm',
    'clean_machine',
    'clean_container',
  ].contains(environmentKind)) {
    throw ArgumentError('Invalid environment declaration');
  }
  final report = <String, dynamic>{
    'passed': false,
    'tested_at_utc': DateTime.now().toUtc().toIso8601String(),
    'environment_declared_by_operator': environmentKind,
    'package_path': root.path,
    'os': Platform.operatingSystemVersion,
    'runtime_only': runtimeOnly,
  };
  Future<void> save() async {
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }

  await save();
  try {
    if (!Platform.isLinux && !Platform.isMacOS) {
      throw UnsupportedError('Use the Windows package verifier on Windows');
    }
    final manifest = jsonDecode(
      await File('${root.path}/manifest.json').readAsString(),
    ) as Map<String, dynamic>;
    report['manifest'] = manifest;
    report['installed_payload_bytes'] =
        (manifest['files'] as List).fold<int>(
          0,
          (sum, file) => sum + (file['bytes'] as int),
        ) +
        await File('${root.path}/manifest.json').length();
    report['installed_size_scope'] = 'Extracted payload including verifier, manifest and documentation; excludes system runtime prerequisites';
    File inside(String path) {
      if (path.startsWith('/') || path.split('/').contains('..')) {
        throw StateError('Invalid package path: $path');
      }
      final file = File('${root.path}/$path');
      if (!file.resolveSymbolicLinksSync().startsWith(
        '${root.resolveSymbolicLinksSync()}/',
      )) {
        throw StateError('Package file escapes package: $path');
      }
      return file;
    }

    for (final entry in manifest['files'] as List) {
      final file = inside(entry['name'] as String);
      if (await file.length() != entry['bytes'] ||
          sha256.convert(await file.readAsBytes()).toString() !=
              entry['sha256']) {
        throw StateError('Package hash mismatch: ${entry['name']}');
      }
    }
    final executable = inside(manifest['executable'] as String);
    final library = inside(manifest['library'] as String);
    final helper = File('${executable.parent.path}/gpuidart-launcher');
    final dependencies = <String, Object>{};
    report['dependency_inspection'] = dependencies;
    for (final file in [
      executable,
      library,
      helper,
      File(Platform.resolvedExecutable),
    ]) {
      final relative = file.absolute.path.substring(
        '${root.absolute.path}/'.length,
      );
      final inspection =
          (manifest['build_dependency_inspection'] as Map?)?[relative];
      if (runtimeOnly) {
        if (inspection is! Map ||
            inspection['output'] is! String ||
            (inspection['output'] as String).isEmpty ||
            (inspection['output'] as String).contains('not found')) {
          throw StateError(
            'Missing or failed build-time dependency inspection: $relative',
          );
        }
        dependencies[file.path] = {
          'scope': 'Recorded at build time; inspection tool not executed on this machine',
          ...inspection,
        };
        continue;
      }
      final result = await Process.run(
        Platform.isMacOS ? '/usr/bin/otool' : '/usr/bin/ldd',
        [if (Platform.isMacOS) '-L', file.path],
      );
      dependencies[file.path] = {
        'status': result.exitCode,
        'stdout': result.stdout,
        'stderr': result.stderr,
      };
      if (result.exitCode != 0 || '${result.stdout}'.contains('not found')) {
        throw StateError('Unresolved dependency: ${file.path}');
      }
    }
    if (Platform.isMacOS) {
      final app = executable.parent.parent.parent;
      final signature = await Process.run('/usr/bin/codesign', [
        '--verify',
        '--deep',
        '--strict',
        app.path,
      ]);
      report['signature_verification'] = {
        'status': signature.exitCode,
        'stderr': signature.stderr,
        'scope':
            'Ad-hoc signature integrity; no Developer ID or notarization claim',
      };
      if (signature.exitCode != 0) throw StateError('Invalid app signature');
    }
    final temporary = await Directory.systemTemp.createTemp(
      'gpuidart-package-run-',
    );
    final home = Directory('${temporary.path}/home')..createSync();
    final environment = <String, String>{
      'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
      'HOME': home.path,
      'TMPDIR': temporary.path,
      for (final key in [
        'DISPLAY',
        'XAUTHORITY',
        'XDG_RUNTIME_DIR',
        'DBUS_SESSION_BUS_ADDRESS',
        'LANG',
        'LC_ALL',
        'LIBGL_ALWAYS_SOFTWARE',
      ])
        if (Platform.environment[key] case final String value) key: value,
    };
    report['working_directory'] = temporary.path;
    report['environment'] = environment;
    final process = await OwnedProcess.start(
      executable.path,
      ['--self-test'],
      launcherPath: helper.path,
      workingDirectory: temporary.path,
      environment: environment,
      includeParentEnvironment: false,
    );
    final output = process.process.stdout.transform(utf8.decoder).join();
    final errors = process.process.stderr.transform(utf8.decoder).join();
    try {
      final status = await process.process.exitCode.timeout(
        const Duration(seconds: 45),
      );
      report['application_exit_code'] = status;
      report['stderr'] = await errors;
      report['stdout'] = await output;
      if (status != 0) {
        throw StateError('Packaged self-test exited with $status');
      }
      final app =
          jsonDecode(report['stdout'] as String) as Map<String, dynamic>;
      report['application'] = app;
      if (app['passed'] != true || app['mode'] != 'aot') {
        throw StateError('Self-test must report passed true and mode aot');
      }
      final runtime = app['runtime'] as Map;
      final expectedLibrary = library.resolveSymbolicLinksSync();
      final rootPath = '${root.resolveSymbolicLinksSync()}/';
      for (final role in ['application', 'ui']) {
        final details = runtime[role] as Map;
        final images = (details['loaded_images'] as List).cast<String>().map((
          path,
        ) {
          final file = File(path);
          return file.existsSync() ? file.resolveSymbolicLinksSync() : path;
        }).toList();
        if (!images.contains(expectedLibrary)) {
          throw StateError('$role did not load the packaged SDK library');
        }
        for (final image in images) {
          final allowed =
              image.startsWith(rootPath) ||
              (Platform.isMacOS
                  ? image.startsWith('/System/Library/') ||
                        image.startsWith('/usr/lib/')
                  : image.startsWith('/usr/lib/') ||
                        image.startsWith('/lib/') ||
                        image.startsWith('/lib64/'));
          if (!allowed) {
            throw StateError(
              '$role loaded an image outside the package/system directories: $image',
            );
          }
          if (image.contains('/dart-sdk/') || image.contains('/.cargo/')) {
            throw StateError('Development dependency loaded: $image');
          }
        }
      }
      if (Platform.isMacOS &&
          (runtime['ui']['main_thread'] != true ||
              runtime['ui']['pid'] == runtime['application']['pid'])) {
        throw StateError('macOS UI did not use a main-thread companion');
      }
      final window = app['native']['window'] as Map;
      if ((window['scale_factor'] as num) <= 0 ||
          (window['width'] as num) <= 0 ||
          (window['height'] as num) <= 0) {
        throw StateError('No valid native window geometry');
      }
      report['passed'] = true;
      report['limitation'] = 'Hash, extracted launch, dependency and native-window checks only. Environment cleanliness is an operator declaration. Human IME, Retina/fractional scaling and physical presentation remain separate checks.';
      stdout.writeln(
        'PASS: extracted AOT self-test and packaged libraries. Report: ${reportFile.path}',
      );
    } finally {
      await process.stop();
    }
  } catch (error, stack) {
    report['passed'] = false;
    report['error'] = '$error';
    report['stack'] = '$stack';
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    await save();
  }
}
