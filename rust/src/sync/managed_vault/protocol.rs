use std::collections::BTreeMap;

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};

use super::PullOp;

pub(super) const PULL_BIN_MAGIC_V2: &[u8; 5] = b"SLVB2";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(super) struct PullEnvelopeMetaV2 {
    pub(super) protocol_version: u32,
    pub(super) generation_id: String,
    #[serde(default)]
    pub(super) checkpoint_token: Option<String>,
    pub(super) has_more: bool,
    #[serde(default)]
    pub(super) high_water: Option<u64>,
    #[serde(default)]
    pub(super) history_lower_bound: Option<BTreeMap<String, i64>>,
    #[serde(default)]
    pub(super) reseed_required: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(super) struct PullEnvelopeV2 {
    #[serde(flatten)]
    pub(super) meta: PullEnvelopeMetaV2,
    #[serde(default)]
    pub(super) ops: Vec<PullOp>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct PullOpBinV2 {
    pub(super) meta: PullEnvelopeMetaV2,
    pub(super) ops: Vec<super::pull_recovery::PullOpBin>,
}

pub(super) fn decode_pull_bin_v2_response(bytes: &[u8]) -> Result<PullOpBinV2> {
    if bytes.len() < PULL_BIN_MAGIC_V2.len() + 8 {
        return Err(anyhow!("invalid pull_bin_v2 response: too short"));
    }
    if &bytes[..PULL_BIN_MAGIC_V2.len()] != PULL_BIN_MAGIC_V2 {
        return Err(anyhow!("invalid pull_bin_v2 response: bad magic"));
    }

    let mut cursor = PULL_BIN_MAGIC_V2.len();
    let metadata_len = u32::from_le_bytes(
        bytes[cursor..cursor + 4]
            .try_into()
            .map_err(|_| anyhow!("invalid pull_bin_v2 response: metadata_len"))?,
    ) as usize;
    cursor += 4;

    if cursor + metadata_len > bytes.len() {
        return Err(anyhow!("invalid pull_bin_v2 response: truncated metadata"));
    }
    let meta: PullEnvelopeMetaV2 = serde_json::from_slice(&bytes[cursor..cursor + metadata_len])?;
    cursor += metadata_len;

    if cursor + 4 > bytes.len() {
        return Err(anyhow!("invalid pull_bin_v2 response: truncated count"));
    }
    let count = u32::from_le_bytes(
        bytes[cursor..cursor + 4]
            .try_into()
            .map_err(|_| anyhow!("invalid pull_bin_v2 response: count"))?,
    ) as usize;
    cursor += 4;

    let mut ops: Vec<super::pull_recovery::PullOpBin> = Vec::with_capacity(count);
    for _ in 0..count {
        if cursor + 2 > bytes.len() {
            return Err(anyhow!(
                "invalid pull_bin_v2 response: truncated device_id_len"
            ));
        }
        let device_len = u16::from_le_bytes(
            bytes[cursor..cursor + 2]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin_v2 response: device_id_len"))?,
        ) as usize;
        cursor += 2;

        if cursor + device_len > bytes.len() {
            return Err(anyhow!("invalid pull_bin_v2 response: truncated device_id"));
        }
        let device_id = String::from_utf8(bytes[cursor..cursor + device_len].to_vec())
            .map_err(|_| anyhow!("invalid pull_bin_v2 response: device_id not utf-8"))?;
        cursor += device_len;

        if cursor + 8 > bytes.len() {
            return Err(anyhow!("invalid pull_bin_v2 response: truncated seq"));
        }
        let seq = i64::from_le_bytes(
            bytes[cursor..cursor + 8]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin_v2 response: seq"))?,
        );
        cursor += 8;

        if cursor + 2 > bytes.len() {
            return Err(anyhow!("invalid pull_bin_v2 response: truncated op_id_len"));
        }
        let op_id_len = u16::from_le_bytes(
            bytes[cursor..cursor + 2]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin_v2 response: op_id_len"))?,
        ) as usize;
        cursor += 2;

        if cursor + op_id_len > bytes.len() {
            return Err(anyhow!("invalid pull_bin_v2 response: truncated op_id"));
        }
        let op_id = String::from_utf8(bytes[cursor..cursor + op_id_len].to_vec())
            .map_err(|_| anyhow!("invalid pull_bin_v2 response: op_id not utf-8"))?;
        cursor += op_id_len;

        if cursor + 4 > bytes.len() {
            return Err(anyhow!(
                "invalid pull_bin_v2 response: truncated ciphertext_len"
            ));
        }
        let cipher_len = u32::from_le_bytes(
            bytes[cursor..cursor + 4]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin_v2 response: ciphertext_len"))?,
        ) as usize;
        cursor += 4;

        if cursor + cipher_len > bytes.len() {
            return Err(anyhow!(
                "invalid pull_bin_v2 response: truncated ciphertext"
            ));
        }
        let ciphertext = bytes[cursor..cursor + cipher_len].to_vec();
        cursor += cipher_len;

        ops.push(super::pull_recovery::PullOpBin {
            device_id,
            seq,
            op_id,
            ciphertext,
        });
    }

    Ok(PullOpBinV2 { meta, ops })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_pull_bin_v2_response_rejects_truncated_count_after_metadata() {
        let meta = PullEnvelopeMetaV2 {
            protocol_version: 2,
            generation_id: "generation-a".to_string(),
            checkpoint_token: Some("checkpoint-a".to_string()),
            has_more: false,
            high_water: Some(7),
            history_lower_bound: None,
            reseed_required: false,
        };

        let metadata = serde_json::to_vec(&meta).expect("serialize metadata");
        let mut payload = Vec::new();
        payload.extend_from_slice(PULL_BIN_MAGIC_V2);
        payload.extend_from_slice(&(metadata.len() as u32).to_le_bytes());
        payload.extend_from_slice(&metadata);

        let error = decode_pull_bin_v2_response(&payload).expect_err("truncated count should fail");
        assert!(error
            .to_string()
            .contains("invalid pull_bin_v2 response: truncated count"));
    }
}
