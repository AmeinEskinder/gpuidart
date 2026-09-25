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
