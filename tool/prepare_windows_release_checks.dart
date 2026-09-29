import 'dart:io';

import 'src/archives.dart';
import 'src/commands.dart';
import 'src/toolchain.dart';
import 'src/windows_tool.dart';
import 'windows/common.dart';

String xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

Future<Directory> prepareWindowsReleaseChecks({
  required File archive,
  String vgpu = 'Enable',
}) async {
  if (!['Enable', 'Disable'].contains(vgpu)) {
    throw ArgumentError('vGPU must be Enable or Disable');
  }
  if (!await archive.exists()) {
    throw ArgumentError('Archive does not exist: ${archive.path}');
  }
  final parent = await Directory('build/release-checks')
      .create(recursive: true);
  final run = await parent.createTemp(
    '${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '')}-',
  );
  final input = await Directory('${run.path}/input').create();
  final output = await Directory('${run.path}/results').create();
  await archive.copy('${input.path}/candidate.zip');
  await File('tool/windows/ime-results.md')
      .copy('${output.path}/ime-results.md');
  final environment =
      await windowsQuery(['environment']) as Map<String, dynamic>;
  await File(await windowsTool())
      .copy('${input.path}/gpuidart-windows-tool.exe');
  await command(dartExecutable, [
    'compile',
    'exe',
    'tool/windows/sandbox_release_check.dart',
    '-o',
    '${input.path}/sandbox_release_check.exe',
  ]);
  // The runner itself must start before package extraction on an empty guest.
  final unpacked = await Directory.systemTemp.createTemp('gpuidart-candidate-');
  try {
    await extractZip(archive, unpacked);
    for (final name in [
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'msvcp140.dll',
    ]) {
      final runtime = File('${unpacked.path}/$name');
      if (await runtime.exists()) await runtime.copy('${input.path}/$name');
    }
  } finally {
    await unpacked.delete(recursive: true);
  }
  final hash = await fileHash(archive);
  await writeJson('${input.path}/candidate.json', {
    'prepared_at_utc': timestamp(),
    'original_archive': archive.absolute.path,
    'zip_sha256': hash,
    'host_identity': environment['machine_identity'],
    'identity_kind': environment['identity_kind'],
    'vgpu': vgpu,
  });
  await File('${run.path}/check.wsb').writeAsString('''<Configuration>
  <vGPU>$vgpu</vGPU>
  <Networking>Disable</Networking>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <PrinterRedirection>Disable</PrinterRedirection>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MemoryInMB>4096</MemoryInMB>
  <MappedFolders>
    <MappedFolder><HostFolder>${xml(input.absolute.path)}</HostFolder><SandboxFolder>C:\\GPUI-Input</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>${xml(output.absolute.path)}</HostFolder><SandboxFolder>C:\\GPUI-Results</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>C:\\GPUI-Input\\sandbox_release_check.exe</Command></LogonCommand>
</Configuration>
''');
  await File('${run.path}/README.txt')
      .writeAsString('''GPUI-Dart clean Windows check

Double-click check.wsb after enabling Windows Sandbox and completing any required restart.
The guest runs the packaged verifier automatically. Watch results/status.json.
Keep Sandbox open until status is passed or failed. The output remains on the host.
Input is read-only. Only this run's results folder is writable. No SDK or network is supplied.
Virtual GPU sharing: $vgpu. Disable uses software rendering.
This checks packaging, not physical-GPU performance.
Candidate SHA-256: $hash

For the manual screen check, open the extracted GPUI Dart candidate folder on the guest desktop.
Launch the executable named in manifest.json. Follow RELEASE-CHECKS.md.
This automated run does not claim human IME verification.
''');
  return run.absolute;
}

Future<void> main(List<String> arguments) async {
  final args = options(arguments, {'zip', 'vgpu'});
  final run = await prepareWindowsReleaseChecks(
    archive: File(args['zip'] ?? 'build/WatchlistMvp-windows-x64.zip'),
    vgpu: args['vgpu'] ?? 'Enable',
  );
  stdout.writeln(run.path);
}
