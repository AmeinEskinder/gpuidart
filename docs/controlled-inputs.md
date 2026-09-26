# Controlled text inputs

Inputs remain native-retained by default. Opt into application writes with
`UiInput('name', controlled: true)`. Snapshots still contain no input text.

```dart
final base = await host.readInput('name');
try {
  final applied = await host.writeInput(
    base,
    text: 'Dart',
    selection: const UiTextSelection(4, 4),
  );
  print(applied.editRevision);
} on InputWriteException catch (error) {
  // Inspect error.reason and error.current; do not blindly overwrite an edit.
}
```

`readInput` and `writeInput` use an acknowledged command on the bounded native
channel, including normal request deadlines and failure settlement. They are
available through the public SDK import. The optional `gd_input` native export
is resolved on first use; a missing export reports a rebuild instruction. Build
the native library and macOS launcher from the same SDK revision.

## Ownership and conflicts

Each state includes the input ID, generation, edit revision, text (`value`),
forward selection and `composing` flag. Removing/recreating an input or changing
its controlled mode changes its generation. The edit revision advances when
the host observes a change in text, selection or composition. It is a conflict
token, not a keystroke count: GPUI can coalesce notifications. Each command also
samples the current native state before validating its token.

Writes are atomic for text and selection. Rejections preserve native state and
return `InputWriteException` with a reason and the current state:

| Reason | Meaning |
| --- | --- |
| `missing` | Input removed; current state is null |
| `not_controlled` | Application writes were not enabled |
| `composing` | Marked native IME composition is active |
| `stale` | Generation or edit revision differs from the supplied base |
| `invalid_selection` | Selection exceeds the resulting text or splits a UTF-16 surrogate pair |

Composition conflicts take precedence over stale revisions. No rejected write
is saved for later. Let native composition finish, obtain a fresh state, then
decide whether retrying still matches the user's intent. `unmark_text` can end
composition without a notification in the pinned Kit; `readInput` and writes
resample it. Native controlled edits emit `input` events with `event.inputState`;
selection/composition changes can also emit those events without changing text.
Programmatic writes do not echo user-input events and do not move focus.

Selections use UTF-16 code units, matching Dart string offsets. Only forward
ranges are exposed. Native grapheme boundaries may further adjust a valid
selection; use the acknowledged selection. Writes accept at most 1 MiB of valid
UTF-8 text. Replacing text uses Kit's value setter and clears its undo history;
selection-only and no-op writes preserve it. An omitted selection after text
replacement uses Kit's default cursor placement. Application snapshots alone
never reset text, selection, composition or undo.

## Evidence scope

Native tests drive GPUI's actual input handler through marked composition,
commit and unmark, and prove write rejection and state preservation. The
live-window test verifies FFI acknowledgements, Unicode selection, conflicts,
generations, absence of input echoes and correlated traces. See
[control-catalog evidence](../reports/control-catalog/README.md).

These software tests do not establish OS IME behavior for this new write path.
Earlier Windows and Linux IME observations cover native-retained input. macOS
IME remains unverified. No presentation timing claim follows from a write ack.
