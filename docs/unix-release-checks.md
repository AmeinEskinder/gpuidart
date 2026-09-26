# macOS and Linux release checks

These instructions cover the initial targets: macOS 15 on ARM64 and Ubuntu
24.04 x64 with glibc 2.39 and X11. Native Wayland, Intel Macs and older OS
versions are unverified. Windows has its own release checklist.

## Build and extract

From the repository root with the pinned Dart and Rust toolchains:

```sh
dart run tool/build.dart
dart run tool/check.dart
dart run tool/package.dart --name=Watchlist
dart run tool/verify_package.dart build/Watchlist-linux-x64.tar.gz build/linux-package.json
# On macOS, use Watchlist-macos-arm64.tar.gz and a separate report path.
```

The package command builds the native library in release mode and the Dart
application as AOT. The Linux archive contains the application, shared library
and launcher. The macOS archive contains an `.app` bundle whose `Contents/MacOS`
directory holds those files. Keep the complete archive contents together.
The standalone `verify` executable includes its own AOT runtime.

The verifier checks hashes, `ldd` or `otool -L`, actual loaded-image paths in
both application and UI processes, and the watchlist self-test. It uses a fresh
home directory, an unrelated working directory and a restricted environment.
It checks native window dimensions and records scale. A positive scale at one
setting does not prove Retina, fractional scaling or mixed-monitor behavior.

The supplied watchlist implements the verifier's internal `--self-test`
contract: one JSON object with `passed: true`, `mode: "aot"`, native window
geometry, and runtime diagnostics for application/UI processes. A custom entry
point must supply equivalent checks; a successful process exit alone is not a
verification pass. Use [the watchlist entry point](../example/watchlist/main.dart)
as the current reference. This diagnostic format is not a public SDK API.

## Linux runtime environment

Use an X11 session with `DISPLAY` set. Unset `WAYLAND_DISPLAY` and `ZED_HEADLESS`
when launching this initial host. The native host rejects other backends.

The system supplies glibc, libstdc++, Fontconfig, FreeType, X11/XCB, xkbcommon,
Wayland client libraries used by the compiled backend, GLib, OpenSSL, Zstandard
and a Vulkan implementation. The retained dependency inspection is the
authoritative list for each artifact. For the software-rendered container
check, CI installs Mesa Vulkan plus Xvfb, Openbox, xauth and fonts. That check
does not establish a physical GPU or desktop compositor result.

## macOS distribution

The evaluation bundle declares macOS 15 and high-resolution capability. Its
code has ad-hoc signatures, checked by the verifier. It is not a Developer ID
release and has not been notarized. Do not disable Gatekeeper to turn this
into a claimed distribution pass.

GPUI-Dart uses the MIT License; the archive includes `LICENSE`. Dependencies
retain their own terms in the accompanying license files and inventory.

Before public distribution, sign every shipped
executable/library and the app with the owner's Developer ID, enable and test
the hardened runtime with the required entitlements, submit with `notarytool`,
and staple/validate the ticket. Repeat the extracted-package tests on the exact
signed artifact and on a clean Mac with quarantine intact. See
[Apple's distribution guidance](https://developer.apple.com/developer-id/) and
[notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
The current work does not establish which hardened-runtime entitlements the
Dart FFI callbacks require.

## Clean environment

1. Provision a separate machine or VM without Dart, Flutter, Rust or build tools.
   Record image, OS version, architecture and installed runtime packages.
2. Copy the archive, record its SHA-256 and extract it outside a source checkout.
3. Run `./verify --runtime-only --environment=clean_vm --report=verification.json`. Use
   `clean_machine` for a physical machine. These values record an operator's
   declaration; they do not certify how the environment was provisioned.
   `--runtime-only` uses the package's recorded build-time `otool`/`ldd`
   inspection, verifies file hashes and inspects actual loaded images. It does
   not run the inspection tool again; macOS `otool` belongs to the developer
   toolchain. Default verification reruns that tool when available.
4. Retain the report even if it fails. Record missing dependencies before
   installing them, then retain the later attempt separately.
5. Launch the application normally, including Finder on macOS. Search for
   `ALP0000`, select it, add it to the shortlist and simulate a price update.
   Confirm the price reads `100.07` and the instrument remains saved.

Linux CI also uses a fresh Ubuntu container without development SDKs, recording
`clean_container`. This establishes that container's runtime dependency closure.
It does not replace the clean desktop/VM check or its human observations.

## Human input and display observation sheet

Create one retained report per OS/backend. Record artifact hash/source, OS,
CPU, GPU/driver, compositor or WindowServer, monitor resolutions/scales, input
device, keyboard layout and the exact IME name/version. Mark each item pass,
fail or untested; include notes and captures for failures and composition.

| Check | macOS 15 ARM64 | Ubuntu 24.04 X11 |
| --- | --- | --- |
| Normal launch and window close leave no companion | Untested | Untested |
| Mouse selection, keyboard navigation, copy/paste and undo/redo | Untested | Untested |
| IME preedit and candidate window follow the caret | Untested | Untested |
| Candidate navigation and commit insert text exactly once | Untested | Untested |
| Escape cancels composition without residual text | Untested | Untested |
| Non-ASCII selection/replacement, Backspace/Delete and arrows | Untested | Untested |
| Scroll and resize preserve usable controls and focus | Untested | Untested |
| Code reload preserves committed input, focus, selection and scroll | Untested | Untested |
| Reload during active composition, with actual outcome recorded | Untested | Untested |
| Retina / fractional scaling and mixed-monitor movement | Untested | Untested |

For macOS, use an installed Apple Japanese/Chinese/Korean input source and
record its selection. For Linux, record the installed IBus/Fcitx configuration,
XIM environment and input module in use. Starting an IME service or injecting
Unicode does not establish composition support. Verify preedit, candidate
placement, commit and cancellation through the actual input method.

The project has no human pass recorded for these Unix sheets. Automated checks
must not fill the table with inferred passes.
