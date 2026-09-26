use crate::protocol::{MAX_MESSAGE_BYTES, Node, Snapshot, TableData};
use serde::{Deserialize, Serialize};
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    rc::Rc,
};

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Initial {
    pub snapshot: Snapshot,
    pub datasets: Vec<Upload>,
    #[serde(default)]
    pub window: WindowConfig,
}

#[derive(Deserialize, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct WindowConfig {
    pub title: String,
    pub width: f32,
    pub height: f32,
}

impl Default for WindowConfig {
    fn default() -> Self {
        Self {
            title: "GPUI-Dart".into(),
            width: 860.,
            height: 650.,
        }
    }
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Upload {
    pub id: String,
    pub revision: u64,
    pub data: TableData,
}

impl Initial {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        let initial: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        if initial.window.title.trim().is_empty()
            || !(320.0..=8192.0).contains(&initial.window.width)
            || !(240.0..=8192.0).contains(&initial.window.height)
        {
            return Err("Invalid window title or dimensions".into());
        }
        initial.snapshot.validate()?;
        let mut ids = HashSet::new();
        for upload in &initial.datasets {
            if upload.id.is_empty() || upload.revision != 1 || !ids.insert(upload.id.as_str()) {
                return Err("Initial datasets require unique IDs and revision 1".into());
            }
            upload.data.validate()?;
        }
        validate_references(&initial.snapshot, |id| ids.contains(id))?;
        validate_views(&initial.snapshot, |id| {
            initial
                .datasets
                .iter()
                .find(|upload| upload.id == id)
                .map(|upload| upload.data.columns.len())
        })?;
        Ok(initial)
    }
}

impl TableData {
    pub fn validate(&self) -> Result<(), String> {
        if self.columns.is_empty() || self.columns.len() > 64 || self.rows.len() > 100_000 {
            return Err("Dataset requires 1..64 columns and at most 100000 rows".into());
        }
        if self.rows.iter().any(|row| row.len() != self.columns.len()) {
            return Err("Dataset row width does not match its columns".into());
        }
        if let Some(ids) = &self.ids {
            if ids.len() != self.rows.len() {
                return Err("Dataset ids must parallel its rows".into());
            }
            let mut seen = HashSet::new();
            if ids.iter().any(|id| id.is_empty() || !seen.insert(id)) {
                return Err("Dataset ids must be nonempty and unique".into());
            }
        }
        Ok(())
    }
}

/// View column indices are checked against the dataset's width here, where
/// the shape is known; `Snapshot::validate` only bounds them below 64.
pub fn validate_views(
    snapshot: &Snapshot,
    columns: impl Fn(&str) -> Option<usize>,
) -> Result<(), String> {
    let mut error = None;
    snapshot.root.visit(&mut |node| {
        if let Node::Table {
            dataset,
            view: Some(view),
            ..
        } = node
        {
            let width = columns(dataset).unwrap_or(0);
            let column = view
                .sort
                .iter()
                .map(|key| key.column)
                .chain(view.filter.iter().map(|term| term.column))
                .find(|column| *column >= width);
            if let Some(column) = column {
                error = Some(format!(
                    "Table view references column {column} beyond dataset {dataset}'s {width} columns"
                ));
            }
        }
    });
    error.map_or(Ok(()), Err)
}

pub fn validate_references(
    snapshot: &Snapshot,
    contains: impl Fn(&str) -> bool,
) -> Result<(), String> {
    let mut missing = None;
    snapshot.root.visit(&mut |node| {
        if let Node::Table { dataset, .. } = node {
            if !contains(dataset) {
                missing = Some(dataset.clone());
            }
        }
    });
    missing.map_or(Ok(()), |id| Err(format!("Unknown dataset: {id}")))
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Update {
    pub request: u64,
    pub id: String,
    pub base_revision: u64,
    pub revision: u64,
    pub change: Change,
}

#[derive(Deserialize, Serialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum Change {
    Replace { data: TableData },
    Edit { edits: Vec<Edit> },
    Release,
}

