//! In-place application of operation updates against the retained tree.
//!
//! The previous path cloned the whole tree, walked it once per operation and
//! revalidated every node. This path keeps an index of node IDs and parents
//! so each operation costs its path from the root, mutates the applied tree
//! directly, records an undo entry per operation, and checks only what an
//! operation can break: identity, size, depth and the touched nodes. Own
//! fields of inserted and set nodes were validated when the update parsed.
use super::*;

/// Every node ID in the applied tree and each node's parent.
#[derive(Clone, Debug, Default)]
pub struct TreeIndex {
    pub ids: HashSet<String>,
    parents: HashMap<String, String>,
}

impl TreeIndex {
    pub fn of(root: &Node) -> Self {
        let mut index = Self::default();
        index.add_subtree(None, root);
        index
    }

    fn add_subtree(&mut self, parent: Option<&str>, node: &Node) {
        self.ids.insert(node.id().to_owned());
        if let Some(parent) = parent {
            self.parents.insert(node.id().to_owned(), parent.to_owned());
        }
        if let Some(children) = node.children() {
            for child in children {
                self.add_subtree(Some(node.id()), child);
            }
        }
    }

    fn remove_subtree(&mut self, node: &Node) {
        node.visit(&mut |node| {
            self.ids.remove(node.id());
            self.parents.remove(node.id());
        });
    }

    /// Ancestors from the root's child down to `id`, or None when `id` is
    /// unknown. The root has an empty chain.
    fn chain(&self, id: &str) -> Option<Vec<String>> {
        if !self.ids.contains(id) {
            return None;
        }
        let mut chain = Vec::new();
        let mut current = id;
        while let Some(parent) = self.parents.get(current) {
            chain.push(current.to_owned());
            current = parent;
        }
        chain.reverse();
        Some(chain)
    }

    /// The parent of `id`, or None for the root and unknown IDs.
    pub fn parent(&self, id: &str) -> Option<&str> {
        self.parents.get(id).map(String::as_str)
    }

    fn depth(&self, id: &str) -> usize {
        let mut depth = 0;
        let mut current = id;
        while let Some(parent) = self.parents.get(current) {
            depth += 1;
            current = parent;
        }
        depth
    }

    fn is_within(&self, id: &str, ancestor: &str) -> bool {
        let mut current = id;
        loop {
            if current == ancestor {
                return true;
            }
            match self.parents.get(current) {
                Some(parent) => current = parent,
                None => return false,
            }
        }
    }
}

/// The node with `id`, found along its ancestor chain.
pub fn get<'a>(root: &'a Node, index: &TreeIndex, id: &str) -> Option<&'a Node> {
    let chain = index.chain(id)?;
    let mut node = root;
    for step in chain {
        node = node.children()?.iter().find(|child| child.id() == step)?;
    }
    Some(node)
}

fn locate<'a>(root: &'a mut Node, index: &TreeIndex, id: &str) -> Option<&'a mut Node> {
    let chain = index.chain(id)?;
    let mut node = root;
    for step in chain {
        node = children_mut(node)?
            .iter_mut()
            .find(|child| child.id() == step)?;
    }
    Some(node)
}

fn height(node: &Node) -> usize {
    node.children().map_or(0, |children| {
        children
            .iter()
            .map(|child| height(child) + 1)
            .max()
            .unwrap_or(0)
    })
}

/// What an update changed, for the checks that follow application.
#[derive(Debug, Default)]
pub struct Touched {
    /// Roots of inserted subtrees.
    pub inserted: Vec<String>,
    /// Nodes whose own fields changed.
    pub set: Vec<String>,
    /// Containers whose child list changed.
    pub structure: Vec<String>,
}

/// One applied operation's inverse.
#[derive(Debug)]
pub enum Undo {
    Insert {
        id: String,
    },
    Set {
        id: String,
        previous: Node,
    },
    Remove {
        parent: String,
        index: usize,
        node: Node,
    },
    Reparent {
        id: String,
        parent: String,
        index: usize,
    },
    Children {
        id: String,
        order: Vec<String>,
    },
}

