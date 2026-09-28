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

/// A request to open a secondary window with its own initial description.
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct WindowOpen {
    pub request: u64,
    /// The window ID Dart assigned; 1 or above, unique while the window lives.
    pub id: u32,
    pub initial: Initial,
}

impl WindowOpen {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        let open: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        if open.id == 0 || open.request == 0 {
            return Err("Window requests need a nonzero request and window ID".into());
        }
        open.initial.validate()?;
        Ok(open)
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
        initial.validate()?;
        Ok(initial)
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.window.title.trim().is_empty()
            || !(320.0..=8192.0).contains(&self.window.width)
            || !(240.0..=8192.0).contains(&self.window.height)
        {
            return Err("Invalid window title or dimensions".into());
        }
        self.snapshot.validate()?;
        let mut ids = HashSet::new();
        for upload in &self.datasets {
            if upload.id.is_empty() || upload.revision != 1 || !ids.insert(upload.id.as_str()) {
                return Err("Initial datasets require unique IDs and revision 1".into());
            }
            upload.data.validate()?;
        }
        validate_references(&self.snapshot, |id| ids.contains(id))?;
        validate_context_menus(&self.snapshot, |id| {
            self.datasets
                .iter()
                .any(|u| u.id == id && u.data.ids.is_some())
        })?;
        validate_views(&self.snapshot, |id| {
            self.datasets
                .iter()
                .find(|upload| upload.id == id)
                .map(|upload| upload.data.columns.len())
        })?;
        Ok(())
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
        if let Some(format) = &self.format {
            for (column, spec) in &format.columns {
                if *column >= self.columns.len() {
                    return Err(format!(
                        "Format references column {column} beyond {} columns",
                        self.columns.len()
                    ));
                }
                if let Some(number) = &spec.number {
                    if number.decimals > 6 {
                        return Err("Number format allows 0..6 decimals".into());
                    }
                }
                if spec.rules.len() > 16 {
                    return Err("At most 16 format rules per column".into());
                }
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
        let (dataset, view, axes) = match node {
            Node::Table { dataset, view, .. } => (dataset, view.as_ref(), Vec::new()),
            Node::List {
                dataset,
                column,
                view,
                ..
            } => (dataset, view.as_ref(), vec![*column]),
            Node::Chart { chart, .. } => (
                &chart.dataset,
                chart.view.as_ref(),
                vec![chart.label_column, chart.value_column],
            ),
            _ => return,
        };
        let width = columns(dataset).unwrap_or(0);
        let mut referenced = axes;
        if let Some(view) = view {
            referenced.extend(view.referenced_columns());
        }
        if let Some(column) = referenced.iter().find(|column| **column >= width) {
            error = Some(format!(
                "View references column {column} beyond dataset {dataset}'s {width} columns"
            ));
        }
    });
    error.map_or(Ok(()), Err)
}

/// The dataset checks for one node: its reference, row menus and view
/// columns. Whole publications visit every node; updates visit the touched
/// ones.
pub fn validate_dataset_node(
    node: &Node,
    contains: &impl Fn(&str) -> bool,
    columns: &impl Fn(&str) -> Option<usize>,
    has_ids: &impl Fn(&str) -> bool,
) -> Result<(), String> {
    if let Some(dataset) = node.dataset() {
        if !contains(dataset) {
            return Err(format!("Unknown dataset: {dataset}"));
        }
    }
    if let Node::Table {
        dataset,
        context_menu,
        ..
    } = node
    {
        if !context_menu.is_empty() && !has_ids(dataset) {
            return Err(format!(
                "Row context menus require stable record IDs: {dataset}"
            ));
        }
    }
    let (dataset, view, axes) = match node {
        Node::Table { dataset, view, .. } => (dataset, view.as_ref(), Vec::new()),
        Node::List {
            dataset,
            column,
            view,
            ..
        } => (dataset, view.as_ref(), vec![*column]),
        Node::Chart { chart, .. } => (
            &chart.dataset,
            chart.view.as_ref(),
            vec![chart.label_column, chart.value_column],
        ),
        _ => return Ok(()),
    };
    let width = columns(dataset).unwrap_or(0);
    let mut referenced = axes;
    if let Some(view) = view {
        referenced.extend(view.referenced_columns());
    }
    if let Some(column) = referenced.iter().find(|column| **column >= width) {
        return Err(format!(
            "View references column {column} beyond dataset {dataset}'s {width} columns"
        ));
    }
    Ok(())
}

