# Host failures

## Native boundary

The exported FFI functions catch Rust panics that unwind to the adapter boundary. Submission and runner functions return `-4` for a caught panic. Creation returns a null pointer. Void cleanup functions log caught panics to stderr. A caught UI-loop panic emits an error event followed by closed and clears the running flag before returning. The process must discard that host.

This is limited containment. Rust aborts, access violations, invalid FFI pointers, and panics inside non-unwinding platform callbacks can still terminate the process. A catch around `gd_run` cannot recover those failures. See Rust's [catch_unwind contract](https://doc.rust-lang.org/std/panic/fn.catch_unwind.html) and [FFI unwinding rules](https://doc.rust-lang.org/nomicon/ffi.html#ffi-and-unwinding).

Retained input, table and dataset lookups return errors when an entry is missing. Publication validates the complete snapshot before changing the view. If native retained state becomes inconsistent, the view reports an error and requests shutdown.

Development and test builds retain line-table debug information for the adapter crate. Dependencies keep their existing stripped profiles. Release builds explicitly use Rust unwinding so the boundary guards are active.

## Native regression evidence

`cargo test --locked -p gpuidart` passes ten tests after this hardening. The exported-function test exercises invalid messages, singleton creation, the 64-command queue limit, close while full, an injected UI-loop unwind, error/closed delivery and subsequent host creation. A headless test checks missing retained controls and datasets return errors. These tests do not claim recovery from a GPUI platform-callback abort.

## Dart protocol and deadlines

The Dart callback validates UTF-8, the event envelope and required field types before updating host state or completing requests. It exposes immutable event data. A malformed event, a mismatched dataset acknowledgement or a native error fails outstanding requests and closes the host. Native submission status `-4` also closes the host. Ordinary validation and queue-full errors reject the request without closing it.

`GpuiHost.open` and `openView` accept `requestTimeout`, defaulting to 30 seconds, and `shutdownTimeout`, defaulting to 10 seconds. Both must be positive. The request deadline covers startup, snapshot publication, dataset transactions and diagnostics. A missing acknowledgement produces `TimeoutException` and closes the host. The change may already have applied in Rust, so retrying on that host is unsafe. Dart commits a dataset change only after a matching acknowledgement.

`close()` and `done` complete normally after native teardown. They can fail before teardown if the shutdown deadline expires. In that case the host retains its native allocation, callback and runner isolate until `gd_run` actually returns. A late return performs cleanup. If the native loop never returns, the application needs process termination to recover; a timeout cannot safely kill a thread inside FFI or free memory it may still use. Do not open another host after a shutdown timeout.

The native event subscription receives a terminal error event. Await or handle request futures and `done` as well. Stop application timers and event handlers when the host fails. The SDK catches protocol handling errors, not exceptions in application event listeners.

## Dart regression evidence

`./tool/check.ps1` builds the test-only `test/fixtures/fault_host.rs` DLL under `.cache` before running Dart tests. The fixture uses the public ABI to send malformed events, omit acknowledgements, mismatch dataset identity, report a native failure, omit closed and delay native exit. It counts allocated/freed event buffers and early destruction attempts. The test checks that failed transactions preserve Dart data and shutdown never destroys a running host.

The 23 Dart tests also cover pure Dart schema validation, immutable data, Unicode JSON encoding, native event decoding, launcher readiness and the real GPUI window. All passed locally. The fixture is not included in application packages.
