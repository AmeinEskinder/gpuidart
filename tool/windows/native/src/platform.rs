use serde_json::{Map, Value, json};
use std::{
    ffi::c_void,
    mem::{size_of, zeroed},
    ptr::{null, null_mut},
    time::Duration,
};
use windows_sys::Win32::{
    Foundation::*,
    Graphics::Gdi::*,
    Storage::Xps::PrintWindow,
    System::{Diagnostics::ToolHelp::*, ProcessStatus::*, SystemInformation::*, Threading::*},
    UI::{HiDpi::*, Input::KeyboardAndMouse::*, WindowsAndMessaging::*},
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn check(ok: bool) -> Result<()> {
    if ok {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error().into())
    }
}
fn wide(value: &[u16]) -> String {
    String::from_utf16_lossy(&value[..value.iter().position(|v| *v == 0).unwrap_or(value.len())])
}
struct Handle(HANDLE);
impl Drop for Handle {
    fn drop(&mut self) {
        unsafe {
            CloseHandle(self.0);
        }
    }
}

pub fn run(args: Vec<String>) -> Result<()> {
    let command = args.first().map(String::as_str).unwrap_or("");
    let value = match command {
        "os" => operating_system()?,
        "setup-environment" => Value::Object(setup_environment()),
        "environment" => environment()?,
        "inspect-process" => inspect(args.get(1).ok_or("Missing process ID")?.parse()?)?,
        "processes-containing" => processes(args.get(1).ok_or("Missing command line fragment")?)?,
        "watchlist" => {
            let pid = args.get(1).ok_or("Missing process ID")?.parse()?;
            watchlist(pid, args.get(2).ok_or("Missing step")?, args.get(3).map(String::as_str))?;
            json!({"passed": true})
        }
        _ => return Err("Expected os, setup-environment, environment, inspect-process PID, processes-containing TEXT, or watchlist PID STEP [CAPTURE]".into()),
    };
    println!("{}", serde_json::to_string(&value)?);
    Ok(())
}

struct Search {
    pid: u32,
    window: HWND,
}
unsafe extern "system" fn enum_window(window: HWND, data: LPARAM) -> i32 {
    let search = unsafe { &mut *(data as *mut Search) };
    let mut pid = 0;
    let mut rect = unsafe { zeroed() };
    unsafe {
        GetWindowThreadProcessId(window, &mut pid);
        GetClientRect(window, &mut rect);
    }
    if pid == search.pid && rect.right > 100 && rect.bottom > 100 {
        search.window = window;
        0
    } else {
        1
    }
}
fn find(pid: u32) -> HWND {
    let mut search = Search {
        pid,
        window: null_mut(),
    };
    unsafe {
        EnumWindows(Some(enum_window), (&mut search as *mut Search) as LPARAM);
    }
    search.window
}
fn inspect(pid: u32) -> Result<Value> {
    let process =
        Handle(unsafe { OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, 0, pid) });
    check(!process.0.is_null())?;
    let mut modules = vec![null_mut(); 1024];
    let mut needed = 0;
    unsafe {
        check(
            EnumProcessModulesEx(
                process.0,
                modules.as_mut_ptr(),
                (modules.len() * size_of::<HMODULE>()) as u32,
                &mut needed,
                LIST_MODULES_ALL,
            ) != 0,
        )?;
    }
    if needed as usize > modules.len() * size_of::<HMODULE>() {
        modules.resize(needed as usize / size_of::<HMODULE>(), null_mut());
        unsafe {
            check(
                EnumProcessModulesEx(
                    process.0,
                    modules.as_mut_ptr(),
                    needed,
                    &mut needed,
                    LIST_MODULES_ALL,
                ) != 0,
            )?;
        }
    }
    let mut paths = vec![];
    for module in &modules[..needed as usize / size_of::<HMODULE>()] {
        let mut path = vec![0; 32768];
        unsafe {
            check(
                GetModuleFileNameExW(process.0, *module, path.as_mut_ptr(), path.len() as u32) != 0,
            )?;
        }
        paths.push(wide(&path));
    }
    let window = find(pid);
    let (dpi, per_monitor) = if window.is_null() {
        (0, false)
    } else {
        unsafe {
            (
                GetDpiForWindow(window),
                AreDpiAwarenessContextsEqual(
                    GetWindowDpiAwarenessContext(window),
                    DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
                ) != 0,
            )
        }
    };
    Ok(json!({"window_dpi": dpi, "per_monitor_v2": per_monitor, "loaded_modules": paths}))
}

