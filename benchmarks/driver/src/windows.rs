use crate::schedule::Schedule;
use anyhow::{bail, ensure, Context, Result};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    ffi::c_void,
    fs::{self, File},
    io::BufWriter,
    mem::size_of,
    os::windows::{io::AsRawHandle, process::CommandExt},
    path::Path,
    process::{Child, Command, Stdio},
    ptr::{null, null_mut},
    thread::sleep,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

type Handle = *mut c_void;
#[repr(C)]
#[derive(Default, Clone, Copy)]
struct Point {
    x: i32,
    y: i32,
}
#[repr(C)]
#[derive(Default)]
struct Rect {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
}
#[repr(C)]
#[derive(Default, Clone, Copy)]
struct MouseInput {
    x: i32,
    y: i32,
    data: u32,
    flags: u32,
    time: u32,
    extra: usize,
}
#[repr(C)]
#[derive(Default)]
struct Input {
    kind: u32,
    mouse: MouseInput,
}
#[repr(C)]
#[derive(Default)]
struct FileTime {
    low: u32,
    high: u32,
}
#[repr(C)]
#[derive(Default)]
struct Memory {
    size: u32,
    faults: u32,
    peak_working: usize,
    working: usize,
    peak_paged: usize,
    paged: usize,
    peak_nonpaged: usize,
    nonpaged: usize,
    pagefile: usize,
    peak_pagefile: usize,
    private: usize,
}
#[repr(C)]
struct BitmapHeader {
    size: u32,
    width: i32,
    height: i32,
    planes: u16,
    bits: u16,
    compression: u32,
    image_size: u32,
    xppm: i32,
    yppm: i32,
    colors: u32,
    important: u32,
}

#[link(name = "user32")]
extern "system" {
    fn EnumWindows(
        callback: unsafe extern "system" fn(Handle, isize) -> i32,
        parameter: isize,
    ) -> i32;
    fn GetWindowThreadProcessId(window: Handle, process: *mut u32) -> u32;
    fn IsWindowVisible(window: Handle) -> i32;
    fn GetWindowTextW(window: Handle, title: *mut u16, maximum: i32) -> i32;
    fn GetClientRect(window: Handle, rect: *mut Rect) -> i32;
    fn GetWindowRect(window: Handle, rect: *mut Rect) -> i32;
    fn ClientToScreen(window: Handle, point: *mut Point) -> i32;
    fn GetDpiForWindow(window: Handle) -> u32;
    fn MonitorFromWindow(window: Handle, flags: u32) -> Handle;
    fn SetForegroundWindow(window: Handle) -> i32;
    fn ShowWindow(window: Handle, command: i32) -> i32;
    fn GetForegroundWindow() -> Handle;
    fn MoveWindow(window: Handle, x: i32, y: i32, width: i32, height: i32, repaint: i32) -> i32;
    fn SetWindowPos(
        window: Handle,
        after: Handle,
        x: i32,
        y: i32,
        width: i32,
        height: i32,
        flags: u32,
    ) -> i32;
    fn WindowFromPoint(point: Point) -> Handle;
    fn RealChildWindowFromPoint(parent: Handle, point: Point) -> Handle;
    fn ScreenToClient(window: Handle, point: *mut Point) -> i32;
    fn GetAncestor(window: Handle, flags: u32) -> Handle;
    fn SetCursorPos(x: i32, y: i32) -> i32;
    fn GetCursorPos(point: *mut Point) -> i32;
    fn GetSystemMetrics(index: i32) -> i32;
    fn SendInput(count: u32, inputs: *const Input, size: i32) -> u32;
    fn PostMessageW(window: Handle, message: u32, wparam: usize, lparam: isize) -> i32;
    fn SetProcessDPIAware() -> i32;
    fn PrintWindow(window: Handle, device: Handle, flags: u32) -> i32;
    fn GetDC(window: Handle) -> Handle;
    fn ReleaseDC(window: Handle, device: Handle) -> i32;
}
#[link(name = "gdi32")]
extern "system" {
    fn CreateCompatibleDC(device: Handle) -> Handle;
    fn CreateDIBSection(
        device: Handle,
        info: *const BitmapHeader,
        usage: u32,
        bits: *mut *mut u8,
        section: Handle,
        offset: u32,
    ) -> Handle;
    fn SelectObject(device: Handle, object: Handle) -> Handle;
    fn DeleteObject(object: Handle) -> i32;
    fn DeleteDC(device: Handle) -> i32;
    fn GdiFlush() -> i32;
    fn BitBlt(
        dest: Handle,
        x: i32,
        y: i32,
        width: i32,
        height: i32,
        source: Handle,
        sx: i32,
        sy: i32,
        rop: u32,
    ) -> i32;
}
#[link(name = "kernel32")]
extern "system" {
    fn CreateWaitableTimerExW(
        attributes: Handle,
        name: *const u16,
        flags: u32,
        access: u32,
    ) -> Handle;
    fn SetWaitableTimer(
        timer: Handle,
        due: *const i64,
        period: i32,
        callback: Handle,
        argument: Handle,
        resume: i32,
    ) -> i32;
    fn WaitForSingleObject(handle: Handle, milliseconds: u32) -> u32;
    fn CloseHandle(handle: Handle) -> i32;
    fn GetCurrentProcess() -> Handle;
    fn GetCurrentThread() -> Handle;
    fn SetPriorityClass(process: Handle, class: u32) -> i32;
    fn SetThreadPriority(thread: Handle, priority: i32) -> i32;
    fn SetThreadExecutionState(flags: u32) -> u32;
    fn QueryPerformanceCounter(counter: *mut i64) -> i32;
    fn QueryPerformanceFrequency(frequency: *mut i64) -> i32;
    fn GetProcessTimes(
        process: Handle,
        creation: *mut FileTime,
        exit: *mut FileTime,
        kernel: *mut FileTime,
        user: *mut FileTime,
    ) -> i32;
}
#[link(name = "psapi")]
extern "system" {
    fn GetProcessMemoryInfo(process: Handle, counters: *mut Memory, size: u32) -> i32;
}
#[link(name = "shcore")]
extern "system" {
    fn GetDpiForMonitor(monitor: Handle, kind: i32, x: *mut u32, y: *mut u32) -> i32;
}
#[link(name = "winmm")]
extern "system" {
    fn timeBeginPeriod(period: u32) -> u32;
    fn timeEndPeriod(period: u32) -> u32;
}
#[link(name = "ntdll")]
extern "system" {
    fn NtQueryTimerResolution(maximum: *mut u32, minimum: *mut u32, current: *mut u32) -> i32;
}

