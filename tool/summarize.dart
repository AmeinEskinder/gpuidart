import 'dart:convert';
import 'dart:io';

Map<String, dynamic> read(String name) {
  final file = File('reports/$name.json');
  final result = jsonDecode(
    file.readAsStringSync().replaceFirst('\uFEFF', ''),
  ) as Map<String, dynamic>;
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
  return result;
}

String ms(dynamic value) => ((value as num) / 1000).toStringAsFixed(2);
String mib(dynamic value) =>
    ((value as num) / (1024 * 1024)).toStringAsFixed(2);

void main() {
  final package = read('package');
  final measurement = read('aot-measurement');
  read('aot-self-test');
  final virtualization = read('virtualization');
  final reload = read('reload');
  final environment = read('environment');
  final dart = measurement['dart'] as Map;
  final native = measurement['native'] as Map;
  final repaints = measurement['unchanged_repaints'] as Map;
  final rows = virtualization['samples'] as List;
  final unpacked = (package['files'] as List).fold<int>(
    0,
    (total, file) => total + file['bytes'] as int,
  );
  final report = StringBuffer('''# Desktop prototype measurements

Generated from the adjacent JSON reports by `dart run tool/summarize.dart`.

## Packaged application

- ZIP: **${mib(package['zip_bytes'])} MiB**. Payload files: **${mib(unpacked)} MiB**, excluding manifest/ZIP overhead.
- AOT launch and 120-update measurement passed after extracting the ZIP outside the repository, using an unrelated working directory and a Windows-only PATH.
- Loaded DLL paths confirm the packaged GPUI DLL, packaged CRT and Windows Common Controls v6. No loaded module came from the repository or a Dart/Flutter SDK directory.
- A clean machine without an installed SDK has not been tested.

## Local AOT sample

${measurement['rows']} records; ${measurement['updates']} iterations, each awaiting one cell transaction and one counter snapshot, then delaying 16 ms. This is not a fixed-rate load test. Native histograms cover startup, forced repaints and updates together. Separate publication scaling results are in [data-publication.md](data-publication.md).

| Metric | p50 | p95 | p99 |
| --- | ---: | ---: | ---: |
''');
  for (final entry in <String, dynamic>{
    'Dart description build': dart['description_build'],
    'Dart JSON encode, allocate and copy': dart['encode'],
    'Publish to applied acknowledgement (includes encoding)':
        dart['publish_to_applied'],
    'Dataset JSON encode, allocate and copy': dart['data_encode'],
    'Dataset publish to applied acknowledgement':
        dart['data_publish_to_applied'],
    'Native draw': native['draw'],
    'Native dirty to presentation submission':
        native['dirty_to_present_submit'],
  }.entries) {
    report.writeln(
      '| ${entry.key} | ${ms(entry.value['p50_us'])} ms | ${ms(entry.value['p95_us'])} ms | ${ms(entry.value['p99_us'])} ms |',
    );
  }
  report.writeln();
  report.write('''
RSS after the workload: **${mib(measurement['process']['rss_bytes'])} MiB**; process peak: **${mib(measurement['process']['peak_rss_bytes'])} MiB**. These include the Dart runtime and native renderer.

Description samples include the first build. Initial dataset encoding is reported separately in the raw JSON. Snapshot encoding contains no table records. Native application acknowledgement and presentation submission are separate timestamps; neither measures the moment pixels become visible. No controlled OS input-to-present measurement has been made. Any input samples in the raw report are incidental window events. The earlier full-data results remain in [baseline-snapshots/summary.md](baseline-snapshots/summary.md).

## Unchanged repaint probe

The probe observed **${repaints['native_after']['native']['materializations'] - repaints['native_before']['native']['materializations']} native view materializations**. During that interval:

- Dart description builds: **${repaints['dart_after']['description_builds'] - repaints['dart_before']['description_builds']}**.
- Dart snapshot encodes: **${repaints['dart_after']['encoded_snapshots'] - repaints['dart_before']['encoded_snapshots']}**.
- Dart UI callbacks: **${repaints['dart_after']['ui_callbacks'] - repaints['dart_before']['ui_callbacks']}**.
- Total FFI callbacks: **${repaints['dart_after']['ffi_callbacks'] - repaints['dart_before']['ffi_callbacks']}**, the diagnostic completion itself.

These counters cover the registered builder and host callbacks. They do not claim the Dart runtime or unrelated application work stops executing.

## Viewport work

Ten warmed redraws per case, a fixed 860 × 650 window and a 320 px table. The allocator measures successful Rust allocation/reallocation requests on the headless UI thread during redraw. Data creation, publication, other threads and GPU allocations are excluded. Row/cell counts are construction calls, including layout measurement and overscan.

| Records | Row constructions | Cell constructions | Allocation calls | Bytes requested |
| ---: | ---: | ---: | ---: | ---: |
''');
  for (final row in rows) {
    report.writeln(
      '| ${row['data_rows']} | ${row['rows_constructed']} | ${row['cells_constructed']} | ${row['allocation_calls']} | ${row['allocated_bytes']} |',
    );
  }
  report.writeln();
  report.write('''
Rendering work stayed proportional to the viewport. Total storage and initial upload still grow with record count. Ordinary snapshots reference existing data, and record edits transfer only changed values.

## Actual Dart code reload

`DemoApplication.heading` changed in the same live process and isolate. The VM accepted the new source and the rebuilt native description contained the new heading. Counter, Dart text state, edited dataset value/revision, input entity/text/focus/selection and table entity/scroll offset remained equal. Reload plus reassembly to the applied acknowledgement took **${ms(reload['reload_and_reassemble_us'])} ms** in this single development run. Invalid source was rejected and the previous code remained active.

The fixture seeds state through a development extension. Separate headless tests type Unicode, select by keyboard, navigate rows, dispatch wheel input, resize the window and verify retained state. The reload result establishes a component method edit; it does not establish arbitrary structural changes or AOT reload.

## Environment and outstanding checks

- ${environment['os']['Caption']} ${environment['os']['BuildNumber']}; ${environment['cpu'][0]['Name']}.
- ${environment['dart']}; GPUI Kit `21622a70efd25219d26aa459164878c4da9e39f8`, GPUI 0.3.6, Rust 1.98.1, native release build with profiler enabled.
- Installed GPUs: ${(environment['gpu'] as List).map((gpu) => gpu['Name']).join(', ')}. The report does not identify which adapter rendered the window.
- Seven native tests, one live Dart integration test and Dart analysis passed during this milestone.
- Human visual inspection, including IME composition, is pending: the desktop automation connection failed after retry and reset. Windows Sandbox is not installed on this machine.
- GPUI Shell/QuickJS and GPUIX/Solid comparisons, controlled input latency and clean-machine installation verification remain outstanding. These local measurements establish no ranking against those runtimes.
''');
  File('reports/summary.md').writeAsStringSync(report.toString());
  stdout.writeln('Wrote reports/summary.md');
}
