//! External libatspi reads and actions. GIO observes the independent cache bus.
use crate::{Request, Result};
use serde_json::{json, Value};
use std::{
    ffi::{c_char, c_int, c_long, c_void, CStr, CString},
    fmt, ptr,
};

mod cache;
pub use cache::cache_events;

type Object = *mut c_void;
#[repr(C)]
struct GError {
    domain: u32,
    code: c_int,
    message: *mut c_char,
}
#[repr(C)]
struct GArray {
    data: *mut *mut c_char,
    len: u32,
}
#[repr(C)]
struct Rect {
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
}

#[link(name = "glib-2.0")]
extern "C" {
    fn g_free(data: *mut c_void);
    fn g_error_free(error: *mut GError);
    fn g_quark_to_string(quark: u32) -> *const c_char;
    fn g_array_unref(array: *mut GArray);
}
#[link(name = "gobject-2.0")]
extern "C" {
    fn g_object_unref(object: Object);
}
#[link(name = "atspi")]
extern "C" {
    fn atspi_init() -> c_int;
    fn atspi_exit() -> c_int;
    fn atspi_set_timeout(value: c_int, startup: c_int);
    fn atspi_get_desktop(index: c_int) -> Object;
    fn atspi_accessible_get_child_count(obj: Object, error: *mut *mut GError) -> c_int;
    fn atspi_accessible_get_child_at_index(
        obj: Object,
        index: c_int,
        error: *mut *mut GError,
    ) -> Object;
    fn atspi_accessible_get_process_id(obj: Object, error: *mut *mut GError) -> u32;
    fn atspi_accessible_get_name(obj: Object, error: *mut *mut GError) -> *mut c_char;
    fn atspi_accessible_get_description(obj: Object, error: *mut *mut GError) -> *mut c_char;
    fn atspi_accessible_get_accessible_id(obj: Object, error: *mut *mut GError) -> *mut c_char;
    fn atspi_accessible_get_role_name(obj: Object, error: *mut *mut GError) -> *mut c_char;
    fn atspi_accessible_get_state_set(obj: Object) -> Object;
    fn atspi_accessible_get_interfaces(obj: Object) -> *mut GArray;
    fn atspi_accessible_get_action_iface(obj: Object) -> Object;
    fn atspi_accessible_get_text_iface(obj: Object) -> Object;
    fn atspi_accessible_get_value_iface(obj: Object) -> Object;
    fn atspi_accessible_get_table_iface(obj: Object) -> Object;
    fn atspi_accessible_get_editable_text_iface(obj: Object) -> Object;
    fn atspi_accessible_get_component_iface(obj: Object) -> Object;
    fn atspi_state_set_contains(obj: Object, state: c_int) -> c_int;
    fn atspi_action_get_n_actions(obj: Object, error: *mut *mut GError) -> c_int;
    fn atspi_action_get_action_name(
        obj: Object,
        index: c_int,
        error: *mut *mut GError,
    ) -> *mut c_char;
    fn atspi_action_do_action(obj: Object, index: c_int, error: *mut *mut GError) -> c_int;
    fn atspi_text_get_text(
        obj: Object,
        start: c_int,
        end: c_int,
        error: *mut *mut GError,
    ) -> *mut c_char;
    fn atspi_value_get_current_value(obj: Object, error: *mut *mut GError) -> f64;
    fn atspi_value_get_minimum_value(obj: Object, error: *mut *mut GError) -> f64;
    fn atspi_value_get_maximum_value(obj: Object, error: *mut *mut GError) -> f64;
    fn atspi_value_get_minimum_increment(obj: Object, error: *mut *mut GError) -> f64;
    fn atspi_value_set_current_value(obj: Object, value: f64, error: *mut *mut GError) -> c_int;
    fn atspi_table_get_n_rows(obj: Object, error: *mut *mut GError) -> c_int;
    fn atspi_table_get_n_columns(obj: Object, error: *mut *mut GError) -> c_int;
    fn atspi_editable_text_set_text_contents(
        obj: Object,
        value: *const c_char,
        error: *mut *mut GError,
    ) -> c_int;
    fn atspi_component_grab_focus(obj: Object, error: *mut *mut GError) -> c_int;
    fn atspi_component_get_extents(obj: Object, coord: c_int, error: *mut *mut GError)
        -> *mut Rect;
    fn atspi_generate_mouse_event(
        x: c_long,
        y: c_long,
        name: *const c_char,
        error: *mut *mut GError,
    ) -> c_int;
}

#[derive(Debug)]
pub struct StaleTree(String);
impl fmt::Display for StaleTree {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}
impl std::error::Error for StaleTree {}

#[derive(Debug)]
struct BusError {
    domain: String,
    code: i32,
    message: String,
}
impl fmt::Display for BusError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}({}): {}", self.domain, self.code, self.message)
    }
}
impl std::error::Error for BusError {}

