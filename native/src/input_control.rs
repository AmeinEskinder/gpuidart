use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Selection {
    pub start: usize,
    pub end: usize,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
pub(crate) struct State {
    pub generation: u64,
    pub edit_revision: u64,
    pub controlled: bool,
    pub value: String,
    pub selection: Selection,
    pub composing: bool,
}

#[derive(Deserialize, Serialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Operation {
    Read {},
    Write {
        generation: u64,
        base_revision: u64,
        text: Option<String>,
        selection: Option<Selection>,
    },
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Request {
    pub request: u64,
    pub id: String,
    pub operation: Operation,
}

impl Request {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.is_empty() || bytes.len() > crate::protocol::MAX_MESSAGE_BYTES {
            return Err("Invalid input command size".into());
        }
        let request: Self = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        if request.request == 0 || request.id.is_empty() {
            return Err("Input request requires a positive request and nonempty ID".into());
        }
        if let Operation::Write {
            generation,
            text,
            selection,
            ..
        } = &request.operation
        {
            if *generation == 0
                || (text.is_none() && selection.is_none())
                || text.as_ref().is_some_and(|s| s.len() > 1024 * 1024)
                || selection.as_ref().is_some_and(|s| s.start > s.end)
            {
                return Err("Invalid input write; text is limited to 1 MiB UTF-8".into());
            }
        }
        Ok(request)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Status {
    Read,
    Applied,
    Missing,
    NotControlled,
    Composing,
    Stale,
    InvalidSelection,
}

pub(crate) fn byte_offset(text: &str, utf16: usize) -> Option<usize> {
    let mut units = 0;
    for (offset, character) in text.char_indices() {
        if units == utf16 {
            return Some(offset);
        }
        units += character.len_utf16();
    }
    (units == utf16).then_some(text.len())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn controlled_input_wire_bounds_and_utf16_boundaries() {
        assert_eq!(byte_offset("A😀日", 0), Some(0));
        assert_eq!(byte_offset("A😀日", 1), Some(1));
        assert_eq!(byte_offset("A😀日", 2), None);
        assert_eq!(byte_offset("A😀日", 3), Some(5));
        assert_eq!(byte_offset("A😀日", 4), Some(8));
        assert_eq!(byte_offset("A😀日", 5), None);
        let read = serde_json::json!({"request":1,"id":"name","operation":{"op":"read"}});
        assert!(Request::parse(&serde_json::to_vec(&read).unwrap()).is_ok());
        for op in [
            serde_json::json!({"op":"unknown"}),
            serde_json::json!({"op":"write","generation":0,"base_revision":0,"text":"x"}),
            serde_json::json!({"op":"write","generation":1,"base_revision":0}),
            serde_json::json!({"op":"write","generation":1,"base_revision":0,"selection":{"start":2,"end":1}}),
            serde_json::json!({"op":"write","generation":1,"base_revision":0,"text":"x".repeat(1024*1024+1)}),
            serde_json::json!({"op":"read","unexpected":true}),
        ] {
            let mut value = read.clone();
            value["operation"] = op;
            assert!(Request::parse(&serde_json::to_vec(&value).unwrap()).is_err());
        }
    }
}
