use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize)]
pub(super) struct GlobalLogPushRequest<'a> {
    pub(super) base_global_seq: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) generation_id: Option<&'a str>,
    pub(super) batch_id: &'a str,
    pub(super) ops: Vec<GlobalLogPushOp>,
}

#[derive(Debug, Serialize)]
pub(super) struct GlobalLogPushOp {
    pub(super) device_id: String,
    pub(super) seq: i64,
    pub(super) op_id: String,
    pub(super) client_op_id: String,
    pub(super) ciphertext_b64: String,
}

#[derive(Debug, Deserialize)]
pub(super) struct GlobalLogPushResponse {
    pub(super) generation_id: String,
    pub(super) accepted: u64,
    pub(super) committed_from_seq: Option<i64>,
    pub(super) committed_to_seq: Option<i64>,
    pub(super) remote_latest_global_seq: i64,
}

#[derive(Debug, Deserialize, Serialize)]
pub(super) struct GlobalLogPushErrorResponse {
    pub(super) error: String,
    pub(super) remote_generation_id: Option<String>,
    pub(super) remote_latest_global_seq: Option<i64>,
}

#[derive(Debug, Serialize)]
pub(super) struct GlobalLogPullRequest {
    pub(super) after_global_seq: i64,
    pub(super) limit: i64,
}

#[derive(Debug, Clone, Deserialize)]
pub(super) struct GlobalLogPullOp {
    pub(super) global_seq: i64,
    pub(super) device_id: String,
    pub(super) seq: i64,
    pub(super) op_id: String,
    pub(super) client_op_id: String,
    pub(super) ciphertext_b64: String,
}

#[derive(Debug, Deserialize)]
pub(super) struct GlobalLogPullResponse {
    pub(super) generation_id: String,
    pub(super) remote_latest_global_seq: i64,
    pub(super) has_more: bool,
    pub(super) ops: Vec<GlobalLogPullOp>,
}

#[derive(Debug, Deserialize)]
pub(super) struct GlobalLogPullErrorResponse {
    pub(super) error: String,
    pub(super) reason: Option<String>,
    pub(super) remote_generation_id: Option<String>,
    pub(super) remote_latest_global_seq: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub(super) struct GlobalLogResetResponse {
    pub(super) generation_id: String,
    pub(super) remote_latest_global_seq: i64,
    pub(super) deleted_meta: i64,
    pub(super) deleted_blobs: i64,
}