fn registry_string(key: &str, name: &str) -> Result<String> {
    Ok(windows_registry::LOCAL_MACHINE
        .open(key)?
        .get_string(name)?)
}

#[link(name = "ntdll")]
unsafe extern "system" {
    fn RtlGetVersion(version: *mut OSVERSIONINFOEXW) -> i32;
}

fn operating_system() -> Result<Value> {
    let mut version: OSVERSIONINFOEXW = unsafe { zeroed() };
    version.dwOSVersionInfoSize = size_of::<OSVERSIONINFOEXW>() as u32;
    let status = unsafe { RtlGetVersion(&mut version) };
    if status < 0 {
        return Err(format!("RtlGetVersion failed: NTSTATUS {status:x}").into());
    }
    let mut process_machine = 0;
    let mut native_machine = 0;
    unsafe {
        check(
            IsWow64Process2(
                GetCurrentProcess(),
                &mut process_machine,
                &mut native_machine,
            ) != 0,
        )?;
    }
    let (bits, architecture) = match native_machine {
        IMAGE_FILE_MACHINE_AMD64 => ("64-bit", "x86_64"),
        IMAGE_FILE_MACHINE_ARM64 => ("64-bit", "aarch64"),
        IMAGE_FILE_MACHINE_I386 => ("32-bit", "x86"),
        _ => ("Unknown", "unknown"),
    };
    // ProductName may retain "Windows 10" on Windows 11. Keep the raw value
    // for audit and record when the caption is inferred from the client build.
    let product_name = registry_string(
        r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
        "ProductName",
    )
    .ok();
    let (caption, caption_source) = os_caption(&version, product_name.as_deref());
    Ok(json!({
        "Caption": caption,
        "Version": format!("{}.{}.{}", version.dwMajorVersion, version.dwMinorVersion, version.dwBuildNumber),
        "OSArchitecture": bits, "native_architecture": architecture,
        "version_source": "RtlGetVersion", "architecture_source": "IsWow64Process2",
        "caption_source": caption_source, "registry_product_name": product_name,
    }))
}

fn os_caption(version: &OSVERSIONINFOEXW, product: Option<&str>) -> (String, &'static str) {
    if let Some(product) = product {
        if version.dwMajorVersion == 10
            && version.dwBuildNumber >= 22000
            && version.wProductType == 1
            && product.contains("Windows 10")
        {
            return (
                product.replacen("Windows 10", "Windows 11", 1),
                "Windows 11 client caption inferred from RtlGetVersion build >= 22000 and registry ProductName edition",
            );
        }
        return (product.to_owned(), "Registry ProductName");
    }
    (
        format!(
            "Microsoft Windows NT {}.{}.{}",
            version.dwMajorVersion, version.dwMinorVersion, version.dwBuildNumber
        ),
        "NT version from RtlGetVersion; marketing name unavailable",
    )
}
fn machine_uuid() -> Result<String> {
    let provider = u32::from_be_bytes(*b"RSMB");
    let size = unsafe { GetSystemFirmwareTable(provider, 0, null_mut(), 0) };
    check(size != 0)?;
    let mut bytes = vec![0u8; size as usize];
    let written = unsafe { GetSystemFirmwareTable(provider, 0, bytes.as_mut_ptr().cast(), size) };
    if written != size || bytes.len() < 8 {
        return Err("Could not read complete SMBIOS table".into());
    }
    smbios_uuid(&bytes[8..])
}
fn smbios_uuid(table: &[u8]) -> Result<String> {
    let mut offset = 0;
    while offset + 4 <= table.len() {
        let kind = table[offset];
        let length = table[offset + 1] as usize;
        if length < 4 || offset + length > table.len() {
            break;
        }
        if kind == 1 && length >= 24 {
            let uuid = &table[offset + 8..offset + 24];
            if uuid.iter().all(|v| *v == 0) || uuid.iter().all(|v| *v == 255) {
                return Err("SMBIOS system UUID is not available".into());
            }
            return Ok(format!(
                "{:08x}-{:04x}-{:04x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
                u32::from_le_bytes(uuid[0..4].try_into()?),
                u16::from_le_bytes(uuid[4..6].try_into()?),
                u16::from_le_bytes(uuid[6..8].try_into()?),
                uuid[8],
                uuid[9],
                uuid[10],
                uuid[11],
                uuid[12],
                uuid[13],
                uuid[14],
                uuid[15]
            ));
        }
        if kind == 127 {
            break;
        }
        offset += length;
        while offset + 1 < table.len() && (table[offset] != 0 || table[offset + 1] != 0) {
            offset += 1;
        }
        offset += 2;
    }
    Err("SMBIOS system UUID was not found".into())
}

