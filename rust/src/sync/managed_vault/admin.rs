use anyhow::{anyhow, Result};
use serde::Serialize;

#[derive(Debug, Serialize)]
struct ClearDeviceRequest<'a> {
    device_id: &'a str,
}

pub fn clear_vault(base_url: &str, vault_id: &str, id_token: &str) -> Result<()> {
    let http = super::runtime::client()?;
    let reset_endpoint =
        super::runtime::url(base_url, &format!("/v2/vaults/{vault_id}/sync/reset"))?;
    let reset_resp = http
        .post(reset_endpoint)
        .bearer_auth(id_token)
        .json(&serde_json::json!({}))
        .send()?;
    let reset_status = reset_resp.status();
    let reset_text = reset_resp.text().unwrap_or_default();
    if reset_status.is_success() {
        return Ok(());
    }
    if !matches!(reset_status.as_u16(), 404 | 405) {
        return Err(anyhow!(
            "managed-vault clear failed: HTTP {reset_status} {reset_text}"
        ));
    }

    let legacy_endpoint =
        super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:clear"))?;
    let legacy_resp = http.post(legacy_endpoint).bearer_auth(id_token).send()?;
    let legacy_status = legacy_resp.status();
    let legacy_text = legacy_resp.text().unwrap_or_default();
    if !legacy_status.is_success() {
        return Err(anyhow!(
            "managed-vault clear failed: v2 reset unavailable (HTTP {reset_status} {reset_text}); legacy clear failed: HTTP {legacy_status} {legacy_text}"
        ));
    }
    Ok(())
}

pub fn clear_device(base_url: &str, vault_id: &str, id_token: &str, device_id: &str) -> Result<()> {
    let http = super::runtime::client()?;
    let endpoint =
        super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:clear_device"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&ClearDeviceRequest { device_id })
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!(
            "managed-vault clear-device failed: HTTP {status} {text}"
        ));
    }
    Ok(())
}
