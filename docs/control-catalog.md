# Settings controls milestone

Design baseline: `52a9e9e`, committed before code as `420c7f6`. This document
defines the contract; [the evidence report](../reports/control-catalog/README.md)
records implementation and verification status. The snapshot/dataset architecture
and the pinned GPUI Kit revision remain unchanged.

## Application and scope

`example/settings/` edits application preferences: a display name,
notifications, appearance, and a numeric density preference. General and
Appearance navigation use existing buttons. Apply saves the in-process draft;
Reset asks for confirmation before restoring defaults. These are demonstration
preferences, not changes to the operating system. The existing host scrollbar
handles a small settings form; this does not introduce a virtualized list.

Four new controls are sufficient:

| Dart node / wire kind | Need | Native component |
| --- | --- | --- |
| `UiCheckbox` / `checkbox` | Enable notifications | Component Checkbox |
| `UiSlider` / `slider` | Choose density within a bounded numeric range | Component Slider and retained SliderState |
| `UiSelect` / `select` | Choose appearance from named choices | Component Select and retained SelectState |
| `UiConfirmDialog` / `confirm_dialog` | Confirm reset without losing the draft on cancellation | Component Dialog with a trigger and standard footer |

Radio groups, switches, tabs, tooltips, sheets, and general lists were deferred at this milestone; the later milestones bound them ([binding table](binding-table.md)).
The screen does not require them. Dialog content is intentionally a bounded
title/message and confirm/cancel labels, not an arbitrary nested UI tree.

## Wire contract and ownership

Each kind has the existing `id` and optional `style`. Styles use the existing
typed values and theme tokens. No new theme vocabulary is needed. Node IDs
continue to identify retained controls; removing a node disposes its state.

* Checkbox: `label`, `checked` boolean, `disabled` boolean (default false).
  `checkbox_change` carries `revision`, `id`, and `checked`.
* Slider: `min`, `max`, `step`, `number`, `disabled` boolean. Values must be
  finite, within +/-1,000,000, with min < max, 0 < step <= max-min, and the
  number inside the range. Steps must remain nonzero at both endpoints in
  native 32-bit precision. Pointer values snap to multiples of step relative
  to zero, then clamp to the endpoints. `slider_change` carries `revision`, `id`, and
  `number`. A single numeric value is supported, not a range slider.
* Select: `options` (1..256 unique nonempty string IDs and labels), nullable
  `selected` option ID, `placeholder`, and `disabled` boolean.
  `select_change` carries `revision`, `id`, and nullable `selected` ID.
  Labels and identities are separate, so relabeling does not change selection.
* Confirmation dialog: `label` for its trigger, `title`, `message`,
  `confirm_label`, `cancel_label`, and `disabled` boolean.
  `dialog_result` carries `revision`, `id`, and `confirmed` boolean.
  Escape/cancel reports false; confirm reports true. Native owns opening,
  dismissal, focus trapping and focus restoration. It never resets app data.
  Style applies to the trigger; the modal uses Kit's current theme. The opening
  description and revision stay fixed until dismissal. Removing or disabling
  the trigger cancels its active dialog once. Only one confirmation can be
  open in this host at a time.

New labels and placeholders have a 1,024 UTF-8 byte limit, messages 8,192 bytes,
and option IDs 256 bytes. Existing overall snapshot limits still apply.
Snapshot validation rejects malformed values before reconciliation.

Checkbox/select/slider values are supplied by the application. Events request
an application-state change; the application publishes the resulting snapshot.
The control shows the interaction at once: a checkbox toggles, a slider follows
the drag and a select shows the pick, so feedback never waits for the
application. Snapshot writes are authoritative: every publication shows its
values, including a publication that repeats the previous value, which undoes
an interaction the application did not accept. Applications must process
requests in delivery order; event revisions identify their source, and must
not be used to discard valid requests merely because a newer snapshot was
published. A checkbox activated twice before the application publishes
reports the toggle each time, so the second request carries the original
value. Disabled controls produce no change requests. Unrelated snapshots retain
focus and existing entity identity and must not reopen or dismiss a select
popup.

Keyboard behavior is part of each binding: Tab traversal and Space for the
checkbox; arrows and Home/End for the slider; native select navigation,
confirmation and dismissal; native dialog confirmation, cancellation and focus
restoration. The pinned slider has no keyboard interface, so its binding adds
a retained focus handle and keyboard stepping around the existing component.
Keyboard handling must respect disabled state and prevent duplicate requests.

## Controlled text input

