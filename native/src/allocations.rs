use std::{
    alloc::{GlobalAlloc, Layout, System},
    cell::Cell,
};

struct MeasuredAllocator;
#[global_allocator]
static ALLOCATOR: MeasuredAllocator = MeasuredAllocator;

thread_local! {
    static SAMPLE: Cell<Option<(u64, u64)>> = const { Cell::new(None) };
}

fn record(bytes: usize) {
    let _ = SAMPLE.try_with(|sample| {
        if let Some((calls, total)) = sample.get() {
            sample.set(Some((calls + 1, total + bytes as u64)));
        }
    });
}

// Counts successful requests on the test's UI thread, not live heap size or GPU memory.
unsafe impl GlobalAlloc for MeasuredAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let result = unsafe { System.alloc(layout) };
        if !result.is_null() {
            record(layout.size());
        }
        result
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let result = unsafe { System.alloc_zeroed(layout) };
        if !result.is_null() {
            record(layout.size());
        }
        result
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let result = unsafe { System.realloc(ptr, layout, size) };
        if !result.is_null() {
            record(size);
        }
        result
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) };
    }
}

pub(crate) fn measure(action: impl FnOnce()) -> (u64, u64) {
    struct Reset;
    impl Drop for Reset {
        fn drop(&mut self) {
            SAMPLE.with(|sample| sample.set(None));
        }
    }
    SAMPLE.with(|sample| {
        assert!(sample.get().is_none(), "Nested allocation measurement");
        sample.set(Some((0, 0)));
    });
    let _reset = Reset;
    action();
    SAMPLE.with(|sample| sample.get().unwrap())
}
