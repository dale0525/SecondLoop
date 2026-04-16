use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;

use crate::crypto::{decrypt_bytes, derive_root_key, encrypt_bytes, fill_random_bytes, KdfParams};

const RECOVERY_ENVELOPE_AAD: &[u8] = b"sync.recovery.envelope.v1";
const RECOVERY_SALT_LEN: usize = 16;

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize, PartialEq, Eq)]
pub struct RecoveryEnvelope {
    pub version: u32,
    pub wrapped_sync_key_b64: String,
    pub kdf: RecoveryKdfParams,
}

#[derive(Clone, Debug, serde::Deserialize, serde::Serialize, PartialEq, Eq)]
pub struct RecoveryKdfParams {
    pub version: u32,
    pub m_cost_kib: u32,
    pub t_cost: u32,
    pub p_cost: u32,
    pub salt_b64: String,
}

pub fn recovery_kdf_params_v1() -> KdfParams {
    KdfParams {
        m_cost_kib: 64 * 1024,
        t_cost: 3,
        p_cost: 1,
    }
}

pub fn create_recovery_envelope(sync_key: &[u8; 32], passphrase: &str) -> Result<RecoveryEnvelope> {
    let mut salt = [0u8; RECOVERY_SALT_LEN];
    fill_random_bytes(&mut salt)?;
    create_recovery_envelope_with_params(sync_key, passphrase, &salt, &recovery_kdf_params_v1())
}

pub fn create_recovery_envelope_with_params(
    sync_key: &[u8; 32],
    passphrase: &str,
    salt: &[u8; RECOVERY_SALT_LEN],
    kdf: &KdfParams,
) -> Result<RecoveryEnvelope> {
    let kek = derive_root_key(passphrase, salt, kdf)?;
    let wrapped = encrypt_bytes(&kek, sync_key, RECOVERY_ENVELOPE_AAD)?;
    Ok(RecoveryEnvelope {
        version: 1,
        wrapped_sync_key_b64: B64.encode(wrapped),
        kdf: RecoveryKdfParams {
            version: 1,
            m_cost_kib: kdf.m_cost_kib,
            t_cost: kdf.t_cost,
            p_cost: kdf.p_cost,
            salt_b64: B64.encode(salt),
        },
    })
}

pub fn recover_sync_key(envelope: &RecoveryEnvelope, passphrase: &str) -> Result<[u8; 32]> {
    if envelope.version != 1 {
        return Err(anyhow!("unsupported recovery envelope version"));
    }
    if envelope.kdf.version != 1 {
        return Err(anyhow!("unsupported recovery kdf version"));
    }

    let salt = B64
        .decode(&envelope.kdf.salt_b64)
        .map_err(|_| anyhow!("invalid recovery salt"))?;
    if salt.len() != RECOVERY_SALT_LEN {
        return Err(anyhow!("invalid recovery salt length"));
    }

    let wrapped = B64
        .decode(&envelope.wrapped_sync_key_b64)
        .map_err(|_| anyhow!("invalid wrapped sync key"))?;

    let kdf = KdfParams {
        m_cost_kib: envelope.kdf.m_cost_kib,
        t_cost: envelope.kdf.t_cost,
        p_cost: envelope.kdf.p_cost,
    };
    let kek = derive_root_key(passphrase, &salt, &kdf)?;
    let plaintext = decrypt_bytes(&kek, &wrapped, RECOVERY_ENVELOPE_AAD)?;
    if plaintext.len() != 32 {
        return Err(anyhow!("invalid wrapped sync key length"));
    }

    let mut sync_key = [0u8; 32];
    sync_key.copy_from_slice(&plaintext);
    Ok(sync_key)
}
