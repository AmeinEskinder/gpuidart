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
            ids: None,
            format: None,
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

#[test]
fn record_ids_validate_and_survive_edits() {
    let with_ids = |ids: Vec<&str>| TableData {
        columns: vec!["A".into()],
        rows: vec![vec!["x".into()], vec!["y".into()]],
        ids: Some(ids.iter().map(|id| id.to_string()).collect()),
        format: None,
    };
    assert!(with_ids(vec!["r1"]).validate().is_err(), "length mismatch");
    assert!(with_ids(vec!["r1", "r1"]).validate().is_err(), "duplicate");
    assert!(with_ids(vec!["r1", ""]).validate().is_err(), "empty");
    assert!(with_ids(vec!["r1", "r2"]).validate().is_ok());

    let mut store = Store::new(vec![Upload {
        id: "records".into(),
        revision: 1,
        data: with_ids(vec!["r1", "r2"]),
    }]);
    // Edits keep identity: rows change, ids do not.
    store
        .apply(edit(
            1,
            vec![Edit::Row {
                row: 0,
                values: vec!["changed".into()],
            }],
        ))
        .unwrap();
    {
        let data = &store.entries["records"].borrow().data;
        assert_eq!(data.rows[0][0], "changed");
        assert_eq!(data.ids.as_ref().unwrap(), &["r1", "r2"]);
    }

    // Replace may supply a new ID set.
    store
        .apply(Update {
            request: 2,
            id: "records".into(),
            base_revision: 2,
            revision: 3,
            change: Change::Replace {
                data: TableData {
                    columns: vec!["A".into()],
                    rows: vec![vec!["z".into()]],
                    ids: Some(vec!["r9".into()]),
                    format: None,
                },
            },
        })
        .unwrap();
    {
        let data = &store.entries["records"].borrow().data;
        assert_eq!(data.ids.as_ref().unwrap(), &["r9"]);
    }

    // Replace with malformed ids rejects.
    assert!(
        store
            .apply(Update {
                request: 3,
                id: "records".into(),
                base_revision: 3,
                revision: 4,
                change: Change::Replace {
                    data: TableData {
                        columns: vec!["A".into()],
                        rows: vec![vec!["z".into()]],
                        ids: Some(vec!["r9".into(), "r9".into()]),
                        format: None,
                    },
                },
            })
            .is_err()
    );
}

#[test]
fn view_columns_must_exist_in_the_dataset() {
    let view = crate::protocol::TableView {
        sort: vec![crate::protocol::SortKey {
            column: 2,
            direction: crate::protocol::SortDirection::Asc,
        }],
        filter: vec![],
    };
    let snapshot = crate::protocol::Snapshot {
        revision: 1,
        actions: vec![],
        root: Node::Table {
            id: "t".into(),
            style: None,
            dataset: "records".into(),
            view: Some(view),
        },
    };
    assert!(validate_views(&snapshot, |_| Some(2)).is_err());
    assert!(validate_views(&snapshot, |_| Some(3)).is_ok());
}

#[test]
fn cell_format_validates_columns_decimals_and_rule_counts() {
    let format = |column: usize, decimals: u8, rules: usize| {
        let rules: Vec<String> = (0..rules)
            .map(|i| format!(r#"{{"when":{{"op":"gt","value":"{i}"}},"color":"token:success"}}"#))
            .collect();
        format!(
            r#"{{"columns":{{"{column}":{{"number":{{"decimals":{decimals}}},"rules":[{}]}}}}}}"#,
            rules.join(",")
        )
    };
    let data_with = |format: String| {
        serde_json::from_str::<TableData>(&format!(
            r#"{{"columns":["a","b"],"rows":[],"format":{format}}}"#
        ))
        .unwrap()
    };
    assert!(
        data_with(format(2, 2, 0)).validate().is_err(),
        "column >= width"
    );
    assert!(data_with(format(1, 2, 0)).validate().is_ok());
    assert!(data_with(format(1, 7, 0)).validate().is_err(), "7 decimals");
    assert!(data_with(format(1, 6, 0)).validate().is_ok());
    assert!(data_with(format(1, 2, 17)).validate().is_err(), "17 rules");
    assert!(data_with(format(1, 2, 16)).validate().is_ok());

    // Replace may change the format; Edit cannot carry one.
    let mut store = Store::new(vec![Upload {
        id: "records".into(),
        revision: 1,
        data: TableData {
            columns: vec!["A".into()],
            rows: vec![vec!["1".into()]],
            ids: None,
            format: None,
        },
    }]);
    store
        .apply(Update {
            request: 2,
            id: "records".into(),
            base_revision: 1,
            revision: 2,
            change: Change::Replace {
                data: data_with(format(0, 3, 1)),
            },
        })
        .unwrap();
    let data = &store.entries["records"].borrow().data;
    assert!(data.format.is_some());
    assert!(
        serde_json::from_str::<Edit>(
            r#"{"kind":"cell","row":0,"column":0,"value":"x","format":null}"#
        )
        .is_err()
    );
}
