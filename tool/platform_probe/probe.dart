import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:gpuidart/src/windows.dart';

typedef Callback = Void Function(Uint32);

Future<int> runWorker(String path, int address) => Isolate.run(() {
  report('dart_runner_thread', thread(path));
  final run = DynamicLibrary.open(path)
      .lookupFunction<
        Int32 Function(Pointer<NativeFunction<Callback>>),
        int Function(Pointer<NativeFunction<Callback>>)
      >('gdp_run');
  return run(Pointer.fromAddress(address));
});

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
  if (args.length != 1) {
    throw ArgumentError('Supply an absolute probe library path');
  }
  final path = File(args.single).absolute.path;
  report('dart_application_thread', thread(path));
  final lib = DynamicLibrary.open(path);
  final signal = lib.lookupFunction<Void Function(Uint32), void Function(int)>(
    'gdp_signal',
  );
  final callbacks = <int>[];
  final echoed = Completer<void>();
  final callback = NativeCallable<Callback>.listener((int value) {
    callbacks.add(value);
    report('dart_callback', {'value': value, ...thread(path)});
    if (value == 1) signal(7);
    if (value == 7 && !echoed.isCompleted) echoed.complete();
  });
  final address = callback.nativeFunction.address;
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
