use crate::credential::SecretMaterial;
use aes_gcm::aead::rand_core::RngCore;
use aes_gcm::aead::{Aead, KeyInit, OsRng, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use chrono::{DateTime, TimeZone, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

const BACKUP_MAGIC: &[u8; 8] = b"AWBKP001";
const NONCE_BYTES: usize = 12;
const HASH_BYTES: usize = 32;
const FIXED_HEADER_BYTES: usize = BACKUP_MAGIC.len() + 2 + 8 + HASH_BYTES;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum DataProtectionError {
    #[error("backup request is invalid")]
    InvalidRequest,
    #[error("backup belongs to another App")]
    AppMismatch,
    #[error("backup authentication failed")]
    AuthenticationFailed,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BackupMetadata {
    pub app_id: String,
    pub created_at: DateTime<Utc>,
    pub plaintext_bytes: u64,
    pub plaintext_sha256: String,
    pub envelope_sha256: String,
}

#[derive(Debug)]
pub struct EncryptedBackup {
    pub bytes: Vec<u8>,
    pub metadata: BackupMetadata,
}

#[derive(Debug)]
pub struct DecryptedBackup {
    pub bytes: Vec<u8>,
    pub metadata: BackupMetadata,
}

pub struct EncryptedBackupCodec {
    key: [u8; 32],
}

impl EncryptedBackupCodec {
    pub fn new(key: SecretMaterial) -> Result<Self, DataProtectionError> {
        Self::new_borrowed(&key)
    }

    pub fn new_borrowed(key: &SecretMaterial) -> Result<Self, DataProtectionError> {
        if key.expose_bytes().len() != 32 {
            return Err(DataProtectionError::InvalidRequest);
        }
        let mut stored = [0; 32];
        stored.copy_from_slice(key.expose_bytes());
        Ok(Self { key: stored })
    }

    pub fn encrypt(
        &self,
        app_id: &str,
        plaintext: &[u8],
    ) -> Result<EncryptedBackup, DataProtectionError> {
        validate_app_id(app_id)?;
        let created_at = Utc::now();
        let plaintext_sha256 = Sha256::digest(plaintext);
        let header = encode_header(app_id, created_at, &plaintext_sha256)?;
        let mut nonce = [0; NONCE_BYTES];
        OsRng.fill_bytes(&mut nonce);
        let cipher = self.cipher()?;
        let ciphertext = cipher
            .encrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: plaintext,
                    aad: &header,
                },
            )
            .map_err(|_| DataProtectionError::AuthenticationFailed)?;
        let mut bytes = Vec::with_capacity(header.len() + NONCE_BYTES + ciphertext.len());
        bytes.extend_from_slice(&header);
        bytes.extend_from_slice(&nonce);
        bytes.extend_from_slice(&ciphertext);
        let envelope_sha256 = hex::encode(Sha256::digest(&bytes));
        Ok(EncryptedBackup {
            metadata: BackupMetadata {
                app_id: app_id.into(),
                created_at,
                plaintext_bytes: plaintext.len() as u64,
                plaintext_sha256: hex::encode(plaintext_sha256),
                envelope_sha256,
            },
            bytes,
        })
    }

    pub fn decrypt(
        &self,
        expected_app_id: &str,
        envelope: &[u8],
    ) -> Result<DecryptedBackup, DataProtectionError> {
        validate_app_id(expected_app_id)?;
        let decoded = decode_header(envelope)?;
        if decoded.app_id != expected_app_id {
            return Err(DataProtectionError::AppMismatch);
        }
        let ciphertext_start = decoded.header_bytes + NONCE_BYTES;
        let plaintext = self
            .cipher()?
            .decrypt(
                Nonce::from_slice(&envelope[decoded.header_bytes..ciphertext_start]),
                Payload {
                    msg: &envelope[ciphertext_start..],
                    aad: &envelope[..decoded.header_bytes],
                },
            )
            .map_err(|_| DataProtectionError::AuthenticationFailed)?;
        if Sha256::digest(&plaintext).as_ref() != decoded.plaintext_sha256 {
            return Err(DataProtectionError::AuthenticationFailed);
        }
        Ok(DecryptedBackup {
            metadata: BackupMetadata {
                app_id: decoded.app_id,
                created_at: decoded.created_at,
                plaintext_bytes: plaintext.len() as u64,
                plaintext_sha256: hex::encode(decoded.plaintext_sha256),
                envelope_sha256: hex::encode(Sha256::digest(envelope)),
            },
            bytes: plaintext,
        })
    }

    fn cipher(&self) -> Result<Aes256Gcm, DataProtectionError> {
        Aes256Gcm::new_from_slice(&self.key).map_err(|_| DataProtectionError::InvalidRequest)
    }
}

impl Drop for EncryptedBackupCodec {
    fn drop(&mut self) {
        self.key.fill(0);
    }
}

struct DecodedHeader {
    app_id: String,
    created_at: DateTime<Utc>,
    header_bytes: usize,
    plaintext_sha256: [u8; HASH_BYTES],
}

fn encode_header(
    app_id: &str,
    created_at: DateTime<Utc>,
    plaintext_sha256: &[u8],
) -> Result<Vec<u8>, DataProtectionError> {
    let app_id_bytes = app_id.as_bytes();
    let app_id_len =
        u16::try_from(app_id_bytes.len()).map_err(|_| DataProtectionError::InvalidRequest)?;
    let mut header = Vec::with_capacity(FIXED_HEADER_BYTES + app_id_bytes.len());
    header.extend_from_slice(BACKUP_MAGIC);
    header.extend_from_slice(&app_id_len.to_be_bytes());
    header.extend_from_slice(&created_at.timestamp_millis().to_be_bytes());
    header.extend_from_slice(plaintext_sha256);
    header.extend_from_slice(app_id_bytes);
    Ok(header)
}

fn decode_header(envelope: &[u8]) -> Result<DecodedHeader, DataProtectionError> {
    if envelope.len() <= FIXED_HEADER_BYTES + NONCE_BYTES + 16
        || envelope.get(..BACKUP_MAGIC.len()) != Some(BACKUP_MAGIC)
    {
        return Err(DataProtectionError::InvalidRequest);
    }
    let app_id_len = u16::from_be_bytes(
        envelope[8..10]
            .try_into()
            .map_err(|_| DataProtectionError::InvalidRequest)?,
    ) as usize;
    let header_bytes = FIXED_HEADER_BYTES
        .checked_add(app_id_len)
        .ok_or(DataProtectionError::InvalidRequest)?;
    if app_id_len == 0 || envelope.len() <= header_bytes + NONCE_BYTES + 16 {
        return Err(DataProtectionError::InvalidRequest);
    }
    let timestamp = i64::from_be_bytes(
        envelope[10..18]
            .try_into()
            .map_err(|_| DataProtectionError::InvalidRequest)?,
    );
    let created_at = Utc
        .timestamp_millis_opt(timestamp)
        .single()
        .ok_or(DataProtectionError::InvalidRequest)?;
    let plaintext_sha256 = envelope[18..50]
        .try_into()
        .map_err(|_| DataProtectionError::InvalidRequest)?;
    let app_id = std::str::from_utf8(&envelope[50..header_bytes])
        .map_err(|_| DataProtectionError::InvalidRequest)?
        .to_string();
    validate_app_id(&app_id)?;
    Ok(DecodedHeader {
        app_id,
        created_at,
        header_bytes,
        plaintext_sha256,
    })
}

fn validate_app_id(app_id: &str) -> Result<(), DataProtectionError> {
    if app_id.is_empty()
        || app_id.len() > 255
        || !app_id
            .bytes()
            .all(|value| value.is_ascii_alphanumeric() || matches!(value, b'.' | b'-' | b'_'))
    {
        Err(DataProtectionError::InvalidRequest)
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn codec(value: u8) -> EncryptedBackupCodec {
        EncryptedBackupCodec::new(SecretMaterial::new(vec![value; 32]).unwrap()).unwrap()
    }

    #[test]
    fn encrypted_backup_round_trips_and_binds_app_and_key() {
        let backup = codec(7)
            .encrypt("com.example.app", b"sqlite bytes")
            .unwrap();
        let decoded = codec(7).decrypt("com.example.app", &backup.bytes).unwrap();
        assert_eq!(decoded.bytes, b"sqlite bytes");
        assert_eq!(decoded.metadata.plaintext_bytes, 12);
        assert_eq!(
            codec(7)
                .decrypt("com.other.app", &backup.bytes)
                .unwrap_err(),
            DataProtectionError::AppMismatch,
        );
        assert_eq!(
            codec(8)
                .decrypt("com.example.app", &backup.bytes)
                .unwrap_err(),
            DataProtectionError::AuthenticationFailed,
        );
    }

    #[test]
    fn encrypted_backup_rejects_tampering_and_malformed_headers() {
        let mut bytes = codec(7)
            .encrypt("com.example.app", b"sqlite bytes")
            .unwrap()
            .bytes;
        let last = bytes.len() - 1;
        bytes[last] ^= 1;
        assert_eq!(
            codec(7).decrypt("com.example.app", &bytes).unwrap_err(),
            DataProtectionError::AuthenticationFailed,
        );
        assert_eq!(
            codec(7)
                .decrypt("com.example.app", b"not a backup")
                .unwrap_err(),
            DataProtectionError::InvalidRequest,
        );
    }
}
