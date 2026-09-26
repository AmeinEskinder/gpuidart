# Accessibility work order

Status: platform spike in progress. This document is a design and acceptance
contract, not a claim that the SDK is accessible. Reference code: `3a72688`.

## Platform spike

The pinned GPUI Kit revision is `21622a70efd25219d26aa459164878c4da9e39f8`;
it uses `gpui-pre` 0.3.6. The source contains actual AccessKit adapters:

| Backend | Adapter | External client for this milestone |
| --- | --- | --- |
| Windows | `accesskit_windows::Adapter`, UIA events | `System.Windows.Automation` |
| Linux X11 | `accesskit_unix::Adapter`, AT-SPI bus | GI `Atspi` over session D-Bus |
| macOS | `accesskit_macos::SubclassingAdapter` on NSWindow | `AXUIElement` targeting companion PID |

Windows local spike queried the real settings window and invoked its Appearance
button through UIA. Checkbox Toggle, input Value, select Value/Selection/ExpandCollapse,
and slider RangeValue patterns exist. Select and slider have empty names; ordinary
`UiText` labels are missing. Slider is reported writable but its Base implementation
registers only Increment/Decrement, and those handlers do not guard disabled state.
These findings require action verification, not just role/name assertions.

Linux and macOS probes are committed before the model implementation. The external
macOS client checks Accessibility authorization and fails explicitly when absent;
it does not alter TCC. Provider introspection and an internal debug tree cannot
substitute for a successful external AX query. X11 verification does not establish
Wayland support. All probe failures and environment limitations are retained.

## Model and defaults

Each node gains optional typed `semantics`. Labels are limited to 1,024 UTF-8
bytes, descriptions to 4,096. Roles use a closed enum. Containers can represent
groups, lists and sections; text can represent labels or headings. Controls keep
their functional roles. Their checked, disabled, expanded, selected, text and
range states come from the actual retained control state, including native edits
that precede a Dart acknowledgement. Overrides must not advertise a different
action or value from the control; incompatible roles/states are rejected.

The wire design must distinguish annotations from control state. Repeating a
slider's range or a checkbox's checked property in a semantics override must not
create a second source of truth. The final field matrix and rejected combinations
will be recorded with the wire-model commit.

Defaults: visible button/checkbox labels; current input value with placeholder as
fallback name; select current choice plus explicit name/placeholder; slider actual
range/value; open dialog title, description and modal state. Explicit names do
not change visible text. SDK node IDs become queryable stable identifiers where
the pinned adapter supports them. GPUI's underlying identity includes ancestor
IDs, so reparenting is not claimed to preserve platform identity.

## Native tree and actions

Use GPUI's existing tree and adapters. Do not publish a parallel simulated tree.
GPUI sends a coherent tree during its frame lifecycle after materialization;
snapshot acknowledgement is not an accessibility publication fence. Verifiers
wait for expected platform state with a deadline. Native focus/selection/value
changes must notify and be reflected without requiring a replacement snapshot.

Control actions use existing state/event paths with disabled checks and bounds.
Tests verify effects, not merely advertised pattern names. A provider that accepts
an action but does not change state fails verification.

Tables expose table dimensions, column headers, rendered rows and cells. Row and
cell IDs derive from dataset identity and stable record ID (source index only for
legacy datasets without IDs). Sort/filter updates view indices and selection while
preserving record identity. The tree is viewport bounded: no eager 100,000-row
semantic allocation. The initial scope cannot promise offscreen-cell discovery or
screen-reader navigation across virtualized ranges until platform actions prove it.

## Verification and completion

1. Freeze spike findings and design before wire changes.
2. Per-control wire validation and real GPUI headless tests for semantics/actions.
3. Windows external UIA queries/actions first; Linux AT-SPI and macOS AX in hosted
   sessions. Missing permissions are reported as failures/unavailable evidence.
4. Extend settings' 15-step verifier with platform assertions; add Watchlist
   labels, generated table semantics and portable verification.
5. Re-run 100k JIT/AOT and reload checks; retain failures under
   `reports/accessibility/`; update SDK/roadmap limitations.
6. Require green platform queries and existing suites at final pushed commit.

Programmatic semantics complement screenshots; they do not prove visual layout,
contrast, occlusion, or screen-reader usability. Human NVDA/VoiceOver sessions,
Mac hardware observations, signing, historical reload disposition and presentation
latency stay outside this milestone. Live announcements are added only if the
spike establishes a supported GPUI API and an observable platform result.