`UiInput(controlled: true)` opts into application writes. The default remains
native-retained input. A separate acknowledged `GpuiHost.writeInput` command
sets text and/or UTF-16 selection; snapshots do not repeatedly reset input text.
The command uses the bounded host channel and normal request timeouts.

Each controlled input exposes a generation (changed on remove/recreate) and an
edit revision. A write names both; stale generation/revision is rejected with
the current state. Invalid UTF-16 boundaries, including the middle of a
surrogate pair, are rejected. The response includes resulting text, selection,
generation, edit revision, and composition state. Programmatic writes do not
echo as user edits. Native edits advance the edit revision.

During marked IME composition, native is authoritative: a write is rejected
with a composition conflict, without changing text, selection, focus, undo, or
marked text. No deferred write is queued. The application can retry against a
fresh state after composition ends. The pinned InputState exposes marked text
through GPUI's EntityInputHandler; tests exercise this same handler, including
commit and cancellation. Software composition tests are not hardware IME
verification. Existing Windows/Linux IME evidence must not be represented as
verification of the new controlled-write path. No macOS IME claim is made.

## Verification and commit sequence

1. Commit this design before code.
2. One commit per new control, with bounds/invalid-wire tests, Dart codec/event
   tests, and native headless interaction tests covering disabled state,
   keyboard behavior, styling and retained focus/state across snapshots.
3. Controlled-input command and conflict/selection tests, with bounded failure
   behavior and no change to existing uncontrolled inputs.
4. Settings application and a portable live-window verifier for each control,
   apply/reset/cancel, controlled edits, and snapshot retention. Record whether
   interaction uses OS input or GPUI dispatch; neither establishes hardware IME.
5. Record a keep-or-skip decision on a single versioned schema generating wire
   codecs/models/docs. Keep ergonomic wrappers and semantic tests either way.
6. Retain failures and evidence under `reports/control-catalog/`, update SDK
   docs and README, run settings and existing 100k smokes, and obtain green
   Windows/macOS/Linux hosted checks at the final pushed commit.

The milestone is complete only with a clean pushed tree and those verification
results. Accessibility-tree work, macOS IME, presentation latency, signing,
physical Mac observations, and the historical reload disposition remain out of
scope. Catalog breadth is not an acceptance criterion.

## Schema decision

[Keep manual codecs for this milestone](protocol-schema-decision.md). Generation
remains a separate migration with versioning, deterministic output and wire
equivalence gates. The public Dart API and semantic tests remain either way.

## Toggle, choice and display additions

`UiSwitch`, `UiRadioGroup`, `UiProgress` and `UiSeparator` follow the settings
contract above. A switch behaves like a checkbox: `switch_change` carries the
requested `checked` value, the switch shows the toggle at once, and the next
publication's value is authoritative. Progress is display only: `value` is a
percentage from 0 to 100 and an absent value shows an indeterminate bar. A
separator is a horizontal or vertical rule with an optional centered label.
Labels keep the select and dialog bounds, and semantics roles are `switch`,
`progress_bar` and `separator`. Radio groups, tabs and button tooltips are the
retained, keyboard-navigable controls described in
[navigation and charts](navigation-and-charts.md). Canvases and native
animation are described in [canvas and animation](canvas-animation.md).

`UiDatePicker` is a calendar picker holding one `YYYY-MM-DD` date or none,
with a placeholder and a disabled flag. It follows the settings contract:
`date_change` carries `revision`, `id` and the nullable requested `date`
(null when the user clears it), the picker shows the choice at once, and the
next publication's value is authoritative. Both sides reject a value that is
not a real calendar date, and its semantics role is `combobox`.

`UiIcon` shows one Lucide icon from the catalog GPUI Kit bundles, by file
stem (`search`, `chevron-down`); the Dart side checks the name's shape and
native rejects a name the catalog lacks, so a typo is a rejected description
rather than a blank. `UiImage` shows a raster or SVG image from a file path,
recognised by extension, or from inline bytes with an explicit format; the
bytes travel base64 encoded, are decoded once per node and content, and the
decode is dropped when the node leaves the description. Both take the `image`
semantics role and are display only.

`UiMenuButton` is a button that opens a popup menu of the same `UiMenuEntry`
items application menus take: actions bound to global `UiAction` names, with
optional `checked` and `disabled` flags, and separators. Choosing an action
emits that action on the event channel, like a menu bar item.
The host also exposes the platform's file and folder choosers, save dialog,
URL handler and file manager through `pickPaths`, `pickSavePath`, `openUrl`
and `revealPath`; dialogs resolve when they close and `openUrl` only accepts
http, https and mailto. The headless platform leaves these unimplemented, so
they are covered by protocol tests and manual runs only.
