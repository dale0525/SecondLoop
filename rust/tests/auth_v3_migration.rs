use std::fs;
use std::path::Path;

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use serde_json::json;
use tempfile::tempdir;

fn read_auth_json(app_dir: &Path) -> serde_json::Value {
    let path = app_dir.join("auth.json");
    let raw = fs::read_to_string(path).expect("read auth.json");
    serde_json::from_str(&raw).expect("parse auth.json")
}

fn write_legacy_v2_auth_file(
    app_dir: &Path,
    password: &str,
    session_key: [u8; 32],
    kdf_params: &KdfParams,
) {
    let salt = [3u8; 16];
    let password_hash = derive_root_key(password, &salt, kdf_params).expect("derive hash");
    let file = json!({
        "version": 2,
        "salt_b64": B64.encode(salt),
        "password_hash_b64": B64.encode(password_hash),
        "session_key_b64": B64.encode(session_key),
        "kdf_params": {
            "m_cost_kib": kdf_params.m_cost_kib,
            "t_cost": kdf_params.t_cost,
            "p_cost": kdf_params.p_cost
        }
    });
    fs::create_dir_all(app_dir).expect("create app dir");
    fs::write(
        app_dir.join("auth.json"),
        serde_json::to_vec_pretty(&file).expect("serialize v2 auth"),
    )
    .expect("write v2 auth");
}

#[test]
fn init_writes_v3_without_plain_session_key() {
    let tmp = tempdir().expect("tempdir");
    let app_dir = tmp.path();

    let key =
        auth::init_master_password(app_dir, "pw", KdfParams::for_test()).expect("init master");
    auth::validate_key(app_dir, &key).expect("validate key");

    let auth_json = read_auth_json(app_dir);
    assert_eq!(auth_json["version"], 3);
    assert!(auth_json["session_key_b64"].is_null());
    assert!(auth_json["session_key_wrapped_b64"].is_string());
    assert!(auth_json["session_key_hash_b64"].is_string());
}

#[test]
fn unlock_migrates_v2_to_v3() {
    let tmp = tempdir().expect("tempdir");
    let app_dir = tmp.path();
    let session_key = [7u8; 32];
    let kdf = KdfParams::for_test();

    write_legacy_v2_auth_file(app_dir, "pw", session_key, &kdf);

    let unlocked = auth::unlock_with_password(app_dir, "pw").expect("unlock");
    assert_eq!(unlocked, session_key);

    let auth_json = read_auth_json(app_dir);
    assert_eq!(auth_json["version"], 3);
    assert!(auth_json["session_key_b64"].is_null());
    assert!(auth_json["session_key_wrapped_b64"].is_string());
    assert!(auth_json["session_key_hash_b64"].is_string());
}

#[test]
fn validate_key_migrates_v2_to_v3() {
    let tmp = tempdir().expect("tempdir");
    let app_dir = tmp.path();
    let session_key = [8u8; 32];
    let kdf = KdfParams::for_test();

    write_legacy_v2_auth_file(app_dir, "pw", session_key, &kdf);

    auth::validate_key(app_dir, &session_key).expect("validate key");

    let auth_json = read_auth_json(app_dir);
    assert_eq!(auth_json["version"], 3);
    assert!(auth_json["session_key_b64"].is_null());
    assert!(auth_json["session_key_wrapped_b64"].is_string());
    assert!(auth_json["session_key_hash_b64"].is_string());
}
