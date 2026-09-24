final class HostMetrics {
  int descriptionBuilds = 0;
  int encodedSnapshots = 0;
  int encodedBytes = 0;
  int ffiCallbacks = 0;
  int uiCallbacks = 0;
  int diagnosticCallbacks = 0;
  final List<int> buildMicroseconds = [];
  final List<int> encodeMicroseconds = [];
  final List<int> applyMicroseconds = [];

  static void sample(List<int> samples, int value) {
    if (samples.length < 4096) samples.add(value);
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
