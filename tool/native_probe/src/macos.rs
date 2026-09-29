//! The external AX API and Metal enumeration, without an AppKit application.
use crate::{Request, Result};
use serde_json::{json, Value};
use std::{
    ffi::{c_char, c_void, CStr},
    fmt, ptr,
};

type Ref = *const c_void;
#[repr(C)]
#[derive(Default, Copy, Clone)]
struct Point {
    x: f64,
    y: f64,
}
#[repr(C)]
#[derive(Default)]
struct Size {
    width: f64,
    height: f64,
}

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFRelease(value: Ref);
    fn CFRetain(value: Ref) -> Ref;
    fn CFEqual(a: Ref, b: Ref) -> u8;
    fn CFGetTypeID(value: Ref) -> usize;
    fn CFStringGetTypeID() -> usize;
    fn CFStringCreateWithBytes(
        allocator: Ref,
        bytes: *const u8,
        count: isize,
        encoding: u32,
        external: u8,
    ) -> Ref;
    fn CFStringGetLength(value: Ref) -> isize;
    fn CFStringGetMaximumSizeForEncoding(length: isize, encoding: u32) -> isize;
    fn CFStringGetCString(value: Ref, buffer: *mut c_char, size: isize, encoding: u32) -> u8;
    fn CFBooleanGetTypeID() -> usize;
    fn CFBooleanGetValue(value: Ref) -> u8;
    fn CFNumberGetTypeID() -> usize;
    fn CFNumberGetValue(value: Ref, number_type: isize, output: *mut c_void) -> u8;
    fn CFNumberCreate(allocator: Ref, number_type: isize, value: *const c_void) -> Ref;
    fn CFArrayGetTypeID() -> usize;
    fn CFArrayGetCount(value: Ref) -> isize;
    fn CFArrayGetValueAtIndex(value: Ref, index: isize) -> Ref;
    static kCFBooleanTrue: Ref;
}
#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn AXIsProcessTrusted() -> u8;
    fn AXUIElementCreateApplication(pid: i32) -> Ref;
    fn AXUIElementSetMessagingTimeout(element: Ref, seconds: f32) -> i32;
    fn AXUIElementCopyAttributeValue(element: Ref, attribute: Ref, value: *mut Ref) -> i32;
    fn AXUIElementCopyActionNames(element: Ref, names: *mut Ref) -> i32;
    fn AXUIElementPerformAction(element: Ref, action: Ref) -> i32;
    fn AXUIElementSetAttributeValue(element: Ref, attribute: Ref, value: Ref) -> i32;
    fn AXValueGetValue(value: Ref, kind: u32, output: *mut c_void) -> u8;
}
#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGEventCreateMouseEvent(source: Ref, kind: u32, position: Point, button: u32) -> Ref;
    fn CGEventPost(location: u32, event: Ref);
}

struct Cf(Ref);
impl Cf {
    fn owned(value: Ref) -> Result<Self> {
        if value.is_null() {
            Err("Native API returned no object".into())
        } else {
            Ok(Self(value))
        }
    }
    fn string(text: &str) -> Result<Self> {
        unsafe {
            Self::owned(CFStringCreateWithBytes(
                ptr::null(),
                text.as_ptr(),
                text.len() as isize,
                0x08000100,
                0,
            ))
        }
    }
}
impl Drop for Cf {
    fn drop(&mut self) {
        unsafe { CFRelease(self.0) }
    }
}

#[derive(Debug)]
struct StaleElement(String);
impl fmt::Display for StaleElement {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Invalid AX element at {}", self.0)
    }
}
impl std::error::Error for StaleElement {}

