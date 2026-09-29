import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

typedef Json = Map<String, dynamic>;

const implementations = ['rust', 'dart', 'solid', 'shell', 'flutter'];
const workloads = ['idle', 'scroll', 'cell', 'burst'];
const rates = {'idle': 0, 'scroll': 60, 'cell': 5, 'burst': 30, 'view': 1};
String repositoryRoot() {
  var dir = File.fromUri(Platform.script).parent;
  while (!File('${dir.path}/pubspec.yaml').existsSync() ||
      !Directory('${dir.path}/benchmarks').existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError('Cannot locate repository root');
    }
    dir = dir.parent;
  }
  return dir.path;
}

class Options {
  final Map<String, String> values = {};
  Options(List<String> args, {Set<String> flags = const {}}) {
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) {
        throw ArgumentError('Expected --option, got $arg');
      }
      final parts = arg.substring(2).split('=');
      final key = parts.first;
      if (values.containsKey(key)) {
        throw ArgumentError('Duplicate option --$key');
      }
      if (parts.length > 1) {
        values[key] = parts.sublist(1).join('=');
      } else if (flags.contains(key)) {
        values[key] = 'true';
      } else {
        if (++i >= args.length || args[i].startsWith('--')) {
          throw ArgumentError('Missing value for --$key');
        }
        values[key] = args[i];
      }
    }
  }
  String string(String key, [String? fallback]) =>
      values.remove(key) ?? fallback ?? (throw ArgumentError('Missing --$key'));
  bool flag(String key) {
    final value = values.remove(key);
    if (value != null && value != 'true' && value != 'false') {
      throw ArgumentError('--$key expects true or false');
    }
    return value == 'true';
  }

  int integer(String key, int fallback, int min, int max) {
    final value = int.parse(string(key, '$fallback'));
    if (value < min || value > max) {
      throw ArgumentError('--$key must be $min..$max');
    }
    return value;
  }

  List<String> selection([String fallback = 'rust,dart']) {
    final result = string('implementations', fallback).split(',');
    if (result.toSet().length != result.length ||
        result.any((v) => !implementations.contains(v))) {
      throw ArgumentError(
        'Implementations must be distinct and selected from ${implementations.join(',')}',
      );
    }
    return result;
  }

  void done() {
    if (values.isNotEmpty) {
      throw ArgumentError('Unknown options: ${values.keys.join(', ')}');
    }
  }
}

dynamic readJson(String path) =>
    jsonDecode(File(path).readAsStringSync().replaceFirst('\ufeff', ''));
void writeJson(String path, Object? value) {
  File(path).parent.createSync(recursive: true);
  File(
    path,
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');
}

List<dynamic> array(dynamic value) => value == null
    ? []
    : value is List
    ? value
    : [value];
dynamic at(dynamic value, String path) {
  for (final key in path.split('.')) {
    if (value is Map) {
      value = value[key];
    } else {
      return null;
    }
  }
  return value;
}

num number(dynamic value) => value is num ? value : num.tryParse('$value') ?? 0;
List<File> namedFiles(String path, String name) =>
    Directory(path)
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last == name)
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
Future<String> hash(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

// PresentMon fields may be quoted, including commas and embedded newlines.
List<Json> readCsv(String path) {
  final text = File(path).readAsStringSync().replaceFirst('\ufeff', '');
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (c == ',' || c == '\n' || c == '\r')) {
      row.add(field.toString());
      field = StringBuffer();
      if (c != ',') {
        if (row.any((s) => s.isNotEmpty)) rows.add(row);
        row = [];
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      }
    } else {
      field.write(c);
    }
  }
  if (quoted) throw FormatException('Unterminated CSV quote in $path');
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  if (rows.isEmpty) return [];
  final headers = rows.removeAt(0);
  return rows.map((r) {
    if (r.length != headers.length) {
      throw FormatException('CSV column count mismatch in $path');
    }
    return <String, dynamic>{
      for (var i = 0; i < headers.length; i++) headers[i]: r[i],
    };
  }).toList();
}

void writeCsv(String path, List<Json> rows) {
  if (rows.isEmpty) return;
  String escape(Object? v) => '"${('$v').replaceAll('"', '""')}"';
  final keys = rows.first.keys.toList();
  File(path).writeAsStringSync(
    '${[keys.map(escape).join(','), ...rows.map((row) => keys.map((k) => escape(row[k])).join(','))].join('\n')}\n',
  );
}

List<num> column(Iterable<Json> rows, String key) => rows
    .map((row) => num.tryParse('${row[key]}'))
    .whereType<num>()
    .where((n) => n.isFinite && n >= 0)
    .toList();
Json? distribution(Iterable<dynamic> values) {
  final sorted = values.whereType<num>().toList()..sort();
  if (sorted.isEmpty) return null;
  num percentile(double p) => sorted[(p * sorted.length).ceil() - 1];
  return {
    'samples': sorted.length,
    'p50': percentile(.5),
    'p95': percentile(.95),
    'p99': percentile(.99),
    'max': sorted.last,
  };
}

Json? acrossRuns(Iterable<dynamic> values) {
  final sorted = values.whereType<num>().toList()..sort();
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  return {
    'runs': sorted.length,
    'median': sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2,
    'min': sorted.first,
    'max': sorted.last,
  };
}

// .NET's Math.Round uses ties to even; Dart's round uses ties away from zero.
num roundEven(num value, [int digits = 0]) {
  final scale = [1, 10, 100, 1000][digits];
  final scaled = value * scale;
  final lower = scaled.floor();
  return ((scaled - lower == .5)
          ? (lower.isEven ? lower : lower + 1)
          : scaled.round()) /
      scale;
}

Future<void> guarded(Future<void> Function() body) async {
  try {
    await body();
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
