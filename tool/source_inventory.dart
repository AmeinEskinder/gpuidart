import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

const languages = {
  '.dart': 'Dart',
  '.rs': 'Rust',
  '.ps1': 'PowerShell',
  '.psm1': 'PowerShell',
  '.cs': 'C#',
  '.csx': 'C#',
  '.swift': 'Swift',
  '.py': 'Python',
  '.pyw': 'Python',
  '.js': 'JavaScript',
  '.jsx': 'JavaScript',
  '.mjs': 'JavaScript',
  '.ts': 'TypeScript',
  '.tsx': 'TypeScript',
  '.c': 'C',
  '.h': 'C',
  '.cpp': 'C++',
  '.cc': 'C++',
  '.hpp': 'C++',
  '.m': 'Objective-C',
  '.mm': 'Objective-C++',
  '.sh': 'Shell',
  '.bash': 'Shell',
  '.rb': 'Ruby',
  '.go': 'Go',
  '.java': 'Java',
  '.kt': 'Kotlin',
  '.metal': 'Metal',
  '.wgsl': 'WGSL',
  '.glsl': 'GLSL',
};

enum SourceScope { maintained, vendor, comparison, interface, evidence }

SourceScope scopeOf(String path) {
  if (path.startsWith('native/vendor/')) return SourceScope.vendor;
  if (path.startsWith('reports/')) return SourceScope.evidence;
  if (path == 'native/include/gpuidart.h') return SourceScope.interface;
  for (final fixture in ['native', 'dart', 'flutter', 'solid', 'shell']) {
    if (path.startsWith('benchmarks/$fixture/')) {
      return SourceScope.comparison;
    }
  }
  return SourceScope.maintained;
}

Future<String> git(List<String> args) async {
  final result = await Process.run('git', args);
  if (result.exitCode != 0) throw StateError('git: ${result.stderr}');
  return result.stdout as String;
}

Future<Map<String, Object?>> inventory(String revision) async {
  final commit = (await git(['rev-parse', '--verify', '$revision^{commit}']))
      .trim();
  final tree = await git(['ls-tree', '-rlz', commit]);
  final sources = <({String path, String object, int bytes})>[];
  var trackedFiles = 0;
  for (final record in tree.split('\u0000').where((s) => s.isNotEmpty)) {
    trackedFiles++;
    final parts = record.split('\t');
    final path = parts.skip(1).join('\t');
    if (!languages.containsKey(p.extension(path).toLowerCase())) continue;
    final metadata = parts.first.split(RegExp(r'\s+'));
    if (metadata[1] != 'blob' || !metadata[0].startsWith('100')) {
      throw StateError('Source must be a regular Git blob: $path');
    }
    sources.add((
      path: path,
      object: metadata[2],
      bytes: int.parse(metadata[3]),
    ));
  }
  final process = await Process.start('git', ['cat-file', '--batch']);
  final output = process.stdout.fold(BytesBuilder(copy: false), (bytes, chunk) {
    bytes.add(chunk);
    return bytes;
  });
  final errors = process.stderr.transform(utf8.decoder).join();
  for (final source in sources) {
    process.stdin.writeln(source.object);
  }
  await process.stdin.close();
  final bytes = (await output).takeBytes();
  if (await process.exitCode != 0) throw StateError(await errors);
  final files = <Map<String, Object>>[];
  var offset = 0;
  for (final source in sources) {
    final headerEnd = bytes.indexOf(10, offset);
    if (headerEnd < 0) throw StateError('Truncated Git object header');
    final header = ascii.decode(bytes.sublist(offset, headerEnd)).split(' ');
    if (header.length != 3 ||
        header[0] != source.object ||
        header[1] != 'blob' ||
        int.parse(header[2]) != source.bytes) {
      throw StateError('Unexpected Git object for ${source.path}');
    }
    offset = headerEnd + 1;
    final end = offset + source.bytes;
    if (end >= bytes.length || bytes[end] != 10) {
      throw StateError('Truncated Git object for ${source.path}');
    }
    var lines = 0;
    for (var i = offset; i < end; i++) {
      if (bytes[i] == 10) lines++;
    }
    if (end > offset && bytes[end - 1] != 10) lines++;
    files.add({
      'path': source.path,
      'object': source.object,
      'language': languages[p.extension(source.path).toLowerCase()]!,
      'scope': scopeOf(source.path).name,
      'bytes': source.bytes,
      'lines': lines,
    });
    offset = end + 1;
  }
  final violations = files
      .where(
        (file) =>
            file['scope'] == SourceScope.maintained.name &&
            file['language'] != 'Dart' &&
            file['language'] != 'Rust',
      )
      .toList();
  Map<String, Object> totals(Iterable<Map<String, Object>> selected) {
    final byLanguage = <String, Map<String, num>>{};
    var totalBytes = 0;
    for (final file in selected) {
      final values = byLanguage.putIfAbsent(
        file['language'] as String,
        () => {'files': 0, 'bytes': 0, 'lines': 0},
      );
      values['files'] = values['files']! + 1;
      values['bytes'] = values['bytes']! + (file['bytes'] as int);
      values['lines'] = values['lines']! + (file['lines'] as int);
      totalBytes += file['bytes'] as int;
    }
    for (final values in byLanguage.values) {
      values['byte_percent'] = totalBytes == 0
          ? 0
          : values['bytes']! * 100 / totalBytes;
    }
    return {'source_bytes': totalBytes, 'languages': byLanguage};
  }

  return {
    'source_commit': commit,
    'method': 'Tracked regular source blobs at the stated Git commit. Byte and line counts use Git object contents, independent of checkout line endings. Percentages use recognized source bytes, not all repository assets. This is not GitHub Linguist classification.',
    'tracked_files': trackedFiles,
    'extensions': languages,
    'scope_rules': {
      'vendor':
          'native/vendor/**; upstream sources and documented adapter patches',
      'comparison': 'benchmarks/{native,dart,flutter,solid,shell}/**; comparison applications. JS/TS execute in the compared engines; Flutter Windows runner files belong to that fixture.',
      'interface': 'native/include/gpuidart.h; C ABI declarations only, implemented in Rust',
      'evidence': 'reports/**; retained historical evidence',
      'maintained': 'All other recognized source files, including CLI, framework, tests, examples, benchmark drivers and analysis',
    },
    'repository_source': totals(files),
    'by_scope': {
      for (final scope in SourceScope.values)
        scope.name: totals(files.where((file) => file['scope'] == scope.name)),
    },
    'passed': violations.isEmpty,
    'violations': violations,
    'files': files,
  };
}

Future<void> main(List<String> args) async {
  var revision = 'HEAD';
  String? report;
  for (final arg in args) {
    if (arg.startsWith('--ref=')) {
      revision = arg.substring(6);
    } else if (arg.startsWith('--report=')) {
      report = arg.substring(9);
    } else {
      throw ArgumentError(
        'Usage: source_inventory.dart [--ref=REVISION] [--report=FILE]',
      );
    }
  }
  final result = await inventory(revision);
  final json = '${const JsonEncoder.withIndent('  ').convert(result)}\n';
  if (report == null) {
    stdout.write(json);
  } else {
    final file = File(report);
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
    stdout.writeln('Source inventory: passed=${result['passed']}; $report');
  }
  if (result['passed'] != true) exitCode = 1;
}
