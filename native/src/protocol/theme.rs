use super::*;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ThemeMode {
    #[default]
    Light,
    Dark,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ThemeSpec {
    #[serde(default)]
    pub mode: ThemeMode,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub overrides: BTreeMap<String, String>,
}

impl ThemeSpec {
    pub fn colors(&self) -> Result<Vec<(ThemeToken, u32)>, String> {
        if self.overrides.len() > 16 {
            return Err("Theme supports at most 16 token overrides".into());
        }
        self.overrides
            .iter()
            .map(|(name, value)| {
                let token = ThemeToken::parse(name)?;
                if value.len() != 7
                    || !value.starts_with('#')
                    || !value.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
                {
                    return Err("Theme colors must be opaque #RRGGBB values".into());
                }
                let rgb = u32::from_str_radix(&value[1..], 16).map_err(|e| e.to_string())?;
                Ok((token, rgb))
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn theme_wire_rejects_injection_and_unknown_tokens() {
        let snapshot =
            |theme| json!({"revision":1,"theme":theme,"root":{"kind":"text","id":"t","text":"T"}});
        for theme in [
            json!({"mode":"system"}),
            json!({"mode":"dark","url":"theme.json"}),
            json!({"overrides":{"unknown":"#123456"}}),
            json!({"overrides":{"primary":"token:foreground"}}),
            json!({"overrides":{"primary":"#12345600"}}),
            json!({"overrides":{"primary":"#ZZZZZZ"}}),
            json!({"overrides":{"primary":"#日00"}}),
        ] {
            assert!(Snapshot::parse(&serde_json::to_vec(&snapshot(theme)).unwrap()).is_err());
        }
        let parsed = Snapshot::parse(
            &serde_json::to_vec(&snapshot(json!({
                "mode":"dark", "overrides":{"primary":"#123abc","foreground":"#ffffff"}
            })))
            .unwrap(),
        )
        .unwrap();
        let theme = parsed.theme.as_ref().unwrap();
        assert_eq!(theme.mode, ThemeMode::Dark);
        assert_eq!(theme.colors().unwrap().len(), 2);
        let roundtrip = Snapshot::parse(&serde_json::to_vec(&parsed).unwrap()).unwrap();
        assert_eq!(roundtrip.theme, parsed.theme);
    }
}