pub fn validate_context_menus(
    snapshot: &Snapshot,
    has_ids: impl Fn(&str) -> bool,
) -> Result<(), String> {
    let mut missing = None;
    snapshot.root.visit(&mut |node| {
        if let Node::Table {
            dataset,
            context_menu,
            ..
        } = node
        {
            if !context_menu.is_empty() && !has_ids(dataset) {
                missing = Some(dataset.clone());
            }
        }
    });
    missing.map_or(Ok(()), |id| {
        Err(format!("Row context menus require stable record IDs: {id}"))
    })
}

pub fn validate_references(
    snapshot: &Snapshot,
    contains: impl Fn(&str) -> bool,
) -> Result<(), String> {
    let mut missing = None;
    snapshot.root.visit(&mut |node| {
        if let Some(dataset) = node.dataset() {
            if !contains(dataset) {
                missing = Some(dataset.to_owned());
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

/// One step of an edit batch. Steps apply in order, so a row index refers to
/// the records as the previous steps left them.
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
    /// Inserts a record before index `at`; `at` equal to the row count
    /// appends. `id` is required exactly when the dataset has record IDs.
    Insert {
        at: usize,
        values: Vec<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        id: Option<String>,
    },
    Delete {
        row: usize,
    },
    /// Moves the record at `row` so that it sits at index `to` afterwards.
    Move {
        row: usize,
        to: usize,
    },
}

impl Edit {
    pub fn is_structural(&self) -> bool {
        matches!(
            self,
            Self::Insert { .. } | Self::Delete { .. } | Self::Move { .. }
        )
    }
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
    /// The replacement revision. Cell/row edits preserve this generation.
    pub generation: u64,
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
                    generation: upload.revision,
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
                    current.generation = update.revision;
                    current.data = data;
                    current.revision = update.revision;
                } else {
                    self.used_ids.insert(update.id.clone());
                    self.entries.insert(
                        update.id.clone(),
                        Rc::new(RefCell::new(Dataset {
                            id: update.id,
                            revision: update.revision,
                            generation: update.revision,
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
                // Validate the whole batch against the shape each step leaves
                // behind before writing anything. Only the row count and the
                // set of record IDs change shape; the set is built once, on the
                // first insert, and IDs deleted earlier in the batch stay
                // reserved until the next batch.
                let width = current.data.columns.len();
                let identity = current.data.ids.is_some();
                let mut len = current.data.rows.len();
                let mut live: Option<HashSet<&str>> = None;
                for edit in &edits {
                    match edit {
                        Edit::Cell { row, column, .. } if *row < len && *column < width => {}
                        Edit::Row { row, values } if *row < len && values.len() == width => {}
                        Edit::Insert { at, values, id } => {
                            if *at > len || values.len() != width || len >= 100_000 {
                                return Err(
                                    "Dataset insert has an invalid index or width, or exceeds 100000 rows"
                                        .into(),
                                );
                            }
                            match (identity, id) {
                                (false, None) => {}
                                (true, Some(id)) => {
                                    let live = live.get_or_insert_with(|| {
                                        current
                                            .data
                                            .ids
                                            .as_ref()
                                            .map(|ids| ids.iter().map(String::as_str).collect())
                                            .unwrap_or_default()
                                    });
                                    if id.is_empty() || !live.insert(id) {
                                        return Err(format!(
                                            "Dataset insert needs a nonempty unused record ID: {id}"
                                        ));
                                    }
                                }
                                _ => {
                                    return Err(
                                        "Dataset insert carries a record ID exactly when the dataset has record IDs"
                                            .into(),
                                    );
                                }
                            }
                            len += 1;
                        }
                        Edit::Delete { row } if *row < len => len -= 1,
                        Edit::Move { row, to } if *row < len && *to < len => {}
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
                        Edit::Insert { at, values, id } => {
                            work.cells_written += values.len();
                            current.data.rows.insert(at, values);
                            if let (Some(ids), Some(id)) = (&mut current.data.ids, id) {
                                ids.insert(at, id);
                            }
                        }
                        Edit::Delete { row } => {
                            current.data.rows.remove(row);
                            if let Some(ids) = &mut current.data.ids {
                                ids.remove(row);
                            }
                        }
                        Edit::Move { row, to } => {
                            let record = current.data.rows.remove(row);
                            current.data.rows.insert(to, record);
                            if let Some(ids) = &mut current.data.ids {
                                let id = ids.remove(row);
                                ids.insert(to, id);
                            }
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
