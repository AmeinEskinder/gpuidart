use super::{borrowed_text, call, GError, Object, Owned};
use crate::Result;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    ffi::{c_char, c_int, c_void, CString},
    io::{self, BufRead, Write},
    ptr,
    sync::mpsc,
    time::{Duration, Instant},
};

type Signal = unsafe extern "C" fn(
    Object,
    *const c_char,
    *const c_char,
    *const c_char,
    *const c_char,
    Object,
    Object,
);
#[link(name = "gio-2.0")]
extern "C" {
    fn g_bus_get_sync(bus: c_int, cancel: Object, error: *mut *mut GError) -> Object;
    fn g_dbus_connection_new_for_address_sync(
        address: *const c_char,
        flags: u32,
        observer: Object,
        cancel: Object,
        error: *mut *mut GError,
    ) -> Object;
    fn g_dbus_connection_call_sync(
        connection: Object,
        bus: *const c_char,
        path: *const c_char,
        interface: *const c_char,
        method: *const c_char,
        parameters: Object,
        result_type: Object,
        flags: u32,
        timeout: c_int,
        cancel: Object,
        error: *mut *mut GError,
    ) -> Object;
    fn g_dbus_connection_signal_subscribe(
        connection: Object,
        sender: *const c_char,
        interface: *const c_char,
        member: *const c_char,
        path: *const c_char,
        arg0: *const c_char,
        flags: u32,
        callback: Option<Signal>,
        data: Object,
        destroy: Option<unsafe extern "C" fn(Object)>,
    ) -> u32;
    fn g_dbus_connection_signal_unsubscribe(connection: Object, id: u32);
}
#[link(name = "glib-2.0")]
extern "C" {
    fn g_variant_unref(value: Object);
    fn g_variant_ref_sink(value: Object) -> Object;
    fn g_variant_n_children(value: Object) -> usize;
    fn g_variant_get_child_value(value: Object, index: usize) -> Object;
    fn g_variant_get_type_string(value: Object) -> *const c_char;
    fn g_variant_get_string(value: Object, length: *mut usize) -> *const c_char;
    fn g_variant_get_uint32(value: Object) -> u32;
    fn g_variant_new_string(value: *const c_char) -> Object;
    fn g_variant_new_tuple(children: *const Object, count: usize) -> Object;
    fn g_main_context_iteration(context: Object, may_block: c_int) -> c_int;
}
struct Variant(Object);
impl Drop for Variant {
    fn drop(&mut self) {
        unsafe { g_variant_unref(self.0) }
    }
}

unsafe fn bus_call(
    connection: Object,
    bus: &str,
    path: &str,
    interface: &str,
    method: &str,
    args: Object,
) -> Result<Variant> {
    let bus = CString::new(bus)?;
    let path = CString::new(path)?;
    let interface = CString::new(interface)?;
    let method = CString::new(method)?;
    let value = call(|e| {
        g_dbus_connection_call_sync(
            connection,
            bus.as_ptr(),
            path.as_ptr(),
            interface.as_ptr(),
            method.as_ptr(),
            args,
            ptr::null_mut(),
            0,
            3000,
            ptr::null_mut(),
            e,
        )
    })?;
    if value.is_null() {
        return Err("D-Bus call returned no value".into());
    }
    Ok(Variant(value))
}

struct Monitor {
    process: u32,
    owners: HashMap<String, u32>,
    report: Value,
    stop: bool,
}

unsafe fn observe(
    connection: Object,
    sender: *const c_char,
    name: *const c_char,
    parameters: Object,
    state: &mut Monitor,
) -> Result<()> {
    let name = borrowed_text(name);
    let expected = match name.as_str() {
        "AddAccessible" => "((so)(so)(so)iiassusau)",
        "RemoveAccessible" => "(so)",
        _ => return Ok(()),
    };
    let sender_name = borrowed_text(sender);
    let owner = match state.owners.get(&sender_name) {
        Some(owner) => *owner,
        None => {
            let child = g_variant_new_string(sender);
            let args = Variant(g_variant_ref_sink(g_variant_new_tuple(&child, 1)));
            let response = bus_call(
                connection,
                "org.freedesktop.DBus",
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
                "GetConnectionUnixProcessID",
                args.0,
            )?;
            let owner = Variant(g_variant_get_child_value(response.0, 0));
            let pid = g_variant_get_uint32(owner.0);
            state.owners.insert(sender_name, pid);
            pid
        }
    };
    if owner != state.process {
        return Ok(());
    }
    let field = if name == "AddAccessible" {
        "add"
    } else {
        "remove"
    };
    state.report[field] = json!(state.report[field].as_u64().unwrap_or(0) + 1);
    let arguments = g_variant_n_children(parameters);
    let signature = if arguments == 1 {
        let child = Variant(g_variant_get_child_value(parameters, 0));
        Some(borrowed_text(g_variant_get_type_string(child.0)))
    } else {
        None
    };
    if signature.as_deref() != Some(expected) {
        state.report["invalid"].as_array_mut().unwrap().push(json!({"signal":name, "arguments":arguments, "signature":borrowed_text(g_variant_get_type_string(parameters))}));
        state.stop = true;
    }
    Ok(())
}

