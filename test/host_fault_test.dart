@TestOn('windows || linux || mac-os')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/platform.dart';
import 'package:test/test.dart';

void main() {
  final path = File('.cache/${nativeLibraryName('fault_host')}').absolute.path;
  late DynamicLibrary fixture;
  late int Function() allocated, freed, destroyed, earlyDestroy;
  setUpAll(() {
    fixture = DynamicLibrary.open(path);
    int Function() counter(String name) => fixture
        .lookupFunction<Uint64 Function(), int Function()>('fixture_$name');
    allocated = counter('allocated');
    freed = counter('freed');
    destroyed = counter('destroyed');
    earlyDestroy = counter('early_destroy');
  });
  tearDown(() {
    expect(
      earlyDestroy(),
      0,
      reason: 'Must wait for gd_run before destruction',
    );
    expect(freed(), allocated(), reason: 'Every native event must be freed');
  });

  Future<GpuiHost> open(
    String mode, {
    List<TableDataset> datasets = const [],
  }) => GpuiHost.open(
    UiText('mode', mode),
    libraryPath: path,
    datasets: datasets,
    requestTimeout: const Duration(milliseconds: 500),
    shutdownTimeout: const Duration(milliseconds: 150),
  );
  TableDataset records() => TableDataset(
    'records',
    columns: ['Value'],
    rows: [
      ['before'],
    ],
  );

  test('missing ready acknowledgement closes and releases startup', () async {
    final before = destroyed();
    await expectLater(open('no_ready'), throwsA(isA<TimeoutException>()));
    expect(destroyed(), before + 1);
  });

  test(
    'malformed event fails all pending requests and closes the host',
    () async {
      final host = await open('malformed');
      final diagnostic = expectLater(
        host.diagnose('inspect'),
        throwsFormatException,
      );
      final done = expectLater(host.done, throwsFormatException);
      await expectLater(
        host.publish(const UiText('label', 'update')),
        throwsFormatException,
      );
      await diagnostic;
      await done;
      expect(
        () => host.publish(const UiText('label', 'late')),
        throwsStateError,
      );
    },
  );

  for (final mode in ['drop_snapshot', 'drop_dataset', 'drop_diagnostic']) {
    test('$mode reports a deadline and stops further transactions', () async {
      final dataset = records();
      final host = await open(mode, datasets: [dataset]);
      final done = expectLater(host.done, throwsA(isA<TimeoutException>()));
      final Future<Object?> pending = switch (mode) {
        'drop_snapshot' => host.publish(const UiText('label', 'update')),
        'drop_dataset' => host.editDataset(dataset, [
          const CellEdit(0, 0, 'after'),
        ]),
        _ => host.diagnose('inspect'),
      };
      await expectLater(pending, throwsA(isA<TimeoutException>()));
      await done;
      expect(dataset.cell(0, 0), 'before');
      expect(dataset.revision, 1);
    });
  }

  test('mismatched dataset acknowledgement never commits Dart state', () async {
    final dataset = records();
    final host = await open('mismatch', datasets: [dataset]);
    final done = expectLater(host.done, throwsFormatException);
    await expectLater(
      host.editDataset(dataset, [const CellEdit(0, 0, 'after')]),
      throwsFormatException,
    );
    await done;
    expect(dataset.cell(0, 0), 'before');
    expect(dataset.revision, 1);
  });

  test(
    'native failure after ready preserves the error while draining closed',
    () async {
      final host = await open('native_error');
      final failure = throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'injected native failure',
        ),
      );
      final done = expectLater(host.done, failure);
      await expectLater(host.publish(const UiText('label', 'update')), failure);
      await done;
    },
  );

  for (final operation in ['snapshot', 'dataset', 'diagnostic']) {
    test('caught panic during $operation submission closes the host', () async {
      final dataset = records();
      final host = await open('submit_panic', datasets: [dataset]);
      final done = expectLater(host.done, throwsStateError);
      await expectLater(
        () => switch (operation) {
          'snapshot' => host.publish(const UiText('label', 'update')),
          'dataset' => host.editDataset(dataset, [
            const CellEdit(0, 0, 'after'),
          ]),
          _ => host.diagnose('inspect'),
        },
        throwsStateError,
      );
      await done;
      expect(dataset.cell(0, 0), 'before');
      expect(dataset.revision, 1);
    });
  }

  test('runner exit without closed has a bounded failure', () async {
    final before = destroyed();
    final host = await open('no_closed');
    await expectLater(
      host.close(),
      throwsA(anyOf(isA<StateError>(), isA<TimeoutException>())),
    );
    // The public shutdown deadline can precede the event-drain deadline.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(destroyed(), before + 1);
  });

  test(
    'shutdown deadline retains memory until the native loop returns',
    () async {
      final before = destroyed();
      final host = await open('delayed_exit');
      await expectLater(host.close(), throwsA(isA<TimeoutException>()));
      expect(destroyed(), before);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(destroyed(), before + 1);
    },
  );
}
