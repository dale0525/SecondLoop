use anyhow::{anyhow, Result};
use rusqlite::Connection;
use serde::Deserialize;
use std::collections::BTreeMap;

use super::pending_apply::{
    cursor_repair_marker_attempted, has_local_oplog_for_device, mark_cursor_repair_attempted,
    remote_ahead_cursor_devices, update_since_map,
};

#[derive(Debug, Deserialize)]
pub(super) struct PullResponseWithMax {
    pub(super) ops: Vec<super::PullOp>,
    pub(super) next: BTreeMap<String, i64>,
    #[serde(default)]
    pub(super) max: BTreeMap<String, i64>,
    #[serde(default)]
    pub(super) needs_reseed: BTreeMap<String, bool>,
    #[serde(default)]
    pub(super) history_lower_bound: BTreeMap<String, i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct PullOpBin {
    pub(super) device_id: String,
    pub(super) seq: i64,
    pub(super) op_id: String,
    pub(super) ciphertext: Vec<u8>,
}

#[derive(Debug, Default)]
pub(super) struct RemoteAheadRepairTracker {
    repaired_max_by_device: BTreeMap<String, i64>,
}

pub(super) enum RemoteAheadRepairOutcome {
    NotNeeded,
    Recovered,
    Exhausted(Vec<String>),
}

pub(super) fn repeated_remote_ahead_repair_error(devices: &[String]) -> anyhow::Error {
    anyhow!(
        "managed-vault pull stalled after repeated remote-ahead repair for device(s): {}",
        devices.join(", ")
    )
}

pub(super) fn probe_failure_indicates_json_unavailable(error: &anyhow::Error) -> bool {
    error.to_string().contains("HTTP 404")
}

pub(super) fn maybe_recover_stale_since_map(
    conn: &Connection,
    scope_id: &str,
    local_device_id: &str,
    since: &mut BTreeMap<String, i64>,
) -> Result<bool> {
    if since.is_empty() {
        return Ok(false);
    }

    let mut changed = false;
    for (device_id, last_seq) in since.clone() {
        if device_id == local_device_id || last_seq <= 0 {
            continue;
        }

        if cursor_repair_marker_attempted(conn, scope_id, &device_id)? {
            continue;
        }

        if has_local_oplog_for_device(conn, &device_id)? {
            continue;
        }

        since.insert(device_id.clone(), 0);
        mark_cursor_repair_attempted(conn, scope_id, &device_id)?;
        changed = true;
    }

    if changed {
        update_since_map(conn, scope_id, since)?;
    }

    Ok(changed)
}

pub(super) fn attempt_remote_ahead_repair(
    tracker: &mut RemoteAheadRepairTracker,
    conn: &Connection,
    scope_id: &str,
    local_device_id: &str,
    since: &mut BTreeMap<String, i64>,
    remote_max: &BTreeMap<String, i64>,
) -> Result<RemoteAheadRepairOutcome> {
    let ahead_devices = remote_ahead_cursor_devices(since, remote_max, local_device_id);
    if ahead_devices.is_empty() {
        return Ok(RemoteAheadRepairOutcome::NotNeeded);
    }

    let mut changed = false;
    let mut exhausted = Vec::new();
    for device_id in ahead_devices {
        let max_seq = remote_max.get(&device_id).copied().unwrap_or(0);
        if tracker
            .repaired_max_by_device
            .get(&device_id)
            .copied()
            .unwrap_or(i64::MIN)
            >= max_seq
        {
            exhausted.push(device_id);
            continue;
        }

        since.insert(device_id.clone(), 0);
        tracker.repaired_max_by_device.insert(device_id, max_seq);
        changed = true;
    }

    if changed {
        update_since_map(conn, scope_id, since)?;
        return Ok(RemoteAheadRepairOutcome::Recovered);
    }

    Ok(RemoteAheadRepairOutcome::Exhausted(exhausted))
}

pub(super) fn probe_pull_response_with_max(
    http: &super::runtime::Client,
    endpoint_json: &str,
    id_token: &str,
    request: &super::PullRequest<'_>,
) -> Result<PullResponseWithMax> {
    let resp = http
        .post(endpoint_json)
        .bearer_auth(id_token)
        .json(request)
        .send()?;

    let status = resp.status();
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!("managed-vault pull failed: HTTP {status} {text}"));
    }

    let body = resp.bytes()?;
    serde_json::from_slice(body.as_ref())
        .map_err(|error| anyhow!("managed-vault pull response decode failed: {error}"))
}

