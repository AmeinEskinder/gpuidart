use super::Node;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticRole {
    Group,
    List,
    ListItem,
    Label,
    Heading,
    Button,
    Checkbox,
    Slider,
    Textbox,
    Combobox,
    Table,
    Switch,
    RadioGroup,
    ProgressBar,
    Separator,
    TabList,
    Image,
    Chart,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Semantics {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub role: Option<SemanticRole>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub heading_level: Option<usize>,
}

impl Semantics {
    pub fn validate(&self, node: &Node) -> Result<(), String> {
        if self
            .label
            .as_ref()
            .is_some_and(|s| s.is_empty() || s.len() > 1024)
        {
            return Err("Semantics label must contain 1..1024 UTF-8 bytes".into());
        }
        use SemanticRole::*;
        if let Some(role) = self.role {
            let valid = match node {
                Node::Column { .. }
                | Node::Row { .. }
                | Node::Stack { .. }
                | Node::Scroll { .. }
                | Node::Panes { .. } => {
                    matches!(role, Group | List | ListItem)
                }
                Node::Text { .. } => matches!(role, Label | Heading),
                Node::Button { .. } | Node::ConfirmDialog { .. } => role == Button,
                Node::Checkbox { .. } => role == Checkbox,
                Node::Slider { .. } => role == Slider,
                Node::Input { .. } => role == Textbox,
                Node::Tabs { .. } => role == TabList,
                Node::RadioGroup { .. } => role == RadioGroup,
                Node::Select { .. } | Node::DatePicker { .. } => role == Combobox,
                Node::Table { .. } => role == Table,
                Node::Tree { .. } => role == List,
                Node::Switch { .. } => role == Switch,
                Node::Progress { .. } => role == ProgressBar,
                Node::Separator { .. } => role == Separator,
                Node::Canvas { .. } | Node::Icon { .. } | Node::Image { .. } => role == Image,
                Node::MenuButton { .. } => role == Button,
                Node::List { .. } => role == List,
                Node::Chart { .. } => role == Chart,
            };
            if !valid {
                return Err(format!(
                    "Semantics role is incompatible with node {}",
                    node.id()
                ));
            }
        }
        if (self.role == Some(Heading)) != self.heading_level.is_some()
            || self.heading_level.is_some_and(|n| !(1..=6).contains(&n))
        {
            return Err("Heading role requires a level from 1 through 6".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use crate::protocol::Snapshot;
    use serde_json::{Value, json};

    fn parse(kind: &str, props: Value, semantics: Value) -> Result<Snapshot, String> {
        let mut root = props;
        root["kind"] = json!(kind);
        root["id"] = json!("control");
        root["semantics"] = semantics;
        Snapshot::parse(&serde_json::to_vec(&json!({"revision":1,"root":root})).unwrap())
    }

    #[test]
    fn every_control_accepts_names_but_rejects_false_roles() {
        for (kind, props, role) in [
            ("column", json!({"children":[]}), "group"),
            ("row", json!({"children":[]}), "list"),
            ("text", json!({"text":"Visible"}), "label"),
            ("button", json!({"label":"Go"}), "button"),
            (
                "checkbox",
                json!({"label":"Check", "checked":true}),
                "checkbox",
            ),
            (
                "slider",
                json!({"min":0,"max":100,"step":1,"number":20}),
                "slider",
            ),
            (
                "select",
                json!({"options":[{"id":"a","label":"A"}],"selected":"a"}),
                "combobox",
            ),
            ("input", json!({"placeholder":"Name"}), "textbox"),
            ("table", json!({"dataset":"data"}), "table"),
            (
                "confirm_dialog",
                json!({"label":"Reset","title":"Reset?","message":"Sure?","confirm_label":"Yes","cancel_label":"No"}),
                "button",
            ),
        ] {
            let snapshot = parse(
                kind,
                props.clone(),
                json!({"role":role,"label":"Accessible name"}),
            )
            .unwrap();
            let encoded = serde_json::to_value(snapshot).unwrap();
            assert_eq!(encoded["root"]["semantics"]["label"], "Accessible name");
            assert!(
                parse(kind, props, json!({"role":"heading","heading_level":2})).is_err()
                    || kind == "text"
            );
        }
    }

    #[test]
    fn annotations_are_bounded_and_cannot_forge_control_state() {
        let props = json!({"text":"Title"});
        for invalid in [
            json!({"label":""}),
            json!({"label":"x".repeat(1025)}),
            json!({"label":"\u{65e5}".repeat(342)}),
            json!({"role":"heading"}),
            json!({"role":"heading","heading_level":7}),
            json!({"heading_level":1}),
            json!({"checked":true}),
            json!({"role":"imaginary"}),
        ] {
            assert!(parse("text", props.clone(), invalid).is_err());
        }
        assert!(
            parse(
                "text",
                props,
                json!({"role":"heading","heading_level":2,"label":"Title"})
            )
            .is_ok()
        );
    }
}
