use crate::protocol::{IndexPatch, MAX_MESSAGE_BYTES, Node, Snapshot, TableData};
use serde::{Deserialize, Serialize};
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    rc::Rc,
    sync::Arc,
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

/// Records a dataset may hold. Uploads larger than one message arrive as an
/// appended sequence, so the cap is a memory bound rather than a transfer one.
pub const MAX_ROWS: usize = 1_000_000;

impl TableData {
    pub fn validate(&self) -> Result<(), String> {
        if self.columns.is_empty() || self.columns.len() > 64 || self.rows.len() > MAX_ROWS {
            return Err(format!(
                "Dataset requires 1..64 columns and at most {MAX_ROWS} rows"
            ));
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
    Replace {
        data: TableData,
    },
    /// Records added after the existing ones, with their IDs exactly when the
    /// dataset has record IDs. Large uploads arrive as a schema followed by
    /// appended slices, each under the message limit.
    Append {
        rows: Vec<Vec<String>>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        ids: Option<Vec<String>>,
        /// More slices of the same upload follow: the records are stored and
        /// acknowledged, but views, tables and charts wait for the last slice,
        /// so an upload of many slices recomputes each view once.
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        more: bool,
    },
    Edit {
        edits: Vec<Edit>,
    },
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

    /// What this edit does to the record indices a view index holds, for
    /// edits that change which records exist or where.
    pub fn index_patch(&self) -> Option<IndexPatch> {
        match self {
            Edit::Insert { at, .. } => Some(IndexPatch::Insert(*at)),
            Edit::Delete { row } => Some(IndexPatch::Delete(*row)),
            Edit::Move { row, to } => Some(IndexPatch::Move(*row, *to)),
            Edit::Cell { .. } | Edit::Row { .. } => None,
        }
    }
}

/// Prefix of a framed dataset message: `GDP1`, a little-endian u32 header
/// length, the JSON header, then the records as `u32 count, u32 columns,
/// u8 has_ids`, every cell as `u32 length` and UTF-8 bytes row by row, and
/// the record IDs the same way. The header is an append whose `rows` and
/// `ids` are empty; the body supplies them without JSON quoting.
pub const PACKED_MAGIC: &[u8; 4] = b"GDP1";

impl Update {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() > MAX_MESSAGE_BYTES {
            return Err("Dataset message exceeds 16 MiB".into());
        }
        if let Some(framed) = bytes.strip_prefix(PACKED_MAGIC) {
            return Self::parse_packed(framed);
        }
        let update: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        update.checked()
    }

    fn checked(self) -> Result<Self, String> {
        if self.id.is_empty()
            || self.request == 0
            || self.base_revision.checked_add(1) != Some(self.revision)
        {
            return Err("Dataset update requires an ID and the next revision".into());
        }
        Ok(self)
    }

    fn parse_packed(bytes: &[u8]) -> Result<Self, String> {
        let (header_len, rest) = read_u32(bytes)?;
        if header_len as usize > rest.len() {
            return Err("Packed dataset header exceeds the message".into());
        }
        let (header, body) = rest.split_at(header_len as usize);
        let mut update: Self = serde_json::from_slice(header).map_err(|e| e.to_string())?;
        let Change::Append { rows, ids, .. } = &mut update.change else {
            return Err("Packed records need an append header".into());
        };
        if !rows.is_empty() || ids.as_ref().is_some_and(|ids| !ids.is_empty()) {
            return Err("Packed append carries its records in the body only".into());
        }
        let (count, body) = read_u32(body)?;
        let (width, body) = read_u32(body)?;
        let (has_ids, mut cursor) = read_u8(body)?;
        if width == 0 || width > 64 || count as usize > MAX_ROWS || has_ids > 1 {
            return Err(
                "Packed records need 1..64 columns, at most the row cap and a 0/1 id flag".into(),
            );
        }
        let mut decoded = Vec::with_capacity(count as usize);
        for _ in 0..count {
            let mut row = Vec::with_capacity(width as usize);
            for _ in 0..width {
                let (cell, rest) = read_text(cursor)?;
                row.push(cell);
                cursor = rest;
            }
            decoded.push(row);
        }
        let decoded_ids = if has_ids == 1 {
            let mut list = Vec::with_capacity(count as usize);
            for _ in 0..count {
                let (id, rest) = read_text(cursor)?;
                list.push(id);
                cursor = rest;
            }
            Some(list)
        } else {
            None
        };
        if !cursor.is_empty() {
            return Err("Packed records have trailing bytes".into());
        }
        *rows = decoded;
        *ids = decoded_ids;
        update.checked()
    }
}

fn read_u32(bytes: &[u8]) -> Result<(u32, &[u8]), String> {
    let (head, rest) = bytes
        .split_at_checked(4)
        .ok_or("Packed records end inside a length")?;
    Ok((
        u32::from_le_bytes(head.try_into().expect("four bytes")),
        rest,
    ))
}

fn read_u8(bytes: &[u8]) -> Result<(u8, &[u8]), String> {
    let (&flag, rest) = bytes
        .split_first()
        .ok_or("Packed records end before the id flag")?;
    Ok((flag, rest))
}

fn read_text(bytes: &[u8]) -> Result<(String, &[u8]), String> {
    let (len, rest) = read_u32(bytes)?;
    let (text, rest) = rest
        .split_at_checked(len as usize)
        .ok_or("Packed record text exceeds the message")?;
    let text = String::from_utf8(text.to_vec())
        .map_err(|_| "Packed record text is not UTF-8".to_owned())?;
    Ok((text, rest))
}

pub struct Dataset {
    /// The replacement revision. Cell/row edits preserve this generation.
    pub generation: u64,
    pub id: String,
    pub revision: u64,
    /// The records, shared with any view job computing over them off the
    /// frame thread: a job clones the `Arc` and the store mutates through
    /// `Arc::make_mut`, which copies only if a job still holds the snapshot.
    /// The view queue keeps that from happening while a job is in flight.
    pub data: Arc<TableData>,
    /// Sorted 64-bit hashes of every record ID, eight bytes per record, so
    /// appends and inserts check uniqueness by binary search. A hit is
    /// confirmed against the records themselves, so a collision costs a scan
    /// rather than a wrong answer. Deleted IDs leave their hash behind (the
    /// index is a superset of the live IDs) and the index is rebuilt once the
    /// stale entries outnumber the live ones.
    ids_index: Vec<u64>,
    stale_ids: usize,
}

fn index_of(data: &TableData) -> Vec<u64> {
    let mut hashes: Vec<u64> = data
        .ids
        .as_ref()
        .map(|ids| ids.iter().map(|id| id_hash(id)).collect())
        .unwrap_or_default();
    hashes.sort_unstable();
    hashes
}

fn id_hash(id: &str) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    id.hash(&mut hasher);
    hasher.finish()
}

