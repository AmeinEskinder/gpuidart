/// Development support is separate from the application's UI and dataset API.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'gpuidart.dart';

/// Registers the development launcher's rebuild and close extensions.
/// Rebuilds use the existing application object; this is a no-op in AOT builds.
void registerGpuiReload(
  GpuiHost host, {
  Map<String, Object?> Function()? describe,
}) {
  if (const bool.fromEnvironment('dart.vm.product')) return;
  registerExtension('ext.gpuidart.reassemble', (_, _) async {
    await host.rebuild();
    return ServiceExtensionResponse.result(jsonEncode(describe?.call() ?? {}));
  });
  registerExtension('ext.gpuidart.close', (_, _) async {
    unawaited(host.close());
    return ServiceExtensionResponse.result('{}');
  });
}
