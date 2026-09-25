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
the same 12 native tests and 22 applicable Dart tests. Linux SDK execution is
pending its first hosted run. No shipped Windows candidate was replaced.

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
