use std::io::{Read, Write};

use anyhow::{anyhow, Result};
use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::aead::{Aead, Payload};
use chacha20poly1305::{KeyInit, XChaCha20Poly1305, XNonce};
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use rand::rngs::OsRng;
use rand::RngCore;

const SYNC_OP_COMPRESSED_MAGIC_V1: &[u8; 5] = b"SLOP1";
const SYNC_OP_COMPRESSED_CODEC_GZIP: u8 = 1;
const SYNC_OP_COMPRESSED_HEADER_LEN: usize = 10;
const SYNC_OP_COMPRESS_THRESHOLD_BYTES: usize = 4 * 1024;

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

    let maybe_wrapped_plaintext = maybe_wrap_sync_op_payload(plaintext, aad)?;
    let plaintext_for_encrypt = maybe_wrapped_plaintext.as_deref().unwrap_or(plaintext);

    let ciphertext = cipher
        .encrypt(
            nonce,
            Payload {
                msg: plaintext_for_encrypt,
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

    let plaintext = cipher
        .decrypt(
            nonce,
            Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map_err(|_| anyhow!("decrypt failed"))?;

    maybe_unwrap_sync_op_payload(plaintext, aad)
}

fn is_sync_op_aad(aad: &[u8]) -> bool {
    aad.starts_with(b"sync.ops:")
}

fn maybe_wrap_sync_op_payload(plaintext: &[u8], aad: &[u8]) -> Result<Option<Vec<u8>>> {
    if !is_sync_op_aad(aad) || plaintext.len() <= SYNC_OP_COMPRESS_THRESHOLD_BYTES {
        return Ok(None);
    }

    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder
        .write_all(plaintext)
        .map_err(|e| anyhow!("sync op payload compress write failed: {e}"))?;
    let compressed = encoder
        .finish()
        .map_err(|e| anyhow!("sync op payload compress finish failed: {e}"))?;

    let envelope_len = SYNC_OP_COMPRESSED_HEADER_LEN + compressed.len();
    if envelope_len >= plaintext.len() {
        return Ok(None);
    }

    let original_len = u32::try_from(plaintext.len())
        .map_err(|_| anyhow!("sync op payload too large for compression envelope"))?;

    let mut wrapped = Vec::with_capacity(envelope_len);
    wrapped.extend_from_slice(SYNC_OP_COMPRESSED_MAGIC_V1);
    wrapped.push(SYNC_OP_COMPRESSED_CODEC_GZIP);
    wrapped.extend_from_slice(&original_len.to_le_bytes());
    wrapped.extend_from_slice(&compressed);
    Ok(Some(wrapped))
}

fn maybe_unwrap_sync_op_payload(plaintext: Vec<u8>, aad: &[u8]) -> Result<Vec<u8>> {
    if !is_sync_op_aad(aad) || !plaintext.starts_with(SYNC_OP_COMPRESSED_MAGIC_V1) {
        return Ok(plaintext);
    }
    if plaintext.len() < SYNC_OP_COMPRESSED_HEADER_LEN {
        return Err(anyhow!("sync op compressed payload header is too short"));
    }

    let codec = plaintext[SYNC_OP_COMPRESSED_MAGIC_V1.len()];
    if codec != SYNC_OP_COMPRESSED_CODEC_GZIP {
        return Err(anyhow!(
            "unsupported sync op compressed payload codec: {codec}"
        ));
    }

    let len_start = SYNC_OP_COMPRESSED_MAGIC_V1.len() + 1;
    let len_end = len_start + 4;
    let mut expected_len_bytes = [0u8; 4];
    expected_len_bytes.copy_from_slice(&plaintext[len_start..len_end]);
    let expected_len = u32::from_le_bytes(expected_len_bytes) as usize;

    let compressed = &plaintext[SYNC_OP_COMPRESSED_HEADER_LEN..];
    let mut decoder = GzDecoder::new(compressed);
    let mut out = Vec::with_capacity(expected_len);
    decoder
        .read_to_end(&mut out)
        .map_err(|e| anyhow!("sync op payload decompress failed: {e}"))?;

    if out.len() != expected_len {
        return Err(anyhow!(
            "sync op payload length mismatch after decompress: expected {expected_len}, got {}",
            out.len()
        ));
    }

    Ok(out)
}
