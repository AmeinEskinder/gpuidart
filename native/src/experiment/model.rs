use crate::protocol::{Node, Snapshot};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Strategy {
    Snapshot,
    Subviews,
    Patches,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Change {
    Snapshot {
        root: Node,
    },
    Subviews {
        replacements: Vec<Node>,
        removed: Vec<String>,
        order: Option<Vec<String>>,
    },
    Patches {
        ops: Vec<Patch>,
    },
}

#[derive(Debug, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Patch {
    Text {
        id: String,
        text: String,
    },
    Insert {
        parent: String,
        index: usize,
        node: Node,
    },
    Remove {
        id: String,
    },
    Move {
        parent: String,
        id: String,
        index: usize,
    },
}

pub(crate) struct Candidate {
    pub snapshot: Snapshot,
    pub changed_parts: Vec<String>,
    pub staging_us: u64,
    pub validation_us: u64,
}

/// Experimental transaction, separate from the SDK protocol. No retained state
/// changes until the complete candidate has passed validation.
pub(crate) fn propose(
    current: &Snapshot,
    strategy: Strategy,
    base: u64,
    revision: u64,
    change: Change,
    resync: bool,
) -> Result<Candidate, String> {
    if (!resync && base != current.revision) || revision <= current.revision {
        return Err(format!("Stale revision; current is {}", current.revision));
    }
    let staged = std::time::Instant::now();
    let mut changed_parts = Vec::new();
    let root = match change {
        Change::Snapshot { root } if strategy == Strategy::Snapshot || resync => {
            changed_parts.extend(children(&root)?.iter().map(|node| node.id().to_owned()));
            root
        }
        Change::Subviews {
            replacements,
            removed,
            order,
        } if strategy == Strategy::Subviews => {
            // Deliberately account for the full staging clone and global validation.
            let mut root = current.root.clone();
            let nodes = children_mut(&mut root)?;
            for id in removed {
                let index = nodes
                    .iter()
                    .position(|node| node.id() == id)
                    .ok_or("Missing subview")?;
                nodes.remove(index);
                changed_parts.push(id);
            }
            for node in replacements {
                changed_parts.push(node.id().to_owned());
                if let Some(index) = nodes.iter().position(|old| old.id() == node.id()) {
                    nodes[index] = node;
                } else {
                    nodes.push(node);
                }
            }
            if let Some(order) = order {
                if order.len() != nodes.len() {
                    return Err("Subview order length mismatch".into());
                }
                let mut by_id: HashMap<_, _> = std::mem::take(nodes)
                    .into_iter()
                    .map(|node| (node.id().to_owned(), node))
                    .collect();
                for id in order {
                    nodes.push(
                        by_id
                            .remove(&id)
                            .ok_or("Unknown or repeated subview in order")?,
                    );
                }
                if !by_id.is_empty() {
                    return Err("Incomplete subview order".into());
                }
            }
            root
        }
        Change::Patches { ops } if strategy == Strategy::Patches => {
            let mut root = current.root.clone();
            for op in ops {
                match op {
                    Patch::Text { id, text } => match find_mut(&mut root, &id) {
                        Some(Node::Text { text: value, .. }) => *value = text,
                        _ => return Err("Text patch target missing or wrong kind".into()),
                    },
                    Patch::Insert {
                        parent,
                        index,
                        node,
                    } => {
                        let nodes =
                            children_mut(find_mut(&mut root, &parent).ok_or("Missing parent")?)?;
                        if index > nodes.len() {
                            return Err("Insert index out of bounds".into());
                        }
                        nodes.insert(index, node);
                    }
                    Patch::Remove { id } => {
                        remove(&mut root, &id).ok_or("Remove target missing or root")?;
                    }
                    Patch::Move { parent, id, index } => {
                        let node = remove(&mut root, &id).ok_or("Move target missing or root")?;
                        let nodes = children_mut(
                            find_mut(&mut root, &parent)
                                .ok_or("Move parent missing or inside moved node")?,
                        )?;
                        if index > nodes.len() {
                            return Err("Move index out of bounds".into());
                        }
                        nodes.insert(index, node);
                    }
                }
            }
            root
        }
        _ => return Err("Message strategy does not match this process".into()),
    };
    let staging_us = staged.elapsed().as_micros() as u64;
    let snapshot = Snapshot {
        revision,
        actions: current.actions.clone(),
        root,
    };
    let validation = std::time::Instant::now();
    snapshot.validate()?;
    // This experiment uses a column of fixed-size independently owned parts.
    children(&snapshot.root)?;
    if strategy == Strategy::Subviews {
        let before = state_owners(&current.root)?;
        let after = state_owners(&snapshot.root)?;
        for (id, owner) in &before {
            if after.get(id).is_some_and(|next| next != owner) {
                return Err(
                    "Subview control reparenting requires state migration; rejected".into(),
                );
            }
        }
    }
    let validation_us = validation.elapsed().as_micros() as u64;
    Ok(Candidate {
        snapshot,
        changed_parts,
        staging_us,
        validation_us,
    })
}

