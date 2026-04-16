use anyhow::{anyhow, Result};
use rusqlite::Connection;
use std::collections::BTreeMap;

use crate::crypto::decrypt_bytes;

#[derive(Debug, Clone)]
pub(super) struct PullCipherOp {
    pub(super) device_id: String,
    pub(super) seq: i64,
    pub(super) op_id: String,
    pub(super) ciphertext: Vec<u8>,
}

pub(super) fn next_since_from_ops(
    current_since: &BTreeMap<String, i64>,
    ops: &[PullCipherOp],
) -> BTreeMap<String, i64> {
    let mut next_since = current_since.clone();
    for op in ops {
        next_since
            .entry(op.device_id.clone())
            .and_modify(|seq| *seq = (*seq).max(op.seq))
            .or_insert(op.seq);
    }
    next_since
}

pub(super) fn apply_pull_cipher_ops(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    scope_id: &str,
    previous_since: &BTreeMap<String, i64>,
    next_since: &mut BTreeMap<String, i64>,
    ops: &[PullCipherOp],
) -> Result<u64> {
    let mut batch_applied = 0u64;
    super::with_immediate_transaction(conn, || {
        let mut pending = super::load_pending_apply_op_ids(conn, scope_id)?;
        for op in ops {
            let plaintext = decrypt_bytes(
                sync_key,
                &op.ciphertext,
                format!("sync.ops:{}:{}", op.device_id, op.seq).as_bytes(),
            )?;
            let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
            let op_id = op_json["op_id"]
                .as_str()
                .ok_or_else(|| anyhow!("sync op missing op_id"))?;
            let envelope_op_id = op.op_id.trim();
            if !envelope_op_id.is_empty() && op_id != envelope_op_id {
                return Err(anyhow!(
                    "managed vault pull op_id mismatch: envelope={} plaintext={}",
                    op.op_id,
                    op_id
                ));
            }

            let inserted = super::super::insert_remote_oplog(conn, db_key, &plaintext, &op_json)?;
            if !inserted {
                continue;
            }

            match super::super::apply_op(conn, db_key, &op_json) {
                Ok(_) => {
                    batch_applied += 1;
                }
                Err(error) if super::is_foreign_key_constraint_error(&error) => {
                    pending.insert(op_id.to_string());
                    super::super::kv_set_i64(conn, &super::pending_apply_key(scope_id, op_id), 1)?;
                }
                Err(error) => return Err(error),
            }
        }

        super::apply_pending_ops_until_stable(conn, db_key, scope_id, &mut pending)?;
        super::rewind_since_for_unresolved_pending_devices(conn, &pending, next_since)?;

        if *next_since != *previous_since {
            super::update_since_map(conn, scope_id, next_since)?;
        }

        Ok(())
    })?;
    Ok(batch_applied)
}
