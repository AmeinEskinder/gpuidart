import 'dart:io';

import '../tool/build.dart' as build;
import '../tool/check.dart' as check;
import '../tool/dev.dart' as dev;
import '../tool/doctor.dart' as doctor;
import '../tool/env.dart' as env;
import '../tool/package.dart' as package;
import '../tool/verify_package.dart' as verify;

const usage = '''GPUI-Dart developer tools

Usage: gpuidart [--sdk=PATH] COMMAND [ARGUMENTS]

  doctor [--json]                  Check the installed toolchain
  build [--release]                Build the native runtime
  run [ENTRY.dart] [ARGUMENTS]     Run with Dart code reload
  check [--headless]               Run the SDK checks
  package [--name=NAME] [--entry=FILE] [--crt-directory=DIR]
                                  Build a desktop application archive
          [--signing-identity=IDENTITY --notary-profile=PROFILE]
          [--signing-keychain=PATH]  Sign and notarize a macOS package
  verify ARCHIVE [REPORT] [ENVIRONMENT] [--runtime-only] [--require-notarized]
                                  Verify a packaged application
  exec COMMAND [ARGUMENTS]         Run a tool with the discovered toolchain

Uses the SDK checkout in the current directory, beside this executable, or
GPUIDART_SDK. Entry paths are relative to that SDK checkout.
''';

Future<void> main(List<String> args) async {
  try {
    String? sdk = Platform.environment['GPUIDART_SDK'];
    if (args.isNotEmpty && args.first.startsWith('--sdk=')) {
      sdk = args.first.substring(6);
      args = args.skip(1).toList();
    }
    if (args.isEmpty || args.first == '--help' || args.first == 'help') {
      stdout.write(usage);
      return;
    }
    if (args.first == '--version') {
      stdout.writeln('gpuidart 0.1.0');
      return;
    }
    final commands = <String, Future<void> Function(List<String>)>{
      'doctor': doctor.main,
      'build': build.main,
      'run': dev.main,
      'check': check.main,
      'package': package.main,
      'verify': verify.main,
      'exec': env.main,
    };
    final command = commands[args.first];
    if (command == null) {
      throw ArgumentError('Unknown command: ${args.first}\n$usage');
    }
    Directory.current = _sdkRoot(sdk);
    await command(args.skip(1).toList());
  } catch (error) {
    stderr.writeln('gpuidart: $error');
    exitCode = error is ArgumentError ? 64 : 1;
  }
}

Directory _sdkRoot(String? explicit) {
  bool isSdk(Directory directory) =>
      File('${directory.path}/pubspec.yaml').existsSync() &&
      File('${directory.path}/native/Cargo.toml').existsSync() &&
      File('${directory.path}/tool/build.dart').existsSync();
  if (explicit != null) {
    final directory = Directory(explicit).absolute;
    if (isSdk(directory)) return directory;
    throw ArgumentError('Not a GPUI-Dart SDK checkout: $explicit');
  }
  for (var candidate in [
    Directory.current,
    File(Platform.resolvedExecutable).parent,
  ]) {
    while (true) {
      if (isSdk(candidate)) return candidate;
      final parent = candidate.parent;
      if (parent.path == candidate.path) break;
      candidate = parent;
    }
  }
  throw StateError(
    'SDK checkout not found. Set GPUIDART_SDK or use --sdk=PATH.',
  );
}