unsafe fn borrowed_text(value: *const c_char) -> String {
    if value.is_null() {
        String::new()
    } else {
        CStr::from_ptr(value).to_string_lossy().into_owned()
    }
}
unsafe fn text(value: *mut c_char) -> String {
    let result = borrowed_text(value);
    g_free(value.cast());
    result
}
fn call<T>(f: impl FnOnce(*mut *mut GError) -> T) -> Result<T> {
    let mut error = ptr::null_mut();
    let value = f(&mut error);
    if error.is_null() {
        return Ok(value);
    }
    unsafe {
        let result = BusError {
            domain: borrowed_text(g_quark_to_string((*error).domain)),
            code: (*error).code,
            message: borrowed_text((*error).message),
        };
        g_error_free(error);
        Err(result.into())
    }
}
struct Owned(Object);
impl Owned {
    fn required(value: Object) -> Result<Self> {
        if value.is_null() {
            Err("Missing AT-SPI interface".into())
        } else {
            Ok(Self(value))
        }
    }
}
impl Drop for Owned {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe { g_object_unref(self.0) }
        }
    }
}
struct Session;
impl Drop for Session {
    fn drop(&mut self) {
        unsafe {
            atspi_exit();
        }
    }
}

unsafe fn visit(
    element: Object,
    parent: Option<usize>,
    elements: &mut Vec<(Owned, Option<usize>)>,
) -> Result<()> {
    if element.is_null() {
        return Err(StaleTree("Child disappeared after its parent child-count read".into()).into());
    }
    let owned = Owned(element);
    if elements.len() >= 4096 {
        return Err("AT-SPI tree exceeds probe bound".into());
    }
    let index = elements.len();
    elements.push((owned, parent));
    let count = call(|e| atspi_accessible_get_child_count(element, e))?;
    for child in 0..count {
        visit(
            call(|e| atspi_accessible_get_child_at_index(element, child, e))?,
            Some(index),
            elements,
        )?;
    }
    Ok(())
}

unsafe fn action_names(action: Object) -> Result<Vec<String>> {
    let count = call(|e| atspi_action_get_n_actions(action, e))?;
    (0..count)
        .map(|i| call(|e| atspi_action_get_action_name(action, i, e)).map(|p| text(p)))
        .collect()
}

