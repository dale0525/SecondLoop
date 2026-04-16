use anyhow::{anyhow, Result};

fn unsupported() -> anyhow::Error {
    anyhow!("audio_transcribe_unsupported_on_wasm")
}

#[flutter_rust_bridge::frb]
pub fn audio_transcribe_local_whisper(
    _app_dir: String,
    _model_name: String,
    _lang: String,
    _wav_bytes: Vec<u8>,
) -> Result<String> {
    Err(unsupported())
}

#[flutter_rust_bridge::frb]
pub fn audio_transcribe_byok_profile(
    _app_dir: String,
    _key: Vec<u8>,
    _profile_id: String,
    _local_day: String,
    _lang: String,
    _mime_type: String,
    _audio_bytes: Vec<u8>,
) -> Result<String> {
    Err(unsupported())
}

#[flutter_rust_bridge::frb]
pub fn audio_transcribe_byok_profile_multimodal(
    _app_dir: String,
    _key: Vec<u8>,
    _profile_id: String,
    _local_day: String,
    _lang: String,
    _mime_type: String,
    _audio_bytes: Vec<u8>,
) -> Result<String> {
    Err(unsupported())
}