fn check(ok: bool, message: &str) -> Result<()> {
    ensure!(ok, "{message}: {}", std::io::Error::last_os_error());
    Ok(())
}
fn qpc() -> i64 {
    let mut value = 0;
    unsafe {
        QueryPerformanceCounter(&mut value);
    }
    value
}
fn frequency() -> i64 {
    let mut value = 0;
    unsafe {
        QueryPerformanceFrequency(&mut value);
    }
    value
}
fn client(window: Handle) -> Rect {
    let mut rect = Rect::default();
    unsafe {
        GetClientRect(window, &mut rect);
    }
    rect
}
fn scale(window: Handle) -> Result<f64> {
    let (mut x, mut y) = (0, 0);
    unsafe {
        check(
            GetDpiForMonitor(MonitorFromWindow(window, 2), 0, &mut x, &mut y) == 0,
            "Cannot determine monitor DPI",
        )?;
    }
    Ok(x as f64 / 96.0)
}
fn describe(window: Handle) -> String {
    let mut pid = 0;
    let mut title = [0u16; 1024];
    unsafe {
        GetWindowThreadProcessId(window, &mut pid);
        let len = GetWindowTextW(window, title.as_mut_ptr(), 1024);
        format!(
            "{:?} pid={} visible={} title={}",
            window,
            pid,
            IsWindowVisible(window) != 0,
            String::from_utf16_lossy(&title[..len as usize])
        )
    }
}
fn focus(window: Handle) -> Result<()> {
    let current = unsafe { GetForegroundWindow() };
    ensure!(
        current == window,
        "Benchmark window lost focus; input stopped. Target: {}; foreground: {}",
        describe(window),
        describe(current)
    );
    Ok(())
}
fn packet(flags: u32, data: u32, sequence: u32) -> Input {
    Input {
        kind: 0,
        mouse: MouseInput {
            flags,
            data,
            extra: if sequence == 0 {
                0
            } else {
                0x47500000 | sequence as usize
            },
            ..Default::default()
        },
    }
}
fn mouse(inputs: &[Input]) -> Result<u32> {
    let accepted = unsafe {
        SendInput(
            inputs.len() as u32,
            inputs.as_ptr(),
            size_of::<Input>() as i32,
        )
    };
    check(accepted == inputs.len() as u32, "SendInput failed")?;
    Ok(accepted)
}
fn screen_point(window: Handle, x: f64, y: f64) -> Result<Point> {
    let scale = scale(window)?;
    let mut point = Point {
        x: (x * scale) as i32,
        y: (y * scale) as i32,
    };
    unsafe {
        check(
            ClientToScreen(window, &mut point) != 0,
            "ClientToScreen failed",
        )?;
    }
    Ok(point)
}
fn message_target(window: Handle, point: &mut Point) -> Handle {
    unsafe {
        let child = RealChildWindowFromPoint(window, *point);
        if child.is_null() || child == window {
            window
        } else {
            ClientToScreen(window, point);
            ScreenToClient(child, point);
            child
        }
    }
}
fn post(window: Handle, message: u32, wparam: usize, point: Point) -> Result<()> {
    unsafe {
        check(
            PostMessageW(
                window,
                message,
                wparam,
                ((point.y << 16) | (point.x & 0xffff)) as isize,
            ) != 0,
            "PostMessage failed",
        )
    }
}
fn message_click(window: Handle, y: f64) -> Result<()> {
    let scale = scale(window)?;
    let mut point = Point {
        x: (140.0 * scale) as i32,
        y: (y * scale) as i32,
    };
    let target = message_target(window, &mut point);
    post(target, 0x200, 0, point)?;
    post(target, 0x201, 1, point)?;
    post(target, 0x202, 0, point)
}
fn message_wheel(window: Handle, delta: i32) -> Result<()> {
    let scale = scale(window)?;
    let mut point = Point {
        x: (400.0 * scale) as i32,
        y: (270.0 * scale) as i32,
    };
    let target = message_target(window, &mut point);
    unsafe {
        ClientToScreen(target, &mut point);
    }
    post(target, 0x20a, (delta << 16) as usize, point)
}

