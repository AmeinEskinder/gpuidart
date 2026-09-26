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

Radio groups, switches, tabs, tooltips, sheets, and general lists are deferred.
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
Native slider dragging and select popup state are retained for interaction.
Snapshot writes are authoritative. Applications must process requests in
delivery order; event revisions identify their source, and must not be used to
discard valid requests merely because a newer snapshot was published. Disabled
controls produce no change requests. Unrelated snapshots retain focus and
existing entity identity and must not reopen or dismiss a select popup.

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
