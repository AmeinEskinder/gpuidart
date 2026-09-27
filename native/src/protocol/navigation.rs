use super::*;

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ChoiceOption {
    pub id: String,
    pub label: String,
    #[serde(default)]
    pub disabled: bool,
}

pub(super) fn validate_choices(options: &[ChoiceOption], selected: &str) -> Result<(), String> {
    if options.is_empty() || options.len() > 32 {
        return Err("Choice groups require 1..32 options".into());
    }
    let mut ids = HashSet::new();
    for option in options {
        if option.id.is_empty()
            || option.id.len() > 256
            || !ids.insert(&option.id)
            || option.label.is_empty()
            || option.label.len() > 1024
        {
            return Err("Invalid or duplicate choice option".into());
        }
    }
    if !options.iter().any(|o| o.id == selected && !o.disabled) {
        return Err("Selected choice must be an enabled option".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn choice_groups_bound_options_and_reject_invalid_selection() {
        for (kind, role) in [("tabs", "tab_list"), ("radio_group", "radio_group")] {
            let parse = |options, selected| {
                Snapshot::parse(
                    &serde_json::to_vec(&json!({
                        "revision":1,"root":{"kind":kind,"id":"navigation", "options":options,
                        "selected":selected,"semantics":{"role":role,"label":"Pages"}}
                    }))
                    .unwrap(),
                )
            };
            let options = json!([{"id":"a","label":"A"},{"id":"b","label":"B","disabled":true}]);
            let node = parse(options.clone(), "a").unwrap();
            assert!(Snapshot::parse(&serde_json::to_vec(&node).unwrap()).is_ok());
            for selected in ["b", "missing", ""] {
                assert!(parse(options.clone(), selected).is_err());
            }
            for invalid in [
                json!([]),
                json!([{"id":"a","label":""}]),
                json!([{"id":"a","label":"A"},{"id":"a","label":"Duplicate"}]),
                json!([{"id":"a","label":"A","url":"bad"}]),
                json!([{"id":"a","label":"x".repeat(1025)}]),
                json!([{"id":"x".repeat(257),"label":"A"}]),
                json!(
                    (0..33)
                        .map(|i| json!({"id":i.to_string(),"label":"X"}))
                        .collect::<Vec<_>>()
                ),
            ] {
                assert!(parse(invalid, "a").is_err());
            }
        }
    }
}