struct Driver {
    timer: Handle,
    resolution: u32,
    priority: bool,
    activation_clicks: u32,
    placed: Point,
}
impl Driver {
    fn new() -> Result<Self> {
        unsafe {
            SetProcessDPIAware();
            let timer = CreateWaitableTimerExW(null_mut(), null(), 2, 0x00100002);
            check(
                !timer.is_null(),
                "Cannot create high resolution driver timer",
            )?;
            timeBeginPeriod(1);
            let (mut maximum, mut minimum, mut resolution) = (0, 0, 0);
            if NtQueryTimerResolution(&mut maximum, &mut minimum, &mut resolution) != 0 {
                resolution = 0;
            }
            let priority = SetPriorityClass(GetCurrentProcess(), 0x80) != 0
                && SetThreadPriority(GetCurrentThread(), 2) != 0;
            SetThreadExecutionState(0x80000003);
            Ok(Self {
                timer,
                resolution,
                priority,
                activation_clicks: 0,
                placed: Point::default(),
            })
        }
    }
    fn pause(&self) -> Result<()> {
        unsafe {
            check(
                SetWaitableTimer(self.timer, &-10000, 0, null_mut(), null_mut(), 0) != 0
                    && WaitForSingleObject(self.timer, 2000) == 0,
                "Driver timer wait failed",
            )
        }
    }
    fn warm(&self) -> Result<()> {
        mouse(&[packet(1, 0, 0)])?;
        self.pause()
    }
    fn prepare(&mut self, window: Handle, activate: bool) -> Result<()> {
        unsafe {
            ShowWindow(window, if activate { 5 } else { 4 });
            let mut outer = Rect::default();
            GetWindowRect(window, &mut outer);
            let inner = client(window);
            let s = scale(window)?;
            check(
                MoveWindow(
                    window,
                    80,
                    80,
                    (860.0 * s) as i32 + outer.right - outer.left - inner.right,
                    (650.0 * s) as i32 + outer.bottom - outer.top - inner.bottom,
                    1,
                ) != 0,
                "MoveWindow failed",
            )?;
            if activate && GetForegroundWindow() != window {
                SetForegroundWindow(window);
                if GetForegroundWindow() != window {
                    check(
                        SetWindowPos(window, -1isize as Handle, 0, 0, 0, 0, 0x13) != 0,
                        "Cannot expose benchmark window for activation",
                    )?;
                    let result = (|| {
                        let point = screen_point(window, 800.0, 600.0)?;
                        let covering = GetAncestor(WindowFromPoint(point), 2);
                        ensure!(
                            covering == window,
                            "Benchmark activation point is occluded; no click sent. Covering: {}",
                            describe(covering)
                        );
                        check(
                            SetCursorPos(point.x, point.y) != 0,
                            "Cannot position benchmark activation click",
                        )?;
                        mouse(&[packet(2, 0, 0), packet(4, 0, 0)])?;
                        self.activation_clicks += 1;
                        Ok(())
                    })();
                    SetWindowPos(window, -2isize as Handle, 0, 0, 0, 0, 0x13);
                    result?;
                }
            }
            Ok(())
        }
    }
    fn pointer(&mut self, window: Handle, x: f64, y: f64) -> Result<()> {
        focus(window)?;
        let point = screen_point(window, x, y)?;
        let mut now = Point::default();
        unsafe {
            if GetCursorPos(&mut now) == 0 || now.x != point.x || now.y != point.y {
                check(SetCursorPos(point.x, point.y) != 0, "SetCursorPos failed")?;
            }
        }
        self.placed = point;
        Ok(())
    }
    fn require_pointer(&self) -> Result<()> {
        let mut now = Point::default();
        unsafe {
            check(GetCursorPos(&mut now) != 0, "GetCursorPos failed")?;
        }
        ensure!(
            (now.x - self.placed.x).abs() <= 2 && (now.y - self.placed.y).abs() <= 2,
            "Benchmark pointer moved; input stopped. Placed at {},{}; now at {},{}",
            self.placed.x,
            self.placed.y,
            now.x,
            now.y
        );
        Ok(())
    }
    fn click(&mut self, window: Handle, y: f64, sequence: u32) -> Result<u32> {
        self.pointer(window, 140.0, y)?;
        focus(window)?;
        mouse(&[packet(2, 0, sequence), packet(4, 0, sequence)])
    }
    fn wheel(&self, window: Handle, delta: i32, sequence: u32) -> Result<u32> {
        focus(window)?;
        self.require_pointer()?;
        mouse(&[packet(0x800, delta as u32, sequence)])
    }
    fn hover(&self, window: Handle, x: f64, y: f64) -> Result<()> {
        focus(window)?;
        let point = screen_point(window, x, y)?;
        let mut input = packet(0x8001, 0, 0);
        unsafe {
            input.mouse.x =
                (point.x as f64 * 65535.0 / (GetSystemMetrics(0) - 1) as f64).round() as i32;
            input.mouse.y =
                (point.y as f64 * 65535.0 / (GetSystemMetrics(1) - 1) as f64).round() as i32;
        }
        mouse(&[input])?;
        Ok(())
    }
}
impl Drop for Driver {
    fn drop(&mut self) {
        unsafe {
            SetThreadExecutionState(0x80000000);
            SetThreadPriority(GetCurrentThread(), 0);
            SetPriorityClass(GetCurrentProcess(), 0x20);
            timeEndPeriod(1);
            CloseHandle(self.timer);
        }
    }
}

