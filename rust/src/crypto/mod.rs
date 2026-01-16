use anyhow::{anyhow, Result};
use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::aead::{Aead, Payload};
use chacha20poly1305::{KeyInit, XChaCha20Poly1305, XNonce};
use rand::rngs::OsRng;
use rand::RngCore;

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize)]
pub struct KdfParams {
    pub m_cost_kib: u32,
    pub t_cost: u32,
    pub p_cost: u32,
}

impl KdfParams {
    pub fn for_test() -> Self {
        Self {
            m_cost_kib: 1024,
            t_cost: 1,
            p_cost: 1,
        }
    }
}

pub fn derive_root_key(password: &str, salt: &[u8], params: &KdfParams) -> Result<[u8; 32]> {
    let argon_params = Params::new(params.m_cost_kib, params.t_cost, params.p_cost, Some(32))
        .map_err(|_| anyhow!("argon2 params"))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon_params);

    let mut output = [0u8; 32];
    argon2
        .hash_password_into(password.as_bytes(), salt, &mut output)
        .map_err(|_| anyhow!("argon2 hash"))?;
    Ok(output)
}

pub fn encrypt_bytes(key: &[u8; 32], plaintext: &[u8], aad: &[u8]) -> Result<Vec<u8>> {
    let cipher = XChaCha20Poly1305::new_from_slice(key).map_err(|_| anyhow!("invalid key"))?;

    let mut nonce_bytes = [0u8; 24];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = XNonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(
            nonce,
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| anyhow!("encrypt failed"))?;

    let mut blob = Vec::with_capacity(nonce_bytes.len() + ciphertext.len());
    blob.extend_from_slice(&nonce_bytes);
    blob.extend_from_slice(&ciphertext);
    Ok(blob)
}

pub fn decrypt_bytes(key: &[u8; 32], blob: &[u8], aad: &[u8]) -> Result<Vec<u8>> {
    if blob.len() < 24 {
        return Err(anyhow!("ciphertext too short"));
    }

    let (nonce_bytes, ciphertext) = blob.split_at(24);
    let cipher = XChaCha20Poly1305::new_from_slice(key).map_err(|_| anyhow!("invalid key"))?;
    let nonce = XNonce::from_slice(nonce_bytes);

    cipher
        .decrypt(
            nonce,
            Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map_err(|_| anyhow!("decrypt failed"))
}
