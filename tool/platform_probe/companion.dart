import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

String label() => 'probe-before';

Future<void> main(List<String> args) async {
  final serve = args.contains('--serve');
  final native = args.first;
  final process = await Process.start(native, ['--stdio']);
  final ready = Completer<void>();
  final checkpoints = <Map<String, dynamic>>[];
  final pending = <Completer<Map<String, dynamic>>>[];
  Map<String, dynamic>? applied;
  var ticks = 0;
  final heartbeat = Timer.periodic(
    const Duration(milliseconds: 20),
    (_) => ticks++,
  );
  var exited = false;
  final deadline = Timer(const Duration(seconds: 35), () {
    process.kill(ProcessSignal.sigkill);
    stderr.writeln('Companion probe deadline');
    exit(124);
  });
  final errors = process.stderr.listen(stderr.add);
  final outputDone = Completer<void>();
  final events = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) {
          stdout.writeln(line);
          if (!line.startsWith('{')) return;
          final event = jsonDecode(line) as Map<String, dynamic>;
          checkpoints.add(event);
          if (event['stage'] == 'native_callback' &&
              event['detail']['value'] == 1 &&
              !ready.isCompleted) {
            ready.complete();
          }
          if (event['stage'] == 'label_applied') {
            applied = {
              ...event['detail'] as Map<String, dynamic>,
              'native_pid': event['pid'],
            };
            if (pending.isNotEmpty) pending.removeAt(0).complete(applied);
          }
        },
        onDone: outputDone.complete,
        onError: outputDone.completeError,
      );
  Future<Map<String, dynamic>> publish() async {
    final completion = Completer<Map<String, dynamic>>();
    pending.add(completion);
    process.stdin.writeln(jsonEncode({'op': 'label', 'value': label()}));
    await process.stdin.flush();
    return completion.future.timeout(const Duration(seconds: 5));
  }

  void close() {
    if (!exited) process.stdin.writeln(jsonEncode({'op': 'close'}));
  }

  try {
    await ready.future.timeout(const Duration(seconds: 15));
    await publish();
    registerExtension(
      'ext.gpuidart.inspect',
      (_, _) async => ServiceExtensionResponse.result(
        jsonEncode({'applied': applied, 'dart_pid': pid, 'ticks': ticks}),
      ),
    );
    registerExtension(
      'ext.gpuidart.reassemble',
      (_, _) async =>
          ServiceExtensionResponse.result(jsonEncode(await publish())),
    );
    registerExtension('ext.gpuidart.close', (_, _) async {
      close();
      return ServiceExtensionResponse.result('{"closing":true}');
    });
    if (!serve) {
      await Future<void>.delayed(const Duration(seconds: 2));
      close();
    }
    final status = await process.exitCode;
    exited = true;
    await outputDone.future;
    final beforeQuit = checkpoints
        .where((event) => event['stage'] == 'before_quit')
        .firstOrNull;
    final uiThread = checkpoints
        .where((event) => event['stage'] == 'app_callback')
        .firstOrNull;
    final passed =
        status == 0 &&
        ticks > 0 &&
        applied != null &&
        beforeQuit?['detail']['resized_render'] == true &&
        (!Platform.isMacOS || uiThread?['main_thread'] == 1);
    stdout.writeln(
      jsonEncode({
        'stage': 'companion_complete',
        'detail': {
          'passed': passed,
          'native_exit': status,
          'ticks': ticks,
          'dart_pid': pid,
          'native_pid': process.pid,
          'applied': applied,
        },
      }),
    );
    if (!passed) exitCode = 1;
  } finally {
    if (!exited) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 5));
    }
    deadline.cancel();
    heartbeat.cancel();
    await errors.cancel();
    await events.cancel();
  }
}
