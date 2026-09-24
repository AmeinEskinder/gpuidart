use super::*;

fn upload(count: usize) -> Upload {
    Upload {
        id: "records".into(),
        revision: 1,
        data: TableData {
            columns: vec!["A".into(), "B".into()],
            rows: (0..count)
                .map(|i| vec![i.to_string(), "original".into()])
                .collect(),
        },
    }
}

fn edit(base: u64, edits: Vec<Edit>) -> Update {
    Update {
        request: 1,
        id: "records".into(),
        base_revision: base,
        revision: base + 1,
        change: Change::Edit { edits },
    }
}

#[test]
fn invalid_batch_and_stale_revision_preserve_all_records() {
    let mut store = Store::new(vec![upload(100)]);
    let identity = store.entries["records"].clone();
    let invalid = edit(
        1,
        vec![
            Edit::Cell {
                row: 0,
                column: 1,
                value: "changed".into(),
            },
            Edit::Row {
                row: 99,
                values: vec!["wrong width".into()],
            },
        ],
    );
    assert!(store.apply(invalid).is_err());
    assert_eq!(identity.borrow().revision, 1);
    assert_eq!(identity.borrow().data.rows[0][1], "original");
    let work = store
        .apply(edit(
            1,
            vec![
                Edit::Cell {
                    row: 0,
                    column: 1,
                    value: "changed".into(),
                },
                Edit::Row {
                    row: 99,
                    values: vec!["99".into(), "last".into()],
                },
            ],
        ))
        .unwrap();
    assert_eq!(work.records_checked, 2);
    assert_eq!(work.cells_written, 3);
    assert_eq!(identity.borrow().data.rows[99][1], "last");
    assert!(
        store
            .apply(edit(
                1,
                vec![Edit::Cell {
                    row: 0,
                    column: 1,
                    value: "stale".into()
                }]
            ))
            .is_err()
    );
    assert_eq!(identity.borrow().data.rows[0][1], "changed");
    assert!(Rc::ptr_eq(&identity, &store.entries["records"]));

    store
        .apply(Update {
            request: 2,
            id: "records".into(),
            base_revision: 2,
            revision: 3,
            change: Change::Replace {
                data: upload(3).data,
            },
        })
        .unwrap();
    assert_eq!(identity.borrow().revision, 3);
    assert_eq!(identity.borrow().data.rows.len(), 3);
    assert!(Rc::ptr_eq(&identity, &store.entries["records"]));
    store
        .apply(Update {
            request: 3,
            id: "records".into(),
            base_revision: 3,
            revision: 4,
            change: Change::Release,
        })
        .unwrap();
    assert!(store.entries.is_empty());
    assert!(
        store
            .apply(Update {
                request: 4,
                id: "records".into(),
                base_revision: 0,
                revision: 1,
                change: Change::Replace {
                    data: upload(1).data
                }
            })
            .is_err()
    );
}

#[test]
fn initial_upload_rejects_bad_data_and_missing_references() {
    let malformed = br#"{"snapshot":{"revision":1,"root":{"kind":"table","id":"table","dataset":"records"}},"datasets":[{"id":"records","revision":1,"data":{"columns":["A","B"],"rows":[["x"]]}}]}"#;
    assert!(
        Initial::parse(malformed)
            .err()
            .unwrap()
            .contains("row width")
    );
    let missing = br#"{"snapshot":{"revision":1,"root":{"kind":"table","id":"table","dataset":"missing"}},"datasets":[]}"#;
    assert!(
        Initial::parse(missing)
            .err()
            .unwrap()
            .contains("Unknown dataset")
    );
}

#[test]
fn one_cell_decode_and_apply_allocations_are_independent_of_dataset_size() {
    let bytes = br#"{"request":1,"id":"records","base_revision":1,"revision":2,"change":{"op":"edit","edits":[{"kind":"cell","row":4,"column":1,"value":"changed"}]}}"#;
    let mut results = Vec::new();
    for count in [100, 10_000, 100_000] {
        let mut store = Store::new(vec![upload(count)]);
        let mut work = Work::default();
        let (allocations, allocated_bytes) = crate::allocations::measure(|| {
            work = store.apply(Update::parse(bytes).unwrap()).unwrap();
        });
        assert_eq!(work.records_checked, 1);
        assert_eq!(work.cells_written, 1);
        assert_eq!(store.entries["records"].borrow().data.rows[4][1], "changed");
        results.push(serde_json::json!({"records":count,"transferred_bytes":bytes.len(),"allocation_calls":allocations,"allocated_bytes":allocated_bytes,"records_checked":work.records_checked,"cells_written":work.cells_written}));
    }
    for result in &results[1..] {
        assert_eq!(result["allocation_calls"], results[0]["allocation_calls"]);
        assert_eq!(result["allocated_bytes"], results[0]["allocated_bytes"]);
    }
    if let Ok(path) = std::env::var("GPUIDART_DATA_ALLOCATION_REPORT") {
        std::fs::write(path, serde_json::to_string_pretty(&serde_json::json!({"scope":"Rust JSON decode and dataset transaction; excludes renderer", "samples":results})).unwrap()).unwrap();
    }
}