#[cfg(test)]
mod tests {
    use super::{OSVERSIONINFOEXW, os_caption, smbios_uuid};

    #[test]
    fn distinguishes_windows_11_clients_from_server_product_names() {
        let mut version = OSVERSIONINFOEXW {
            dwMajorVersion: 10,
            dwMinorVersion: 0,
            dwBuildNumber: 26200,
            wProductType: 1,
            ..Default::default()
        };
        assert_eq!(
            os_caption(&version, Some("Windows 10 Pro")).0,
            "Windows 11 Pro"
        );
        version.wProductType = 3;
        assert_eq!(
            os_caption(&version, Some("Windows Server 2025 Datacenter")).0,
            "Windows Server 2025 Datacenter"
        );
        assert_eq!(
            os_caption(&version, None).0,
            "Microsoft Windows NT 10.0.26200"
        );
        version.wProductType = 1;
        version.dwBuildNumber = 19045;
        assert_eq!(
            os_caption(&version, Some("Windows 10 Pro")).0,
            "Windows 10 Pro"
        );
    }

    #[test]
    fn reads_system_uuid_after_a_record_with_strings() {
        let mut table = vec![0, 4, 0, 0, b'x', 0, 0, 1, 24, 0, 0, 0, 0, 0, 0];
        table.extend(1u8..=16);
        table.extend([0, 0]);
        assert_eq!(
            smbios_uuid(&table).unwrap(),
            "04030201-0605-0807-090a-0b0c0d0e0f10"
        );
    }

    #[test]
    fn rejects_missing_and_invalid_uuid_records() {
        for table in [
            vec![],
            vec![1, 24, 0, 0],
            vec![0, 0, 0, 0],
            vec![
                1, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            ],
        ] {
            assert!(smbios_uuid(&table).is_err());
        }
    }
}

fn network_cost() -> windows::core::Result<Value> {
    use windows::Networking::Connectivity::{NetworkCostType, NetworkInformation};
    let profile = match NetworkInformation::GetInternetConnectionProfile() {
        Ok(profile) => profile,
        // The bindings represent a successful null WinRT interface as an
        // empty error (HRESULT 0). A disconnected machine has no profile.
        Err(error) if error.code().is_ok() => {
            return Ok(json!({
                "cost": "Disconnected", "roaming": false, "over_data_limit": false,
            }));
        }
        Err(error) => return Err(error),
    };
    let cost = profile.GetConnectionCost()?;
    Ok(json!({
        "cost": match cost.NetworkCostType()? { NetworkCostType::Unrestricted => "Unrestricted", NetworkCostType::Fixed => "Fixed", NetworkCostType::Variable => "Variable", _ => "Unknown" },
        "roaming": cost.Roaming()?, "over_data_limit": cost.OverDataLimit()?,
    }))
}