unsafe fn read_or_act(request: &Request, application: Object) -> Result<Value> {
    // The caller owns the application reference; traversal holds its own reference.
    #[link(name = "gobject-2.0")]
    extern "C" {
        fn g_object_ref(object: Object) -> Object;
    }
    let mut elements = Vec::new();
    visit(g_object_ref(application), None, &mut elements)?;
    if request.operation != "query" {
        let mut matches = Vec::new();
        for (element, _) in &elements {
            let label = if request.id.is_empty() {
                text(call(|e| atspi_accessible_get_name(element.0, e))?)
            } else {
                text(call(|e| atspi_accessible_get_accessible_id(element.0, e))?)
            };
            if label
                != (if request.id.is_empty() {
                    &request.name
                } else {
                    &request.id
                })
                .as_str()
            {
                continue;
            }
            if request.operation == "invoke-menu"
                && !["menu item", "check menu item", "radio menu item"].contains(
                    &text(call(|e| atspi_accessible_get_role_name(element.0, e))?).as_str(),
                )
            {
                continue;
            }
            matches.push(element.0);
        }
        if matches.len() != 1 {
            return Err(format!(
                "Expected one AT-SPI element named {}, got {}",
                request.name,
                matches.len()
            )
            .into());
        }
        let element = matches[0];
        let mut output = json!({"api":"AT-SPI", "operation":request.operation, "accepted":true});
        let accepted = match request.operation.as_str() {
            "invoke" | "toggle" | "select" | "invoke-menu" => {
                let action = Owned::required(atspi_accessible_get_action_iface(element))?;
                let names = action_names(action.0)?;
                let candidates: Vec<_> = names
                    .iter()
                    .enumerate()
                    .filter(|(_, s)| ["click", "press", "toggle"].contains(&s.as_str()))
                    .collect();
                if candidates.len() != 1 {
                    return Err(format!("Expected one click action, got {names:?}").into());
                }
                call(|e| atspi_action_do_action(action.0, candidates[0].0 as i32, e))?
            }
            "hover" => {
                let component = Owned::required(atspi_accessible_get_component_iface(element))?;
                let bounds = call(|e| atspi_component_get_extents(component.0, 0, e))?;
                if bounds.is_null() {
                    return Err("Hover target has no bounds".into());
                }
                let Rect {
                    x,
                    y,
                    width,
                    height,
                } = ptr::read(bounds);
                g_free(bounds.cast());
                if width <= 0 || height <= 0 {
                    return Err("Hover target has no bounds".into());
                }
                output["bounds"] = json!([x, y, width, height]);
                call(|e| {
                    atspi_generate_mouse_event(
                        (x + width / 2) as c_long,
                        (y + height / 2) as c_long,
                        c"abs".as_ptr(),
                        e,
                    )
                })?
            }
            "set-value" => {
                let interface = Owned::required(atspi_accessible_get_editable_text_iface(element))?;
                let value = CString::new(request.value.as_str())?;
                call(|e| atspi_editable_text_set_text_contents(interface.0, value.as_ptr(), e))?
            }
            "set-range" => {
                let interface = Owned::required(atspi_accessible_get_value_iface(element))?;
                let value = request.value.parse()?;
                call(|e| atspi_value_set_current_value(interface.0, value, e))?
            }
            "focus" => {
                let interface = Owned::required(atspi_accessible_get_component_iface(element))?;
                call(|e| atspi_component_grab_focus(interface.0, e))?
            }
            _ => unreachable!(),
        };
        if accepted == 0 {
            return Err(format!("AT-SPI rejected {}", request.operation).into());
        }
        return Ok(output);
    }
    let mut nodes = Vec::new();
    for (element, parent) in &elements {
        let element = element.0;
        let state = Owned::required(atspi_accessible_get_state_set(element))?;
        let mut node = json!({
            "parent":parent,
            "name":text(call(|e| atspi_accessible_get_name(element, e))?),
            "description":text(call(|e| atspi_accessible_get_description(element, e))?),
            "role":text(call(|e| atspi_accessible_get_role_name(element, e))?),
            "id":text(call(|e| atspi_accessible_get_accessible_id(element, e))?),
        });
        for (field, bit) in [
            ("enabled", 8),
            ("focused", 12),
            ("focusable", 11),
            ("checked", 4),
            ("selected", 23),
            ("expanded", 10),
            ("modal", 16),
        ] {
            node[field] = json!(atspi_state_set_contains(state.0, bit) != 0);
        }
        let interfaces = atspi_accessible_get_interfaces(element);
        let mut names = Vec::new();
        if !interfaces.is_null() {
            for i in 0..(*interfaces).len {
                names.push(text(*(*interfaces).data.add(i as usize)));
            }
            g_array_unref(interfaces);
        }
        node["interfaces"] = json!(names);
        let action = Owned(atspi_accessible_get_action_iface(element));
        if !action.0.is_null() {
            node["actions"] = json!(action_names(action.0)?);
        }
        let txt = Owned(atspi_accessible_get_text_iface(element));
        if !txt.0.is_null() {
            node["value"] = json!(text(call(|e| atspi_text_get_text(txt.0, 0, -1, e))?));
        }
        let numeric = Owned(atspi_accessible_get_value_iface(element));
        if !numeric.0.is_null() {
            node["number"] = json!(call(|e| atspi_value_get_current_value(numeric.0, e))?);
            node["min"] = json!(call(|e| atspi_value_get_minimum_value(numeric.0, e))?);
            node["max"] = json!(call(|e| atspi_value_get_maximum_value(numeric.0, e))?);
            node["step"] = json!(call(|e| atspi_value_get_minimum_increment(numeric.0, e))?);
        }
        let table = Owned(atspi_accessible_get_table_iface(element));
        if !table.0.is_null() {
            node["rows"] = json!(call(|e| atspi_table_get_n_rows(table.0, e))?);
            node["columns"] = json!(call(|e| atspi_table_get_n_columns(table.0, e))?);
        }
        nodes.push(node);
    }
    Ok(json!({"api":"AT-SPI", "process":request.process, "nodes":nodes}))
}

pub fn accessibility(request: &Request) -> Result<Value> {
    unsafe {
        if atspi_init() != 0 {
            return Err("AT-SPI initialization failed".into());
        }
        let _session = Session;
        atspi_set_timeout(3000, 10000);
        let desktop = Owned::required(atspi_get_desktop(0))?;
        let mut applications = Vec::new();
        for index in 0..call(|e| atspi_accessible_get_child_count(desktop.0, e))? {
            let child = Owned(call(|e| {
                atspi_accessible_get_child_at_index(desktop.0, index, e)
            })?);
            if !child.0.is_null()
                && call(|e| atspi_accessible_get_process_id(child.0, e))? == request.process as u32
            {
                applications.push(child);
            }
        }
        if applications.len() != 1 {
            return Err(format!(
                "Expected one AT-SPI app for {}, got {}",
                request.process,
                applications.len()
            )
            .into());
        }
        let app = applications[0].0;
        let result = read_or_act(request, app);
        if request.operation == "query" {
            if let Err(error) = &result {
                if let Some(bus) = error.downcast_ref::<BusError>() {
                    if bus.domain == "atspi_error" && bus.code == 0 {
                        if let Ok(value) = call(|e| atspi_accessible_get_accessible_id(app, e)) {
                            text(value);
                            return Err(StaleTree(format!("Stale AT-SPI object: {}; owned application root still answers AccessibleId", bus.message)).into());
                        }
                    }
                    if bus.domain == "atspi_error"
                        && bus.code == 1
                        && (bus.message.starts_with("/org/a11y/atspi/accessible/")
                            || bus
                                .message
                                .starts_with("Unknown object '/org/a11y/atspi/accessible/"))
                    {
                        return Err(
                            StaleTree(format!("Stale AT-SPI element: {}", bus.message)).into()
                        );
                    }
                }
            }
        } else if let Err(error) = &result {
            if error.downcast_ref::<StaleTree>().is_some() {
                return Err(error.to_string().into());
            }
        }
        result
    }
}
