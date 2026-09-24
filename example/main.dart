import 'dart:async';

import 'package:gpuidart/gpuidart.dart';

Future<void> main() async {
  var count = 0;
  var name = '';
  var status = 'Waiting for an asynchronous update...';
  final rows = List.generate(
    10000,
    (i) => ['$i', 'Instrument $i', '${100 + i / 100}'],
  );
  UiNode build() => UiColumn('main', [
    const UiText('title', 'Dart application · GPUI Kit controls'),
    UiText('count', 'Count: $count'),
    const UiButton('increment', 'Increment'),
    const UiInput('name', placeholder: 'Type here; state survives updates'),
    UiText('greeting', name.isEmpty ? 'Enter a name' : 'Hello, $name'),
    UiText('status', status),
    UiTable('quotes', columns: ['ID', 'Instrument', 'Price'], rows: rows),
  ]);

  final host = await GpuiHost.open(build());
  Future<void> handle(GpuiEvent event) async {
    if (event.type == 'click' && event.id == 'increment') {
      count++;
      await host.publish(build());
    } else if (event.type == 'input' && event.id == 'name') {
      name = event.value!;
      await host.publish(build());
    } else if (event.type == 'error') {
      print(event);
    }
  }

  final subscription = host.events.listen((event) {
    unawaited(handle(event).catchError((Object error) => print(error)));
  });
  final timer = Timer(const Duration(seconds: 2), () async {
    status = 'Dart Future/Timer completed while GPUI was running';
    try {
      await host.publish(build());
    } on StateError {
      /* Window closed. */
    }
  });
  try {
    await host.done;
  } finally {
    timer.cancel();
    await subscription.cancel();
  }
}