unsafe extern "C" fn signal(
    connection: Object,
    sender: *const c_char,
    _path: *const c_char,
    _interface: *const c_char,
    name: *const c_char,
    parameters: Object,
    data: *mut c_void,
) {
    let state = &mut *data.cast::<Monitor>();
    if let Err(error) = observe(connection, sender, name, parameters, state) {
        state.report["error"] = json!(error.to_string());
        state.stop = true;
    }
}

unsafe fn monitor(state: &mut Monitor) -> Result<()> {
    let session = Owned::required(call(|e| g_bus_get_sync(2, ptr::null_mut(), e))?)?;
    let address = bus_call(
        session.0,
        "org.a11y.Bus",
        "/org/a11y/bus",
        "org.a11y.Bus",
        "GetAddress",
        ptr::null_mut(),
    )?;
    let child = Variant(g_variant_get_child_value(address.0, 0));
    let connection = Owned::required(call(|e| {
        g_dbus_connection_new_for_address_sync(
            g_variant_get_string(child.0, ptr::null_mut()),
            1 | 8,
            ptr::null_mut(),
            ptr::null_mut(),
            e,
        )
    })?)?;
    let subscription = g_dbus_connection_signal_subscribe(
        connection.0,
        ptr::null(),
        c"org.a11y.atspi.Cache".as_ptr(),
        ptr::null(),
        ptr::null(),
        ptr::null(),
        0,
        Some(signal),
        (state as *mut Monitor).cast(),
        None,
    );
    let result = (|| -> Result<()> {
        // This round-trip is ordered after AddMatch and before readiness.
        bus_call(
            connection.0,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "GetId",
            ptr::null_mut(),
        )?;
        let (sender, receiver) = mpsc::channel();
        std::thread::spawn(move || {
            let mut line = String::new();
            let _ = io::stdin().lock().read_line(&mut line);
            let _ = sender.send(());
        });
        println!("ready");
        io::stdout().flush()?;
        let deadline = Instant::now() + Duration::from_secs(60);
        while !state.stop {
            while g_main_context_iteration(ptr::null_mut(), 0) != 0 {
                if state.stop {
                    break;
                }
            }
            if receiver.try_recv().is_ok() {
                break;
            }
            if Instant::now() >= deadline {
                return Err("Cache monitor deadline expired".into());
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        Ok(())
    })();
    g_dbus_connection_signal_unsubscribe(connection.0, subscription);
    result
}

pub fn cache_events(process: u32, output: &str) -> Result<()> {
    if process == 0 {
        return Err("PID must be positive".into());
    }
    // Reserve the report before subscribing; never overwrite earlier evidence.
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(output)?;
    let mut state = Monitor {
        process,
        owners: HashMap::new(),
        stop: false,
        report: json!({"api":"Gio.DBusConnection", "process":process, "add":0, "remove":0, "invalid":[], "passed":false}),
    };
    if let Err(error) = unsafe { monitor(&mut state) } {
        state.report["error"] = json!(error.to_string());
    }
    let passed = state.report["add"].as_u64().unwrap_or(0) > 0
        && state.report["remove"].as_u64().unwrap_or(0) > 0
        && state.report["invalid"].as_array().unwrap().is_empty()
        && state.report.get("error").is_none();
    state.report["passed"] = json!(passed);
    serde_json::to_writer_pretty(&mut file, &state.report)?;
    file.write_all(b"\n")?;
    if passed {
        Ok(())
    } else {
        Err("AT-SPI cache signal verification failed; see report".into())
    }
}
