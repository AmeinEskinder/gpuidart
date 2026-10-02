use std::{
    sync::LazyLock,
    time::{Duration, Instant},
};

use anyhow::{Context, Result};
use gpui_util::ResultExt;
use windows::Win32::{
    Foundation::{HANDLE, HWND},
    Graphics::Dwm::{DWM_TIMING_INFO, DwmFlush, DwmGetCompositionTimingInfo},
    System::{
        Performance::{QueryPerformanceCounter, QueryPerformanceFrequency},
        Threading::{
            CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, CreateWaitableTimerExW, SetWaitableTimer,
            TIMER_ALL_ACCESS, WaitForSingleObject,
        },
    },
};

static QPC_TICKS_PER_SECOND: LazyLock<u64> = LazyLock::new(|| {
    let mut frequency = 0;
    // On systems that run Windows XP or later, the function will always succeed and
    // will thus never return zero.
    unsafe { QueryPerformanceFrequency(&mut frequency).unwrap() };
    frequency as u64
});

const VSYNC_INTERVAL_THRESHOLD: Duration = Duration::from_millis(1);
const DEFAULT_VSYNC_INTERVAL: Duration = Duration::from_micros(16_666); // ~60Hz

pub(crate) struct VSyncProvider {
    interval: Duration,
    f: Box<dyn Fn() -> bool>,
}

impl VSyncProvider {
    pub(crate) fn new() -> Self {
        let interval = get_dwm_interval()
            .context("Failed to get DWM interval")
            .log_err()
            .unwrap_or(DEFAULT_VSYNC_INTERVAL);
        let f = Box::new(|| unsafe { DwmFlush().is_ok() });
        Self { interval, f }
    }

    pub(crate) fn wait_for_vsync(&self) {
        let vsync_start = Instant::now();
        let wait_succeeded = (self.f)();
        let elapsed = vsync_start.elapsed();
        // DwmFlush and DCompositionWaitForCompositorClock returns very early
        // instead of waiting until vblank when the monitor goes to sleep or is
        // unplugged (nothing to present due to desktop occlusion). We use 1ms as
        // a threshold for the duration of the wait functions and fallback to
        // Sleep() if it returns before that. This could happen during normal
        // operation for the first call after the vsync thread becomes non-idle,
        // but it shouldn't happen often.
        if !wait_succeeded || elapsed < VSYNC_INTERVAL_THRESHOLD {
            log::trace!("VSyncProvider::wait_for_vsync() took less time than expected");
            std::thread::sleep(self.interval);
        }
    }
}

fn get_dwm_interval() -> Result<Duration> {
    let mut timing_info = DWM_TIMING_INFO {
        cbSize: std::mem::size_of::<DWM_TIMING_INFO>() as u32,
        ..Default::default()
    };
    unsafe { DwmGetCompositionTimingInfo(HWND::default(), &mut timing_info) }?;
    let interval = retrieve_duration(timing_info.qpcRefreshPeriod, *QPC_TICKS_PER_SECOND);
    // Check for interval values that are impossibly low. A 29 microsecond
    // interval was seen (from a qpcRefreshPeriod of 60).
    if interval < VSYNC_INTERVAL_THRESHOLD {
        Ok(retrieve_duration(
            timing_info.rateRefresh.uiDenominator as u64,
            timing_info.rateRefresh.uiNumerator as u64,
        ))
    } else {
        Ok(interval)
    }
}

#[inline]
fn retrieve_duration(counts: u64, ticks_per_second: u64) -> Duration {
    let ticks_per_microsecond = ticks_per_second / 1_000_000;
    Duration::from_micros(counts / ticks_per_microsecond)
}

/// `GPUI_FRAME_PACING=0` turns the pacing off; `GPUI_FRAME_PACING_MARGIN_US`
/// replaces the margin, for finding it.
const FRAME_PACING: &str = "GPUI_FRAME_PACING";
const FRAME_PACING_MARGIN_US: &str = "GPUI_FRAME_PACING_MARGIN_US";
/// How long before the vertical blank a present must be made to be composed
/// at it. Found by sweeping the margin on the burst workload on 2026-09-30 (series pace-*-burst-20260930h): the smallest margin at which at least 99 percent of frames were still shown at the second blank.
const FRAME_PACING_MARGIN: Duration = Duration::from_micros(5000);
/// The draw time assumed before there are samples.
const UNMEASURED_DRAW: Duration = Duration::from_millis(5);

