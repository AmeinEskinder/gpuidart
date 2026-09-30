#![allow(non_upper_case_globals)] // Preserve the SDK enum names in matches.
use crate::{Request, Result};
use serde_json::{json, Value};
use std::fmt;
use windows::{
    core::{BSTR, PCWSTR},
    Win32::{
        Foundation::{E_NOINTERFACE, POINT},
        System::{
            Com::*,
            Rpc::{RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE},
            Variant::{VARIANT, VT_NULL},
            Wmi::*,
        },
        UI::{Accessibility::*, WindowsAndMessaging::*},
    },
};

struct Com;
impl Com {
    fn init() -> Result<Self> {
        unsafe { CoInitializeEx(None, COINIT_MULTITHREADED).ok()? };
        Ok(Self)
    }
}
impl Drop for Com {
    fn drop(&mut self) {
        unsafe { CoUninitialize() }
    }
}

#[derive(Debug)]
pub struct StaleTree(String);
impl fmt::Display for StaleTree {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}
impl std::error::Error for StaleTree {}

unsafe fn context() -> Value {
    let mut pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), Some(&mut pid));
    let mut point = POINT::default();
    let cursor = GetPhysicalCursorPos(&mut point)
        .is_ok()
        .then(|| vec![point.x, point.y]);
    json!({"foreground_process": pid, "cursor": cursor})
}

fn optional_pattern<T>(result: windows::core::Result<T>) -> Result<Option<T>> {
    match result {
        Ok(pattern) => Ok(Some(pattern)),
        Err(error)
            // windows-core represents a successful null COM result as Error::empty().
            if error.code().0 == 0
                || error.code() == E_NOINTERFACE
                || error.code().0 as u32 == UIA_E_NOTSUPPORTED =>
        {
            Ok(None)
        }
        Err(error) => Err(error.into()),
    }
}