struct Bitmap {
    dc: Handle,
    bitmap: Handle,
    old: Handle,
    bits: *mut u8,
    width: u32,
    height: u32,
}
impl Bitmap {
    fn capture(window: Handle, offscreen: bool) -> Result<Self> {
        unsafe {
            let rect = client(window);
            ensure!(
                rect.right > 0 && rect.bottom > 0,
                "Empty window client area"
            );
            let screen = GetDC(null_mut());
            check(!screen.is_null(), "GetDC failed")?;
            let dc = CreateCompatibleDC(screen);
            ReleaseDC(null_mut(), screen);
            check(!dc.is_null(), "CreateCompatibleDC failed")?;
            let header = BitmapHeader {
                size: size_of::<BitmapHeader>() as u32,
                width: rect.right,
                height: -rect.bottom,
                planes: 1,
                bits: 32,
                compression: 0,
                image_size: 0,
                xppm: 0,
                yppm: 0,
                colors: 0,
                important: 0,
            };
            let mut bits = null_mut();
            let bitmap = CreateDIBSection(dc, &header, 0, &mut bits, null_mut(), 0);
            if bitmap.is_null() {
                DeleteDC(dc);
                bail!("CreateDIBSection failed");
            }
            let old = SelectObject(dc, bitmap);
            let result = Self {
                dc,
                bitmap,
                old,
                bits,
                width: rect.right as u32,
                height: rect.bottom as u32,
            };
            if offscreen {
                check(PrintWindow(window, dc, 3) != 0, "PrintWindow failed")?;
            } else {
                focus(window)?;
                let p = screen_point(window, 0.0, 0.0)?;
                let source = GetDC(null_mut());
                let copied = BitBlt(
                    dc,
                    0,
                    0,
                    rect.right,
                    rect.bottom,
                    source,
                    p.x,
                    p.y,
                    0x00cc0020,
                );
                ReleaseDC(null_mut(), source);
                check(copied != 0, "BitBlt failed")?;
            }
            GdiFlush();
            Ok(result)
        }
    }
    fn bytes(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.bits, (self.width * self.height * 4) as usize) }
    }
    fn has_content(&self) -> bool {
        let bytes = self.bytes();
        let step = (self.width.min(self.height) / 64).max(1) as usize;
        let (mut differing, mut sampled) = (0, 0);
        for y in (0..self.height as usize).step_by(step) {
            for x in (0..self.width as usize).step_by(step) {
                sampled += 1;
                let offset = (y * self.width as usize + x) * 4;
                if (0..3)
                    .map(|c| (bytes[offset + c] as i32 - bytes[c] as i32).abs())
                    .sum::<i32>()
                    > 24
                {
                    differing += 1;
                }
            }
        }
        differing * 100 > sampled
    }
    fn save(&self, path: &Path) -> Result<()> {
        let mut encoder =
            png::Encoder::new(BufWriter::new(File::create(path)?), self.width, self.height);
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        let rgb: Vec<_> = self
            .bytes()
            .chunks_exact(4)
            .flat_map(|p| [p[2], p[1], p[0]])
            .collect();
        encoder.write_header()?.write_image_data(&rgb)?;
        Ok(())
    }
}
impl Drop for Bitmap {
    fn drop(&mut self) {
        unsafe {
            SelectObject(self.dc, self.old);
            DeleteObject(self.bitmap);
            DeleteDC(self.dc);
        }
    }
}

