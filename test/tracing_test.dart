@TestOn('windows')
library;

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/tracing.dart';
import 'package:test/test.dart';

void main() {
  test('application spans are bounded and preserve exceptions', () {
    expect(() => GpuiTrace(capacity: 0), throwsRangeError);
    expect(() => GpuiTrace(capacity: 8193), throwsRangeError);
    final trace = GpuiTrace(capacity: 2);
    expect(trace.measure('build', () => 42), 42);
    expect(
      () => trace.measure('failed', () => throw StateError('secret')),
      throwsStateError,
    );
    trace.measure('overflow', () {});
    final data = trace.toJson();
    final records = data['records'] as List;
    expect(records, hasLength(2));
    expect(records[1]['status'], -1);
    expect(data.toString(), isNot(contains('secret')));
    expect((data['metadata'] as Map)['dart_dropped'], 1);
    expect((data['metadata'] as Map)['capture_complete'], false);
    expect(() => trace.measure('', () {}), throwsArgumentError);
    for (final record in records) {
      expect(record['end'], greaterThanOrEqualTo(record['start'] as int));
    }
  });

  test(
    'tracing needs optional exports and cannot reuse a host attempt',
    () async {
      final trace = GpuiTrace();
      Future<GpuiHost> open() => GpuiHost.open(
        const UiText('mode', 'normal'),
        libraryPath: '.cache/fault_host.dll',
        trace: trace,
      );
      await expectLater(
        open(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('does not support tracing'),
          ),
        ),
      );
      await expectLater(
        open(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('separate trace'),
          ),
        ),
      );
      var built = false;
      await expectLater(
        GpuiHost.openView(() {
          built = true;
          return const UiText('mode', 'normal');
        }, trace: trace),
        throwsStateError,
      );
      expect(built, false);
    },
  );
}