fn accessibility_inner(request: &Request) -> Result<Value> {
    let _com = Com::init()?;
    unsafe {
        let automation: IUIAutomation =
            CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER)?;
        let condition = automation
            .CreatePropertyCondition(UIA_ProcessIdPropertyId, &VARIANT::from(request.process))?;
        let window = automation
            .GetRootElement()?
            .FindFirst(TreeScope_Children, &condition)
            .map_err(|e| {
                format!(
                    "No UIA window for process {}; context={}; {e}",
                    request.process,
                    context()
                )
            })?;
        eprintln!("stage window {:?}", window.CurrentNativeWindowHandle()?);
        let elements = window.FindAll(TreeScope_Subtree, &automation.CreateTrueCondition()?)?;
        let count = elements.Length()?;
        eprintln!("stage elements {count}");
        if count > 4096 {
            return Err(format!("UIA tree exceeds probe bound: {count}").into());
        }
        if request.operation != "query" {
            let mut matches = Vec::new();
            for index in 0..count {
                let element = elements.GetElement(index)?;
                let matched = if request.id.is_empty() {
                    element.CurrentName()?.to_string() == request.name
                } else {
                    element.CurrentAutomationId()?.to_string() == request.id
                };
                if matched
                    && (request.operation != "invoke-menu"
                        || element.CurrentControlType()? == UIA_MenuItemControlTypeId)
                {
                    matches.push(element);
                }
            }
            if matches.len() != 1 {
                return Err(format!(
                    "Expected one UIA element named '{}', got {}",
                    request.name,
                    matches.len()
                )
                .into());
            }
            let element = &matches[0];
            let mut details = json!({});
            match request.operation.as_str() {
                "invoke" | "invoke-menu" => {
                    element
                        .GetCurrentPatternAs::<IUIAutomationInvokePattern>(UIA_InvokePatternId)?
                        .Invoke()?;
                    if request.operation == "invoke-menu" {
                        details["pattern"] = json!("Invoke");
                    }
                }
                "toggle" => element
                    .GetCurrentPatternAs::<IUIAutomationTogglePattern>(UIA_TogglePatternId)?
                    .Toggle()?,
                "set-value" => {
                    element
                        .GetCurrentPatternAs::<IUIAutomationValuePattern>(UIA_ValuePatternId)?
                        .SetValue(&BSTR::from(&request.value))?;
                }
                "set-range" => element
                    .GetCurrentPatternAs::<IUIAutomationRangeValuePattern>(UIA_RangeValuePatternId)?
                    .SetValue(request.value.parse()?)?,
                "focus" => element.SetFocus()?,
                "select" => element
                    .GetCurrentPatternAs::<IUIAutomationSelectionItemPattern>(
                        UIA_SelectionItemPatternId,
                    )?
                    .Select()?,
                "hover" => {
                    let bounds = element.CurrentBoundingRectangle()?;
                    let width = bounds.right - bounds.left;
                    let height = bounds.bottom - bounds.top;
                    details["bounds"] = json!([bounds.left, bounds.top, width, height]);
                    if width <= 0 || height <= 0 {
                        return Err("Hover target has no bounds".into());
                    }
                    let _ = SetForegroundWindow(window.CurrentNativeWindowHandle()?);
                    if context()["foreground_process"] != request.process {
                        return Err(format!(
                            "Owned window did not gain foreground access; context={}",
                            context()
                        )
                        .into());
                    }
                    SetPhysicalCursorPos(bounds.left + width / 2, bounds.top + height / 2)?;
                }
                _ => unreachable!(),
            }
            return Ok(
                json!({"api":"UIAutomationClient", "operation":request.operation, "accepted":true, "details":details, "context":context()}),
            );
        }
        let mut nodes = Vec::new();
        let mut identifiers = std::collections::HashSet::new();
        for index in 0..count {
            let element = elements.GetElement(index)?;
            let identifier = element.CurrentAutomationId()?.to_string();
            if !identifier.is_empty() && !identifiers.insert(identifier.clone()) {
                return Err(format!("Duplicate UIA AutomationId: {identifier}").into());
            }
            let control_type = element.CurrentControlType()?.0;
            let roles = [
                "Button",
                "Calendar",
                "CheckBox",
                "ComboBox",
                "Edit",
                "Hyperlink",
                "Image",
                "ListItem",
                "List",
                "Menu",
                "MenuBar",
                "MenuItem",
                "ProgressBar",
                "RadioButton",
                "ScrollBar",
                "Slider",
                "Spinner",
                "StatusBar",
                "Tab",
                "TabItem",
                "Text",
                "ToolBar",
                "ToolTip",
                "Tree",
                "TreeItem",
                "Custom",
                "Group",
                "Thumb",
                "DataGrid",
                "DataItem",
                "Document",
                "SplitButton",
                "Window",
                "Pane",
                "Header",
                "HeaderItem",
                "Table",
                "TitleBar",
                "Separator",
                "SemanticZoom",
                "AppBar",
            ];
            let role = roles
                .get((control_type - 50000) as usize)
                .ok_or_else(|| format!("Unknown UIA control type {control_type}"))?;
            let description =
                BSTR::try_from(&element.GetCurrentPropertyValue(UIA_FullDescriptionPropertyId)?)
                    .map(|s| s.to_string())
                    .unwrap_or_default();
            let mut node = json!({
                "name":element.CurrentName()?.to_string(), "description":description,
                "help":element.CurrentHelpText()?.to_string(), "role":format!("ControlType.{role}"),
                "id":identifier, "enabled":element.CurrentIsEnabled()?.as_bool(),
                "focused":element.CurrentHasKeyboardFocus()?.as_bool(), "focusable":element.CurrentIsKeyboardFocusable()?.as_bool(),
                "offscreen":element.CurrentIsOffscreen()?.as_bool(),
            });
            let mut patterns = Vec::new();
            for (id, name) in [
                (UIA_InvokePatternId, "Invoke"),
                (UIA_SelectionPatternId, "Selection"),
                (UIA_ValuePatternId, "Value"),
                (UIA_RangeValuePatternId, "RangeValue"),
                (UIA_ScrollPatternId, "Scroll"),
                (UIA_ExpandCollapsePatternId, "ExpandCollapse"),
                (UIA_GridPatternId, "Grid"),
                (UIA_GridItemPatternId, "GridItem"),
                (UIA_MultipleViewPatternId, "MultipleView"),
                (UIA_WindowPatternId, "Window"),
                (UIA_SelectionItemPatternId, "SelectionItem"),
                (UIA_DockPatternId, "Dock"),
                (UIA_TablePatternId, "Table"),
                (UIA_TableItemPatternId, "TableItem"),
                (UIA_TextPatternId, "Text"),
                (UIA_TogglePatternId, "Toggle"),
                (UIA_TransformPatternId, "Transform"),
                (UIA_ScrollItemPatternId, "ScrollItem"),
            ] {
                if optional_pattern(element.GetCurrentPattern(id))?.is_some() {
                    patterns.push(format!("{name}PatternIdentifiers.Pattern"));
                }
            }
            node["patterns"] = json!(patterns);
            if let Some(p) = optional_pattern(
                element.GetCurrentPatternAs::<IUIAutomationTogglePattern>(UIA_TogglePatternId),
            )? {
                node["checked"] = json!(match p.CurrentToggleState()? {
                    ToggleState_Off => "Off",
                    ToggleState_On => "On",
                    _ => "Indeterminate",
                });
            }
            if let Some(p) = optional_pattern(
                element.GetCurrentPatternAs::<IUIAutomationValuePattern>(UIA_ValuePatternId),
            )? {
                node["value"] = json!(p.CurrentValue()?.to_string());
                node["read_only"] = json!(p.CurrentIsReadOnly()?.as_bool());
            }
            if let Some(p) = optional_pattern(
                element
                    .GetCurrentPatternAs::<IUIAutomationRangeValuePattern>(UIA_RangeValuePatternId),
            )? {
                node["number"] = json!(p.CurrentValue()?);
                node["min"] = json!(p.CurrentMinimum()?);
                node["max"] = json!(p.CurrentMaximum()?);
                node["step"] = json!(p.CurrentSmallChange()?);
                node["read_only"] = json!(p.CurrentIsReadOnly()?.as_bool());
            }
            if let Some(p) = optional_pattern(
                element.GetCurrentPatternAs::<IUIAutomationExpandCollapsePattern>(
                    UIA_ExpandCollapsePatternId,
                ),
            )? {
                node["expanded"] = json!(match p.CurrentExpandCollapseState()? {
                    ExpandCollapseState_Collapsed => "Collapsed",
                    ExpandCollapseState_Expanded => "Expanded",
                    ExpandCollapseState_PartiallyExpanded => "PartiallyExpanded",
                    _ => "LeafNode",
                });
            }
            if let Some(p) = optional_pattern(
                element.GetCurrentPatternAs::<IUIAutomationWindowPattern>(UIA_WindowPatternId),
            )? {
                node["modal"] = json!(p.CurrentIsModal()?.as_bool());
            }
            if let Some(p) = optional_pattern(
                element.GetCurrentPatternAs::<IUIAutomationSelectionItemPattern>(
                    UIA_SelectionItemPatternId,
                ),
            )? {
                node["selected"] = json!(p.CurrentIsSelected()?.as_bool());
            }
            if let Some(p) = optional_pattern(
                element.GetCurrentPatternAs::<IUIAutomationGridPattern>(UIA_GridPatternId),
            )? {
                node["rows"] = json!(p.CurrentRowCount()?);
                node["columns"] = json!(p.CurrentColumnCount()?);
            }
            if let Some(p) = optional_pattern(
                element.GetCurrentPatternAs::<IUIAutomationGridItemPattern>(UIA_GridItemPatternId),
            )? {
                node["row"] = json!(p.CurrentRow()?);
                node["column"] = json!(p.CurrentColumn()?);
            }
            nodes.push(node);
        }
        eprintln!("stage nodes {}", nodes.len());
        Ok(
            json!({"api":"UIAutomationClient", "process":request.process, "context":context(), "nodes":nodes}),
        )
    }
}