unsafe fn string(value: Ref) -> Result<String> {
    if CFGetTypeID(value) != CFStringGetTypeID() {
        return Err("Expected a CoreFoundation string".into());
    }
    let size = CFStringGetMaximumSizeForEncoding(CFStringGetLength(value), 0x08000100) + 1;
    let mut bytes = vec![0u8; size as usize];
    if CFStringGetCString(value, bytes.as_mut_ptr().cast(), size, 0x08000100) == 0 {
        return Err("Cannot decode CoreFoundation string".into());
    }
    Ok(CStr::from_ptr(bytes.as_ptr().cast()).to_str()?.to_owned())
}
unsafe fn scalar(value: Ref) -> Result<Option<Value>> {
    let kind = CFGetTypeID(value);
    if kind == CFStringGetTypeID() {
        return Ok(Some(json!(string(value)?)));
    }
    if kind == CFBooleanGetTypeID() {
        return Ok(Some(json!(CFBooleanGetValue(value) != 0)));
    }
    if kind == CFNumberGetTypeID() {
        let mut number = 0f64;
        if CFNumberGetValue(value, 6, (&mut number as *mut f64).cast()) == 0 {
            return Err("Cannot decode CoreFoundation number".into());
        }
        return Ok(Some(json!(number)));
    }
    Ok(None)
}
unsafe fn array(value: Ref) -> Result<Vec<Cf>> {
    if CFGetTypeID(value) != CFArrayGetTypeID() {
        return Err("Expected a CoreFoundation array".into());
    }
    (0..CFArrayGetCount(value))
        .map(|i| Cf::owned(CFRetain(CFArrayGetValueAtIndex(value, i))))
        .collect()
}
unsafe fn attribute(element: Ref, key: &str) -> Result<Option<Cf>> {
    let key_string = Cf::string(key)?;
    let mut value = ptr::null();
    match AXUIElementCopyAttributeValue(element, key_string.0, &mut value) {
        0 => Ok(Some(Cf::owned(value)?)),
        -25202 => Err(StaleElement(key.to_owned()).into()),
        -25205 | -25212 => Ok(None),
        code => Err(format!("{key}: AXError {code}").into()),
    }
}
unsafe fn label(element: Ref) -> Result<String> {
    for key in ["AXTitle", "AXDescription"] {
        if let Some(value) = attribute(element, key)? {
            if let Some(Value::String(value)) = scalar(value.0)? {
                if !value.is_empty() {
                    return Ok(value);
                }
            }
        }
    }
    Ok(String::new())
}
unsafe fn visit(
    element: Cf,
    parent: Option<usize>,
    elements: &mut Vec<(Cf, Option<usize>)>,
) -> Result<()> {
    if elements
        .iter()
        .any(|(existing, _)| CFEqual(existing.0, element.0) != 0)
    {
        return Ok(());
    }
    if elements.len() >= 4096 {
        return Err("AX tree exceeds probe bound".into());
    }
    let index = elements.len();
    let children = attribute(element.0, "AXChildren")?
        .map(|a| array(a.0))
        .transpose()?
        .unwrap_or_default();
    elements.push((element, parent));
    for child in children {
        visit(child, Some(index), elements)?;
    }
    Ok(())
}
unsafe fn set(element: Ref, key: &str, value: Ref) -> Result<i32> {
    Ok(AXUIElementSetAttributeValue(
        element,
        Cf::string(key)?.0,
        value,
    ))
}

unsafe fn attempt(request: &Request, restarts: &[String]) -> Result<Value> {
    if AXIsProcessTrusted() == 0 {
        return Err(
            "AXIsProcessTrusted=false; external AX access requires Accessibility authorization"
                .into(),
        );
    }
    let app = Cf::owned(AXUIElementCreateApplication(request.process))?;
    let timeout = AXUIElementSetMessagingTimeout(app.0, 3.0);
    if timeout != 0 {
        return Err(format!("Cannot set AX timeout: {timeout}").into());
    }
    let mut elements = Vec::new();
    visit(Cf::owned(CFRetain(app.0))?, None, &mut elements)?;
    if let Some(menu) = attribute(app.0, "AXMenuBar")? {
        visit(menu, Some(0), &mut elements)?;
    }
    let mut output =
        json!({"api":"AXUIElement", "process":request.process, "query_restarts":restarts});
    if request.operation == "query" {
        let mut nodes = Vec::new();
        for (element, parent) in &elements {
            let mut node = json!({"name":label(element.0)?, "parent":parent});
            for (field, key) in [
                ("description", "AXHelp"),
                ("role", "AXRole"),
                ("id", "AXIdentifier"),
                ("subrole", "AXSubrole"),
                ("modal", "AXModal"),
                ("value", "AXValue"),
                ("min", "AXMinValue"),
                ("max", "AXMaxValue"),
                ("enabled", "AXEnabled"),
                ("focused", "AXFocused"),
                ("selected", "AXSelected"),
                ("expanded", "AXExpanded"),
            ] {
                if let Some(value) = attribute(element.0, key)? {
                    if let Some(value) = scalar(value.0)? {
                        node[field] = value;
                    }
                }
            }
            let mut actions = ptr::null();
            let status = AXUIElementCopyActionNames(element.0, &mut actions);
            if status == -25202 {
                return Err(StaleElement("AXActionNames".into()).into());
            }
            if status != 0 && status != -25208 {
                return Err(format!("AX actions: {status}").into());
            }
            let mut names = Vec::new();
            if !actions.is_null() {
                let actions = Cf(actions);
                for action in array(actions.0)? {
                    names.push(string(action.0)?);
                }
            }
            node["actions"] = json!(names);
            nodes.push(node);
        }
        output["nodes"] = json!(nodes);
    } else {
        let mut matches = Vec::new();
        for (element, _) in &elements {
            if request.operation == "invoke-menu"
                && attribute(element.0, "AXRole")?
                    .map(|v| string(v.0))
                    .transpose()?
                    .as_deref()
                    != Some("AXMenuItem")
            {
                continue;
            }
            let matched = if request.id.is_empty() {
                label(element.0)? == request.name
            } else {
                attribute(element.0, "AXIdentifier")?
                    .map(|v| string(v.0))
                    .transpose()?
                    .as_deref()
                    == Some(&request.id)
            };
            if matched {
                matches.push(element.0);
            }
        }
        if matches.len() != 1 {
            return Err(format!(
                "Expected one AX element named {}, got {}",
                request.name,
                matches.len()
            )
            .into());
        }
        let element = matches[0];
        let status = match request.operation.as_str() {
            "invoke" | "toggle" | "select" | "invoke-menu" => {
                AXUIElementPerformAction(element, Cf::string("AXPress")?.0)
            }
            "set-value" => set(element, "AXValue", Cf::string(&request.value)?.0)?,
            "set-range" => {
                let number: f64 = request.value.parse()?;
                if !number.is_finite() {
                    return Err("Invalid number".into());
                }
                let value = Cf::owned(CFNumberCreate(
                    ptr::null(),
                    6,
                    (&number as *const f64).cast(),
                ))?;
                set(element, "AXValue", value.0)?
            }
            "focus" => set(element, "AXFocused", kCFBooleanTrue)?,
            "hover" => {
                let position =
                    attribute(element, "AXPosition")?.ok_or("Hover target has no bounds")?;
                let size = attribute(element, "AXSize")?.ok_or("Hover target has no bounds")?;
                let mut point = Point::default();
                let mut dimensions = Size::default();
                if AXValueGetValue(position.0, 1, (&mut point as *mut Point).cast()) == 0
                    || AXValueGetValue(size.0, 2, (&mut dimensions as *mut Size).cast()) == 0
                    || dimensions.width <= 0.0
                    || dimensions.height <= 0.0
                {
                    return Err("Invalid hover bounds".into());
                }
                let _ = set(app.0, "AXFrontmost", kCFBooleanTrue)?;
                let event = Cf::owned(CGEventCreateMouseEvent(
                    ptr::null(),
                    5,
                    Point {
                        x: point.x + dimensions.width / 2.0,
                        y: point.y + dimensions.height / 2.0,
                    },
                    0,
                ))?;
                CGEventPost(0, event.0);
                0
            }
            _ => unreachable!(),
        };
        if status != 0 {
            return Err(format!("AX action failed: {status}").into());
        }
        output["operation"] = json!(request.operation);
        output["accepted"] = json!(true);
    }
    Ok(output)
}

