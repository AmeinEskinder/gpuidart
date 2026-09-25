# Platform feasibility probe

This executable is isolated from the production GPUI-Dart host. It uses the
same pinned GPUI Kit dependency. The initial UI follows the toolkit's
`examples/hello_world/src/main.rs` and adds an input, resize and bounded exit.

Build and run from the repository root:

```sh
cargo build --locked -p gpuidart-platform-probe
dart run tool/platform_probe/run.dart
```

On Windows first load `tool/env.ps1`. On Linux provide an X11 display and Vulkan
driver. The hosted job uses Xvfb and Mesa software rendering. The output directory
defaults to `build/platform-probe`; pass another path to retain separate attempts.

Each command has a deadline and separate stdout/stderr. `results.json` records
exit codes, timeout, tool versions and environment observations. The runner
returns failure if any launcher fails. In particular, macOS worker rejection
is an unsupported launch strategy, never a successful window check.

The probe reports native thread IDs and platform main-thread predicates. Windows
does not have a main-thread predicate in this probe and reports `-1`; compare its
executable entry and UI thread IDs directly. macOS uses `pthread_main_np`, Linux
uses `gettid() == getpid()`.

The Rust executable tries the process main thread and a worker in separate
processes. Dart JIT and AOT report application/runner thread identities, receive
an asynchronous ready callback, signal back to the UI loop and await its echo.
A periodic Dart timer proves that the application isolate remained runnable.
The native result requires both rendering and a render at the requested resized
viewport. Callback addresses remain live until the native runner returns.

Render callbacks do not establish physical presentation. VM-service startup is
captured, but service discovery, reload and application-state preservation need
separate probes. Button/input controls are available for input testing; the
initial automated run did not inject input. Linux runs with
`GPUIDART_PROBE_INPUT=1` now require both exact probe text and a button click.
`xdotool` drives the isolated X11 display. This does not claim human/IME
verification. The runner also requires a pre-quit resize checkpoint; macOS's
process-terminating quit path is recorded separately from a returned FFI call.

## Probe development failures

- The first native compile omitted `StyledExt` and assumed the toolkit window
  helper returned a handle instead of its handle/view pair. Corrected to the
  pinned API. A separate binary name avoids Windows PDB output collisions.
- The first Windows Dart load failed with error 127 because the probe DLL lacked
  the Common Controls manifest. The probe now reuses the SDK build script.
- The first Dart worker closure captured the enclosing async context and failed
  isolate message validation in JIT and AOT. A separate function now captures
  only the path and callback address. The failed logs remain in the report.
- The probe now uses the existing Windows DPI setup before loading the DLL;
  the first successful FFI run reported scale 1.0 while the native executable
  reported 1.25 on this desktop.
- The DPI change initially used a relative import from `lib/`, which failed
  hosted analysis. It now uses the package import. This was introduced after
  the earlier local analysis check and is retained in the CI evidence.