struct DrawTimes {
    micros: [u32; 128],
    next: usize,
    len: usize,
}

static DRAW_TIMES: std::sync::Mutex<DrawTimes> = std::sync::Mutex::new(DrawTimes {
    micros: [0; 128],
    next: 0,
    len: 0,
});

/// A draw that presented took this long from its paint message to the end of
/// the present; the pacer reserves the recent 99th percentile.
pub(crate) fn record_draw(duration: Duration) {
    let mut times = DRAW_TIMES
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let at = times.next;
    times.micros[at] = duration.as_micros().min(u32::MAX as u128) as u32;
    times.next = (at + 1) % times.micros.len();
    times.len = (times.len + 1).min(times.micros.len());
}

fn recent_draw_time() -> Duration {
    let times = DRAW_TIMES
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if times.len < 8 {
        return UNMEASURED_DRAW;
    }
    let mut sorted = times.micros[..times.len].to_vec();
    sorted.sort_unstable();
    let index = (sorted.len() * 99).div_ceil(100).saturating_sub(1);
    Duration::from_micros(sorted[index] as u64)
}

/// Frame pacing. The vsync wait returns just after the compositor's pass,
/// and a frame drawn at once is presented early in the refresh interval and
/// then waits the rest of it for the next pass. The pacer holds the
/// invalidation back so that the present lands late in the interval instead:
/// until the next vertical blank, less the margin the compositor needs, less
/// the recent 99th percentile of the draw time. A frame then carries input
/// up to that later moment and reaches the display at the same blank. When
/// draws are long the wait is zero and the tick behaves as before.
pub(crate) struct FramePacer {
    timer: Option<HANDLE>,
    margin: Option<Duration>,
}

impl FramePacer {
    pub(crate) fn new() -> Self {
        let off = std::env::var(FRAME_PACING).is_ok_and(|value| value == "0");
        let margin = std::env::var(FRAME_PACING_MARGIN_US)
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .map(Duration::from_micros)
            .unwrap_or(FRAME_PACING_MARGIN);
        // A high-resolution waitable timer: Sleep rounds to the scheduler's
        // tick, which is most of what there is to wait.
        let timer = unsafe {
            CreateWaitableTimerExW(
                None,
                windows::core::PCWSTR::null(),
                CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                TIMER_ALL_ACCESS.0,
            )
        }
        .ok();
        Self {
            timer,
            margin: (!off).then_some(margin),
        }
    }

    pub(crate) fn wait(&self) {
        let (Some(timer), Some(margin)) = (self.timer, self.margin) else {
            return;
        };
        let mut timing = DWM_TIMING_INFO {
            cbSize: std::mem::size_of::<DWM_TIMING_INFO>() as u32,
            ..Default::default()
        };
        if unsafe { DwmGetCompositionTimingInfo(HWND::default(), &mut timing) }.is_err() {
            return;
        }
        let period = timing.qpcRefreshPeriod as i64;
        if period <= 0 {
            return;
        }
        let mut now = 0i64;
        if unsafe { QueryPerformanceCounter(&mut now) }.is_err() {
            return;
        }
        let ticks_per_second = *QPC_TICKS_PER_SECOND as i64;
        let to_blank = period - (now - timing.qpcVBlank as i64).rem_euclid(period);
        let reserve =
            (margin + recent_draw_time()).as_micros() as i64 * ticks_per_second / 1_000_000;
        let wait = to_blank - reserve;
        if wait <= 0 {
            return;
        }
        // A relative due time, in 100 ns units.
        let due = -(wait * 10_000_000 / ticks_per_second);
        unsafe {
            if SetWaitableTimer(timer, &due, 0, None, None, false).is_ok() {
                WaitForSingleObject(timer, 100);
            }
        }
    }
}