fn setup_environment() -> Map<String, Value> {
    let restart_reasons: Vec<_> = [
        r"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        r"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
    ]
    .into_iter()
    .filter(|key| windows_registry::LOCAL_MACHINE.open(key).is_ok())
    .collect();
    let network = network_cost().unwrap_or_else(|error| {
        json!({
            "cost": "Unknown", "roaming": false, "over_data_limit": false,
            "inspection_error": error.to_string(),
        })
    });
    Map::from_iter([
        ("restart_pending".into(), json!(!restart_reasons.is_empty())),
        ("restart_reasons".into(), json!(restart_reasons)),
        ("network".into(), network),
    ])
}

fn environment() -> Result<Value> {
    let mut adapters = vec![];
    let mut device: DISPLAY_DEVICEW = unsafe { zeroed() };
    device.cb = size_of::<DISPLAY_DEVICEW>() as u32;
    let mut index = 0;
    while unsafe { EnumDisplayDevicesW(null(), index, &mut device, 0) } != 0 {
        adapters
            .push(json!({"Name": wide(&device.DeviceString), "DeviceID": wide(&device.DeviceID)}));
        index += 1;
    }
    let identity = machine_uuid()?;
    let model = registry_string(r"HARDWARE\DESCRIPTION\System\BIOS", "SystemProductName")?;
    let installed_languages = windows_registry::LOCAL_MACHINE
        .open(r"SYSTEM\CurrentControlSet\Control\MUI\UILanguages")?
        .keys()?
        .collect::<Vec<_>>();
    let mut environment = setup_environment();
    environment.extend([
        ("machine_identity".into(), json!(identity)),
        ("identity_kind".into(), json!("SMBIOS system UUID")),
        ("model".into(), json!(model)),
        ("os".into(), operating_system()?),
        ("graphics_adapters".into(), json!(adapters)),
        ("installed_ui_languages".into(), json!(installed_languages)),
    ]);
    Ok(Value::Object(environment))
}

#[repr(C)]
struct UnicodeString {
    length: u16,
    maximum_length: u16,
    buffer: *const u16,
}
#[link(name = "ntdll")]
unsafe extern "system" {
    fn NtQueryInformationProcess(
        process: HANDLE,
        class: u32,
        information: *mut c_void,
        size: u32,
        returned: *mut u32,
    ) -> i32;
}
fn processes(needle: &str) -> Result<Value> {
    let snapshot = Handle(unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) });
    check(snapshot.0 != INVALID_HANDLE_VALUE)?;
    let mut entry: PROCESSENTRY32W = unsafe { zeroed() };
    entry.dwSize = size_of::<PROCESSENTRY32W>() as u32;
    let mut found = vec![];
    let mut has_next = unsafe { Process32FirstW(snapshot.0, &mut entry) } != 0;
    while has_next {
        let name = wide(&entry.szExeFile).to_ascii_lowercase();
        if name == "dart.exe" || name == "dartvm.exe" {
            let process = Handle(unsafe {
                OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, entry.th32ProcessID)
            });
            if !process.0.is_null() {
                let mut size = 0;
                unsafe {
                    NtQueryInformationProcess(process.0, 60, null_mut(), 0, &mut size);
                }
                if size > 0 {
                    let mut buffer = vec![0usize; (size as usize).div_ceil(size_of::<usize>())];
                    let status = unsafe {
                        NtQueryInformationProcess(
                            process.0,
                            60,
                            buffer.as_mut_ptr().cast(),
                            size,
                            &mut size,
                        )
                    };
                    if status >= 0 {
                        let string = unsafe { &*(buffer.as_ptr().cast::<UnicodeString>()) };
                        let command = String::from_utf16_lossy(unsafe {
                            std::slice::from_raw_parts(string.buffer, string.length as usize / 2)
                        });
                        if command.to_lowercase().contains(&needle.to_lowercase()) {
                            found
                                .push(json!({"pid": entry.th32ProcessID, "command_line": command}));
                        }
                    } else {
                        return Err(format!(
                            "Cannot inspect Dart PID {}: NTSTATUS {status:x}",
                            entry.th32ProcessID
                        )
                        .into());
                    }
                }
            }
        }
        has_next = unsafe { Process32NextW(snapshot.0, &mut entry) } != 0;
    }
    Ok(json!(found))
}

