import 'dart:convert';
import 'dart:io';

import '../src/archives.dart';
import 'common.dart';

Future<void> main(List<String> arguments) async {
  final args = options(arguments, {'input', 'output'});
  final input = args['input'] ?? r'C:\GPUI-Input';
  final output = args['output'] ?? r'C:\GPUI-Results';
  final statusPath = '$output/status.json';
  final status = <String, dynamic>{
    'started_at_utc': timestamp(),
    'status': 'running',
    'passed': false,
  };
  await writeJson(statusPath, status);
  try {
    final identity = await readJson('$input/candidate.json');
    final inspected = await runTimed('$input/gpuidart-windows-tool.exe', [
      'environment',
    ]);
    if (inspected.exitCode != 0) throw StateError('${inspected.stderr}');
    final environment =
        jsonDecode('${inspected.stdout}') as Map<String, dynamic>;
    if (Platform.environment['USERNAME'] != 'WDAGUtilityAccount' ||
        environment['model'] != 'Virtual Machine' ||
        environment['machine_identity'] == identity['host_identity'] ||
        environment['identity_kind'] != identity['identity_kind']) {
      throw StateError(
        'This runner requires a Windows Sandbox guest distinct from the preparation host.',
      );
    }
    final archive = File('$input/candidate.zip');
    final hash = await fileHash(archive);
    if (hash != identity['zip_sha256']) {
      throw StateError('Candidate ZIP hash differs from prepared identity.');
    }
    final sdkCommands = <Map<String, String>>[];
    for (final command in ['dart', 'flutter', 'rustc', 'cargo', 'cl']) {
      final result = await Process.run(
        '${Platform.environment['SystemRoot']}\\System32\\where.exe',
        [command],
      );
      if (result.exitCode == 0) {
        sdkCommands.add({'Name': command, 'Source': '${result.stdout}'.trim()});
      }
    }
    await writeJson('$output/environment.json', {
      ...environment,
      'provisioning': 'Fresh Windows Sandbox, network disabled, package and test runner only',
      'configured_vgpu': identity['vgpu'],
      'zip_sha256': hash,
      'developer_commands': sdkCommands,
    });
    if (sdkCommands.isNotEmpty) {
      throw StateError('Unexpected developer SDK commands in fresh guest.');
    }
    final package = Directory(
      '${Platform.environment['USERPROFILE']}/Desktop/GPUI Dart candidate',
    );
    await package.create();
    await extractZip(archive, package);
    final result = await runTimed('${package.path}/verify.exe', [
      '--environment=clean_vm',
      '--report=$output/verification.json',
    ]);
    await File('$output/verify.stdout.log').writeAsString('${result.stdout}');
    await File('$output/verify.stderr.log').writeAsString('${result.stderr}');
    if (result.exitCode != 0) {
      throw StateError(
        'Packaged verifier exited ${result.exitCode}. See verify.stderr.log.',
      );
    }
    if ((await readJson('$output/verification.json'))['passed'] != true) {
      throw StateError('Packaged verifier did not pass.');
    }
    status.addAll({
      'status': 'passed',
      'passed': true,
      'zip_sha256': hash,
      'human_ime': 'pending',
    });
  } catch (error) {
    status.addAll({'status': 'failed', 'error': '$error'});
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    status['finished_at_utc'] = timestamp();
    await writeJson(statusPath, status);
  }
}
