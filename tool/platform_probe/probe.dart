import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:gpuidart/src/windows.dart';

typedef Callback = Void Function(Uint32);

int codeSignal() => 7;

Future<int> runWorker(String path, int address) => Isolate.run(() {
  report('dart_runner_thread', thread(path));
  final run = DynamicLibrary.open(path)
      .lookupFunction<
        Int32 Function(Pointer<NativeFunction<Callback>>),
        int Function(Pointer<NativeFunction<Callback>>)
      >('gdp_run');
  return run(Pointer.fromAddress(address));
}, debugName: 'gpui-native-loop');

Map<String, Object> thread(String path) {
  final lib = DynamicLibrary.open(path);
  return {
    'pid': pid,
    'thread': lib.lookupFunction<Uint64 Function(), int Function()>(
      'gdp_thread_id',
    )(),
    'main_thread': lib.lookupFunction<Int32 Function(), int Function()>(
      'gdp_is_main_thread',
    )(),
  };
}

void report(String stage, Object detail) => stdout.writeln(
  jsonEncode({
    'stage': stage,
    'detail': detail,
    'dart': Platform.version,
    'os': Platform.operatingSystem,
    'executable': Platform.resolvedExecutable,
  }),
);

Future<void> main(List<String> args) async {
  if (Platform.isWindows) configureWindowsDpi();
  if (args.isEmpty ||
      args.length > 2 ||
      (args.length == 2 && args.last != '--serve')) {
    throw ArgumentError('Supply a probe library path and optional --serve');
  }
  final serve = args.length == 2;
  final path = File(args.first).absolute.path;
  report('dart_application_thread', thread(path));
  final lib = DynamicLibrary.open(path);
  final signal = lib.lookupFunction<Void Function(Uint32), void Function(int)>(
    'gdp_signal',
  );
  final callbacks = <int>[];
  final pending = <int, Completer<void>>{};
  final echoed = Completer<void>();
  final callback = NativeCallable<Callback>.listener((int value) {
    callbacks.add(value);
    report('dart_callback', {'value': value, ...thread(path)});
    if (value == 1) signal(codeSignal());
    pending.remove(value)?.complete();
    if (value == 7 && !echoed.isCompleted) echoed.complete();
  });
  final address = callback.nativeFunction.address;
  if (serve) {
    lib.lookupFunction<Void Function(Uint32), void Function(int)>(
      'gdp_keep_alive',
    )(1);
    registerExtension(
      'ext.gpuidart.inspect',
      (_, _) async => ServiceExtensionResponse.result(
        jsonEncode({
          'pid': pid,
          'callbacks': callbacks,
          'signal': codeSignal(),
        }),
      ),
    );
    registerExtension('ext.gpuidart.reassemble', (_, _) async {
      await echoed.future;
      final value = codeSignal();
      final completion = Completer<void>();
      pending[value] = completion;
      signal(value);
      await completion.future.timeout(const Duration(seconds: 5));
      return ServiceExtensionResponse.result(
        jsonEncode({'signal': value, 'pid': pid}),
      );
    });
    registerExtension('ext.gpuidart.close', (_, _) async {
      signal(99);
      return ServiceExtensionResponse.result('{"closing":true}');
    });
  }
  final timer = Stopwatch()..start();
  var ticks = 0;
  final heartbeat = Timer.periodic(
    const Duration(milliseconds: 20),
    (_) => ticks++,
  );
  // This timeout exits the probe process. It must never free a live callback.
  final deadline = Timer(const Duration(seconds: 30), () {
    report('deadline', {'ticks': ticks});
    exit(124);
  });
  final status = await runWorker(path, address);
  if (status == 0) await echoed.future.timeout(const Duration(seconds: 2));
  heartbeat.cancel();
  deadline.cancel();
  callback.close();
  report('dart_complete', {
    'status': status,
    'callbacks': callbacks,
    'heartbeat_ticks': ticks,
    'elapsed_ms': timer.elapsedMilliseconds,
  });
  // Rejection is useful evidence but is not a successful Dart launcher.
  if (status != 0 || ticks == 0 || !callbacks.contains(7)) exitCode = 1;
}
