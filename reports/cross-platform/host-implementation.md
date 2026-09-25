# Host implementation record

## Launch choices

The Phase 0 jobs [36183690786](https://github.com/AmeinEskinder/gpuidart/actions/runs/36183690786)
and [36184807862](https://github.com/AmeinEskinder/gpuidart/actions/runs/36184807862)
passed their applicable checks. The first established companion JIT/AOT and
actual code reload on both runners. The second added Linux direct-FFI reload
and synthetic GPUI input on the macOS native window. Both keep rejected macOS
worker launches explicitly unsupported. Metadata is retained beside this file;
the companion's raw [macOS reload](hosted-companion/macos/reload.json) and
[Linux reload](hosted-companion/linux/reload.json) records show stable process
and input identity through changed code, invalid-source rejection and recovery.

Implement Linux X11 with the existing blocking FFI runner. Implement macOS with
a native companion that owns the process main thread. The public Dart API and
snapshot/dataset JSON stay the same. The companion is a process boundary, not
Dart VM embedding, and must receive its own overhead measurements later.

These choices cover the declared test environments. Linux native Wayland, human
IME, physical presentation and hardware rendering on consumer Macs remain open.
The macOS input check bypasses OS event injection. Renderer enumeration is being
added because `system_profiler` did not identify a display device on the VM.

## Clock and Linux host changes

- Native trace timestamps use Windows QPC, Linux `CLOCK_MONOTONIC` nanoseconds,
  or raw macOS `mach_absolute_time` ticks. Dart calls the same OS clock.
- Each trace records its frequency, origin, epoch and suspend behavior. Linux
  records `clock_getres`. The QPC one-tick ordering allowance remains Windows
  specific; Unix ordering uncertainty is explicitly uncalibrated.
- A native clock read failure marks the trace incomplete without changing the
  application's UI lifecycle. Trace content omission and bounded storage remain.
- Library resolution retains explicit/environment/sibling/debug precedence and
  the ABI handshake. Linux uses `libgpuidart.so`. The macOS filename is defined,
  but its host remains gated until the companion lifecycle is implemented.
- Linux's real native host rejects Wayland/headless selection with an actionable
  error. The fault library remains usable in headless contract tests.
- `tool/check.dart` owns common checks and fixture compilation; the Windows
  wrapper still initializes its existing toolchain environment.
- Linux headless and X11 window CI are separate jobs. The latter runs real-window
  contracts, the 100k JIT/AOT trace workload and watchlist code reload.

Windows verification before the implementation commit passed 12 native and 27
Dart tests, formatting and analysis. The portable headless runner also passed
the same 12 native tests and 22 applicable Dart tests. Linux SDK execution passed
in [36186548153](https://github.com/AmeinEskinder/gpuidart/actions/runs/36186548153):
12 native tests, 22 headless Dart tests and five real-window Dart tests, plus the
100k JIT/AOT trace workload and actual watchlist reload. The renderer is X11 on
Xvfb with Mesa software Vulkan. Windows hosted checks passed at the same source,
`0893240`, in [36186548065](https://github.com/AmeinEskinder/gpuidart/actions/runs/36186548065).
No shipped Windows candidate was replaced.

The initial edit had one Rust import visibility error and three Dart formatting
lints. Those were corrected before the checks above. The dependency pin and
wire protocol are unchanged; `libc` was already pinned in the lockfile and is
now a direct dependency for Unix clock/thread calls.

## Clock contracts

[Linux's clock API](https://man7.org/linux/man-pages/man2/clock_gettime.2.html)
defines `CLOCK_MONOTONIC` as system-wide boot time excluding suspend, subject to
frequency adjustments. [Apple's Mach clock documentation](https://developer.apple.com/documentation/kernel/mach)
defines absolute uptime ticks excluding sleep; [the timebase documentation](https://developer.apple.com/library/archive/qa/qa1398/_index.html)
describes conversion. This is documented clock behavior. No sleep/resume or
physical presentation experiment has been performed by these checks.

## Owned Unix development sessions

The small `gpuidart-launcher` executable creates a new Unix session with
`setsid`, then replaces itself with Dart. Development teardown sends TERM to
that owned process group, waits at most two seconds, then sends KILL. It also
cleans descendants after the Dart parent exits and handles failure before
session creation. Windows retains `taskkill /T /F`.

The launcher has a separate, version-checked entry for the upcoming macOS UI
companion. It loads the SDK library dynamically so the helper does not include
a second statically linked GPUI copy.

Windows analysis and 22 headless Dart tests passed after this change. The two
new Unix checks exercise a descendant that ignores TERM after its parent exits,
and a failed exec. Both passed on macOS and Linux in
[36187694484](https://github.com/AmeinEskinder/gpuidart/actions/runs/36187694484).
The macOS clock probe now
identifies an Apple Paravirtual Metal device; this is a VM renderer, with no
physical GPU or presentation claim. Raw probe logs are in `hosted-clock/`.

## Initial macOS companion implementation, superseded by version 2

The production bridge now starts the native helper through lifecycle extension
version 1. The helper loads the same SDK dylib and calls its UI entry on the
process main thread. Dart retains the host handle, callback and all pending
acknowledgements until the child is reaped. A private inherited Unix socket
carries length-bounded internal frames; stdout is not part of this transport.
The public snapshot/dataset format and ABI version remain unchanged.

Both command queues have capacity 64, with bounded socket buffers and message
frames. This adds buffering and process cost compared with direct FFI. A native
watchdog terminates a child that has not exited four seconds after close.
macOS sends its final trace before AppKit terminates the child process. Missing
completion, early exit and malformed frames remain failures. A parent EOF closes
the child's UI queue. Unix development group cleanup covers forced parent exit.

Trace records identify their process. Both processes use the same OS clock;
enqueue-to-dequeue now includes socket transport and both queues. Each native
process has a bounded buffer, merged into the configured export capacity, with
overflow counted. Pending or missing child traces keep a capture incomplete.

Windows passed analysis, 12 native tests and all 27 Dart tests after these edits.
The added Unix frame, child failure, shutdown and trace-merge tests and full
macOS SDK jobs are pending hosted execution. The helper is also selectable on
Linux with the internal `GPUIDART_COMPANION=1` test switch. Linux's default remains
the verified direct FFI runner. No new performance claim is made.

## Child ownership correction

Source `7ad3b02` passed Linux's headless and window jobs, but macOS passed only
the headless job. Four real-window tests failed with `No child processes` when
Rust attempted to reap the native child. See
[36188527731](https://github.com/AmeinEskinder/gpuidart/actions/runs/36188527731)
and the retained `macos-companion-v1-failure/` logs. The 100k and reload checks
were not reached. This failure invalidates the first implementation's lifecycle
acceptance, despite the isolated companion probe having passed.

[Dart's macOS process implementation](https://dart.googlesource.com/sdk/+/refs/heads/main/runtime/bin/process_macos.cc)
uses `wait` for any child, then looks up the child's registered Dart exit pipe.
This source behavior explains the observed competing native waiter. Version 2
makes Dart the sole owner of child creation, exit status and termination. Rust
prepares a socket in a private mode-0700 directory, then runs bounded transport.
The helper connects by path, so it does not depend on Dart inheriting arbitrary
file descriptors. Host disposal waits for both transport return and Dart's
reported child exit. A four-second Dart timer kills a stuck closing companion;
the child has an independent four-second exit fallback after parent EOF.

New live-library regression cases cover an early child exit and a child that
never connects, including reaping. Native tests cover frame bounds and private
socket cleanup. The previous Rust-spawn tests were removed with that launch
path. Windows passed analysis, 12 native tests and 27 Dart tests after the fix;
the revised Unix lifecycle still requires hosted verification.

Runtime diagnostics now enumerate loaded images and per-process memory/CPU on
Unix. Linux reports executable file mappings and `smaps_rollup` counters; macOS
reports dyld images, resident size and physical footprint. These probes run only
when requested and will support package verification and separate process
baselines. They do not turn startup or publication timestamps into presentation
measurements.

The first version-2 CI attempt, `fed9f5f`, failed during macOS compilation of
the new runtime probe: Darwin's `timeval.tv_usec` is 32-bit, while the seconds
field is 64-bit. Conversion to 64-bit before arithmetic fixes this target type
difference. The window job was skipped, so that attempt supplies no evidence
about the revised child lifecycle. Its compile log is retained separately.

At `7d05024`, the revised child-failure/reaping tests passed on macOS, and Linux
passed its full jobs. The macOS live host then exposed Darwin's inheritance of
`O_NONBLOCK` on accepted sockets, producing `Resource temporarily unavailable`
before reading a reply. Linux does not inherit that flag. The accept boundary
now explicitly selects blocking mode; a real-socket regression waits for a
delayed frame. This second window failure is retained in
`macos-socket-mode-failure.log`. It is separate from the fixed child-reaping bug.
