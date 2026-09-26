import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Detects accidental changes to the small pinned patch or copied upstream files.
/// Archive checksums were verified when importing; CI needs no network/cache.
void main() {
  var checked = 0;
  for (final name in [
    'accesskit_atspi_common-0.19.1',
    'accesskit_consumer-0.38.0',
    'accesskit_windows-0.34.0',
    'gpui-pre-0.3.6',
  ]) {
    final directory = Directory('native/vendor/$name');
    final manifest = jsonDecode(
      File('${directory.path}/UPSTREAM.json').readAsStringSync(),
    ) as Map;
    final original = Map<String, dynamic>.from(
      manifest['source_sha256'] as Map,
    );
    final patched = Map<String, dynamic>.from(
      manifest['patched_sha256'] as Map,
    );
    if (patched.keys.any((path) => !original.containsKey(path))) {
      throw StateError('Patch without upstream provenance: $name');
    }
    final expected = {...original, ...patched};
    for (final entry in expected.entries) {
      final file = File('${directory.path}/${entry.key}');
      final actual = sha256.convert(file.readAsBytesSync()).toString();
      if (actual != entry.value) {
        throw StateError('Unreviewed vendor change: ${file.path}');
      }
      checked++;
    }
    for (final file
        in directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()) {
      final relative = file.path
          .substring(directory.path.length + 1)
          .replaceAll(r'\', '/');
      if (relative != 'UPSTREAM.json' && !expected.containsKey(relative)) {
        throw StateError('Unrecorded vendor file: ${file.path}');
      }
    }
  }
  stdout.writeln('Verified $checked pinned accessibility dependency files.');
}
