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
        .accessibility_id(id)
        .a11y_synthetic_children(move |tree| {
            if disabled {
                tree.parent_node().set_disabled();
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
        | Node::ConfirmDialog { label, .. } => label.clone(),
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
            Node::Text { .. } => Role::Label,
            Node::Row { .. } | Node::Column { .. } => {
                if node.semantics().is_none() {
                    return element;
                }
                Role::Group
            }
            Node::Table { .. } => Role::Table,
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