pub fn accessibility(request: &Request) -> Result<Value> {
    let mut restarts = Vec::new();
    loop {
        match unsafe { attempt(request, &restarts) } {
            Err(error)
                if request.operation == "query"
                    && restarts.len() < 4
                    && error.downcast_ref::<StaleElement>().is_some() =>
            {
                restarts.push(error.to_string());
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(error) => return Err(format!("{error}; query restarts={restarts:?}").into()),
            value => return value,
        }
    }
}

#[link(name = "Metal", kind = "framework")]
extern "C" {
    fn MTLCopyAllDevices() -> Ref;
    fn MTLCreateSystemDefaultDevice() -> Ref;
}
#[link(name = "objc")]
extern "C" {
    fn sel_registerName(name: *const c_char) -> Ref;
    fn objc_msgSend();
    fn objc_release(value: Ref);
}
struct Objc(Ref);
impl Drop for Objc {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe { objc_release(self.0) }
        }
    }
}

pub fn metal() -> Result<Value> {
    unsafe {
        let send_ref: unsafe extern "C" fn(Ref, Ref) -> Ref =
            std::mem::transmute(objc_msgSend as unsafe extern "C" fn());
        let send_u64: unsafe extern "C" fn(Ref, Ref) -> u64 =
            std::mem::transmute(objc_msgSend as unsafe extern "C" fn());
        let send_bool: unsafe extern "C" fn(Ref, Ref) -> i8 =
            std::mem::transmute(objc_msgSend as unsafe extern "C" fn());
        let send_index: unsafe extern "C" fn(Ref, Ref, usize) -> Ref =
            std::mem::transmute(objc_msgSend as unsafe extern "C" fn());
        let all = Objc(MTLCopyAllDevices());
        if all.0.is_null() {
            return Err("MTLCopyAllDevices returned no array".into());
        }
        let count = send_u64(all.0, sel_registerName(c"count".as_ptr()));
        let mut devices = Vec::new();
        for index in 0..count {
            let device = send_index(
                all.0,
                sel_registerName(c"objectAtIndex:".as_ptr()),
                index as usize,
            );
            devices.push(json!({
                "name":string(send_ref(device, sel_registerName(c"name".as_ptr())))?,
                "registry_id":send_u64(device, sel_registerName(c"registryID".as_ptr())).to_string(),
                "low_power":send_bool(device, sel_registerName(c"isLowPower".as_ptr())) != 0,
                "unified_memory":send_bool(device, sel_registerName(c"hasUnifiedMemory".as_ptr())) != 0,
            }));
        }
        let default = Objc(MTLCreateSystemDefaultDevice());
        let name = if default.0.is_null() {
            None
        } else {
            Some(string(send_ref(
                default.0,
                sel_registerName(c"name".as_ptr()),
            ))?)
        };
        Ok(
            json!({"default_device":name, "devices":devices, "scope":"Metal device enumeration on this runner; no physical GPU or presentation claim"}),
        )
    }
}