impl Dataset {
    /// Whether a record with this ID exists.
    fn has_id(&self, id: &str) -> bool {
        self.ids_index.binary_search(&id_hash(id)).is_ok()
            && self
                .data
                .ids
                .as_ref()
                .is_some_and(|ids| ids.iter().any(|existing| existing == id))
    }

    fn index_ids<'a>(&mut self, ids: impl IntoIterator<Item = &'a String>) {
        self.index_hashes(ids.into_iter().map(|id| id_hash(id)).collect());
    }

    /// Merges sorted or unsorted hashes into the index in one pass over it,
    /// so an appended slice costs its own size plus the index length.
    fn index_hashes(&mut self, mut tail: Vec<u64>) {
        tail.sort_unstable();
        let head = std::mem::take(&mut self.ids_index);
        let mut merged = Vec::with_capacity(head.len() + tail.len());
        let (mut i, mut j) = (0, 0);
        while i < head.len() && j < tail.len() {
            if head[i] <= tail[j] {
                merged.push(head[i]);
                i += 1;
            } else {
                merged.push(tail[j]);
                j += 1;
            }
        }
        merged.extend_from_slice(&head[i..]);
        merged.extend_from_slice(&tail[j..]);
        self.ids_index = merged;
    }
}

/// Whether two sorted slices share a value.
fn sorted_overlap(a: &[u64], b: &[u64]) -> bool {
    let (mut i, mut j) = (0, 0);
    while i < a.len() && j < b.len() {
        match a[i].cmp(&b[j]) {
            std::cmp::Ordering::Less => i += 1,
            std::cmp::Ordering::Greater => j += 1,
            std::cmp::Ordering::Equal => return true,
        }
    }
    false
}

