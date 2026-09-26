import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../src/owned_process.dart';

/// Same framed process transport for all three experimental strategies.
/// This measures protocol/UI tradeoffs; it is not the shipping Dart FFI bridge.
final class ExperimentTransport {
  ExperimentTransport._(this.process, this.responses, this.errors);
  final OwnedProcess process;
  final StreamIterator<Map<String, dynamic>> responses;
  final Future<String> errors;

  static Future<ExperimentTransport> start(
    String binary,
    String launcher,
  ) async {
    final process = await OwnedProcess.start(
      binary,
      [],
      launcherPath: launcher,
    );
    return ExperimentTransport._(
      process,
      StreamIterator(_decode(process.process.stdout)),
      process.process.stderr.transform(utf8.decoder).join(),
    );
  }

  Future<Map<String, dynamic>> send(Map<String, Object?> message) async {
    final total = Stopwatch()..start();
    final encode = Stopwatch()..start();
    var wire = message;
    if (message['kind'] case final String kind) {
      final body = Map<String, Object?>.from(message)..remove('kind');
      if (body['change'] case final Map change) {
        final payload = Map<String, Object?>.from(change);
        final strategy = payload.remove('strategy') as String;
        body['change'] = {strategy: payload};
      }
      wire = {kind: body};
    }
    final text = jsonEncode(wire);
    final jsonUs = encode.elapsedMicroseconds;
    final bytes = utf8.encode(text);
    final encodeUs = encode.elapsedMicroseconds;
    final header = ByteData(4)..setUint32(0, bytes.length, Endian.little);
    final write = Stopwatch()..start();
    process.process.stdin.add(header.buffer.asUint8List());
    process.process.stdin.add(bytes);
    await process.process.stdin.flush();
    final writeUs = write.elapsedMicroseconds;
    if (!await responses.moveNext().timeout(const Duration(seconds: 30))) {
      throw StateError(
        'Experiment process closed without a reply: ${await errors}',
      );
    }
    return {
      ...responses.current,
      'dart_transport': {
        'bytes': bytes.length,
        'framing_bytes': 4,
        'json_us': jsonUs,
        'utf8_us': encodeUs - jsonUs,
        'encode_us': encodeUs,
        'write_flush_us': writeUs,
        'request_reply_us': total.elapsedMicroseconds,
      },
    };
  }

  Future<void> stop() async {
    await process.stop();
    await responses.cancel();
  }
}

Stream<Map<String, dynamic>> _decode(Stream<List<int>> input) async* {
  final buffer = <int>[];
  await for (final chunk in input) {
    buffer.addAll(chunk);
    while (buffer.length >= 4) {
      final header = ByteData.sublistView(
        Uint8List.fromList(buffer.take(4).toList()),
      );
      final size = header.getUint32(0, Endian.little);
      if (size == 0 || size > 16 * 1024 * 1024) {
        throw StateError('Invalid experiment response length');
      }
      if (buffer.length < size + 4) break;
      final value = jsonDecode(utf8.decode(buffer.sublist(4, size + 4)));
      buffer.removeRange(0, size + 4);
      if (value is! Map<String, dynamic>) {
        throw StateError('Invalid experiment response');
      }
      yield value;
    }
  }
  if (buffer.isNotEmpty) throw StateError('Truncated experiment response');
}
