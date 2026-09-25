#[derive(Clone, Copy)]
pub(crate) struct Stamp {
    pub ticks: i64,
    pub thread: u64,
}

pub(crate) fn now() -> Option<Stamp> {
    #[cfg(target_os = "windows")]
    {
        #[link(name = "kernel32")]
        unsafe extern "system" {
            fn QueryPerformanceCounter(value: *mut i64) -> i32;
            fn GetCurrentThreadId() -> u32;
        }
        let mut ticks = 0;
        (unsafe { QueryPerformanceCounter(&mut ticks) } != 0).then(|| Stamp {
            ticks,
            thread: unsafe { GetCurrentThreadId() }.into(),
        })
    }
    #[cfg(target_os = "linux")]
    {
        let mut time = libc::timespec {
            tv_sec: 0,
            tv_nsec: 0,
        };
        (unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut time) } == 0).then(|| Stamp {
            ticks: time.tv_sec * 1_000_000_000 + time.tv_nsec,
            thread: unsafe { libc::gettid() } as u64,
        })
    }
    #[cfg(target_os = "macos")]
    {
        let mut thread = 0;
        (unsafe { libc::pthread_threadid_np(0, &mut thread) } == 0).then(|| Stamp {
            ticks: unsafe { libc::mach_absolute_time() } as i64,
            thread,
        })
    }
}
