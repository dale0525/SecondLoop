use anyhow::Result;
use serde_json::json;

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_cursor_diagnostics(
    _app_dir: String,
    base_url: String,
    vault_id: String,
    _firebase_id_token: Option<String>,
) -> Result<String> {
    Ok(json!({
        "scope_id": format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim()),
        "local_device_id": "unsupported_on_wasm",
        "local_last_pulled_seq_by_device": {},
        "local_last_pushed_seq_by_device": {},
        "local_last_pushed_seq_legacy": null,
        "local_pending_apply_op_ids": [],
        "remote_device_seq_map": null,
        "remote_device_seq_map_source": null,
        "remote_probe_error": "managed_vault_cursor_diagnostics_unsupported_on_wasm"
    })
    .to_string())
}
