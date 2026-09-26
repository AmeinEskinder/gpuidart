# Windows release checks

Use the built gpuidart-windows-x64.zip. The interaction steps below exercise the supplied Market watch example; adapt them when packaging a different entry point. Record the ZIP hash, Windows build, display scale and input method with the result. Automated local verification is in reports/sdk/package.json; it does not replace these checks.

A custom application's `--self-test` must write one UTF-8 JSON object to stdout,
with `mode: "aot"` and boolean `passed: true`. Write diagnostics to UTF-8 stderr.
The standalone verifier preserves non-ASCII text in both streams and rejects
malformed UTF-8.

## Fresh Windows machine or VM

1. Use a newly provisioned Windows x64 machine/VM without Dart, Flutter, Rust or Visual Studio. Record its image/version and installed prerequisites. Do not copy SDKs from the development machine.
2. Extract the complete ZIP. Keep the DLLs beside the executable.
3. Open PowerShell in the extracted directory and run:

   ```powershell
   ./verify.ps1 -Environment clean_vm
   ```

   Use clean_machine for a separate clean physical machine. This option records the operator's declaration; the script does not provision or independently certify a clean environment.
4. Retain verification.json, including the exact package hashes and loaded modules. If it fails, retain the console error and do not install missing prerequisites until recording the original failure.
5. Launch gpuidart.exe normally. Search for ALP0000, select it, add it to the shortlist, simulate a price update, then toggle the shortlist view. Confirm the price reads 100.07 and the row remains saved.
6. Repeat at 125% or 150% scaling. If two differently scaled monitors are available, move the window between them and check text, input caret/candidate placement, hit targets and clipping.

## Human input and IME composition

Use an installed Japanese, Chinese or Korean IME, and record its exact name/version.

1. Focus the search input. Start composing text without committing it. Verify the marked text and candidate window are visible and anchored at the caret.
2. Move through candidates, commit one, and verify the committed text appears exactly once. Unmatched text should show the empty-results message.
3. Compose again and cancel with Escape. Confirm there is no duplicate or residual preedit text.
4. Select part of a string containing non-ASCII characters. Replace it using the IME, then exercise Backspace, Delete, arrows, selection, copy/paste and undo/redo.
5. During JIT development, change WatchlistApplication.heading and save while the input has text, focus and a selection. Confirm the changed heading and preserved input. Separately try reload while composition is active and record the actual outcome.
6. Clear the search, select rows with the mouse and keyboard, scroll, resize and activate each toolbar action. Confirm no hidden or clipped controls and no unexpected focus changes.

Record pass/fail per step, not a single inferred pass. Include screenshots or a short capture of composition and candidate placement. Do not substitute Unicode character injection for IME composition. No input-to-present timing is claimed by these checks.
