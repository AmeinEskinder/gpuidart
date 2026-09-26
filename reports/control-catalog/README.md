# Settings control catalog evidence

Work order: [control-catalog design](../../docs/control-catalog.md), committed
before implementation as `420c7f6`. This is an in-progress milestone. The
settings application, controlled inputs, schema decision and final hosted
verification are not complete.

## Checkbox

Windows local checks on 2026-09-26, debug/headless native build:

* Both checkbox native tests pass: bounded UTF-8 labels and invalid JSON types;
  pointer and Space activation; exactly one event per activation; authoritative
  snapshot value; retained focus; disabled pointer/keyboard suppression; Tab
  traversal past a disabled control; theme-token styling and exact width.
* Full native library suite: 45 passed.
* Dart controls/event/style suites: 10 passed. `dart analyze` passed.
* This establishes component behavior in GPUI's headless test window. It does
  not yet establish live desktop behavior or cross-platform results for the
  new binding.

Retained attempts under `checkbox/`:

1. `native-1`: test compilation failed because an untyped JSON-parsing closure
   inferred a reference lifetime spanning successive mutations of the fixture.
   Adding the explicit `&serde_json::Value` parameter type fixed the test.
2. `native-2`: pointer test passed, Space produced no event. The pinned Kit
   `TestWindowExt::press` dispatches only key-down. Checkbox Space activation
   completes on key-up. The verifier now sends a complete press/release; no
   native checkbox behavior was changed to satisfy the test.
3. `native-3`: both targeted tests passed.
4. `full`: all 45 native tests passed after the verifier correction.

Remaining controls: slider, select, confirmation dialog. Parked hardware,
signing, IME and presentation limitations from the work order remain unchanged.
