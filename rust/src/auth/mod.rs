use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use rand::rngs::OsRng;
use rand::RngCore;

use crate::crypto::{derive_root_key, KdfParams};

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize)]
struct AuthFile {
    version: u32,
    salt_b64: String,
    password_hash_b64: String,
    #[serde(default)]
    session_key_b64: Option<String>,
    kdf_params: KdfParams,
}

fn auth_file_path(app_dir: &Path) -> PathBuf {
    app_dir.join("auth.json")
}

fn decode_key_b64(value: &str, invalid_msg: &str, invalid_len_msg: &str) -> Result<[u8; 32]> {
    let decoded = B64.decode(value).map_err(|_| anyhow!("{}", invalid_msg))?;
    if decoded.len() != 32 {
        return Err(anyhow!("{}", invalid_len_msg));
    }

    let mut key = [0u8; 32];
    key.copy_from_slice(&decoded);
    Ok(key)
}

fn decode_password_hash(file: &AuthFile) -> Result<[u8; 32]> {
    decode_key_b64(
        &file.password_hash_b64,
        "invalid auth file hash",
        "invalid auth file hash length",
    )
}

fn decode_session_key(file: &AuthFile) -> Result<[u8; 32]> {
    if let Some(value) = file.session_key_b64.as_deref() {
        return decode_key_b64(
            value,
            "invalid auth file session key",
            "invalid auth file session key length",
        );
    }

    decode_password_hash(file)
}

fn write_auth_file(
    app_dir: &Path,
    salt: [u8; 16],
    password_hash: [u8; 32],
    session_key: [u8; 32],
    kdf_params: KdfParams,
) -> Result<()> {
    let file = AuthFile {
        version: 2,
        salt_b64: B64.encode(salt),
        password_hash_b64: B64.encode(password_hash),
        session_key_b64: Some(B64.encode(session_key)),
        kdf_params,
    };

    let json = serde_json::to_vec_pretty(&file)?;
    fs::write(auth_file_path(app_dir), json)?;
    Ok(())
}

pub fn is_initialized(app_dir: &Path) -> bool {
    auth_file_path(app_dir).exists()
}

pub fn init_master_password(
    app_dir: &Path,
    password: &str,
    kdf_params: KdfParams,
) -> Result<[u8; 32]> {
    if is_initialized(app_dir) {
        return Err(anyhow!("master password already initialized"));
    }

    fs::create_dir_all(app_dir)?;

    let mut salt = [0u8; 16];
    OsRng.fill_bytes(&mut salt);

    let key = derive_root_key(password, &salt, &kdf_params)?;
    write_auth_file(app_dir, salt, key, key, kdf_params)?;
    Ok(key)
}

pub fn init_master_password_with_existing_key(
    app_dir: &Path,
    password: &str,
    kdf_params: KdfParams,
    session_key: [u8; 32],
) -> Result<[u8; 32]> {
    if is_initialized(app_dir) {
        return Err(anyhow!("master password already initialized"));
    }

    fs::create_dir_all(app_dir)?;

    let mut salt = [0u8; 16];
    OsRng.fill_bytes(&mut salt);

    let password_hash = derive_root_key(password, &salt, &kdf_params)?;
    write_auth_file(app_dir, salt, password_hash, session_key, kdf_params)?;
    Ok(session_key)
}

pub fn unlock_with_password(app_dir: &Path, password: &str) -> Result<[u8; 32]> {
    let bytes = fs::read(auth_file_path(app_dir))?;
    let file: AuthFile = serde_json::from_slice(&bytes)?;

    let salt = B64
        .decode(&file.salt_b64)
        .map_err(|_| anyhow!("invalid auth file salt"))?;
    if salt.len() != 16 {
        return Err(anyhow!("invalid auth file salt length"));
    }

    let expected_hash = decode_password_hash(&file)?;
    let key = derive_root_key(password, &salt, &file.kdf_params)?;
    if key != expected_hash {
        return Err(anyhow!("invalid password"));
    }

    decode_session_key(&file)
}

pub fn validate_key(app_dir: &Path, key: &[u8; 32]) -> Result<()> {
    let bytes = fs::read(auth_file_path(app_dir))?;
    let file: AuthFile = serde_json::from_slice(&bytes)?;

    let expected_key = decode_session_key(&file)?;
    if key.as_slice() != expected_key.as_slice() {
        return Err(anyhow!("invalid key"));
    }

    Ok(())
}