struct App {
    child: Child,
    window: Handle,
}
impl App {
    fn find(&mut self) -> Handle {
        struct Search {
            pid: u32,
            found: Handle,
        }
        unsafe extern "system" fn visit(window: Handle, param: isize) -> i32 {
            let search = &mut *(param as *mut Search);
            let mut pid = 0;
            GetWindowThreadProcessId(window, &mut pid);
            let rect = client(window);
            if pid == search.pid && rect.right > 100 && rect.bottom > 100 {
                search.found = window;
                0
            } else {
                1
            }
        }
        let mut search = Search {
            pid: self.child.id(),
            found: null_mut(),
        };
        unsafe {
            EnumWindows(visit, &mut search as *mut Search as isize);
        }
        self.window = search.found;
        self.window
    }
    fn cpu_ms(&self) -> Result<f64> {
        let (mut created, mut exited, mut kernel, mut user) = (
            FileTime::default(),
            FileTime::default(),
            FileTime::default(),
            FileTime::default(),
        );
        unsafe {
            check(
                GetProcessTimes(
                    self.child.as_raw_handle(),
                    &mut created,
                    &mut exited,
                    &mut kernel,
                    &mut user,
                ) != 0,
                "GetProcessTimes failed",
            )?;
        }
        let ticks = |v: FileTime| ((v.high as u64) << 32) | v.low as u64;
        Ok((ticks(kernel) + ticks(user)) as f64 / 10000.0)
    }
    fn sample(&mut self, elapsed: f64, cpu_start: f64) -> Result<Value> {
        ensure!(
            self.child.try_wait()?.is_none(),
            "Application exited during workload"
        );
        let mut memory = Memory {
            size: size_of::<Memory>() as u32,
            ..Default::default()
        };
        unsafe {
            check(
                GetProcessMemoryInfo(
                    self.child.as_raw_handle(),
                    &mut memory,
                    size_of::<Memory>() as u32,
                ) != 0,
                "GetProcessMemoryInfo failed",
            )?;
        }
        Ok(
            json!({"elapsed_ms":elapsed,"working_set_bytes":memory.working,"private_bytes":memory.private,"cpu_ms":self.cpu_ms()?-cpu_start}),
        )
    }
    fn wait(&mut self, milliseconds: u32) -> Result<bool> {
        Ok(unsafe { WaitForSingleObject(self.child.as_raw_handle(), milliseconds) } == 0)
    }
    fn close(&self) {
        if !self.window.is_null() {
            unsafe {
                PostMessageW(self.window, 0x10, 0, 0);
            }
        }
    }
}
impl Drop for App {
    fn drop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            self.close();
            if !self.wait(3000).unwrap_or(false) {
                let _ = self.child.kill();
            }
            let _ = self.child.wait();
        }
    }
}