pub(crate) fn children(node: &Node) -> Result<&Vec<Node>, String> {
    match node {
        Node::Column { children, .. } => Ok(children),
        _ => Err("Experiment requires a column root".into()),
    }
}
fn children_mut(node: &mut Node) -> Result<&mut Vec<Node>, String> {
    match node {
        Node::Column { children, .. } | Node::Row { children, .. } => Ok(children),
        _ => Err("Target has no children".into()),
    }
}
fn find_mut<'a>(node: &'a mut Node, id: &str) -> Option<&'a mut Node> {
    if node.id() == id {
        return Some(node);
    }
    if let Node::Column { children, .. } | Node::Row { children, .. } = node {
        for child in children {
            if let Some(found) = find_mut(child, id) {
                return Some(found);
            }
        }
    }
    None
}
fn remove(node: &mut Node, id: &str) -> Option<Node> {
    if let Node::Column { children, .. } | Node::Row { children, .. } = node {
        if let Some(index) = children.iter().position(|child| child.id() == id) {
            return Some(children.remove(index));
        }
        for child in children {
            if let Some(found) = remove(child, id) {
                return Some(found);
            }
        }
    }
    None
}
fn state_owners(root: &Node) -> Result<HashMap<String, String>, String> {
    let mut owners = HashMap::new();
    for part in children(root)? {
        part.visit(&mut |node| {
            if matches!(node, Node::Input { .. } | Node::Table { .. }) {
                owners.insert(node.id().to_owned(), part.id().to_owned());
            }
        });
    }
    Ok(owners)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn current() -> Snapshot {
        serde_json::from_value(serde_json::json!({"revision":1,"root":{"kind":"column","id":"root","children":[{"kind":"text","id":"text","text":"old"},{"kind":"input","id":"input","placeholder":""}]}})).unwrap()
    }
    #[test]
    fn staged_patches_are_atomic_and_resync_requires_an_advancing_revision() {
        let current = current();
        let patch = |ops| Change::Patches { ops };
        assert!(propose(&current, Strategy::Patches, 0, 2, patch(vec![]), false).is_err());
        assert!(
            propose(
                &current,
                Strategy::Patches,
                1,
                2,
                patch(vec![
                    Patch::Text {
                        id: "text".into(),
                        text: "new".into()
                    },
                    Patch::Remove {
                        id: "missing".into()
                    }
                ]),
                false
            )
            .is_err()
        );
        assert!(
            matches!(&children(&current.root).unwrap()[0], Node::Text { text, .. } if text == "old")
        );
        assert!(
            propose(
                &current,
                Strategy::Patches,
                1,
                2,
                patch(vec![Patch::Insert {
                    parent: "root".into(),
                    index: 0,
                    node: children(&current.root).unwrap()[0].clone()
                }]),
                false
            )
            .is_err()
        );
        assert!(
            propose(
                &current,
                Strategy::Patches,
                0,
                2,
                Change::Snapshot {
                    root: current.root.clone()
                },
                true
            )
            .is_ok()
        );
        assert!(
            propose(
                &current,
                Strategy::Patches,
                0,
                1,
                Change::Snapshot {
                    root: current.root.clone()
                },
                true
            )
            .is_err()
        );
    }
    #[test]
    fn subview_reordering_preserves_ownership_but_reparenting_is_explicitly_rejected() {
        let current = current();
        let reorder = Change::Subviews {
            replacements: vec![],
            removed: vec![],
            order: Some(vec!["input".into(), "text".into()]),
        };
        assert!(propose(&current, Strategy::Subviews, 1, 2, reorder, false).is_ok());
        let mut root = current.root.clone();
        let nodes = children_mut(&mut root).unwrap();
        let input = nodes.pop().unwrap();
        nodes.push(Node::Column {
            id: "new-owner".into(),
            style: None,
            children: vec![input],
        });
        assert!(
            propose(
                &current,
                Strategy::Subviews,
                1,
                2,
                Change::Snapshot { root },
                true
            )
            .is_err()
        );
    }
}