fn detach_from(
    root: &mut Node,
    index: &TreeIndex,
    id: &str,
    what: &str,
) -> Result<(String, usize, Node), String> {
    let parent_id = index
        .parents
        .get(id)
        .cloned()
        .ok_or_else(|| format!("{what} target is missing or the root: {id}"))?;
    let parent = locate(root, index, &parent_id)
        .ok_or_else(|| format!("{what} target is missing or the root: {id}"))?;
    let children =
        children_mut(parent).ok_or_else(|| format!("{what} parent has no children: {id}"))?;
    let position = children
        .iter()
        .position(|child| child.id() == id)
        .ok_or_else(|| format!("{what} target is missing or the root: {id}"))?;
    Ok((parent_id, position, children.remove(position)))
}

fn attach(
    root: &mut Node,
    index: &TreeIndex,
    parent_id: &str,
    position: Option<usize>,
    node: Node,
    what: &str,
) -> Result<(), String> {
    let parent = locate(root, index, parent_id).ok_or_else(|| {
        format!("{what} parent is missing or inside the moved subtree: {parent_id}")
    })?;
    let children = children_mut(parent)
        .ok_or_else(|| format!("{what} parent has no children: {parent_id}"))?;
    match position {
        Some(position) if position <= children.len() => children.insert(position, node),
        _ => children.push(node),
    }
    Ok(())
}

/// Applies `update` to `root`, keeping `index` in step. On an error the tree
/// and index are already rolled back; on success the returned undo log lets
/// the caller roll back after its own checks.
pub fn apply_in_place(
    root: &mut Node,
    index: &mut TreeIndex,
    update: &Update,
) -> Result<(Touched, Vec<Undo>), String> {
    let mut undo = Vec::with_capacity(update.ops.len());
    let mut touched = Touched::default();
    let outcome = apply_ops(root, index, update, &mut undo, &mut touched);
    match outcome {
        Ok(()) => Ok((touched, undo)),
        Err(message) => {
            rollback(root, index, undo);
            Err(message)
        }
    }
}

fn apply_ops(
    root: &mut Node,
    index: &mut TreeIndex,
    update: &Update,
    undo: &mut Vec<Undo>,
    touched: &mut Touched,
) -> Result<(), String> {
    for op in &update.ops {
        match op {
            Op::Insert { parent, node } => {
                let mut repeated = None;
                node.visit(&mut |candidate| {
                    if repeated.is_none() && index.ids.contains(candidate.id()) {
                        repeated = Some(candidate.id().to_owned());
                    }
                });
                if let Some(id) = repeated {
                    return Err(format!("Insert repeats an existing node ID: {id}"));
                }
                if !index.ids.contains(parent.as_str()) {
                    return Err(format!("Insert parent is missing: {parent}"));
                }
                if index.depth(parent) + 1 + height(node) > 32 {
                    return Err("Snapshot is too large or deeply nested".into());
                }
                attach(root, index, parent, None, node.clone(), "Insert")?;
                index.add_subtree(Some(parent), node);
                if index.ids.len() > 4096 {
                    // Undo the attach through the log so the index stays in step.
                    undo.push(Undo::Insert {
                        id: node.id().to_owned(),
                    });
                    return Err("Snapshot is too large or deeply nested".into());
                }
                undo.push(Undo::Insert {
                    id: node.id().to_owned(),
                });
                touched.inserted.push(node.id().to_owned());
                touched.structure.push(parent.clone());
            }
            Op::Reparent { id, parent } => {
                if !index.parents.contains_key(id.as_str()) {
                    return Err(format!("Reparent target is missing or the root: {id}"));
                }
                if !index.ids.contains(parent.as_str()) || index.is_within(parent, id) {
                    return Err(format!(
                        "Reparent parent is missing or inside the moved subtree: {parent}"
                    ));
                }
                let (old_parent, position, node) = detach_from(root, index, id, "Reparent")?;
                if index.depth(parent) + 1 + height(&node) > 32 {
                    attach(root, index, &old_parent, Some(position), node, "Reparent")?;
                    return Err("Snapshot is too large or deeply nested".into());
                }
                attach(root, index, parent, None, node, "Reparent")?;
                index.parents.insert(id.clone(), parent.clone());
                touched.structure.push(old_parent.clone());
                touched.structure.push(parent.clone());
                undo.push(Undo::Reparent {
                    id: id.clone(),
                    parent: old_parent,
                    index: position,
                });
            }
            Op::Remove { id } => {
                let (parent, position, node) = detach_from(root, index, id, "Remove")?;
                index.remove_subtree(&node);
                touched.structure.push(parent.clone());
                undo.push(Undo::Remove {
                    parent,
                    index: position,
                    node,
                });
            }
            Op::Set { id, node } => {
                let target = locate(root, index, id)
                    .ok_or_else(|| format!("Set target is missing: {id}"))?;
                if std::mem::discriminant(target) != std::mem::discriminant(node) {
                    return Err(format!("Set changes the kind of node: {id}"));
                }
                let mut replacement = node.clone();
                if let (Some(old), Some(new)) =
                    (children_mut(target), children_mut(&mut replacement))
                {
                    // Hold the children in the replacement; `old` is emptied
                    // and refilled from the replacement on rollback.
                    *new = std::mem::take(old);
                }
                let previous = std::mem::replace(target, replacement);
                undo.push(Undo::Set {
                    id: id.clone(),
                    previous,
                });
                touched.set.push(id.clone());
            }
            Op::Children { id, children } => {
                let target = locate(root, index, id)
                    .ok_or_else(|| format!("Children target is missing: {id}"))?;
                let current = children_mut(target)
                    .ok_or_else(|| format!("Children target has no children: {id}"))?;
                if current.len() != children.len() {
                    return Err(format!("Children order must list every child once: {id}"));
                }
                let order: Vec<String> =
                    current.iter().map(|child| child.id().to_owned()).collect();
                let mut by_id: HashMap<String, Node> = std::mem::take(current)
                    .into_iter()
                    .map(|node| (node.id().to_owned(), node))
                    .collect();
                for child in children {
                    match by_id.remove(child) {
                        Some(node) => current.push(node),
                        None => {
                            // Restore the original order before reporting.
                            let mut restored: Vec<Node> = std::mem::take(current);
                            restored.extend(by_id.into_values());
                            restored.sort_by_key(|node| {
                                order
                                    .iter()
                                    .position(|id| id == node.id())
                                    .unwrap_or(usize::MAX)
                            });
                            *current = restored;
                            return Err(format!(
                                "Children order names a node that is not a child: {child}"
                            ));
                        }
                    }
                }
                undo.push(Undo::Children {
                    id: id.clone(),
                    order,
                });
                touched.structure.push(id.clone());
            }
        }
    }
    Ok(())
}