#[derive(Deserialize)]
struct Config {
    executable: String,
    arguments: Vec<String>,
    folder: String,
    environment: HashMap<String, String>,
    workload: String,
    seconds: u32,
    background: bool,
    no_pointer_warmup: bool,
    shell: bool,
    wheel_delta: i32,
    #[serde(default)]
    calibration: Option<Calibration>,
}
#[derive(Deserialize)]
struct Calibration {
    events: u32,
    interval_ms: u64,
}

pub fn run(path: &str) -> Result<()> {
    let config: Config = serde_json::from_reader(File::open(path)?)?;
    ensure!(
        (2..=120).contains(&config.seconds),
        "seconds must be 2..120"
    );
    ensure!(
        ["idle", "scroll", "cell", "burst", "view"].contains(&config.workload.as_str()),
        "Unknown workload"
    );
    let folder = Path::new(&config.folder);
    let mut data = json!({"inputs":[],"process_samples":[],"input_deadlines_missed":0});
    let result = measure(&config, &mut data);
    if let Err(error) = &result {
        data["error"] = json!(format!("{error:#}"));
    }
    fs::write(
        folder.join("driver-result.json"),
        serde_json::to_vec_pretty(&data)?,
    )?;
    result
}

fn measure(c: &Config, data: &mut Value) -> Result<()> {
    let mut driver = Driver::new()?;
    let folder = Path::new(&c.folder);
    let startup = Instant::now();
    let launch = qpc();
    let child = Command::new(&c.executable)
        .args(&c.arguments)
        .current_dir(folder)
        .env_remove("GPUIDART_INPUT_TRACE")
        .env_remove("GPUIDART_NATIVE_TRACE")
        .env_remove("GPUI_PRESENT_FEEDBACK")
        .envs(&c.environment)
        .env(
            "GPUIDART_BENCH_LAUNCH_UTC_MS",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)?
                .as_millis()
                .to_string(),
        )
        .creation_flags(0x08000000)
        .stdin(Stdio::null())
        .stdout(File::create(folder.join("stdout.log"))?)
        .stderr(File::create(folder.join("stderr.log"))?)
        .spawn()
        .context("Starting benchmark fixture")?;
    let mut app = App {
        child,
        window: null_mut(),
    };
    data["process_id"] = json!(app.child.id());
    data["launch_qpc"] = json!(launch);
    while app.find().is_null() && startup.elapsed().as_secs_f64() < 45.0 {
        if let Some(status) = app.child.try_wait()? {
            bail!("Application exited with {status}; see stderr.log");
        }
        sleep(Duration::from_millis(10));
    }
    let window = app.window;
    ensure!(
        !window.is_null(),
        "No visible application window within 45 seconds"
    );
    data["window_available_ms"] = json!(startup.elapsed().as_secs_f64() * 1000.0);
    driver.prepare(window, !c.background)?;
    let mut first_content = -1.0;
    while startup.elapsed().as_millis() < 20000 {
        if Bitmap::capture(window, true)
            .map(|b| b.has_content())
            .unwrap_or(false)
        {
            first_content = startup.elapsed().as_secs_f64() * 1000.0;
            break;
        }
        sleep(Duration::from_millis(5));
    }
    data["first_content_ms"] = json!(first_content);
    sleep(Duration::from_secs(if c.calibration.is_some() {
        2
    } else {
        3
    }));
    driver.prepare(window, !c.background)?;
    sleep(Duration::from_millis(250));
    if !c.background {
        focus(window)?;
        Bitmap::capture(window, false)?.save(&folder.join("before.png"))?;
    }
    let rect = client(window);
    data["dpi_scale"] = json!(scale(window)?);
    data["window_dpi"] = json!(unsafe { GetDpiForWindow(window) });
    data["client_pixels"] =
        json!({"Left":rect.left,"Top":rect.top,"Right":rect.right,"Bottom":rect.bottom});
    if !c.background && !c.no_pointer_warmup {
        match c.workload.as_str() {
            "scroll" => driver.pointer(window, 400.0, 270.0)?,
            "cell" | "view" => driver.pointer(window, 140.0, 69.0)?,
            "burst" => driver.pointer(window, 140.0, 113.0)?,
            _ => (),
        }
        sleep(Duration::from_millis(100));
    }
    if let Some(calibration) = &c.calibration {
        driver.pointer(window, 400.0, 270.0)?;
        sleep(Duration::from_millis(200));
        for _ in 0..calibration.events {
            driver.wheel(window, c.wheel_delta, 0)?;
            sleep(Duration::from_millis(calibration.interval_ms));
        }
    } else {
        if !c.background {
            driver.warm()?;
        }
        let rate = match c.workload.as_str() {
            "scroll" => 60,
            "cell" => 5,
            "burst" => 30,
            "view" => 1,
            _ => 0,
        };
        // Keep the original dry phase and warmup duration so histories have the
        // same scope even though the native loop has no PowerShell JIT cost.
        for measuring in [false, true] {
            let duration = if measuring { c.seconds as f64 } else { 0.6 };
            let mut schedule = Schedule::new(c.seconds as f64, rate);
            data["inputs"] = Value::Array(Vec::with_capacity(schedule.planned as usize));
            data["process_samples"] = Value::Array(Vec::with_capacity(c.seconds as usize * 4 + 1));
            let mut hover_step = 0;
            let mut next_hover = 0.0;
            let mut next_sample = 0.0;
            let cpu_start = app.cpu_ms()?;
            let start = qpc();
            let timer = Instant::now();
            data["start_qpc"] = json!(start);
            data["qpc_frequency"] = json!(frequency());
            loop {
                if !c.background {
                    focus(window)?;
                }
                let elapsed = timer.elapsed().as_secs_f64() * 1000.0;
                if elapsed >= duration * 1000.0 {
                    break;
                }
                if let Some(scheduled) = schedule.due(elapsed) {
                    let timestamp = qpc();
                    let sequence = data["inputs"].as_array().unwrap().len() as u32 + 1;
                    let accepted = if !measuring {
                        driver.warm()?;
                        None
                    } else if c.background {
                        if c.workload == "scroll" {
                            message_wheel(window, c.wheel_delta)?;
                        } else {
                            message_click(
                                window,
                                if c.workload == "burst" { 113.0 } else { 69.0 },
                            )?;
                        }
                        None
                    } else if c.workload == "scroll" {
                        Some(driver.wheel(window, c.wheel_delta, sequence)?)
                    } else {
                        Some(driver.click(
                            window,
                            if c.workload == "burst" { 113.0 } else { 69.0 },
                            sequence,
                        )?)
                    };
                    data["inputs"].as_array_mut().unwrap().push(json!({"sequence":sequence,"qpc":timestamp,"injection_completed_qpc":qpc(),"packets_accepted":accepted,"scheduled_ms":scheduled,"sent_ms":elapsed}));
                    // Persist partial observations in memory before another focus
                    // check can fail; Dart retains them in failure.json.
                    if measuring {
                        data["input_deadlines_missed"] = json!(schedule.missed);
                    }
                }
                if c.workload == "view" && !c.background && elapsed >= next_hover {
                    hover_step += 1;
                    driver.hover(window, 400.0, 230.0 + 40.0 * (hover_step % 6) as f64)?;
                    next_hover += 1000.0 / 60.0;
                    if next_hover < elapsed {
                        next_hover = elapsed + 1000.0 / 60.0;
                    }
                }
                if measuring && elapsed >= next_sample && schedule.can_sample(elapsed) {
                    data["process_samples"]
                        .as_array_mut()
                        .unwrap()
                        .push(app.sample(elapsed, cpu_start)?);
                    next_sample += 250.0;
                }
                driver.pause()?;
            }
            if measuring {
                data["end_qpc"] = json!(qpc());
                let duration_ms = timer.elapsed().as_secs_f64() * 1000.0;
                let cpu_ms = app.cpu_ms()? - cpu_start;
                data["duration_ms"] = json!(duration_ms);
                data["cpu_ms"] = json!(cpu_ms);
                data["cpu_percent_one_core"] = json!(100.0 * cpu_ms / duration_ms);
                data["input_count"] = json!(data["inputs"].as_array().unwrap().len());
                data["input_deadlines_missed"] = json!(schedule.missed);
                data["planned_inputs"] = json!(schedule.planned);
                data["hover_moves"] = json!(hover_step);
            }
        }
    }
    data["activation_clicks"] = json!(driver.activation_clicks);
    data["harness_timer_resolution_ms"] = json!(driver.resolution as f64 / 10000.0);
    data["driver_priority"] = json!(if driver.priority {
        "high priority class, highest thread priority"
    } else {
        "normal; elevation failed"
    });
    sleep(Duration::from_millis(700));
    Bitmap::capture(window, c.background)?.save(&folder.join(if c.background {
        "offscreen.png"
    } else {
        "after.png"
    }))?;
    if c.background {
        message_click(window, 157.0)?;
    } else {
        driver.click(window, 157.0, 0)?;
    }
    if c.shell {
        sleep(Duration::from_secs(2));
        app.close();
    }
    ensure!(
        app.wait(15000)?,
        "Application did not save measurements and exit"
    );
    Ok(())
}

