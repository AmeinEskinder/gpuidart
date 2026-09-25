use gpui_kit::component::StyledExt;
use gpui_kit::component::{
    button::Button,
    input::{Input, InputState},
};
use gpui_kit::*;
use std::sync::{
    Arc,
    atomic::{AtomicU32, Ordering},
};
use std::time::Duration;

static SIGNAL: AtomicU32 = AtomicU32::new(0);

#[unsafe(no_mangle)]
pub extern "C" fn gdp_thread_id() -> u64 {
    #[cfg(target_os = "windows")]
    {
        #[link(name = "kernel32")]
        unsafe extern "system" {
            fn GetCurrentThreadId() -> u32;
        }
        unsafe { GetCurrentThreadId() as u64 }
    }
    #[cfg(target_os = "linux")]
    {
        unsafe { libc::gettid() as u64 }
    }
    #[cfg(target_os = "macos")]
    {
        let mut id = 0;
        unsafe {
            libc::pthread_threadid_np(0, &mut id);
        }
        id
    }
}

/// -1 means no platform main-thread predicate was implemented in this probe.
#[unsafe(no_mangle)]
pub extern "C" fn gdp_is_main_thread() -> i32 {
    #[cfg(target_os = "macos")]
    {
        unsafe { libc::pthread_main_np() }
    }
    #[cfg(target_os = "linux")]
    {
        i32::from(gdp_thread_id() == u64::from(std::process::id()))
    }
    #[cfg(target_os = "windows")]
    {
        -1
    }
}

pub fn report(stage: &str, detail: serde_json::Value) {
    println!(
        "{}",
        serde_json::json!({
            "stage": stage, "pid": std::process::id(), "thread": gdp_thread_id(),
            "main_thread": gdp_is_main_thread(), "os": std::env::consts::OS,
            "arch": std::env::consts::ARCH, "detail": detail,
        })
    );
}

type Callback = extern "C" fn(u32);

struct Probe {
    input: Entity<InputState>,
    renders: Arc<AtomicU32>,
    clicks: Arc<AtomicU32>,
    resized: Arc<AtomicU32>,
}

impl Render for Probe {
    fn render(&mut self, window: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let count = self.renders.fetch_add(1, Ordering::Relaxed) + 1;
        if window.viewport_size() == size(px(720.), px(420.)) {
            self.resized.store(1, Ordering::Release);
        }
        if count <= 3 {
            report(
                "render",
                serde_json::json!({"count": count, "size": format!("{:?}", window.viewport_size()), "scale": window.scale_factor()}),
            );
        }
        let clicks = self.clicks.clone();
        div()
            .v_flex()
            .gap_2()
            .p_4()
            .size_full()
            .child("GPUI-Dart platform probe")
            .child(Input::new(&self.input))
            .child(
                Button::new("probe-button")
                    .label("Probe click")
                    .on_click(move |_, _, _| {
                        let count = clicks.fetch_add(1, Ordering::Relaxed) + 1;
                        report("click", serde_json::json!({"count": count}));
                    }),
            )
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn gdp_signal(value: u32) {
    SIGNAL.store(value, Ordering::Release);
}

/// Isolated feasibility ABI. Callback must remain live until this call returns.
#[unsafe(no_mangle)]
pub extern "C" fn gdp_run(callback: Option<Callback>) -> i32 {
    match std::panic::catch_unwind(|| run(callback)) {
        Ok(status) => status,
        Err(_) => {
            report("panic", serde_json::Value::Null);
            -20
        }
    }
}

fn run(callback: Option<Callback>) -> i32 {
    report("run_enter", serde_json::Value::Null);
    if cfg!(target_os = "macos") && gdp_is_main_thread() != 1 {
        report("rejected_non_main_thread", serde_json::Value::Null);
        return -10;
    }
    SIGNAL.store(0, Ordering::Release);
    let renders = Arc::new(AtomicU32::new(0));
    let clicks = Arc::new(AtomicU32::new(0));
    let result_renders = renders.clone();
    let result_clicks = clicks.clone();
    let resized = Arc::new(AtomicU32::new(0));
    let result_resized = resized.clone();
    let opened = Arc::new(AtomicU32::new(0));
    let result_opened = opened.clone();
    gpui_kit::application().run(move |cx| {
        report("app_callback", serde_json::Value::Null);
        gpui_kit::init(cx);
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::centered(size(px(640.), px(360.)), cx)),
            titlebar: Some(TitlebarOptions {
                title: Some("GPUI-Dart platform probe".into()),
                ..Default::default()
            }),
            ..Default::default()
        };
        let window = gpui_kit::open_window(options, cx, |window, cx| {
            let input = cx.new(|cx| InputState::new(window, cx).placeholder("Type here"));
            cx.new(|_| Probe {
                input,
                renders,
                clicks,
                resized,
            })
        });
        let window = match window {
            Ok((window, _view)) => window,
            Err(error) => {
                report(
                    "open_failed",
                    serde_json::json!({"error": error.to_string()}),
                );
                cx.quit();
                return;
            }
        };
        opened.store(1, Ordering::Release);
        if let Some(callback) = callback {
            callback(1);
        }
        cx.activate(true);
        cx.spawn(async move |cx| {
            for step in 0..500 {
                cx.background_executor()
                    .timer(Duration::from_millis(10))
                    .await;
                if step == 50 {
                    let _ =
                        window.update(cx, |_, window, _| window.resize(size(px(720.), px(420.))));
                    report("resize_requested", serde_json::Value::Null);
                }
                let signal = SIGNAL.swap(0, Ordering::AcqRel);
                if signal != 0 {
                    report("signal_received", serde_json::json!({"value": signal}));
                    if let Some(callback) = callback {
                        callback(signal);
                    }
                }
            }
            let _ = cx.update(|cx| cx.quit());
        })
        .detach();
    });
    let renders = result_renders.load(Ordering::Acquire);
    report(
        "run_return",
        serde_json::json!({"renders": renders, "clicks": result_clicks.load(Ordering::Acquire), "resized_render": result_resized.load(Ordering::Acquire) == 1}),
    );
    if result_opened.load(Ordering::Acquire) == 1
        && renders >= 2
        && result_resized.load(Ordering::Acquire) == 1
    {
        0
    } else {
        -1
    }
}