fn post(window: HWND, message: u32, wp: usize, lp: isize) -> Result<()> {
    unsafe { check(PostMessageW(window, message, wp, lp) != 0) }
}
fn position(x: i32, y: i32) -> isize {
    ((y << 16) | (x & 0xffff)) as isize
}
fn click(window: HWND, scale: f64, x: i32, y: i32) -> Result<()> {
    let point = position((x as f64 * scale) as i32, (y as f64 * scale) as i32);
    post(window, WM_MOUSEMOVE, 0, point)?;
    post(window, WM_LBUTTONDOWN, 1, point)?;
    post(window, WM_LBUTTONUP, 0, point)
}
fn key(window: HWND, key: usize) -> Result<()> {
    post(window, WM_KEYDOWN, key, 0)?;
    post(window, WM_KEYUP, key, 0)
}
fn text(window: HWND, text: &str) -> Result<()> {
    for unit in text.encode_utf16() {
        post(window, WM_CHAR, unit as usize, 0)?;
    }
    Ok(())
}
fn ctrl(window: HWND, key_code: usize) -> Result<()> {
    unsafe {
        let mut message = zeroed();
        PeekMessageW(&mut message, null_mut(), 0, 0, PM_NOREMOVE);
        let current = GetCurrentThreadId();
        let target = GetWindowThreadProcessId(window, null_mut());
        check(AttachThreadInput(current, target, 1) != 0)?;
        let result = (|| {
            let mut saved = [0; 256];
            check(GetKeyboardState(saved.as_mut_ptr()) != 0)?;
            let mut pressed = [0; 256];
            pressed[VK_CONTROL as usize] = 0x80;
            check(SetKeyboardState(pressed.as_ptr()) != 0)?;
            let posted = key(window, key_code);
            std::thread::sleep(Duration::from_millis(150));
            check(SetKeyboardState(saved.as_ptr()) != 0)?;
            posted
        })();
        AttachThreadInput(current, target, 0);
        result
    }
}
fn wheel(window: HWND, scale: f64, x: i32, y: i32) -> Result<()> {
    let mut point = POINT {
        x: (x as f64 * scale) as i32,
        y: (y as f64 * scale) as i32,
    };
    unsafe {
        check(ClientToScreen(window, &mut point) != 0)?;
    }
    post(
        window,
        WM_MOUSEWHEEL,
        (-1200i32 << 16) as usize,
        position(point.x, point.y),
    )
}
fn resize(window: HWND, scale: f64, width: i32, height: i32) -> Result<()> {
    unsafe {
        let mut outer = zeroed();
        let mut inner = zeroed();
        check(GetWindowRect(window, &mut outer) != 0)?;
        check(GetClientRect(window, &mut inner) != 0)?;
        check(
            MoveWindow(
                window,
                outer.left,
                outer.top,
                (width as f64 * scale) as i32 + outer.right - outer.left - inner.right,
                (height as f64 * scale) as i32 + outer.bottom - outer.top - inner.bottom,
                1,
            ) != 0,
        )
    }
}
fn capture(window: HWND, path: &str) -> Result<()> {
    unsafe {
        let mut rect = zeroed();
        check(GetClientRect(window, &mut rect) != 0)?;
        let source = GetDC(window);
        check(!source.is_null())?;
        let device = CreateCompatibleDC(source);
        let bitmap = CreateCompatibleBitmap(source, rect.right, rect.bottom);
        if device.is_null() || bitmap.is_null() {
            if !device.is_null() {
                DeleteDC(device);
            }
            if !bitmap.is_null() {
                DeleteObject(bitmap);
            }
            ReleaseDC(window, source);
            return Err("Could not allocate window capture".into());
        }
        let previous = SelectObject(device, bitmap);
        let result = (|| -> Result<()> {
            check(PrintWindow(window, device, 3) != 0)?;
            SelectObject(device, previous);
            let mut info: BITMAPINFO = zeroed();
            info.bmiHeader.biSize = size_of::<BITMAPINFOHEADER>() as u32;
            info.bmiHeader.biWidth = rect.right;
            info.bmiHeader.biHeight = -rect.bottom;
            info.bmiHeader.biPlanes = 1;
            info.bmiHeader.biBitCount = 32;
            let mut pixels = vec![0u8; rect.right as usize * rect.bottom as usize * 4];
            check(
                GetDIBits(
                    device,
                    bitmap,
                    0,
                    rect.bottom as u32,
                    pixels.as_mut_ptr().cast(),
                    &mut info,
                    DIB_RGB_COLORS,
                ) != 0,
            )?;
            for pixel in pixels.chunks_exact_mut(4) {
                pixel.swap(0, 2);
                pixel[3] = 255;
            }
            let file = std::io::BufWriter::new(std::fs::File::create(path)?);
            let mut encoder = png::Encoder::new(file, rect.right as u32, rect.bottom as u32);
            encoder.set_color(png::ColorType::Rgba);
            encoder.set_depth(png::BitDepth::Eight);
            encoder.write_header()?.write_image_data(&pixels)?;
            Ok(())
        })();
        SelectObject(device, previous);
        DeleteObject(bitmap);
        DeleteDC(device);
        ReleaseDC(window, source);
        result
    }
}
fn watchlist(pid: u32, step: &str, capture_path: Option<&str>) -> Result<()> {
    unsafe {
        SetProcessDPIAware();
    }
    let window = find(pid);
    if window.is_null() {
        return Err("Watchlist process has no window".into());
    }
    let scale = unsafe { GetDpiForWindow(window) } as f64 / 96.0;
    match step {
        "select" => click(window, scale, 40, 280),
        "select-second" => click(window, scale, 40, 312),
        "search" => {
            click(window, scale, 40, 121)?;
            text(window, "ALP0000")
        }
        "type-clear" => {
            click(window, scale, 40, 121)?;
            text(window, "X")?;
            key(window, 8)
        }
        "pin" => click(window, scale, 212, 166),
        "tick" => click(window, scale, 371, 166),
        "shortlist" => click(window, scale, 79, 166),
        "sort" => click(window, scale, 522, 166),
        "action-search" => ctrl(window, 0x46),
        "action-add" => ctrl(window, 0x0d),
        "refine-search" => {
            click(window, scale, 900, 121)?;
            for _ in 0..4 {
                key(window, 8)?;
            }
            Ok(())
        }
        "capture" | "capture-small" | "capture-footer" => {
            capture(window, capture_path.ok_or("Capture path required")?)
        }
        "close" => post(window, WM_CLOSE, 0, 0),
        "down" => key(window, 0x28),
        "scroll" => wheel(window, scale, 400, 270),
        "focus-input" => click(window, scale, 40, 121),
        "unicode" => text(window, "日本語😀"),
        "backspace" => key(window, 8),
        "clear-unicode" => {
            for _ in 0..3 {
                key(window, 8)?;
            }
            Ok(())
        }
        "small" => resize(window, scale, 400, 360),
        "normal" => resize(window, scale, 960, 720),
        "screen-scroll" => wheel(window, scale, 25, 30),
        "burst" => {
            for _ in 0..100 {
                click(window, scale, 370, 154)?;
                std::thread::sleep(Duration::from_millis(10));
            }
            Ok(())
        }
        _ => Err(format!("Unknown watchlist step: {step}").into()),
    }
}
