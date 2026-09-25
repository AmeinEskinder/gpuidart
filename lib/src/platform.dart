import 'dart:io';

String nativeLibraryName(String name) => switch (Platform.operatingSystem) {
  'windows' => '$name.dll',
  'linux' => 'lib$name.so',
  'macos' => 'lib$name.dylib',
  _ => throw UnsupportedError(
    'No GPUI library loader for ${Platform.operatingSystem}',
  ),
};

String resolveNativeLibrary(String? supplied) {
  final name = nativeLibraryName('gpuidart');
  final sibling = File.fromUri(
    File(Platform.resolvedExecutable).parent.uri.resolve(name),
  );
  return File(
    supplied ??
        Platform.environment['GPUIDART_LIBRARY'] ??
        (const bool.fromEnvironment('gpuidart.packaged') || sibling.existsSync()
            ? sibling.path
            : 'target/debug/$name'),
  ).absolute.path;
}

String resolveLauncher({String? libraryPath}) {
  final name = Platform.isWindows
      ? 'gpuidart-launcher.exe'
      : 'gpuidart-launcher';
  final candidates = [
    if (Platform.environment['GPUIDART_LAUNCHER'] case final String supplied)
      supplied
    else ...[
      if (libraryPath != null)
        File.fromUri(File(libraryPath).parent.uri.resolve(name)).path,
      File.fromUri(File(Platform.resolvedExecutable).parent.uri.resolve(name))
          .path,
      'target/debug/$name',
    ],
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return File(path).absolute.path;
  }
  throw StateError(
    'GPUI launcher is missing. Build cargo build -p gpuidart-launcher, '
    'or include $name beside the packaged library.',
  );
}
