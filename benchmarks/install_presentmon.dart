import 'dart:io';

import 'src/common.dart';

Future<void> main(List<String> args) => guarded(() async {
  Options(args).done();
  final destination = File(
    '${repositoryRoot()}/.tools/presentmon/PresentMon.exe',
  );
  destination.parent.createSync(recursive: true);
  const expected =
      'b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af';
  if (!destination.existsSync()) {
    final temporary = File('${destination.path}.download');
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://github.com/GameTechDev/PresentMon/releases/download/v2.6.0/PresentMon-2.6.0-x64.exe',
        ),
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'PresentMon download returned ${response.statusCode}',
        );
      }
      await response.pipe(temporary.openWrite());
      if (await hash(temporary.path) != expected) {
        throw StateError('PresentMon does not match the pinned 2.6.0 binary');
      }
      temporary.renameSync(destination.path);
    } finally {
      client.close();
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
  if (await hash(destination.path) != expected) {
    throw StateError('PresentMon does not match the pinned 2.6.0 binary');
  }
  stdout.writeln(destination.path);
});
