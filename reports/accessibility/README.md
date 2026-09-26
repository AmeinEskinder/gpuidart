# Accessibility milestone: progress and evidence

The milestone is **in progress**. These are feasibility and wire-contract results,
not complete SDK accessibility acceptance or human screen-reader verification.

## Platform spike (`a103da1`)

[Hosted run 36270561107](https://github.com/AmeinEskinder/gpuidart/actions/runs/36270561107)
passed on Windows 2022, macOS 15 ARM64 and Ubuntu 24.04 X11/Xvfb. Each external
client queried the settings window, invoked Appearance using a platform action,
and observed the application change section. Raw responses are retained beside
this report. Local Windows evidence is `windows-spike-1.json`.

| Platform | Actual client | Result scope |
| --- | --- | --- |
| Windows | `System.Windows.Automation` | UIA query and InvokePattern |
| Linux | GI Atspi, session D-Bus | AT-SPI query and action |
| macOS | `AXUIElement`, companion PID | External AX query and AXPress; trust check passed |

No internal inspect payload supplied the roles, names or values. Inspect only
located the native PID. Queries expose existing Kit behavior: named buttons,
checkbox state and input value; the select and slider are unnamed. Text labels
are missing. Slider SetValue effects and disabled action behavior still need
verification; source has only Increment/Decrement handlers without disabled guards.

The Linux runner enables accessibility only inside its disposable D-Bus session.
The macOS probe does not modify TCC, grant itself access or use provider introspection
as an external-query substitute. All clients have a 20-second process deadline
and a 4,096-node result bound. That bound is not a virtualization proof (Windows
currently enumerates before checking the bound).

## Wire model checkpoint

Optional `UiSemantics` / Rust `Semantics` carry a bounded label, compatible role
and heading level. Existing native control properties remain the source of values
and states. This checkpoint does **not** yet apply annotations to rendered controls.
The field matrix and reasons for rejecting independent state overrides are in
`docs/accessibility.md`.

Local checks: 55 native tests passed (including 2 new semantics tests), 3 new Dart
semantics tests passed, analyzer clean; 3 snapshot-experiment tests passed after
the Node structure change. No timing/performance claim is made.

Retained implementation failures: the first source-edit helper used Windows'
default text encoding and stopped on a UTF-8 test fixture; no test data was lost.
The initial build then reported missing `semantics` fields in existing test
literals. The helper was corrected to explicit UTF-8 and the literals updated;
native and experiment tests passed. Dart analyzer also caught an obsolete
constructor argument during removal of the unsupported description field.

## Remaining acceptance work

- Apply annotations to native controls and generate viewport-bounded table semantics.
- Verify actions and disabled/value/focus states, including the slider gap.
- Per-control headless semantics tests; full settings and Watchlist platform track.
- 100k JIT/AOT and reload regression checks after adapter changes.
- All suites/platform queries green at final commit, updated public docs, clean tree.

No claims about screen readers, visual layout, hardware IME, Wayland, visible pixels
or presentation latency. Parked hardware/signing/reload-disposition gates remain parked.
