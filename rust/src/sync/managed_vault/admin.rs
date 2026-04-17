use anyhow::{anyhow, Result};
use serde::Serialize;

#[derive(Debug, Serialize)]
struct ClearDeviceRequest<'a> {
    device_id: &'a str,
}

pub fn clear_vault(base_url: &str, vault_id: &str, id_token: &str) -> Result<()> {
    let http = super::runtime::client()?;
    let endpoint = super::runtime::url(base_url, &format!("/v2/vaults/{vault_id}/sync/reset"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&serde_json::json!({}))
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!("managed-vault clear failed: HTTP {status} {text}"));
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
