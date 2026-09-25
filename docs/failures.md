# Host failures

## Native boundary

The exported FFI functions catch Rust panics that unwind to the adapter boundary. Submission and runner functions return `-4` for a caught panic. Creation returns a null pointer. Void cleanup functions log caught panics to stderr. A caught UI-loop panic emits an error event followed by closed and clears the running flag before returning. The process must discard that host.

This is limited containment. Rust aborts, access violations, invalid FFI pointers, and panics inside non-unwinding platform callbacks can still terminate the process. A catch around `gd_run` cannot recover those failures. See Rust's [catch_unwind contract](https://doc.rust-lang.org/std/panic/fn.catch_unwind.html) and [FFI unwinding rules](https://doc.rust-lang.org/nomicon/ffi.html#ffi-and-unwinding).

Retained input, table and dataset lookups return errors when an entry is missing. Publication validates the complete snapshot before changing the view. If native retained state becomes inconsistent, the view reports an error and requests shutdown.

Development and test builds retain line-table debug information for the adapter crate. Dependencies keep their existing stripped profiles. Release builds explicitly use Rust unwinding so the boundary guards are active.

## Native regression evidence

`cargo test --locked -p gpuidart` passes ten tests after this hardening. The exported-function test exercises invalid messages, singleton creation, the 64-command queue limit, close while full, an injected UI-loop unwind, error/closed delivery and subsequent host creation. A headless test checks missing retained controls and datasets return errors. These tests do not claim recovery from a GPUI platform-callback abort.
