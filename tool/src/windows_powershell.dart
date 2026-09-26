import 'dart:io';

Future<ProcessResult> runWindowsPowerShell(
  List<String> arguments, {
  Map<String, String>? environment,
  String? workingDirectory,
}) {
  // Dart may inherit PowerShell 7 modules that Windows PowerShell cannot load.
  final childEnvironment = {...Platform.environment, ...?environment}
    ..removeWhere((key, _) => key.toUpperCase() == 'PSMODULEPATH');
  return Process.run(
    'powershell.exe',
    arguments,
    environment: childEnvironment,
    includeParentEnvironment: false,
    workingDirectory: workingDirectory,
  );
}
