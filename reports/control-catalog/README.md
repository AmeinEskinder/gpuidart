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

## Select

Local Windows checks: 49 native library tests passed; 6 Dart controls tests
passed; analyzer clean. The select tests cover bounded options, unique stable
IDs, unknown selections, nullable selection, caller-list isolation, style width,
pointer opening, keyboard selection, retention of an open popup across an
unchanged snapshot, reorder/selection identity, Escape cancellation with focus
restoration, disabled activation, and disabling a menu while it is open.

Retained attempts under `select/`:

* `compile`: binding compiled successfully before the new interaction test.
* `native-1`: a 240-pixel input had a wider outer hit target. Clicking its
  reported center only focused it; Down opened the menu and Enter selected the
  original option. The binding now constrains the parent to the declared width.
* `native-2`: targeted tests passed after that fix.
* `full`: the additional disable-while-open test failed. Blurring the menu was
  insufficient because the open popover restored focus while rendering. The
  binding now dispatches Kit's native Cancel action, preserving the committed
  selection while dismissing the menu.
* `full-2`: all 49 native tests passed, including disable-while-open.

## Confirmation dialog

Windows local checks: 51 native library tests passed, 8 Dart controls tests
passed, analyzer clean. Tests cover byte bounds and required labels, styled
trigger bounds, native modal opening, Tab trapping, Escape cancellation and
focus restoration, Enter confirmation, retention through unrelated snapshots,
disabled triggers, and cancellation when the trigger is removed or changes
kind. Results are emitted once and refer to the opening revision.

Retained attempts under `dialog/`: `compile` and `native-1` passed. The expanded
`full` test incorrectly tried to test Tab trapping with Window::focus_next,
which is programmatic focus movement outside the dialog's keyboard handler.
Replacing it with actual GPUI Tab dispatch tests the native focus trap;
`full-2` passed all 51 tests. New control events also count toward the existing
UI-callback metric.

## Controlled inputs

Local Windows `tool/check.dart` passed: 53 native tests, 3 strategy tests, 59
Dart tests including the new live-window input test, formatting, analysis and
native/launcher builds. `input/all/` contains the complete gate logs.

The native input test exercises real handler operations: Unicode text and
UTF-16 selection, invalid surrogate boundaries, native typing, selection-only
conflicts before notifications flush, marked composition, a rejected write
preserving text/selection/focus/marked range, commit and unmark, mode changes,
and generation invalidation after removal/recreation. Programmatic writes do
not echo input events. FFI tests include input command bounds/backpressure;
fault-peer tests cover missing, malformed and mismatched acknowledgements and
submission panic settlement. The live window proves command acknowledgements
and trace correlation; it is not OS IME verification.

Retained input attempts:

* `compile`: initial Rust compile and existing input tests passed.
* `native-1`: behavior test passed, strict wire test failed because serde's
  internally tagged unit Read variant accepted extra fields. Using an empty
  struct variant enforces the intended unknown-field rejection.
* `headless`: full headless gate passed after that correction (53 Dart tests).
* `live`: verifier failed to compile due to an incorrect tracing import.
* `live-2`: input interactions passed, trace assertion failed. The Dart native
  trace decoder's allowed operation list omitted `input_control`.
* `live-3`: targeted live-window test passed after adding the operation.
* `all`: complete gate passed; final trace checks occur after host close so the
  macOS companion's trace can be collected as well.

All four planned controls and controlled inputs are implemented. The settings
application/verifier, schema decision and final evidence are still pending.
Parked hardware,
signing, IME and presentation limitations from the work order remain unchanged.