#[derive(Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Edit {
    Cell {
        row: usize,
        column: usize,
        value: String,
    },
    Row {
        row: usize,
        values: Vec<String>,
    },
}

impl Update {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > MAX_MESSAGE_BYTES {
            return Err("Dataset message exceeds 16 MiB".into());
        }
        let update: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        if update.id.is_empty()
            || update.request == 0
            || update.base_revision.checked_add(1) != Some(update.revision)
        {
            return Err("Dataset update requires an ID and the next revision".into());
        }
        Ok(update)
    }
}

pub struct Dataset {
    pub id: String,
    pub revision: u64,
    pub data: TableData,
}

pub type SharedDataset = Rc<RefCell<Dataset>>;

#[derive(Default)]
pub struct Store {
    pub entries: HashMap<String, SharedDataset>,
    used_ids: HashSet<String>,
}

#[derive(Clone, Default, Debug, Serialize, Deserialize)]
pub struct Work {
    pub records_checked: usize,
    pub cells_written: usize,
}

impl Store {
    pub fn new(uploads: Vec<Upload>) -> Self {
        let mut store = Self::default();
        for upload in uploads {
            store.used_ids.insert(upload.id.clone());
            store.entries.insert(
                upload.id.clone(),
                Rc::new(RefCell::new(Dataset {
                    id: upload.id,
                    revision: upload.revision,
                    data: upload.data,
                })),
            );
        }
        store
    }

    pub fn apply(&mut self, update: Update) -> Result<Work, String> {
        let current = self.entries.get(&update.id);
        let revision = current.map_or(0, |data| data.borrow().revision);
        if update.base_revision != revision || revision.checked_add(1) != Some(update.revision) {
            return Err(format!(
                "Dataset revision conflict: expected {revision}, received {}",
                update.base_revision
            ));
        }
        if current.is_none() && self.used_ids.contains(&update.id) {
            return Err("Released dataset IDs cannot be reused in this host".into());
        }
        match update.change {
            Change::Replace { data } => {
                data.validate()?;
                let work = Work {
                    records_checked: data.rows.len(),
                    cells_written: data.rows.len() * data.columns.len(),
                };
                if let Some(current) = current {
                    let mut current = current.borrow_mut();
                    current.data = data;
                    current.revision = update.revision;
                } else {
                    self.used_ids.insert(update.id.clone());
                    self.entries.insert(
                        update.id.clone(),
                        Rc::new(RefCell::new(Dataset {
                            id: update.id,
                            revision: update.revision,
                            data,
                        })),
                    );
                }
                Ok(work)
            }
            Change::Edit { edits } => {
                let mut current = current.ok_or("Unknown dataset")?.borrow_mut();
                if edits.is_empty() {
                    return Err("Dataset edit batch must be nonempty".into());
                }
                // Validate every edit before taking ownership of any replacement value.
                for edit in &edits {
                    match edit {
                        Edit::Cell { row, column, .. }
                            if *row < current.data.rows.len()
                                && *column < current.data.columns.len() => {}
                        Edit::Row { row, values }
                            if *row < current.data.rows.len()
                                && values.len() == current.data.columns.len() => {}
                        _ => return Err("Dataset edit has an invalid row, column or width".into()),
                    }
                }
                let mut work = Work {
                    records_checked: edits.len(),
                    ..Work::default()
                };
                for edit in edits {
                    match edit {
                        Edit::Cell { row, column, value } => {
                            current.data.rows[row][column] = value;
                            work.cells_written += 1;
                        }
                        Edit::Row { row, values } => {
                            work.cells_written += values.len();
                            current.data.rows[row] = values;
                        }
                    }
                }
                current.revision = update.revision;
                Ok(work)
            }
            Change::Release => {
                if current.is_none() {
                    return Err("Unknown dataset".into());
                }
                self.entries.remove(&update.id);
                Ok(Work::default())
            }
        }
    }
}

#[cfg(test)]
mod tests;
