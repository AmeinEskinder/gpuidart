import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'platform.dart';

/// Internal packaging/baseline probe. Reads the Dart process through its loaded SDK.
Map<String, dynamic> readRuntimeInfo() {
  final library = DynamicLibrary.open(resolveNativeLibrary(null));
  final version = library.lookupFunction<Uint32 Function(), int Function()>(
    'gd_runtime_version',
  );
  if (version() != 1) {
    throw StateError('Unsupported runtime diagnostics version');
  }
  final read = library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Size>)
      >('gd_runtime_read');
  final free = library
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('gd_free_event');
  final length = calloc<Size>();
  Pointer<Uint8> bytes = nullptr;
  try {
    bytes = read(length);
    if (bytes == nullptr || length.value == 0 || length.value > 1024 * 1024) {
      throw StateError('Invalid runtime diagnostics buffer');
    }
    return jsonDecode(utf8.decode(bytes.asTypedList(length.value)))
        as Map<String, dynamic>;
  } finally {
    if (bytes != nullptr) free(bytes, length.value);
    calloc.free(length);
  }
}
