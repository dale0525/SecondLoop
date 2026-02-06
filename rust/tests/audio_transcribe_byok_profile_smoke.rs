use std::fs;

use secondloop_rust::api::audio_transcribe;
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;

#[test]
fn audio_transcribe_byok_profile_requires_existing_profile() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");

    let err = audio_transcribe::audio_transcribe_byok_profile(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        "missing_profile".to_string(),
        "2026-02-06".to_string(),
        "en".to_string(),
        "audio/mp4".to_string(),
        vec![0x00, 0x00, 0x00, 0x18],
    )
    .expect_err("should require existing profile");

    let msg = err.to_string();
    assert!(msg.contains("llm profile not found"));
}

#[test]
fn audio_transcribe_byok_profile_multimodal_requires_existing_profile() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");

    let err = audio_transcribe::audio_transcribe_byok_profile_multimodal(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        "missing_profile".to_string(),
        "2026-02-06".to_string(),
        "en".to_string(),
        "audio/mp4".to_string(),
        vec![0x00, 0x00, 0x00, 0x18],
    )
    .expect_err("should require existing profile");

    let msg = err.to_string();
    assert!(msg.contains("llm profile not found"));
}