pub fn accessibility(request: &Request) -> Result<Value> {
    let result = accessibility_inner(request);
    if request.operation == "query" {
        if let Err(error) = &result {
            if let Some(error) = error.downcast_ref::<windows::core::Error>() {
                if error.code().0 as u32 == UIA_E_ELEMENTNOTAVAILABLE {
                    return Err(StaleTree(format!("Stale UIA element: {error}")).into());
                }
            }
        }
    }
    result
}

pub fn environment() -> Result<Value> {
    let _com = Com::init()?;
    unsafe {
        CoInitializeSecurity(
            None,
            -1,
            None,
            None,
            RPC_C_AUTHN_LEVEL_DEFAULT,
            RPC_C_IMP_LEVEL_IMPERSONATE,
            None,
            EOAC_NONE,
            None,
        )?;
        let locator: IWbemLocator = CoCreateInstance(&WbemLocator, None, CLSCTX_INPROC_SERVER)?;
        let service = locator.ConnectServer(
            &BSTR::from("ROOT\\CIMV2"),
            &BSTR::new(),
            &BSTR::new(),
            &BSTR::new(),
            0,
            &BSTR::new(),
            None,
        )?;
        CoSetProxyBlanket(
            &service,
            RPC_C_AUTHN_WINNT,
            RPC_C_AUTHZ_NONE,
            None,
            RPC_C_AUTHN_LEVEL_CALL,
            RPC_C_IMP_LEVEL_IMPERSONATE,
            None,
            EOAC_NONE,
        )?;
        let mut report = json!({});
        for (class, fields) in [
            (
                "Win32_OperatingSystem",
                &[
                    "Caption",
                    "Version",
                    "BuildNumber",
                    "TotalVisibleMemorySize",
                ][..],
            ),
            (
                "Win32_Processor",
                &["Name", "NumberOfCores", "NumberOfLogicalProcessors"][..],
            ),
            (
                "Win32_VideoController",
                &[
                    "Name",
                    "DriverVersion",
                    "CurrentHorizontalResolution",
                    "CurrentVerticalResolution",
                ][..],
            ),
        ] {
            let query = service.ExecQuery(
                &BSTR::from("WQL"),
                &BSTR::from(format!("SELECT {} FROM {class}", fields.join(","))),
                WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
                None,
            )?;
            let mut rows = Vec::new();
            loop {
                let mut objects = [None];
                let mut returned = 0;
                let status = query.Next(3000, &mut objects, &mut returned);
                status.ok()?;
                if status.0 == WBEM_S_TIMEDOUT.0 {
                    return Err(format!("WMI query timed out: {class}").into());
                }
                if returned == 0 {
                    break;
                }
                let object = objects[0].take().ok_or("WMI returned no object")?;
                let mut row = json!({});
                for field in fields {
                    let key: Vec<u16> = field.encode_utf16().chain(Some(0)).collect();
                    let mut value = VARIANT::default();
                    object.Get(PCWSTR(key.as_ptr()), 0, &mut value, None, None)?;
                    row[*field] = if value.is_empty() || value.vt() == VT_NULL {
                        Value::Null
                    } else if matches!(
                        *field,
                        "NumberOfCores"
                            | "NumberOfLogicalProcessors"
                            | "CurrentHorizontalResolution"
                            | "CurrentVerticalResolution"
                    ) {
                        Value::from(i64::try_from(&value)?)
                    } else {
                        json!(BSTR::try_from(&value)?.to_string())
                    };
                }
                rows.push(row);
            }
            report[class] = json!(rows);
        }
        Ok(report)
    }
}
