use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize};

pub const MAX_MESSAGE_BYTES: usize = 16 * 1024 * 1024;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Snapshot {
    pub revision: u64,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub actions: Vec<ActionBinding>,
    pub root: Node,
}

/// A key binding declared by the application: `name` fires as an `action`
/// event when `keys` is pressed while focus is inside `context`.
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ActionBinding {
    pub name: String,
    pub keys: String,
    /// `"global"` or the ID of a node present in the same snapshot.
    pub context: String,
}

/// Modifiers plus one named key; the closed grammar of `ActionBinding::keys`.
/// `meta` is the platform meta key: cmd on macOS, the windows key on Windows,
/// super on Linux. `ctrl` always means the literal control key.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct KeystrokeSpec {
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    pub meta: bool,
    pub key: String,
}

impl KeystrokeSpec {
    pub fn parse(source: &str) -> Result<Self, String> {
        let mut spec = Self {
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
            key: String::new(),
        };
        let parts: Vec<&str> = source.split('+').collect();
        let Some((key, modifiers)) = parts.split_last() else {
            return Err("Empty key binding".into());
        };
        for modifier in modifiers {
            let flag = match *modifier {
                "ctrl" => &mut spec.ctrl,
                "alt" => &mut spec.alt,
                "shift" => &mut spec.shift,
                "meta" => &mut spec.meta,
                _ => return Err(format!("Unknown modifier in key binding: {source}")),
            };
            if *flag {
                return Err(format!("Duplicate modifier in key binding: {source}"));
            }
            *flag = true;
        }
        let named = matches!(
            *key,
            "enter"
                | "escape"
                | "space"
                | "tab"
                | "up"
                | "down"
                | "left"
                | "right"
                | "home"
                | "end"
                | "pageup"
                | "pagedown"
                | "delete"
                | "backspace"
        ) || key
            .strip_prefix('f')
            .and_then(|n| n.parse::<u8>().ok())
            .is_some_and(|n| (1..=12).contains(&n));
        let printable = key.len() == 1 && {
            let byte = key.as_bytes()[0];
            byte.is_ascii_lowercase() || byte.is_ascii_digit()
        };
        if !named && !printable {
            return Err(format!("Unknown key in key binding: {source}"));
        }
        if printable && !spec.ctrl && !spec.alt && !spec.shift && !spec.meta {
            return Err(format!(
                "Bare printable keys are owned by native text input; add a modifier: {source}"
            ));
        }
        spec.key = key.to_string();
        Ok(spec)
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Node {
    Column {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        children: Vec<Node>,
    },
    Row {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        children: Vec<Node>,
    },
    Text {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        text: String,
    },
    Button {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        label: String,
    },
    Input {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        placeholder: String,
    },
    Table {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        style: Option<Style>,
        dataset: String,
    },
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Style {
    /// Logical px: top, right, bottom, left.
    pub padding: Option<[f32; 4]>,
    pub gap: Option<f32>,
    pub width: Option<Size>,
    pub height: Option<Size>,
    pub align: Option<Align>,
    pub justify: Option<Justify>,
    pub background: Option<Color>,
    pub foreground: Option<Color>,
    pub border_color: Option<Color>,
    pub border_radius: Option<f32>,
    /// Logical px; text nodes only.
    pub font_size: Option<f32>,
    pub font_weight: Option<FontWeight>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Size {
    Px(f32),
    Full,
    Fit,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Align {
    Start,
    Center,
    End,
    Stretch,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Justify {
    Start,
    Center,
    End,
    SpaceBetween,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FontWeight {
    Normal,
    Medium,
    Semibold,
    Bold,
}

/// Theme roles that exist in gpui-kit's `ThemeColor` at the pinned revision.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ThemeToken {
    Background,
    Foreground,
    Primary,
    PrimaryForeground,
    Secondary,
    SecondaryForeground,
    Muted,
    MutedForeground,
    Accent,
    AccentForeground,
    Danger,
    DangerForeground,
    Border,
    Success,
    Warning,
    Info,
}

impl ThemeToken {
    fn parse(name: &str) -> Result<Self, String> {
        Ok(match name {
            "background" => Self::Background,
            "foreground" => Self::Foreground,
            "primary" => Self::Primary,
            "primary_foreground" => Self::PrimaryForeground,
            "secondary" => Self::Secondary,
            "secondary_foreground" => Self::SecondaryForeground,
            "muted" => Self::Muted,
            "muted_foreground" => Self::MutedForeground,
            "accent" => Self::Accent,
            "accent_foreground" => Self::AccentForeground,
            "danger" => Self::Danger,
            "danger_foreground" => Self::DangerForeground,
            "border" => Self::Border,
            "success" => Self::Success,
            "warning" => Self::Warning,
            "info" => Self::Info,
            _ => return Err(format!("Unknown theme token: {name}")),
        })
    }

    fn name(self) -> &'static str {
        match self {
            Self::Background => "background",
            Self::Foreground => "foreground",
            Self::Primary => "primary",
            Self::PrimaryForeground => "primary_foreground",
            Self::Secondary => "secondary",
            Self::SecondaryForeground => "secondary_foreground",
            Self::Muted => "muted",
            Self::MutedForeground => "muted_foreground",
            Self::Accent => "accent",
            Self::AccentForeground => "accent_foreground",
            Self::Danger => "danger",
            Self::DangerForeground => "danger_foreground",
            Self::Border => "border",
            Self::Success => "success",
            Self::Warning => "warning",
            Self::Info => "info",
        }
    }
}

/// `"token:<name>"` or `"#RRGGBB"` / `"#RRGGBBAA"`; hex is stored as 0xRRGGBBAA.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Color {
    Token(ThemeToken),
    Hex(u32),
}

impl Color {
    fn parse(value: &str) -> Result<Self, String> {
        if let Some(name) = value.strip_prefix("token:") {
            return Ok(Self::Token(ThemeToken::parse(name)?));
        }
        if let Some(hex) = value.strip_prefix('#') {
            let channel =
                u32::from_str_radix(hex, 16).map_err(|_| format!("Malformed color: {value}"))?;
            return match hex.len() {
                6 => Ok(Self::Hex(channel << 8 | 0xFF)),
                8 => Ok(Self::Hex(channel)),
                _ => Err(format!("Malformed color: {value}")),
            };
        }
        Err(format!("Malformed color: {value}"))
    }
}

impl<'de> Deserialize<'de> for Color {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = String::deserialize(deserializer)?;
        Self::parse(&value).map_err(serde::de::Error::custom)
    }
}

impl Serialize for Color {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::Token(token) => serializer.serialize_str(&format!("token:{}", token.name())),
            Self::Hex(value) => serializer.serialize_str(&format!("#{value:08X}")),
        }
    }
}

impl Style {
    fn validate(&self, text_node: bool) -> Result<(), String> {
        fn bounded(value: f32, max: f32, field: &str) -> Result<(), String> {
            if !value.is_finite() || value < 0. || value > max {
                return Err(format!("Style {field} must be between 0 and {max}"));
            }
            Ok(())
        }
        if let Some(padding) = self.padding {
            for edge in padding {
                bounded(edge, 512., "padding")?;
            }
        }
        if let Some(gap) = self.gap {
            bounded(gap, 512., "gap")?;
        }
        if let Some(radius) = self.border_radius {
            bounded(radius, 512., "border_radius")?;
        }
        for (field, size) in [("width", self.width), ("height", self.height)] {
            if let Some(Size::Px(value)) = size {
                bounded(value, 8192., field)?;
            }
        }
        if let Some(size) = self.font_size {
            if !size.is_finite() || !(8. ..=96.).contains(&size) {
                return Err("Style font_size must be between 8 and 96".into());
            }
        }
        if !text_node && (self.font_size.is_some() || self.font_weight.is_some()) {
            return Err("Style font_size and font_weight apply to text nodes only".into());
        }
        Ok(())
    }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TableData {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

impl Node {
    pub fn id(&self) -> &str {
        match self {
            Self::Column { id, .. }
            | Self::Row { id, .. }
            | Self::Text { id, .. }
            | Self::Button { id, .. }
            | Self::Input { id, .. }
            | Self::Table { id, .. } => id,
        }
    }

    pub fn style(&self) -> Option<&Style> {
        match self {
            Self::Column { style, .. }
            | Self::Row { style, .. }
            | Self::Text { style, .. }
            | Self::Button { style, .. }
            | Self::Input { style, .. }
            | Self::Table { style, .. } => style.as_ref(),
        }
    }

    pub fn visit(&self, f: &mut impl FnMut(&Node)) {
        f(self);
        if let Self::Column { children, .. } | Self::Row { children, .. } = self {
            for child in children {
                child.visit(f);
            }
        }
    }
}

impl Snapshot {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > MAX_MESSAGE_BYTES {
            return Err("Snapshot exceeds 16 MiB".into());
        }
        let snapshot: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        snapshot.validate()?;
        Ok(snapshot)
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.revision == 0 {
            return Err("Revision must be positive".into());
        }
        let mut ids = HashSet::new();
        fn validate(node: &Node, depth: usize, ids: &mut HashSet<String>) -> Result<(), String> {
            if depth > 32 || ids.len() >= 4096 {
                return Err("Snapshot is too large or deeply nested".into());
            }
            if node.id().is_empty() || !ids.insert(node.id().to_owned()) {
                return Err(format!("Empty or duplicate node ID: {}", node.id()));
            }
            if let Some(style) = node.style() {
                style.validate(matches!(node, Node::Text { .. }))?;
            }
            match node {
                Node::Column { children, .. } | Node::Row { children, .. } => {
                    for child in children {
                        validate(child, depth + 1, ids)?;
                    }
                }
                Node::Table { dataset, .. } if dataset.is_empty() => {
                    return Err("Table dataset ID must be nonempty".into());
                }
                _ => {}
            }
            Ok(())
        }
        validate(&self.root, 0, &mut ids)?;
        self.validate_actions(&ids)
    }

    fn validate_actions(&self, ids: &HashSet<String>) -> Result<(), String> {
        if self.actions.len() > 256 {
            return Err("At most 256 action bindings per snapshot".into());
        }
        let mut names = HashSet::new();
        let mut keys = HashMap::new();
        for binding in &self.actions {
            if binding.name.is_empty() {
                return Err("Action name must be nonempty".into());
            }
            if binding.context != "global" && !ids.contains(&binding.context) {
                return Err(format!(
                    "Action context is not a node in this snapshot: {}",
                    binding.context
                ));
            }
            let spec = KeystrokeSpec::parse(&binding.keys)?;
            if !names.insert((&binding.name, &binding.context)) {
                return Err(format!(
                    "Duplicate action binding: {} in {}",
                    binding.name, binding.context
                ));
            }
            if let Some(existing) = keys.insert((spec, &binding.context), &binding.name) {
                return Err(format!(
                    "Keys {} in {} are bound to both {} and {}",
                    binding.keys, binding.context, existing, binding.name
                ));
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
    Diagnostic {
        request: u64,
        data: serde_json::Value,
    },
    Ready,
    Applied {
        revision: u64,
        native_apply_us: u64,
    },
    Rejected {
        revision: u64,
        message: String,
    },
    DatasetApplied {
        request: u64,
        id: String,
        revision: u64,
        parse_us: u64,
        apply_us: u64,
        work: crate::datasets::Work,
    },
    DatasetRejected {
        request: u64,
        message: String,
    },
    Click {
        revision: u64,
        id: String,
        #[cfg(all(feature = "benchmark-trace", target_os = "windows"))]
        debug_input_sequence: Option<u64>,
    },
    Input {
        revision: u64,
        id: String,
        value: String,
    },
    Action {
        revision: u64,
        name: String,
        context: String,
    },
    TableSelection {
        revision: u64,
        id: String,
        dataset: String,
        dataset_revision: u64,
        row: Option<usize>,
    },
    Error {
        message: String,
    },
    Closed,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_ambiguous_retained_identity() {
        let bytes = br#"{"revision":1,"root":{"kind":"column","id":"root","children":[{"kind":"input","id":"a","placeholder":""},{"kind":"button","id":"a","label":"Save"}]}}"#;
        assert!(Snapshot::parse(bytes).unwrap_err().contains("duplicate"));
    }

    #[test]
    fn rejects_inline_table_records() {
        let bytes = br#"{"revision":1,"root":{"kind":"table","id":"table","dataset":"quotes","data":{"columns":["A"],"rows":[["x"]]}}}"#;
        assert!(Snapshot::parse(bytes).is_err());
    }

    #[test]
    fn parses_valid_styles_on_every_node_kind() {
        let bytes = br##"{"revision":1,"root":{"kind":"column","id":"root",
            "style":{"padding":[16,8,16,8],"gap":12,"width":"full","align":"center","justify":"space_between","background":"token:muted","border_color":"#33415580","border_radius":8},
            "children":[
                {"kind":"text","id":"t","text":"Hi","style":{"foreground":"token:foreground","font_size":14,"font_weight":"semibold","width":{"px":320}}},
                {"kind":"button","id":"b","label":"Go","style":{"background":"#1D4ED8"}},
                {"kind":"input","id":"i","placeholder":"","style":{"height":{"px":40}}},
                {"kind":"row","id":"r","children":[],"style":{"gap":4,"align":"stretch"}},
                {"kind":"table","id":"tbl","dataset":"quotes","style":{"height":"fit"}}
            ]}}"##;
        let snapshot = Snapshot::parse(bytes).unwrap();
        let Node::Column {
            style, children, ..
        } = &snapshot.root
        else {
            unreachable!()
        };
        let style = style.as_ref().unwrap();
        assert_eq!(style.padding, Some([16., 8., 16., 8.]));
        assert_eq!(style.gap, Some(12.));
        assert!(matches!(style.width, Some(Size::Full)));
        assert_eq!(children.len(), 5);
        let Node::Text { style, .. } = &children[0] else {
            unreachable!()
        };
        let style = style.as_ref().unwrap();
        assert_eq!(style.foreground, Some(Color::Token(ThemeToken::Foreground)));
        assert_eq!(style.font_size, Some(14.));
        assert!(matches!(style.width, Some(Size::Px(320.))));
        let Node::Button { style, .. } = &children[1] else {
            unreachable!()
        };
        assert_eq!(
            style.as_ref().unwrap().background,
            Some(Color::Hex(0x1D4ED8FF))
        );
    }

    #[test]
    fn rejects_out_of_bounds_style_values() {
        for style in [
            r#""style":{"padding":[0,0,0,513]}"#,
            r#""style":{"padding":[0,0,-1,0]}"#,
            r#""style":{"gap":512.5}"#,
            r#""style":{"border_radius":1024}"#,
            r#""style":{"width":{"px":8193}}"#,
            r#""style":{"height":{"px":-4}}"#,
            r#""style":{"font_size":7}"#,
            r#""style":{"font_size":97}"#,
        ] {
            let node = if style.contains("font_size") {
                format!(r#"{{"kind":"text","id":"t","text":"x",{style}}}"#)
            } else {
                format!(r#"{{"kind":"column","id":"root","children":[],{style}}}"#)
            };
            let bytes = format!(r#"{{"revision":1,"root":{node}}}"#);
            assert!(
                Snapshot::parse(bytes.as_bytes()).is_err(),
                "must reject {style}"
            );
        }
    }

    #[test]
    fn accepts_boundary_style_values() {
        let bytes = br#"{"revision":1,"root":{"kind":"text","id":"t","text":"x",
            "style":{"padding":[512,512,512,512],"gap":0,"border_radius":512,"width":{"px":0},"height":{"px":8192},"font_size":96}}}"#;
        assert!(Snapshot::parse(bytes).is_ok());
    }

    #[test]
    fn rejects_unknown_theme_token() {
        let bytes = br#"{"revision":1,"root":{"kind":"column","id":"root","children":[],"style":{"background":"token:panel"}}}"#;
        assert!(Snapshot::parse(bytes).unwrap_err().contains("token"));
    }

    #[test]
    fn rejects_malformed_hex_colors() {
        for color in ["#12345", "#GGGGGG", "#1234567", "1D4ED8", ""] {
            let bytes = format!(
                r#"{{"revision":1,"root":{{"kind":"column","id":"root","children":[],"style":{{"background":"{color}"}}}}}}"#
            );
            assert!(
                Snapshot::parse(bytes.as_bytes()).is_err(),
                "must reject {color:?}"
            );
        }
    }

    #[test]
    fn rejects_font_style_on_non_text_nodes() {
        for tail in [
            r#""kind":"column","id":"root","children":[]"#,
            r#""kind":"row","id":"root","children":[]"#,
            r#""kind":"button","id":"root","label":"x""#,
            r#""kind":"input","id":"root","placeholder":"""#,
            r#""kind":"table","id":"root","dataset":"d""#,
        ] {
            for field in [r#""font_size":14"#, r#""font_weight":"bold""#] {
                let bytes = format!(r#"{{"revision":1,"root":{{{tail},"style":{{{field}}}}}}}"#);
                let Err(message) = Snapshot::parse(bytes.as_bytes()) else {
                    panic!("must reject {field} on {tail}");
                };
                assert!(message.contains("text nodes only"), "{message}");
            }
        }
    }

    #[test]
    fn rejects_unknown_style_fields() {
        let bytes =
            br#"{"revision":1,"root":{"kind":"text","id":"t","text":"x","style":{"opacity":0.5}}}"#;
        assert!(Snapshot::parse(bytes).is_err());
    }

    #[test]
    fn parses_valid_action_bindings() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"app.search","keys":"ctrl+f","context":"global"},
            {"name":"watchlist.add","keys":"ctrl+enter","context":"tbl"},
            {"name":"watchlist.add","keys":"ctrl+enter","context":"global"},
            {"name":"app.palette","keys":"meta+shift+p","context":"global"},
            {"name":"app.reload","keys":"f5","context":"global"}
        ],"root":{"kind":"table","id":"tbl","dataset":"d"}}"#;
        let snapshot = Snapshot::parse(bytes).unwrap();
        assert_eq!(snapshot.actions.len(), 5);
        // Same keys+name across nested contexts is legal (innermost wins).
        let spec = KeystrokeSpec::parse("shift+ctrl+f").unwrap();
        assert_eq!(spec, KeystrokeSpec::parse("ctrl+shift+f").unwrap());
        assert!(spec.ctrl && spec.shift && !spec.alt && !spec.meta && spec.key == "f");
        assert_eq!(
            KeystrokeSpec::parse("meta+shift+p").unwrap(),
            KeystrokeSpec {
                ctrl: false,
                alt: false,
                shift: true,
                meta: true,
                key: "p".into()
            }
        );
    }