pub(super) fn probe_requires_json_retry(
    since: &BTreeMap<String, i64>,
    probe: &PullResponseWithMax,
) -> bool {
    !probe.ops.is_empty()
        || !probe.needs_reseed.is_empty()
        || !probe.history_lower_bound.is_empty()
        || probe
            .next
            .iter()
            .any(|(device_id, next_seq)| *next_seq > since.get(device_id).copied().unwrap_or(0))
}

pub(super) fn decode_pull_bin_response(bytes: &[u8]) -> Result<Vec<PullOpBin>> {
    if bytes.len() < super::PULL_BIN_MAGIC_V1.len() + 4 {
        return Err(anyhow!("invalid pull_bin response: too short"));
    }
    if &bytes[..super::PULL_BIN_MAGIC_V1.len()] != super::PULL_BIN_MAGIC_V1 {
        return Err(anyhow!("invalid pull_bin response: bad magic"));
    }

    let mut cursor = super::PULL_BIN_MAGIC_V1.len();
    let count = u32::from_le_bytes(
        bytes[cursor..cursor + 4]
            .try_into()
            .map_err(|_| anyhow!("invalid pull_bin response: count"))?,
    ) as usize;
    cursor += 4;

    let mut out: Vec<PullOpBin> = Vec::with_capacity(count);
    for _ in 0..count {
        if cursor + 2 > bytes.len() {
            return Err(anyhow!(
                "invalid pull_bin response: truncated device_id_len"
            ));
        }
        let device_len = u16::from_le_bytes(
            bytes[cursor..cursor + 2]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin response: device_id_len"))?,
        ) as usize;
        cursor += 2;

        if cursor + device_len > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated device_id"));
        }
        let device_id = String::from_utf8(bytes[cursor..cursor + device_len].to_vec())
            .map_err(|_| anyhow!("invalid pull_bin response: device_id not utf-8"))?;
        cursor += device_len;

        if cursor + 8 > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated seq"));
        }
        let seq = i64::from_le_bytes(
            bytes[cursor..cursor + 8]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin response: seq"))?,
        );
        cursor += 8;

        if cursor + 2 > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated op_id_len"));
        }
        let op_id_len = u16::from_le_bytes(
            bytes[cursor..cursor + 2]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin response: op_id_len"))?,
        ) as usize;
        cursor += 2;

        if cursor + op_id_len > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated op_id"));
        }
        let op_id = String::from_utf8(bytes[cursor..cursor + op_id_len].to_vec())
            .map_err(|_| anyhow!("invalid pull_bin response: op_id not utf-8"))?;
        cursor += op_id_len;

        if cursor + 4 > bytes.len() {
            return Err(anyhow!(
                "invalid pull_bin response: truncated ciphertext_len"
            ));
        }
        let cipher_len = u32::from_le_bytes(
            bytes[cursor..cursor + 4]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin response: ciphertext_len"))?,
        ) as usize;
        cursor += 4;

        if cursor + cipher_len > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated ciphertext"));
        }
        let ciphertext = bytes[cursor..cursor + cipher_len].to_vec();
        cursor += cipher_len;

        out.push(PullOpBin {
            device_id,
            seq,
            op_id,
            ciphertext,
        });
    }

    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probe_requires_json_retry_when_reseed_metadata_arrives_without_ops() {
        let since = BTreeMap::from([("remote-a".to_string(), 4)]);
        let probe = PullResponseWithMax {
            ops: Vec::new(),
            next: BTreeMap::from([("remote-a".to_string(), 4)]),
            max: BTreeMap::new(),
            needs_reseed: BTreeMap::from([("remote-a".to_string(), true)]),
            history_lower_bound: BTreeMap::new(),
        };

        assert!(probe_requires_json_retry(&since, &probe));
    }

    #[test]
    fn probe_requires_json_retry_when_history_lower_bound_arrives_without_ops() {
        let since = BTreeMap::from([("remote-a".to_string(), 4)]);
        let probe = PullResponseWithMax {
            ops: Vec::new(),
            next: BTreeMap::from([("remote-a".to_string(), 4)]),
            max: BTreeMap::new(),
            needs_reseed: BTreeMap::new(),
            history_lower_bound: BTreeMap::from([("remote-a".to_string(), 5)]),
        };

        assert!(probe_requires_json_retry(&since, &probe));
    }
}
