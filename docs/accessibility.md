# Accessibility work order

Status: semantics and native adapters implemented and externally verified on
Windows UIA, Linux X11 AT-SPI and macOS AX. See
[accepted results and retained failures](../reports/accessibility/README.md).
This is not a human screen-reader usability claim. Design reference: `3a72688`.

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
bytes. Roles use a closed enum. Containers can represent
groups, lists and sections; text can represent labels or headings. Controls keep
their functional roles. Their checked, disabled, expanded, selected, text and
range states come from the actual retained control state, including native edits
that precede a Dart acknowledgement. Overrides must not advertise a different
action or value from the control; incompatible roles/states are rejected.

The wire model distinguishes annotations from control state. `UiSemantics` has
`label`, `role`, and `headingLevel` (required for headings, 1 through 6). Control
state is derived, rather than repeated in an independently writable annotation.
This narrows the requested override model: falsely announcing a disabled control
as enabled, or a checkbox as checked, is rejected rather than overriding behavior.
Supplementary descriptions are deferred: the pinned component APIs do not expose
them consistently, and a group wrapper would not describe the same platform node.

| Node | Allowed explicit roles | Native state |
| --- | --- | --- |
| Row/column | group, list, list_item | Descendant controls own state |
| Text | label, heading | Text; heading level |
| Button / confirmation trigger | button | Enabled, focus; modal is a separate generated dialog |
| Checkbox | checkbox | Checked, disabled, focus |
| Slider | slider | Number, range, step, disabled, focus |
| Input | textbox | Native text, selection, focus |
| Select | combobox | Choice, expanded, disabled, focus |
| Table | table | Dimensions, rendered rows/cells, selection |

Unknown fields, mismatched roles, empty explicit names and overlong UTF-8 names
are rejected on both sides. Existing messages without annotations remain valid.

Defaults: visible button/checkbox labels; current input value with placeholder (then node ID) as
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

## Using semantics

```dart
UiColumn('preferences', [
  const UiText('title', 'Preferences',
    semantics: UiSemantics(role: UiRole.heading, headingLevel: 1)),
  const UiInput('name',
    semantics: UiSemantics(label: 'Display name')),
  UiSlider('spacing', min: 8, max: 24, step: 2, number: spacing,
    semantics: const UiSemantics(label: 'Preview spacing')),
], semantics: const UiSemantics(label: 'Preferences form'))
```

Use a persistent control ID and a name that describes the control. Explicit
semantics names do not replace visible labels. Checkbox state, input text, slider
range/value, select state and modal state come from the real native controls.
Labels are 1..1024 UTF-8 bytes; heading levels are 1..6. Controls reject incompatible
roles and independently forged state fields. `UiText` defaults to label; explicit
heading/list/group roles are available for structure.

Native inputs attach structured TextRun children only when accessibility is
active (also in Kit's test-support build). Text comes from the current rendered
native value, including edits that have not caused a Dart snapshot yet. The
GPUI focus hook associates the semantic input with its real editing handle
without adding a tab stop. External Focus actions are checked against native
input focus; isolated X11 checks also compare the platform focused state. The
current adapter does not add text-selection actions or glyph range geometry.
Platform selection/caret navigation is not claimed by these text-value checks.
Select exposes its current choice as a named child for adapters that lack a
scalar string-value query.

Table rows/cells are emitted only for the rendered viewport. Row author IDs encode
`[table ID, dataset ID, "record", record ID]`; datasets without IDs use `"source"`
and a source index. Cell IDs encode `[row author ID, "cell", column index]`.
Names reflect formatted visible cell text. A record ID preserves the semantic key
through view reorder; GPUI ancestor identity still matters. Keys do not promise
persistent OS object handles or offscreen table navigation.

### Known pinned-adapter gaps

- Windows AccessKit 0.34.0 has no Grid/Table coordinate patterns. A narrow
  [pinned dependency patch](../native/vendor/README.md) adds row SelectionItem
  support; the same consumer correction exposes AX selected-row attributes.
  The AT-SPI patch prevents disabled buttons from being reported as enabled.
  The Unix adapter also corrects cache-signal argument encoding; an external
  D-Bus observer checks both addition and removal messages. Unmodified-upstream
  failures and the exact local patches are retained in the report.
- Linux AccessKit AT-SPI 0.19.1 has no EditableText interface. External Text reads
  are supported by structured text children; Linux test edits use declared GPUI
  diagnostic keys. They are not AT-SPI write passes.
- Modal content/decisions are externally queried on macOS; a missing AXModal
  property is not inferred from the internal modal flag.
- Live-region/announcement APIs are not bound or verified. The existence of an
  AccessKit dependency does not establish delivered announcements.

Use `dart run tool/verify_settings.dart REPORT.json --semantics` for the settings
track and `dart run tool/accessibility/watchlist.dart REPORT.json` for Watchlist.
The clients require native platform accessibility access; Linux CI uses a private
D-Bus accessibility session, and the macOS external client must be authorized.
The scripts refuse to replace a prior report and fail on missing platform access.
An internal diagnostic tree never substitutes for an external platform query.

### Reading a changing platform tree

A platform query consists of multiple OS calls and can overlap a frame update.
AT-SPI and AX clients discard the entire read when a referenced object disappears;
they retry only known stale-object errors with a fixed bound. AT-SPI's
APPLICATION_GONE error is eligible only when the same application root still
answers an uncached property request. All retries and client stderr are retained.
Actions are never replayed and a partial tree never passes an assertion. These
read-recovery rules do not make snapshot acknowledgements platform-tree fences.

The Linux Settings control probe also starts an independent D-Bus signal monitor.
It requires correctly typed AddAccessible and RemoveAccessible messages from the
owned native PID. Valid cache message delivery does not establish screen-reader
interpretation, speech, or navigation behavior.

Dependency upgrades must pass the same external actions, disabled-state checks,
focus checks and stable-record selection checks before the small pinned overrides
can be removed. [Vendor provenance](../native/vendor/README.md) records original
archive hashes, per-file hashes, licenses and patch-only diffs.