/// Reverses applied operations, newest first, restoring tree and index.
pub fn rollback(root: &mut Node, index: &mut TreeIndex, undo: Vec<Undo>) {
    for entry in undo.into_iter().rev() {
        match entry {
            Undo::Insert { id } => {
                if let Ok((_, _, node)) = detach_from(root, index, &id, "Rollback") {
                    index.remove_subtree(&node);
                }
            }
            Undo::Set { id, mut previous } => {
                if let Some(target) = locate(root, index, &id) {
                    if let (Some(current), Some(restored)) =
                        (children_mut(target), children_mut(&mut previous))
                    {
                        *restored = std::mem::take(current);
                    }
                    *target = previous;
                }
            }
            Undo::Remove {
                parent,
                index: position,
                node,
            } => {
                index.add_subtree(Some(&parent), &node);
                let _ = attach(root, index, &parent, Some(position), node, "Rollback");
            }
            Undo::Reparent {
                id,
                parent,
                index: position,
            } => {
                if let Ok((_, _, node)) = detach_from(root, index, &id, "Rollback") {
                    index.parents.insert(id.clone(), parent.clone());
                    let _ = attach(root, index, &parent, Some(position), node, "Rollback");
                }
            }
            Undo::Children { id, order } => {
                if let Some(children) = locate(root, index, &id).and_then(children_mut) {
                    children.sort_by_key(|node| {
                        order
                            .iter()
                            .position(|id| id == node.id())
                            .unwrap_or(usize::MAX)
                    });
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tree() -> Node {
        Snapshot::parse(
            br#"{"revision":1,"root":{"kind":"column","id":"root","children":[
                {"kind":"row","id":"header","children":[{"kind":"text","id":"title","text":"T"}]},
                {"kind":"column","id":"body","children":[{"kind":"text","id":"a","text":"a"},{"kind":"text","id":"b","text":"b"}]}
            ]}}"#,
        )
        .unwrap()
        .root
    }

    fn update(ops: serde_json::Value) -> Update {
        serde_json::from_value(serde_json::json!({"revision": 2, "base_revision": 1, "ops": ops}))
            .unwrap()
    }

    fn ids(node: &Node) -> Vec<String> {
        let mut out = Vec::new();
        node.visit(&mut |node| out.push(node.id().to_owned()));
        out
    }

    #[test]
    fn operations_apply_in_place_and_keep_the_index_in_step() {
        let mut root = tree();
        let mut index = TreeIndex::of(&root);
        let (touched, undo) = apply_in_place(
            &mut root,
            &mut index,
            &update(serde_json::json!([
                {"op":"set","id":"title","node":{"kind":"text","id":"title","text":"Changed"}},
                {"op":"insert","parent":"header","node":{"kind":"text","id":"sub","text":"s"}},
                {"op":"reparent","id":"a","parent":"header"},
                {"op":"children","id":"header","children":["a","sub","title"]},
                {"op":"remove","id":"b"}
            ])),
        )
        .unwrap();
        assert_eq!(touched.set, ["title"]);
        assert_eq!(touched.inserted, ["sub"]);
        assert_eq!(undo.len(), 5);
        assert_eq!(ids(&root), ["root", "header", "a", "sub", "title", "body"]);
        assert!(matches!(root.find("title"), Some(Node::Text { text, .. }) if text == "Changed"));
        assert_eq!(index.ids, TreeIndex::of(&root).ids);
        assert_eq!(index.parents, TreeIndex::of(&root).parents);
        rollback(&mut root, &mut index, undo);
        assert_eq!(ids(&root), ids(&tree()));
        assert_eq!(index.parents, TreeIndex::of(&tree()).parents);
        assert!(matches!(root.find("title"), Some(Node::Text { text, .. }) if text == "T"));
    }

    #[test]
    fn failing_operations_roll_back_everything_before_them() {
        let mut root = tree();
        let mut index = TreeIndex::of(&root);
        for ops in [
            serde_json::json!([
                {"op":"set","id":"a","node":{"kind":"text","id":"a","text":"x"}},
                {"op":"insert","parent":"body","node":{"kind":"text","id":"title","text":"dup"}}
            ]),
            serde_json::json!([
                {"op":"remove","id":"b"},
                {"op":"reparent","id":"root","parent":"body"}
            ]),
            serde_json::json!([
                {"op":"reparent","id":"header","parent":"title"}
            ]),
            serde_json::json!([
                {"op":"insert","parent":"header","node":{"kind":"text","id":"n","text":"n"}},
                {"op":"children","id":"body","children":["a","zzz"]}
            ]),
            serde_json::json!([
                {"op":"set","id":"a","node":{"kind":"button","id":"a","label":"kind change"}}
            ]),
        ] {
            let error = apply_in_place(&mut root, &mut index, &update(ops.clone())).unwrap_err();
            assert!(!error.is_empty(), "{ops}");
            assert_eq!(ids(&root), ids(&tree()), "{ops}");
            assert_eq!(index.parents, TreeIndex::of(&tree()).parents, "{ops}");
            assert!(matches!(root.find("a"), Some(Node::Text { text, .. }) if text == "a"));
        }
    }

    #[test]
    fn depth_and_size_limits_hold_under_operations() {
        let mut root = tree();
        let mut index = TreeIndex::of(&root);
        let mut deep = serde_json::json!({"kind":"text","id":"leaf","text":"x"});
        for level in 0..31 {
            deep =
                serde_json::json!({"kind":"column","id":format!("level{level}"),"children":[deep]});
        }
        let error = apply_in_place(
            &mut root,
            &mut index,
            &update(serde_json::json!([{"op":"insert","parent":"body","node":deep}])),
        )
        .unwrap_err();
        assert!(error.contains("deeply nested"));
        assert_eq!(ids(&root), ids(&tree()));
        // Six nodes exist; 4,091 more make 4,097, one over the limit.
        let wide: Vec<_> = (0..4091)
            .map(|i| serde_json::json!({"op":"insert","parent":"body","node":{"kind":"text","id":format!("w{i}"),"text":"w"}}))
            .collect();
        let error =
            apply_in_place(&mut root, &mut index, &update(serde_json::json!(wide))).unwrap_err();
        assert!(error.contains("too large"));
        assert_eq!(ids(&root), ids(&tree()));
        assert_eq!(index.ids.len(), 6);
    }
}
