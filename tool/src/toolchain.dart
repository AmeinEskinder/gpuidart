import 'dart:io';

String get dartExecutable {
  final current = File(Platform.resolvedExecutable);
  final name = current.uri.pathSegments.last.toLowerCase();
  if (name == 'dart' || name == 'dart.exe') return current.path;
  final sdk = Platform.environment['DART_SDK'];
  if (sdk != null) {
    final binary = File('$sdk/bin/dart${Platform.isWindows ? '.exe' : ''}');
    if (binary.existsSync()) return binary.path;
  }
  final found = toolExecutable('dart', Platform.environment);
  if (found.toLowerCase().endsWith('.bat')) {
    final cached = File(
      '${File(found).parent.path}/cache/dart-sdk/bin/dart.exe',
    );
    if (cached.existsSync()) return cached.path;
  }
  return found;
}

/// Builds the environment for SDK tools without changing the invoking shell.
Map<String, String> toolchainEnvironment({
  String? root,
  Map<String, String>? environment,
}) {
  final result = <String, String>{};
  void put(String key, String value) {
    if (Platform.isWindows) {
      result.removeWhere((name, _) => name.toUpperCase() == key.toUpperCase());
    }
    result[key] = value;
  }

  for (final entry in {...Platform.environment, ...?environment}.entries) {
    put(entry.key, entry.value);
  }
  String? get(String key) {
    for (final entry in result.entries) {
      if (Platform.isWindows
          ? entry.key.toUpperCase() == key.toUpperCase()
          : entry.key == key) {
        return entry.value;
      }
    }
    return null;
  }

  final paths = <String>[];
  final toolsDirectory = Directory('${root ?? Directory.current.path}/.tools');
  final tools = toolsDirectory.existsSync()
      ? toolsDirectory.resolveSymbolicLinksSync()
      : toolsDirectory.path;
  final extension = Platform.isWindows ? '.exe' : '';
  if (File('$tools/cargo/bin/cargo$extension').existsSync()) {
    put('CARGO_HOME', '$tools/cargo');
    put('RUSTUP_HOME', '$tools/rustup');
    paths.add('$tools/cargo/bin');
  }
  if (Platform.isWindows) {
    final portable = Directory('$tools/msvc/VC/Tools/MSVC');
    String? vc = _latestDirectory(portable.path);
    String? sdk;
    if (vc != null) {
      sdk = '$tools/msvc/Windows Kits/10';
    } else if (get('VCToolsInstallDir') == null) {
      final programFiles = get('ProgramFiles(x86)');
      if (programFiles != null) {
        final vswhere = File(
          '$programFiles/Microsoft Visual Studio/Installer/vswhere.exe',
        );
        if (vswhere.existsSync()) {
          final found = Process.runSync(vswhere.path, [
            '-latest',
            '-products',
            '*',
            '-requires',
            'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
            '-property',
            'installationPath',
          ]);
          if (found.exitCode == 0 && '${found.stdout}'.trim().isNotEmpty) {
            vc = _latestDirectory('${'${found.stdout}'.trim()}/VC/Tools/MSVC');
            sdk = get('WindowsSdkDir') ?? '$programFiles/Windows Kits/10';
          }
        }
      }
    }
    if (vc != null && sdk != null) {
      final sdkLib = _latestDirectory('$sdk/Lib');
      if (sdkLib == null) {
        throw StateError('Windows SDK libraries missing: $sdk');
      }
      final version = Directory(sdkLib).uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      final compiler = '$vc/bin/Hostx64/x64';
      paths.addAll([compiler, '$sdk/bin/$version/x64']);
      put(
        'INCLUDE',
        '$vc/include;$sdk/Include/$version/ucrt;'
            '$sdk/Include/$version/shared;$sdk/Include/$version/um;'
            '$sdk/Include/$version/winrt',
      );
      put(
        'LIB',
        '$vc/lib/x64;$sdk/Lib/$version/ucrt/x64;$sdk/Lib/$version/um/x64',
      );
      put('VCToolsInstallDir', '$vc/');
      final redist = _latestDirectory(
        '${Directory(vc).parent.parent.parent.path}/Redist/MSVC',
      );
      if (redist != null) put('VCToolsRedistDir', '$redist/');
      put('WindowsSdkDir', '$sdk/');
      put('WindowsSDKVersion', '$version/');
      put('CC', '$compiler/cl.exe');
      put('CXX', '$compiler/cl.exe');
      put('AR', '$compiler/lib.exe');
      put('CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER', '$compiler/link.exe');
    }
  }
  paths.add(File(Platform.resolvedExecutable).parent.path);
  paths.add(get('PATH') ?? '');
  put('PATH', paths.join(Platform.isWindows ? ';' : ':'));
  if (Platform.isMacOS && get('MACOSX_DEPLOYMENT_TARGET') == null) {
    put('MACOSX_DEPLOYMENT_TARGET', '15.0');
  }
  return result;
}

String? _latestDirectory(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) return null;
  final versions = directory.listSync().whereType<Directory>().toList()
    ..sort((a, b) {
      final left = a.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last
          .split('.');
      final right = b.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last
          .split('.');
      for (var i = 0; i < left.length && i < right.length; i++) {
        final order = (int.tryParse(right[i]) ?? 0).compareTo(
          int.tryParse(left[i]) ?? 0,
        );
        if (order != 0) return order;
      }
      return right.length.compareTo(left.length);
    });
  return versions.isEmpty ? null : versions.first.path;
}

/// Windows resolves executables using the parent's PATH, so resolve our tools
/// explicitly before spawning with a discovered child environment.
String toolExecutable(String name, Map<String, String> environment) {
  if (name.contains('/') || name.contains('\\')) return name;
  final path =
      environment.entries
          .where(
            (e) => Platform.isWindows
                ? e.key.toUpperCase() == 'PATH'
                : e.key == 'PATH',
          )
          .map((e) => e.value)
          .firstOrNull ??
      '';
  for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
    if (directory.isEmpty) continue;
    for (final suffix
        in Platform.isWindows ? ['.exe', '.com', '.cmd', '.bat', ''] : ['']) {
      final file = File('$directory/$name$suffix');
      if (!file.existsSync()) continue;
      if (Platform.isWindows &&
          name.toLowerCase() == 'dart' &&
          suffix == '.bat') {
        final cached = File('$directory/cache/dart-sdk/bin/dart.exe');
        if (cached.existsSync()) return cached.absolute.path;
      }
      return file.absolute.path;
    }
  }
  return name;
}
