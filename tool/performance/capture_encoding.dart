import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'snapshot_fixture.dart';

Object encodingFixture(String name) => switch (name) {
  'cell' => {
    'op': 'cells',
    'dataset': 'records',
    'base_revision': 1,
    'revision': 2,
    'cells': [
      {'row': 42, 'column': 1, 'value': '東京 / café / 😀'},
    ],
  },
  'snapshot' => {'revision': 2, 'root': SnapshotFixture(2048).build().toJson()},
  'initial' => {
    'snapshot': {
      'revision': 1,
      'root': {'kind': 'table', 'id': 'table', 'dataset': 'records'},
    },
    'datasets': [
      {
        'id': 'records',
        'revision': 1,
        'data': {
          'columns': ['ID', 'Value'],
          'rows': List.generate(100000, (i) => ['$i', 'Row $i']),
        },
      },
    ],
  },
  'unicode' => {
    'rows': List.generate(100000, (i) => ['$i', '東京 café 😀 "\\\n $i']),
  },
  _ => throw ArgumentError('Unknown encoding fixture'),
};

void verifyEncoding() {
  final utf8Json = JsonUtf8Encoder();
  for (final value in <Object?>[
    null,
    true,
    false,
    0,
    -1,
    1.25,
    -0.0,
    1e100,
    for (var i = 0; i < 0x10000; i += 31) String.fromCharCode(i),
    '\uD800',
    '\uDC00',
    '\uD800x\uDC00',
    '\u2028\u2029',
    {
      'null': null,
      'nested': [true, 42, '東京😀', '\n\t\r\b\f\\"'],
    },
    for (final name in ['cell', 'snapshot', 'initial', 'unicode'])
      encodingFixture(name),
  ]) {
    final old = utf8.encode(jsonEncode(value));
    final next = utf8Json.convert(value);
    if (old.length != next.length) throw StateError('Encoded lengths differ');
    for (var i = 0; i < old.length; i++) {
      if (old[i] != next[i]) throw StateError('Encoded bytes differ at $i');
    }
  }
  final cyclic = <Object>[];
  cyclic.add(cyclic);
  for (final invalid in [
    double.nan,
    double.infinity,
    cyclic,
    {1: 'bad key'},
  ]) {
    for (final encode in [
      (Object value) => utf8.encode(jsonEncode(value)),
      (Object value) => utf8Json.convert(value),
    ]) {
      var rejected = false;
      try {
        encode(invalid);
      } on JsonUnsupportedObjectError {
        rejected = true;
      }
      if (!rejected) throw StateError('Invalid value was accepted');
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.length == 1 && args[0] == '--self-test') {
    verifyEncoding();
    stdout.writeln('Byte equivalence and invalid-value checks passed');
    return;
  }
  if (args.length != 3 || !['legacy', 'fused'].contains(args[1])) {
    throw ArgumentError(
      'Usage: capture_encoding.dart NEW_OUTPUT_JSON legacy|fused cell|snapshot|initial|unicode',
    );
  }
  final output = File(args[0]);
  if (output.existsSync()) throw StateError('Retain earlier capture');
  final fixture = encodingFixture(args[2]);
  final fused = JsonUtf8Encoder();
  final encode = args[1] == 'fused'
      ? (Object value) => fused.convert(value)
      : (Object value) => utf8.encode(jsonEncode(value));
  Map memory() => {
    'rss_bytes': ProcessInfo.currentRss,
    'peak_rss_bytes': ProcessInfo.maxRss,
  };
  final before = memory();
  final samples = <int>[];
  List<int> bytes = [];
  for (var i = 0; i < 26; i++) {
    final clock = Stopwatch()..start();
    bytes = encode(fixture);
    samples.add(clock.elapsedMicroseconds);
  }
  final after = memory();
  await output.writeAsString(
    jsonEncode({
      'passed': true,
      'encoder': args[1],
      'fixture': args[2],
      'before': before,
      'after': after,
      'first_encode_us': samples.first,
      'subsequent_encode_us': samples.skip(1).toList(),
      'bytes': bytes.length,
      'sha256': '${sha256.convert(bytes)}',
      'scope': 'Fresh process, fixture built before timing, first encode separate from 25 subsequent encodes; natural GC, no forced collection. Encoding only, no FFI or renderer. Process RSS/high-water marks include runtime and fixture, not isolated heap allocations.',
    }),
  );
}
