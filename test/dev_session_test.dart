import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/dev_session.dart';

void main() {
  late Directory directory;
  late File serviceInfo;
  late Completer<int> exitCode;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gpuidart-vm-test-');
    serviceInfo = File('${directory.path}/service.json');
    exitCode = Completer<int>();
  });
  tearDown(() async {
    if (!exitCode.isCompleted) exitCode.complete(0);
    await removeSessionDirectory(directory);
  });

  test(
    'service discovery waits through empty and partial JSON writes',
    () async {
      await serviceInfo.writeAsString('');
      final discovery = waitForVmServiceUri(
        serviceInfo,
        deadline: DateTime.now().add(const Duration(seconds: 3)),
        exitCode: exitCode.future,
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      await serviceInfo.writeAsString('{"uri":');
      await Future<void>.delayed(const Duration(milliseconds: 70));
      await serviceInfo.writeAsString('{"uri":"http://127.0.0.1:1234/token/"}');
      expect(await discovery, Uri.parse('http://127.0.0.1:1234/token/'));
    },
  );

  test('service discovery reports early process exit', () async {
    await serviceInfo.writeAsString('{"uri":');
    final discovery = waitForVmServiceUri(
      serviceInfo,
      deadline: DateTime.now().add(const Duration(seconds: 3)),
      exitCode: exitCode.future,
    );
    final expectation = expectLater(
      discovery,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('code 7'),
        ),
      ),
    );
    exitCode.complete(7);
    await expectation;
  });

  test(
    'service discovery stops waiting for an incomplete file at its deadline',
    () async {
      await serviceInfo.writeAsString('{"uri":');
      await expectLater(
        waitForVmServiceUri(
          serviceInfo,
          deadline: DateTime.now().add(const Duration(milliseconds: 100)),
          exitCode: exitCode.future,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('startup deadline'),
          ),
        ),
      );
    },
  );
}