    #[test]
    fn rejects_duplicate_action_name_and_context() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"app.search","keys":"ctrl+f","context":"global"},
            {"name":"app.search","keys":"ctrl+g","context":"global"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        assert!(Snapshot::parse(bytes).unwrap_err().contains("Duplicate"));
    }

    #[test]
    fn rejects_conflicting_keys_in_one_context() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"a","keys":"ctrl+f","context":"global"},
            {"name":"b","keys":"shift+ctrl+f","context":"global"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        let snapshot = Snapshot::parse(bytes);
        assert!(snapshot.is_ok(), "shift+ctrl+f differs from ctrl+f");
        let bytes = br#"{"revision":1,"actions":[
            {"name":"a","keys":"ctrl+f","context":"global"},
            {"name":"b","keys":"ctrl+f","context":"global"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        assert!(
            Snapshot::parse(bytes)
                .unwrap_err()
                .contains("bound to both")
        );
    }

    #[test]
    fn rejects_dangling_action_context() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"a","keys":"ctrl+f","context":"missing"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        assert!(Snapshot::parse(bytes).unwrap_err().contains("not a node"));
    }

    #[test]
    fn rejects_more_than_256_action_bindings() {
        let named = [
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q",
            "r", "s", "t", "u", "v", "w", "x", "y", "z", "enter", "escape", "space", "tab", "up",
            "down",
        ];
        let modifiers = [
            "ctrl+",
            "alt+",
            "shift+",
            "meta+",
            "ctrl+alt+",
            "ctrl+shift+",
            "ctrl+meta+",
            "alt+shift+",
            "alt+meta+",
        ];
        let action = |i: usize| {
            format!(
                r#"{{"name":"a{i}","keys":"{}{}","context":"global"}}"#,
                modifiers[i / named.len()],
                named[i % named.len()]
            )
        };
        let build = |count: usize| {
            format!(
                r#"{{"revision":1,"actions":[{}],"root":{{"kind":"text","id":"t","text":"x"}}}}"#,
                (0..count).map(action).collect::<Vec<_>>().join(",")
            )
        };
        assert!(
            Snapshot::parse(build(257).as_bytes())
                .unwrap_err()
                .contains("256")
        );
        assert!(Snapshot::parse(build(256).as_bytes()).is_ok());
    }

    #[test]
    fn rejects_bare_printable_keys_and_bad_grammar() {
        for keys in [
            "a",
            "7",
            "",
            "ctrl+",
            "+ctrl+f",
            "ctrl++f",
            "ctrl-ctrl-f",
            "ctrl+ctrl+f",
            "super+f",
            "ctrl+F",
            "ctrl+unknown",
            "ctrl+f13",
            "ctrl+page_up",
        ] {
            let bytes = format!(
                r#"{{"revision":1,"actions":[{{"name":"a","keys":"{keys}","context":"global"}}],"root":{{"kind":"text","id":"t","text":"x"}}}}"#
            );
            assert!(
                Snapshot::parse(bytes.as_bytes()).is_err(),
                "must reject keys {keys:?}"
            );
        }
        for keys in [
            "escape",
            "f12",
            "tab",
            "shift+tab",
            "alt+f4",
            "ctrl+alt+delete",
        ] {
            let bytes = format!(
                r#"{{"revision":1,"actions":[{{"name":"a","keys":"{keys}","context":"global"}}],"root":{{"kind":"text","id":"t","text":"x"}}}}"#
            );
            assert!(
                Snapshot::parse(bytes.as_bytes()).is_ok(),
                "must accept keys {keys:?}"
            );
        }
    }

    #[test]
    fn rejects_unknown_action_binding_fields() {
        let bytes = br#"{"revision":1,"actions":[
            {"name":"a","keys":"ctrl+f","context":"global","command":"x"}
        ],"root":{"kind":"text","id":"t","text":"x"}}"#;
        assert!(Snapshot::parse(bytes).is_err());
    }

    #[test]
    fn nodes_without_style_behave_as_before() {
        let bytes = br#"{"revision":1,"root":{"kind":"text","id":"t","text":"x"}}"#;
        let snapshot = Snapshot::parse(bytes).unwrap();
        assert!(snapshot.root.style().is_none());
        let encoded = serde_json::to_value(&snapshot.root).unwrap();
        assert_eq!(
            encoded,
            serde_json::json!({"kind":"text","id":"t","text":"x"})
        );
    }
}
