# Preferences example

Run `dart run example/settings/main.dart` after building the native host with
`dart run tool/build.dart`. For development reload, use
`dart run tool/dev.dart example/settings/main.dart`.

General edits a controlled display name and a notifications checkbox.
Appearance selects an accent and changes preview spacing with a slider. Apply
saves the draft in memory for this session. Reset defaults opens a confirmation
dialog; cancellation preserves both draft and saved preferences. Confirmation
changes only the draft until Apply. These preferences do not change OS settings.

Tab moves between controls. Space toggles the checkbox. Down opens the select;
arrows and Enter choose an option. Slider arrows step by two, with Home/End for
the endpoints. Escape cancels a dialog, Enter confirms it. The native dialog
restores trigger focus after its closing animation.

Name writes use `readInput`/`writeInput` with generation and edit-revision guards.
Navigation and Apply check composition before reading the name. A conflicting
restore keeps the user's newer edit; a conflicting reset reports that it must
be retried. Full snapshots retain a mounted input's text, selection and focus.
Switching sections removes the input and restores its draft value when returning.

## Verification

```
dart run tool/verify_settings.dart build/settings-jit.json
dart compile exe tool/verify_settings.dart -o build/settings-check
```

Place the native library beside the executable (and the companion launcher on
macOS), then run it with a new report path. The verifier refuses to overwrite
evidence. It opens the real application and dispatches native GPUI keys, checking
the application state, native values, retained input identity/selection/focus,
dialog results and focus restoration. It saves a correlated trace alongside the
report. It does not inject OS input or verify hardware IME or presentation.

Preferences are intentionally not persisted to disk. This example demonstrates
the SDK controls and application-state ownership, not a settings storage system.
