final class HostMetrics {
  int descriptionBuilds = 0;
  int encodedSnapshots = 0;
  int encodedBytes = 0;
  int ffiCallbacks = 0;
  int uiCallbacks = 0;
  int diagnosticCallbacks = 0;
  int initialBytes = 0;
  int initialEncodeMicroseconds = 0;
  int dataMessages = 0;
  int dataBytes = 0;
  int dataRecordsChecked = 0;
  int dataCellsWritten = 0;
  final List<int> dataEncodeMicroseconds = [];
  final List<int> dataApplyMicroseconds = [];
  final List<int> nativeDataParseMicroseconds = [];
  final List<int> nativeDataApplyMicroseconds = [];
  final List<int> nativeSnapshotApplyMicroseconds = [];
  final List<int> buildMicroseconds = [];
  final List<int> encodeMicroseconds = [];
  final List<int> applyMicroseconds = [];

  static void sample(List<int> samples, int value) {
    if (samples.length < 4096) samples.add(value);
  }

  void recordEncoding(String kind, int bytes, int microseconds) {
    switch (kind) {
      case 'initial':
        initialBytes = bytes;
        initialEncodeMicroseconds = microseconds;
      case 'dataset':
        dataMessages++;
        dataBytes += bytes;
        sample(dataEncodeMicroseconds, microseconds);
      case 'snapshot':
        encodedSnapshots++;
        encodedBytes += bytes;
        sample(encodeMicroseconds, microseconds);
    }
  }

  Map<String, Object> read() => {
    'description_builds': descriptionBuilds,
    'encoded_snapshots': encodedSnapshots,
    'encoded_bytes': encodedBytes,
    'ffi_callbacks': ffiCallbacks,
    'ui_callbacks': uiCallbacks,
    'diagnostic_callbacks': diagnosticCallbacks,
    'description_build': _percentiles(buildMicroseconds),
    'encode': _percentiles(encodeMicroseconds),
    'publish_to_applied': _percentiles(applyMicroseconds),
    'initial': {'bytes': initialBytes, 'encode_us': initialEncodeMicroseconds},
    'data_messages': dataMessages,
    'data_bytes': dataBytes,
    'data_records_checked': dataRecordsChecked,
    'data_cells_written': dataCellsWritten,
    'data_encode': _percentiles(dataEncodeMicroseconds),
    'data_publish_to_applied': _percentiles(dataApplyMicroseconds),
    'native_data_parse': _percentiles(nativeDataParseMicroseconds),
    'native_data_apply': _percentiles(nativeDataApplyMicroseconds),
    'native_snapshot_apply': _percentiles(nativeSnapshotApplyMicroseconds),
  };

  static Map<String, Object> _percentiles(List<int> samples) {
    final sorted = samples.toList()..sort();
    int at(double fraction) =>
        sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * fraction).round()];
    return {
      'samples': sorted.length,
      'p50_us': at(.50),
      'p95_us': at(.95),
      'p99_us': at(.99),
    };
  }
}
