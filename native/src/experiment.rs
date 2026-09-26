//! Benchmark-only process and wire format. Not exported through the SDK ABI.
pub(crate) mod model;
use crate::datasets::Initial;
use model::{Change, Strategy};
use serde::{Deserialize, Serialize};
use std::io::{Read, Write};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Setup {
    pub strategy: Strategy,
    pub initial: Initial,
}

#[derive(Deserialize)]
#[serde(rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Request {
    Update {
        request: u64,
        base: u64,
        revision: u64,
        change: Change,
        #[serde(default)]
        resync: bool,
    },
    Inspect {
        request: u64,
    },
    Prepare {
        request: u64,
    },
    Close {
        request: u64,
    },
}
impl Request {
    pub fn id(&self) -> u64 {
        match self {
            Self::Update { request, .. }
            | Self::Inspect { request }
            | Self::Prepare { request }
            | Self::Close { request } => *request,
        }
    }
}
pub(crate) struct Incoming {
    pub request: Result<Request, String>,
    pub bytes: usize,
    pub decode_us: u64,
}

fn read_frame(reader: &mut impl Read) -> Result<Vec<u8>, String> {
    let mut length = [0; 4];
    reader.read_exact(&mut length).map_err(|e| e.to_string())?;
    let length = u32::from_le_bytes(length) as usize;
    if length == 0 || length > crate::protocol::MAX_MESSAGE_BYTES {
        return Err("Invalid experiment frame length".into());
    }
    let mut bytes = vec![0; length];
    reader.read_exact(&mut bytes).map_err(|e| e.to_string())?;
    Ok(bytes)
}
pub(crate) fn reply(value: &impl Serialize) {
    let result = (|| {
        let bytes = serde_json::to_vec(value).map_err(|e| e.to_string())?;
        let mut output = std::io::stdout().lock();
        output
            .write_all(&(bytes.len() as u32).to_le_bytes())
            .map_err(|e| e.to_string())?;
        output.write_all(&bytes).map_err(|e| e.to_string())?;
        output.flush().map_err(|e| e.to_string())
    })();
    if let Err(error) = result {
        eprintln!("Experiment reply: {error}");
    }
}

pub fn run() -> Result<(), String> {
    let bytes = read_frame(&mut std::io::stdin().lock())?;
    let setup: Setup = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
    drop(bytes);
    setup.initial.validate()?;
    crate::ui::experiment::validate_geometry(&setup.initial.snapshot)?;
    let (sender, receiver) = async_channel::bounded(64);
    std::thread::spawn(move || {
        let mut input = std::io::stdin().lock();
        while let Ok(bytes) = read_frame(&mut input) {
            let start = std::time::Instant::now();
            let request = serde_json::from_slice::<Request>(&bytes).map_err(|e| e.to_string());
            let close = matches!(request, Ok(Request::Close { .. }));
            let incoming = Incoming {
                request,
                bytes: bytes.len(),
                decode_us: start.elapsed().as_micros() as u64,
            };
            if sender.send_blocking(incoming).is_err() || close {
                break;
            }
        }
    });
    crate::ui::experiment::run(setup, receiver)
}