impl Dataset {
    fn unindex_id(&mut self) {
        self.stale_ids += 1;
        if self.stale_ids > self.ids_index.len() / 2 {
            self.ids_index = index_of(&self.data);
            self.stale_ids = 0;
        }
    }
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
            let ids_index = index_of(&upload.data);
            store.entries.insert(
                upload.id.clone(),
                Rc::new(RefCell::new(Dataset {
                    id: upload.id,
                    revision: upload.revision,
                    generation: upload.revision,
                    data: Arc::new(upload.data),
                    ids_index,
                    stale_ids: 0,
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
                let ids_index = index_of(&data);
                if let Some(current) = current {
                    let mut current = current.borrow_mut();
                    current.generation = update.revision;
                    current.data = Arc::new(data);
                    current.ids_index = ids_index;
                    current.stale_ids = 0;
                    current.revision = update.revision;
                } else {
                    self.used_ids.insert(update.id.clone());
                    self.entries.insert(
                        update.id.clone(),
                        Rc::new(RefCell::new(Dataset {
                            id: update.id,
                            revision: update.revision,
                            generation: update.revision,
                            data: Arc::new(data),
                            ids_index,
                            stale_ids: 0,
                        })),
                    );
                }
                Ok(work)
            }
            Change::Append { rows, ids, .. } => {
                let mut current = current.ok_or("Unknown dataset")?.borrow_mut();
                let width = current.data.columns.len();
                if rows.is_empty() {
                    return Err("Dataset append must carry records".into());
                }
                if current.data.rows.len() + rows.len() > MAX_ROWS {
                    return Err(format!("Dataset append exceeds {MAX_ROWS} rows"));
                }
                if rows.iter().any(|row| row.len() != width) {
                    return Err("Dataset row width does not match its columns".into());
                }
                let mut hashes = Vec::new();
                match (&current.data.ids, &ids) {
                    (None, None) => {}
                    (Some(_), Some(new)) => {
                        if new.len() != rows.len() {
                            return Err("Dataset ids must parallel its rows".into());
                        }
                        if new.iter().any(String::is_empty) {
                            return Err("Dataset ids must be nonempty and unique".into());
                        }
                        hashes = new.iter().map(|id| id_hash(id)).collect();
                        hashes.sort_unstable();
                        // Only a hash repeated in the slice or present in the
                        // index can be a duplicate ID, so the IDs themselves
                        // are compared only then.
                        if hashes.windows(2).any(|pair| pair[0] == pair[1])
                            || sorted_overlap(&current.ids_index, &hashes)
                        {
                            let mut batch: HashSet<&str> = HashSet::with_capacity(new.len());
                            if new.iter().any(|id| current.has_id(id) || !batch.insert(id)) {
                                return Err("Dataset ids must be nonempty and unique".into());
                            }
                        }
                    }
                    _ => {
                        return Err(
                            "Dataset append carries record IDs exactly when the dataset has record IDs"
                                .into(),
                        );
                    }
                }
                let work = Work {
                    records_checked: rows.len(),
                    cells_written: rows.len() * width,
                };
                let dataset = &mut *current;
                let data = Arc::make_mut(&mut dataset.data);
                data.rows.extend(rows);
                if let Some(new) = ids {
                    if let Some(existing) = &mut data.ids {
                        existing.extend(new);
                    }
                    dataset.index_hashes(hashes);
                }
                dataset.revision = update.revision;
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
                // IDs deleted earlier in the batch stay in the index until the
                // batch applies, so they stay reserved; IDs inserted earlier
                // in the batch are tracked here.
                let mut batch_ids: HashSet<&str> = HashSet::new();
                for edit in &edits {
                    match edit {
                        Edit::Cell { row, column, .. } if *row < len && *column < width => {}
                        Edit::Row { row, values } if *row < len && values.len() == width => {}
                        Edit::Insert { at, values, id } => {
                            if *at > len || values.len() != width || len >= MAX_ROWS {
                                return Err(format!(
                                    "Dataset insert has an invalid index or width, or exceeds {MAX_ROWS} rows"
                                ));
                            }
                            match (identity, id) {
                                (false, None) => {}
                                (true, Some(id)) => {
                                    if id.is_empty() || current.has_id(id) || !batch_ids.insert(id)
                                    {
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
                let dataset = &mut *current;
                for edit in edits {
                    let data = Arc::make_mut(&mut dataset.data);
                    match edit {
                        Edit::Cell { row, column, value } => {
                            data.rows[row][column] = value;
                            work.cells_written += 1;
                        }
                        Edit::Row { row, values } => {
                            work.cells_written += values.len();
                            data.rows[row] = values;
                        }
                        Edit::Insert { at, values, id } => {
                            work.cells_written += values.len();
                            data.rows.insert(at, values);
                            if let Some(id) = id {
                                if let Some(ids) = &mut data.ids {
                                    ids.insert(at, id.clone());
                                }
                                dataset.index_ids(std::iter::once(&id));
                            }
                        }
                        Edit::Delete { row } => {
                            data.rows.remove(row);
                            if let Some(ids) = &mut data.ids {
                                ids.remove(row);
                                dataset.unindex_id();
                            }
                        }
                        Edit::Move { row, to } => {
                            let record = data.rows.remove(row);
                            data.rows.insert(to, record);
                            if let Some(ids) = &mut data.ids {
                                let id = ids.remove(row);
                                ids.insert(to, id);
                            }
                        }
                    }
                }
                dataset.revision = update.revision;
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
