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
    kdf_params: KdfParams,
}

fn auth_file_path(app_dir: &Path) -> PathBuf {
    app_dir.join("auth.json")
}

pub fn is_initialized(app_dir: &Path) -> bool {
    auth_file_path(app_dir).exists()
}

pub fn init_master_password(app_dir: &Path, password: &str, kdf_params: KdfParams) -> Result<[u8; 32]> {
    if is_initialized(app_dir) {
        return Err(anyhow!("master password already initialized"));
    }

    fs::create_dir_all(app_dir)?;

    let mut salt = [0u8; 16];
    OsRng.fill_bytes(&mut salt);

    let key = derive_root_key(password, &salt, &kdf_params)?;
    let file = AuthFile {
        version: 1,
        salt_b64: B64.encode(salt),
        password_hash_b64: B64.encode(key),
        kdf_params,
    };

    let json = serde_json::to_vec_pretty(&file)?;
    fs::write(auth_file_path(app_dir), json)?;
    Ok(key)
}

pub fn unlock_with_password(app_dir: &Path, password: &str) -> Result<[u8; 32]> {
    let bytes = fs::read(auth_file_path(app_dir))?;
    let file: AuthFile = serde_json::from_slice(&bytes)?;

    let salt = B64
        .decode(file.salt_b64)
        .map_err(|_| anyhow!("invalid auth file salt"))?;
    if salt.len() != 16 {
        return Err(anyhow!("invalid auth file salt length"));
    }

    let expected_hash = B64
        .decode(file.password_hash_b64)
        .map_err(|_| anyhow!("invalid auth file hash"))?;
    if expected_hash.len() != 32 {
        return Err(anyhow!("invalid auth file hash length"));
    }

    let key = derive_root_key(password, &salt, &file.kdf_params)?;
    if key.as_slice() != expected_hash.as_slice() {
        return Err(anyhow!("invalid password"));
    }

    Ok(key)
}

pub fn validate_key(app_dir: &Path, key: &[u8; 32]) -> Result<()> {
    let bytes = fs::read(auth_file_path(app_dir))?;
    let file: AuthFile = serde_json::from_slice(&bytes)?;

    let expected_hash = B64
        .decode(file.password_hash_b64)
        .map_err(|_| anyhow!("invalid auth file hash"))?;
    if expected_hash.len() != 32 {
        return Err(anyhow!("invalid auth file hash length"));
    }
    if key.as_slice() != expected_hash.as_slice() {
        return Err(anyhow!("invalid key"));
    }

    Ok(())
}

