use super::*;

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct MenuSpec {
    pub id: String,
    pub label: String,
    pub items: Vec<MenuEntry>,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum MenuEntry {
    Separator,
    Action {
        id: String,
        label: String,
        action: String,
        #[serde(default)]
        checked: bool,
        #[serde(default)]
        disabled: bool,
    },
}

pub(super) fn validate(menus: &[MenuSpec], actions: &[ActionBinding]) -> Result<(), String> {
    if menus.len() > 8 {
        return Err("At most 8 application menus are supported".into());
    }
    let mut ids = HashSet::new();
    for menu in menus {
        if menu.id.is_empty()
            || menu.id.len() > 256
            || !ids.insert(&menu.id)
            || menu.label.is_empty()
            || menu.label.len() > 1024
        {
            return Err("Invalid or duplicate application menu".into());
        }
        validate_entries(&menu.items)?;
        for entry in &menu.items {
            if let MenuEntry::Action { action, .. } = entry {
                if !actions
                    .iter()
                    .any(|binding| binding.name == *action && binding.context == "global")
                {
                    return Err(format!(
                        "Menu action requires a global action binding: {action}"
                    ));
                }
            }
        }
    }
    Ok(())
}

pub(crate) fn validate_entries(items: &[MenuEntry]) -> Result<(), String> {
    if items.is_empty() || items.len() > 64 {
        return Err("Menus require 1..64 entries".into());
    }
    let mut ids = HashSet::new();
    for entry in items {
        if let MenuEntry::Action {
            id, label, action, ..
        } = entry
        {
            if id.is_empty()
                || id.len() > 256
                || !ids.insert(id)
                || label.is_empty()
                || label.len() > 1024
                || action.is_empty()
                || action.len() > 256
            {
                return Err("Invalid or duplicate menu entry".into());
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn menus_validate_bounds_entries_and_global_actions() {
        let base = json!({"revision":1,"root":{"kind":"text","id":"t","text":"X"},
            "actions":[{"name":"app.settings","keys":"meta+,","context":"global"}],
            "menus":[{"id":"app","label":"Terminal","items":[{"kind":"action","id":"settings",
                "label":"Settings","action":"app.settings","checked":true},{"kind":"separator"}]}]});
        let parse = |v: &serde_json::Value| Snapshot::parse(&serde_json::to_vec(v).unwrap());
        let valid = parse(&base).unwrap();
        assert!(Snapshot::parse(&serde_json::to_vec(&valid).unwrap()).is_ok());
        for (field, value) in [
            ("id", json!("")),
            ("label", json!("x".repeat(1025))),
            ("action", json!("missing")),
            ("checked", json!("true")),
            ("extra", json!(1)),
        ] {
            let mut v = base.clone();
            v["menus"][0]["items"][0][field] = value;
            assert!(parse(&v).is_err());
        }
        let mut v = base.clone();
        v["menus"][0]["items"] = json!([]);
        assert!(parse(&v).is_err());
        v = base.clone();
        v["menus"] = json!(vec![base["menus"][0].clone(); 9]);
        assert!(parse(&v).is_err());
        v = base.clone();
        v["menus"][0]["items"] = json!(vec![json!({"kind":"separator"}); 65]);
        assert!(parse(&v).is_err());
        v = base.clone();
        v["menus"][0]["items"] = json!(vec![base["menus"][0]["items"][0].clone(); 2]);
        assert!(parse(&v).is_err());
        v = base.clone();
        v["actions"][0]["context"] = json!("t");
        assert!(parse(&v).is_err());
        assert!(KeystrokeSpec::parse(",").is_err());
    }
}
