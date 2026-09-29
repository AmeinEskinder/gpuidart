use super::*;
use crate::protocol::SemanticRole;

struct RootProperties<'a>(&'a mut Interactivity);
impl InteractiveElement for RootProperties<'_> {
    fn interactivity(&mut self) -> &mut Interactivity {
        self.0
    }
}
impl StatefulInteractiveElement for RootProperties<'_> {}

pub(super) fn control_properties(interactivity: &mut Interactivity, id: String, disabled: bool) {
    RootProperties(interactivity)
        .accessibility_id(id.clone())
        .a11y_synthetic_children(move |tree| {
            if disabled {
                tree.parent_node().set_disabled();
            }
            if tree.parent_node().role() == Role::ComboBox {
                if let Some(value) = tree.parent_node().value().map(str::to_owned) {
                    let child_id = tree.synthetic_node_id("selected-value");
                    let mut label = gpui::accesskit::Node::new(Role::Label);
                    label.set_author_id(json!([id, "selected-value"]).to_string());
                    label.set_value(value);
                    tree.push_child(child_id, label);
                }
            }
        });
}

pub(super) fn control<T: InteractiveElement>(mut element: T, node: &Node, disabled: bool) -> T {
    control_properties(element.interactivity(), node.id().to_owned(), disabled);
    element
}

pub(super) fn accessible_name(node: &Node) -> String {
    if let Some(label) = node.semantics().and_then(|s| s.label.as_ref()) {
        return label.clone();
    }
    match node {
        Node::Text { text, .. } => text.clone(),
        Node::Button { label, .. }
        | Node::Checkbox { label, .. }
        | Node::ConfirmDialog { label, .. }
        | Node::MenuButton { label, .. } => label.clone(),
        Node::Input { placeholder, .. } | Node::Select { placeholder, .. }
            if !placeholder.is_empty() =>
        {
            placeholder.clone()
        }
        _ => node.id().to_owned(),
    }
}

pub(super) fn annotate<T: StatefulInteractiveElement>(element: T, node: &Node) -> T {
    let mut element = element.accessibility_id(node.id().to_owned());
    let role = match node.semantics().and_then(|s| s.role) {
        Some(SemanticRole::List) => Role::List,
        Some(SemanticRole::ListItem) => Role::ListItem,
        Some(SemanticRole::Heading) => Role::Heading,
        _ => match node {
            Node::Text { .. } | Node::RichText { .. } => Role::Label,
            Node::Row { .. }
            | Node::Column { .. }
            | Node::Stack { .. }
            | Node::Scroll { .. }
            | Node::Panes { .. }
            | Node::Popover { .. }
            | Node::Sheet { .. } => {
                if node.semantics().is_none() {
                    return element;
                }
                Role::Group
            }
            Node::Table { .. } => Role::Table,
            Node::Tree { .. } => Role::Tree,
            Node::List { .. } => Role::List,
            Node::Slider { .. } => Role::Slider,
            Node::Checkbox { .. } => Role::CheckBox,
            _ => return element,
        },
    };
    element = element.role(role).aria_label(accessible_name(node));
    if role == Role::Label {
        // AccessKit text nodes expose their text through value, unlike headings.
        element = element.aria_value(accessible_name(node));
    }
    if let Some(level) = node.semantics().and_then(|s| s.heading_level) {
        element = element.aria_level(level);
    }
    element
}

/// Read the value Kit placed on this frame, so controlled writes and native
/// editing share one source. No text is copied when accessibility is inactive.
pub(super) fn input_text(interactivity: &mut Interactivity) {
    RootProperties(interactivity).a11y_synthetic_children(|tree| {
        let Some(value) = tree.parent_node().value().map(str::to_owned) else {
            return;
        };
        let id = tree.synthetic_node_id("input-text");
        let mut run = gpui::accesskit::Node::new(Role::TextRun);
        // InputState's public selection API accepts UTF-8 scalar boundaries.
        run.set_character_lengths(
            value
                .chars()
                .map(|c| c.len_utf8() as u8)
                .collect::<Vec<_>>(),
        );
        run.set_value(value);
        tree.push_child(id, run);
    });
}

pub(super) fn description<T: InteractiveElement>(mut element: T, help: String) -> T {
    RootProperties(element.interactivity()).aria_description(help);
    element
}
