use std::panic::{AssertUnwindSafe, catch_unwind};

/// Only unwind panics are recoverable. Callers terminate the affected operation;
/// they must not resume a UI loop whose state may have been partially changed.
pub(crate) fn catch<T>(operation: impl FnOnce() -> T) -> Result<T, String> {
    catch_unwind(AssertUnwindSafe(operation)).map_err(|payload| {
        let message = if let Some(message) = payload.downcast_ref::<String>() {
            message.clone()
        } else if let Some(message) = payload.downcast_ref::<&str>() {
            (*message).to_owned()
        } else {
            "Native panic with a non-string payload".to_owned()
        };
        // A custom panic payload may panic again in Drop at this C boundary.
        std::mem::forget(payload);
        message
    })
}

pub(crate) fn call<T>(fallback: T, operation: impl FnOnce() -> T) -> T {
    match catch(operation) {
        Ok(value) => value,
        Err(message) => {
            use std::io::Write;
            let _ = writeln!(std::io::stderr(), "GPUI-Dart native panic: {message}");
            fallback
        }
    }
}
