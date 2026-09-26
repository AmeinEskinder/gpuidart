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

### Japanese input with Fcitx5 on X11

The [Ubuntu desktop VM observation](../reports/ime/linux-japanese-20260926/README.md)
passed Japanese composition, editing and active-composition code reload with
Fcitx5 5.1.7 and Mozc. Use `XMODIFIERS=@im=fcitx` and enable **Use On The Spot**
in Fcitx's XIM frontend before starting the desktop session. Its config file is
`~/.config/fcitx5/conf/xim.conf`, with `UseOnTheSpot=True`.

The default setting in that environment left preedit outside the input and
misplaced the candidates. Replacing Fcitx inside the running Openbox session
then stalled the window manager's XIM teardown; a fresh guest desktop session
with the setting already applied worked. Configure the option before logging
in for this tested setup. This result does not establish IBus, other IMEs or
native Wayland support.

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
The separate [clean Ubuntu VM check](../reports/ime/linux-japanese-20260926/README.md#clean-launch)
passed the MIT package on Xorg/Openbox, including normal search/save/update and
window closure. It used a virtual display and software Vulkan.

## Human input and display observation sheet

Create one retained report per OS/backend. Record artifact hash/source, OS,
CPU, GPU/driver, compositor or WindowServer, monitor resolutions/scales, input
device, keyboard layout and the exact IME name/version. Mark each item pass,
fail or untested; include notes and captures for failures and composition.

| Check | macOS 15 ARM64 | Ubuntu 24.04 X11 |
| --- | --- | --- |
| Normal launch and window close leave no companion | Untested | Agent-observed pass in VM |
| Mouse selection, keyboard navigation, copy/paste and undo/redo | Untested | Agent-observed pass in VM |
| IME preedit and candidate window follow the caret | Untested | Pass with configured Fcitx5/Mozc; default failed |
| Candidate navigation and commit insert text exactly once | Untested | Agent-observed pass with configured Fcitx5/Mozc |
| Escape cancels composition without residual text | Untested | Agent-observed pass with configured Fcitx5/Mozc |
| Non-ASCII selection/replacement, Backspace/Delete and arrows | Untested | Agent-observed pass with configured Fcitx5/Mozc |
| Scroll and resize preserve usable controls and focus | Untested | Agent-observed pass at recorded VM sizes |
| Code reload preserves committed input, focus, selection and scroll | Untested | Screenshots and state assertions passed |
| Reload during active composition, with actual outcome recorded | Untested | Preedit survived; subsequent conversion and single commit passed |
| Retina / fractional scaling and mixed-monitor movement | Untested | Untested |

For macOS, use an installed Apple Japanese/Chinese/Korean input source and
record its selection. For Linux, record the installed IBus/Fcitx configuration,
XIM environment and input module in use. Starting an IME service or injecting
Unicode does not establish composition support. Verify preedit, candidate
placement, commit and cancellation through the actual input method.

The owner explicitly authorized screenshot/tool observation. The Linux entries
above refer to [the retained agent observation](../reports/ime/linux-japanese-20260926/README.md),
not an independent human observer or inferred passes from automated Unicode
injection. Physical display checks and the macOS sheet remain open.
