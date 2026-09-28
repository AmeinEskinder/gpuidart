import 'dart:io';

/// Fails when the prose drifts from the code it describes.
///
/// Static rules, checked everywhere:
/// - The node kinds are the variants of the native `Node` enum; the Dart
///   `UiNode` subclasses and the README's stated count must match them, and
///   every Dart node class must appear in the SDK reference.
/// - The README overview must not describe publications as a whole
///   description; they travel whole first and as operations afterwards.
///
/// Gate rule, checked when the caller passes the counts it just measured
/// (`--native=N --dart=M`): the roadmap's verification sentence must record
/// those counts. The full gate on Windows passes both; other platforms and
/// the headless gate run different subsets and pass none.
void main(List<String> args) {
  final failures = <String>[];
  int? native;
  int? dart;
  for (final arg in args) {
    if (arg.startsWith('--native=')) native = int.parse(arg.substring(9));
    if (arg.startsWith('--dart=')) dart = int.parse(arg.substring(7));
  }

  final kinds = nodeKinds(File('native/src/protocol.rs').readAsStringSync());
  final dartNodes = <String>[
    for (final entry in Directory('lib/src').listSync())
      if (entry is File && entry.path.endsWith('.dart'))
        ...RegExp(r'class (Ui\w+) extends UiNode')
            .allMatches(entry.readAsStringSync())
            .map((m) => m.group(1)!),
  ];
  if (dartNodes.length != kinds.length) {
    failures.add(
      'The native Node enum has ${kinds.length} kinds ${kinds.join(', ')} '
      'but lib/src declares ${dartNodes.length} UiNode classes '
      '${dartNodes.join(', ')}',
    );
  }

  final readme = File('README.md').readAsStringSync();
  final stated = RegExp(r'exposes ([\w-]+) node kinds')
      .firstMatch(readme)
      ?.group(1);
  final statedCount = stated == null ? null : parseCount(stated);
  if (statedCount != kinds.length) {
    failures.add(
      'README says "exposes ${stated ?? '?'} node kinds"; the native enum has '
      '${kinds.length}',
    );
  }
  final overview = readme.split('\n').take(40).join('\n');
  if (overview.contains('whole UI description')) {
    failures.add(
      'README overview still describes publications as a whole UI '
      'description; they travel whole first and as operations afterwards',
    );
  }

  final reference = File('docs/sdk.md').readAsStringSync();
  for (final node in dartNodes) {
    if (!reference.contains(node)) {
      failures.add('docs/sdk.md does not mention $node');
    }
  }

  final roadmap = File('docs/roadmap.md').readAsStringSync();
  final recordedNative = RegExp(r'native library suite runs (\d+) tests')
      .firstMatch(roadmap)
      ?.group(1);
  final recordedDart = RegExp(r'Dart suite (\d+)')
      .firstMatch(roadmap)
      ?.group(1);
  if (recordedNative == null || recordedDart == null) {
    failures.add(
      'docs/roadmap.md has no verification sentence with the suite counts',
    );
  }
  if (native != null && recordedNative != '$native') {
    failures.add(
      'docs/roadmap.md records $recordedNative native tests; the gate ran '
      '$native',
    );
  }
  if (dart != null && recordedDart != '$dart') {
    failures.add(
      'docs/roadmap.md records $recordedDart Dart tests; the gate ran $dart',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'Docs agree with the code: ${kinds.length} node kinds; roadmap records '
      '$recordedNative native and $recordedDart Dart tests'
      '${native == null ? '' : ' (gate ran $native and ${dart ?? '-'})'}.',
    );
    return;
  }
  for (final failure in failures) {
    stderr.writeln('Docs drift: $failure');
  }
  exit(1);
}

/// The variant names of `pub enum Node` in the native protocol.
List<String> nodeKinds(String source) {
  final start = source.indexOf('pub enum Node {');
  if (start < 0) throw StateError('No Node enum in native/src/protocol.rs');
  var depth = 0;
  var end = start;
  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  final body = source.substring(start, end);
  return RegExp(
    r'^    ([A-Z]\w*) \{',
    multiLine: true,
  ).allMatches(body).map((m) => m.group(1)!).toList();
}

/// A count written as digits or as an English number word up to forty.
int? parseCount(String text) {
  final digits = int.tryParse(text);
  if (digits != null) return digits;
  const units = {
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };
  const tens = {'twenty': 20, 'thirty': 30, 'forty': 40};
  final parts = text.toLowerCase().split('-');
  if (parts.length == 1) return units[parts[0]] ?? tens[parts[0]];
  if (parts.length == 2 && tens.containsKey(parts[0])) {
    final unit = units[parts[1]];
    return unit == null || unit > 9 ? null : tens[parts[0]]! + unit;
  }
  return null;
}
