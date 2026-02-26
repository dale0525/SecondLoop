use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha256};

use crate::crypto::{decrypt_bytes, derive_root_key, encrypt_bytes, KdfParams};

const AUTH_FILE_VERSION_V2: u32 = 2;
const AUTH_FILE_VERSION_V3: u32 = 3;
const AUTH_SESSION_WRAP_AAD: &[u8] = b"auth.session_key.v3";

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize)]
struct AuthFile {
    version: u32,
    salt_b64: String,
    password_hash_b64: String,
    #[serde(default)]
    #[serde(skip_serializing_if = "Option::is_none")]
    session_key_b64: Option<String>,
    #[serde(default)]
    #[serde(skip_serializing_if = "Option::is_none")]
    session_key_wrapped_b64: Option<String>,
    #[serde(default)]
    #[serde(skip_serializing_if = "Option::is_none")]
    session_key_hash_b64: Option<String>,
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

fn decode_salt(file: &AuthFile) -> Result<[u8; 16]> {
    let decoded = B64
        .decode(&file.salt_b64)
        .map_err(|_| anyhow!("invalid auth file salt"))?;
    if decoded.len() != 16 {
        return Err(anyhow!("invalid auth file salt length"));
    }

    let mut salt = [0u8; 16];
    salt.copy_from_slice(&decoded);
    Ok(salt)
}

fn decode_session_key_legacy(file: &AuthFile) -> Result<[u8; 32]> {
    if let Some(value) = file.session_key_b64.as_deref() {
        return decode_key_b64(
            value,
            "invalid auth file session key",
            "invalid auth file session key length",
        );
    }

    decode_password_hash(file)
}

fn decode_wrapped_session_key(file: &AuthFile, password_hash: &[u8; 32]) -> Result<[u8; 32]> {
    let wrapped_b64 = file
        .session_key_wrapped_b64
        .as_deref()
        .ok_or_else(|| anyhow!("missing wrapped session key"))?;
    let wrapped = B64
        .decode(wrapped_b64)
        .map_err(|_| anyhow!("invalid wrapped session key"))?;
    let plaintext = decrypt_bytes(password_hash, &wrapped, AUTH_SESSION_WRAP_AAD)
        .map_err(|e| anyhow!("{e}"))?;
    if plaintext.len() != 32 {
        return Err(anyhow!("invalid wrapped session key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&plaintext);
    Ok(key)
}

fn session_key_hash(session_key: &[u8; 32]) -> [u8; 32] {
    let digest = Sha256::digest(session_key);
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest);
    out
}

fn decode_session_key_hash(file: &AuthFile) -> Result<[u8; 32]> {
    let hash_b64 = file
        .session_key_hash_b64
        .as_deref()
        .ok_or_else(|| anyhow!("missing session key hash"))?;
    decode_key_b64(
        hash_b64,
        "invalid session key hash",
        "invalid session key hash length",
    )
}

fn is_v3(file: &AuthFile) -> bool {
    file.version >= AUTH_FILE_VERSION_V3
        && file.session_key_wrapped_b64.is_some()
        && file.session_key_hash_b64.is_some()
        && file.session_key_b64.is_none()
}

fn write_auth_file(
    app_dir: &Path,
    salt: [u8; 16],
    password_hash: [u8; 32],
    session_key: [u8; 32],
    kdf_params: KdfParams,
) -> Result<()> {
    let wrapped = encrypt_bytes(&password_hash, &session_key, AUTH_SESSION_WRAP_AAD)?;
    let key_hash = session_key_hash(&session_key);
    let file = AuthFile {
        version: AUTH_FILE_VERSION_V3,
        salt_b64: B64.encode(salt),
        password_hash_b64: B64.encode(password_hash),
        session_key_b64: None,
        session_key_wrapped_b64: Some(B64.encode(wrapped)),
        session_key_hash_b64: Some(B64.encode(key_hash)),
        kdf_params,
    };

    let json = serde_json::to_vec_pretty(&file)?;
    fs::write(auth_file_path(app_dir), json)?;
    Ok(())
}

fn migrate_to_v3_if_needed(
    app_dir: &Path,
    file: &AuthFile,
    password_hash: [u8; 32],
    session_key: [u8; 32],
) -> Result<()> {
    if is_v3(file) {
        return Ok(());
    }
    let salt = decode_salt(file)?;
    write_auth_file(
        app_dir,
        salt,
        password_hash,
        session_key,
        file.kdf_params.clone(),
    )
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

    let salt = decode_salt(&file)?;

    let expected_hash = decode_password_hash(&file)?;
    let key = derive_root_key(password, &salt, &file.kdf_params)?;
    if key != expected_hash {
        return Err(anyhow!("invalid password"));
    }

    let session_key =
        if file.version >= AUTH_FILE_VERSION_V3 && file.session_key_wrapped_b64.is_some() {
            decode_wrapped_session_key(&file, &expected_hash)?
        } else {
            decode_session_key_legacy(&file)?
        };

    migrate_to_v3_if_needed(app_dir, &file, expected_hash, session_key)?;
    Ok(session_key)
}

pub fn validate_key(app_dir: &Path, key: &[u8; 32]) -> Result<()> {
    let bytes = fs::read(auth_file_path(app_dir))?;
    let file: AuthFile = serde_json::from_slice(&bytes)?;
    let password_hash = decode_password_hash(&file)?;

    if file.version >= AUTH_FILE_VERSION_V3 && file.session_key_hash_b64.is_some() {
        let expected_key_hash = decode_session_key_hash(&file)?;
        let actual_key_hash = session_key_hash(key);
        if expected_key_hash.as_slice() != actual_key_hash.as_slice() {
            return Err(anyhow!("invalid key"));
        }
        migrate_to_v3_if_needed(app_dir, &file, password_hash, *key)?;
        return Ok(());
    }

    let expected_key = decode_session_key_legacy(&file)?;
    if key.as_slice() != expected_key.as_slice() {
        return Err(anyhow!("invalid key"));
    }

    if file.version <= AUTH_FILE_VERSION_V2 {
        migrate_to_v3_if_needed(app_dir, &file, password_hash, expected_key)?;
    }
    Ok(())
}