pub fn extract_crt(archive: &str, destination: &str) -> Result<()> {
    let mut archive = zip::ZipArchive::new(File::open(archive)?)?;
    let entries: Vec<_> = (0..archive.len())
        .filter(|&i| {
            archive
                .by_index(i)
                .map(|f| {
                    f.name()
                        .replace('\\', "/")
                        .ends_with("/x64/Microsoft.VC143.CRT/vcruntime140.dll")
                })
                .unwrap_or(false)
        })
        .collect();
    ensure!(
        entries.len() == 1,
        "Expected one x64 release CRT entry in the redistributable archive"
    );
    let mut entry = archive.by_index(entries[0])?;
    std::io::copy(&mut entry, &mut File::create(destination)?)?;
    Ok(())
}
pub fn self_test() -> Result<()> {
    ensure!(
        size_of::<Input>() == if size_of::<usize>() == 8 { 40 } else { 28 },
        "Unexpected Win32 INPUT layout"
    );
    ensure!(
        size_of::<BitmapHeader>() == 40,
        "Unexpected bitmap header layout"
    );
    ensure!(frequency() > 0 && qpc() > 0, "QPC unavailable");
    let app = App {
        child: Command::new("cmd.exe")
            .args(["/d", "/c", "exit", "0"])
            .creation_flags(0x08000000)
            .spawn()?,
        window: null_mut(),
    };
    ensure!(app.cpu_ms()? >= 0.0, "Process CPU clock unavailable");
    ensure!(
        focus(-42isize as Handle).is_err(),
        "Focus guard accepted an invalid target"
    );
    let mut memory = Memory {
        size: size_of::<Memory>() as u32,
        ..Default::default()
    };
    unsafe {
        check(
            GetProcessMemoryInfo(GetCurrentProcess(), &mut memory, size_of::<Memory>() as u32) != 0,
            "Process memory sampling unavailable",
        )?;
    }
    Ok(())
}
