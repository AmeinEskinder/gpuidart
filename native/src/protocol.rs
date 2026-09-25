use std::collections::HashSet;

use serde::{Deserialize, Serialize};

pub const MAX_MESSAGE_BYTES: usize = 16 * 1024 * 1024;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Snapshot {
    pub revision: u64,
    pub root: Node,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Node {
    Column { id: String, children: Vec<Node> },
    Row { id: String, children: Vec<Node> },
    Text { id: String, text: String },
    Button { id: String, label: String },
    Input { id: String, placeholder: String },
    Table { id: String, dataset: String },
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
        validate(&self.root, 0, &mut ids)
    }
}

#[derive(Clone, Debug, Serialize)]
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
        #[cfg(feature = "benchmark-trace")]
        debug_input_sequence: Option<u64>,
    },
    Input {
        revision: u64,
        id: String,
        value: String,
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
}
