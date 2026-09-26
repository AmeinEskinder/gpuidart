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

Checkbox commit `cddca71` passed all hosted workflows:
[Windows](https://github.com/AmeinEskinder/gpuidart/actions/runs/36264217019),
[macOS](https://github.com/AmeinEskinder/gpuidart/actions/runs/36264216991),
[Linux](https://github.com/AmeinEskinder/gpuidart/actions/runs/36264217173), and
[Unix lifecycle](https://github.com/AmeinEskinder/gpuidart/actions/runs/36264217047).

## Slider

Windows local debug/headless checks on 2026-09-26: both slider tests passed;
full native suite 47 passed; Dart controls suite 4 passed; analysis passed.
Tests cover finite/bounded ranges and steps representable at both endpoints,
pointer changes, arrows/Home/End, duplicate endpoint suppression, Tab focus,
retained entity/focus, disabled pointer/keyboard behavior, theme styles and width.
The native pointer rounder can overshoot an endpoint that is not a multiple of
step; the binding clamps both its event and state, exercised with range 3..8,
step 5, and a click at the high endpoint.

Retained slider attempts:

* `compile`: missing FluentBuilder import caused compile errors; fixed locally.
* `native-1`: a wildcard test import brought GPUI's `test` macro into the
  expansion of its own test attribute. Explicit imports fixed this harness.
* `native-2`: wrapper bounds were not registered with Kit's test observer.
  The wrapper now uses its existing TestSupportExt hook.
* `native-3`: the wrapper's focus handle was not a Tab stop. This was a binding
  bug; explicitly enabling Tab participation fixed it.
* `native-4`: the test expected the pointer subscription callback before the
  enclosing App update completed. Native pointer state had already changed;
  the test now checks the event after GPUI flushes the update's effects.
* `native-5`: targeted tests passed. `full`: 47 native tests passed.

Remaining controls: select, confirmation dialog. Parked hardware,
signing, IME and presentation limitations from the work order remain unchanged.
