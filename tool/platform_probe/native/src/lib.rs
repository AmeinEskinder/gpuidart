use gpui_kit::component::StyledExt;
use gpui_kit::component::{
    button::Button,
    input::{Input, InputEvent, InputState},
};
use gpui_kit::*;
use std::io::{BufRead, Read};
use std::sync::mpsc::{Receiver, sync_channel};
use std::sync::{
    Arc,
    atomic::{AtomicU32, Ordering},
};
use std::time::Duration;

static SIGNAL: AtomicU32 = AtomicU32::new(0);
static KEEP_ALIVE: AtomicU32 = AtomicU32::new(0);

#[unsafe(no_mangle)]
pub extern "C" fn gdp_keep_alive(value: u32) {
    KEEP_ALIVE.store(value, Ordering::Release);
}

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
    label: String,
    input: Entity<InputState>,
    renders: Arc<AtomicU32>,
    clicks: Arc<AtomicU32>,
    resized: Arc<AtomicU32>,
    _input_subscription: Subscription,
    last_size: Option<Size<Pixels>>,
}

impl Render for Probe {
    fn render(&mut self, window: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let count = self.renders.fetch_add(1, Ordering::Relaxed) + 1;
        if window.viewport_size() == size(px(720.), px(420.)) {
            self.resized.store(1, Ordering::Release);
        }
        if count <= 3 || self.last_size != Some(window.viewport_size()) {
            report(
                "render",
                serde_json::json!({"count": count, "size": format!("{:?}", window.viewport_size()), "scale": window.scale_factor()}),
            );
        }
        self.last_size = Some(window.viewport_size());
        let clicks = self.clicks.clone();
        div()
            .v_flex()
            .gap_2()
            .p_4()
            .size_full()
            .child(self.label.clone())
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
    match std::panic::catch_unwind(|| run(callback, None)) {
        Ok(status) => status,
        Err(_) => {
            report("panic", serde_json::Value::Null);
            -20
        }
    }
}

enum ProbeCommand {
    Label(String),
    Close,
}

/// Separate-process candidate. This protocol is only for the feasibility probe.
pub fn run_companion() -> i32 {
    let (sender, receiver) = sync_channel(64);
    std::thread::spawn(move || {
        let stdin = std::io::stdin();
        let mut input = stdin.lock();
        loop {
            let mut line = Vec::new();
            let read = input.by_ref().take(4097).read_until(b'\n', &mut line);
            if !matches!(read, Ok(1..=4096)) {
                let _ = sender.send(ProbeCommand::Close);
                break;
            }
            let value = serde_json::from_slice::<serde_json::Value>(&line);
            let command = match value {
                Ok(value) if value["op"] == "close" => ProbeCommand::Close,
                Ok(value) if value["op"] == "label" => {
                    match value["value"].as_str().filter(|value| value.len() <= 128) {
                        Some(value) => ProbeCommand::Label(value.to_owned()),
                        None => {
                            let _ = sender.send(ProbeCommand::Close);
                            break;
                        }
                    }
                }
                _ => {
                    let _ = sender.send(ProbeCommand::Close);
                    break;
                }
            };
            if sender.send(command).is_err() {
                break;
            }
        }
    });
    extern "C" fn ready(value: u32) {
        report("native_callback", serde_json::json!({"value": value}));
    }
    run(Some(ready), Some(receiver))
}

fn run(callback: Option<Callback>, commands: Option<Receiver<ProbeCommand>>) -> i32 {
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
    let input_matches = Arc::new(AtomicU32::new(0));
    let result_input_matches = input_matches.clone();
    let quit_renders = renders.clone();
    let quit_clicks = clicks.clone();
    let quit_resized = resized.clone();
    let quit_input_matches = input_matches.clone();
    let opened = Arc::new(AtomicU32::new(0));
    let result_opened = opened.clone();
    let companion = commands.is_some();
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
            let input = cx.new(|cx| {
                let mut input = InputState::new(window, cx).placeholder("Type here");
                if companion {
                    input.set_value("retained probe state", window, cx);
                }
                input
            });
            cx.new(|cx| {
                let subscription =
                    cx.subscribe_in(&input, window, move |_, input, event, _, cx| {
                        if matches!(event, InputEvent::Change) {
                            let matches = input.read(cx).value().as_ref() == "gpui-probe";
                            input_matches.store(u32::from(matches), Ordering::Release);
                            report(
                                "input_changed",
                                serde_json::json!({"matches_probe_text": matches}),
                            );
                        }
                    });
                Probe {
                    label: "GPUI-Dart platform probe".into(),
                    input,
                    renders,
                    clicks,
                    resized,
                    _input_subscription: subscription,
                    last_size: None,
                }
            })
        });
        let (window, view) = match window {
            Ok(window) => window,
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
            let steps = if commands.is_some() || KEEP_ALIVE.load(Ordering::Acquire) == 1 { 3000 } else { 500 };
            for step in 0..steps {
                cx.background_executor()
                    .timer(Duration::from_millis(10))
                    .await;
                if step == 50 {
                    let _ =
                        window.update(cx, |_, window, _| window.resize(size(px(720.), px(420.))));
                    report("resize_requested", serde_json::Value::Null);
                }
                if step == 100 && std::env::var("GPUIDART_PROBE_DISPATCH").as_deref() == Ok("1") {
                    let _ = window.update(cx, |_, window, cx| {
                        let input = view.read(cx).input.clone();
                        input.update(cx, |input, cx| input.focus(window, cx));
                        for key in "gpui-probe".chars() {
                            window.dispatch_keystroke(Keystroke::parse(&key.to_string()).expect("fixed probe key"), cx);
                        }
                        let position = point(px(80.), px(105.));
                        window.dispatch_event(PlatformInput::MouseDown(MouseDownEvent {
                            position, button: MouseButton::Left, click_count: 1, ..Default::default()
                        }), cx);
                        window.dispatch_event(PlatformInput::MouseUp(MouseUpEvent {
                            position, button: MouseButton::Left, click_count: 1, ..Default::default()
                        }), cx);
                        report("gpui_input_dispatched", serde_json::json!({"scope": "Synthetic GPUI events on a real window; bypasses OS event injection and IME"}));
                    });
                }
                let signal = SIGNAL.swap(0, Ordering::AcqRel);
                if signal != 0 {
                    report("signal_received", serde_json::json!({"value": signal}));
                    if signal != 99 {
                        let _ = view.update(cx, |view, cx| {
                            view.label = format!("Dart signal {signal}");
                            report("signal_applied", serde_json::json!({
                                "value": signal, "input_entity": format!("{:?}", view.input.entity_id()),
                                "input_value": view.input.read(cx).value().to_string(),
                            }));
                            cx.notify();
                        });
                    }
                    if let Some(callback) = callback {
                        callback(signal);
                    }
                    if signal == 99 { break; }
                }
                if let Some(commands) = &commands {
                    let mut closing = false;
                    for command in commands.try_iter().take(64) {
                        match command {
                            ProbeCommand::Close => {
                                closing = true;
                                break;
                            }
                            ProbeCommand::Label(label) => {
                                let _ = view.update(cx, |view, cx| {
                                    view.label = label;
                                    report(
                                        "label_applied",
                                        serde_json::json!({
                                            "label": view.label,
                                            "input_entity": format!("{:?}", view.input.entity_id()),
                                            "input_value": view.input.read(cx).value().to_string(),
                                        }),
                                    );
                                    cx.notify();
                                });
                            }
                        }
                    }
                    if closing {
                        break;
                    }
                }
            }
            report(
                "before_quit",
                serde_json::json!({
                    "renders": quit_renders.load(Ordering::Acquire),
                    "clicks": quit_clicks.load(Ordering::Acquire),
                    "resized_render": quit_resized.load(Ordering::Acquire) == 1,
                    "input_matches": quit_input_matches.load(Ordering::Acquire) == 1,
                }),
            );
            let _ = cx.update(|cx| cx.quit());
        })
        .detach();
    });
    let renders = result_renders.load(Ordering::Acquire);
    report(
        "run_return",
        serde_json::json!({"renders": renders, "clicks": result_clicks.load(Ordering::Acquire), "resized_render": result_resized.load(Ordering::Acquire) == 1, "input_matches": result_input_matches.load(Ordering::Acquire) == 1}),
    );
    if result_opened.load(Ordering::Acquire) == 1
        && renders >= 2
        && result_resized.load(Ordering::Acquire) == 1
        && ((std::env::var("GPUIDART_PROBE_INPUT").as_deref() != Ok("1")
            && std::env::var("GPUIDART_PROBE_DISPATCH").as_deref() != Ok("1"))
            || (result_input_matches.load(Ordering::Acquire) == 1
                && result_clicks.load(Ordering::Acquire) >= 1))
    {
        0
    } else {
        -1
    }
}
