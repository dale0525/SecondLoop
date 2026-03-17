use std::sync::OnceLock;

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64_URL;
use base64::Engine as _;
use reqwest::blocking::Client;

pub(super) fn scope_id(base_url: &str, vault_id: &str) -> String {
    let raw = format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim());
    B64_URL.encode(raw.as_bytes())
}

pub(super) fn client() -> Result<Client> {
    static CLIENT: OnceLock<Client> = OnceLock::new();
    Ok(CLIENT.get_or_init(Client::new).clone())
}

pub(super) fn url(base_url: &str, path: &str) -> Result<String> {
    let base = base_url.trim_end_matches('/');
    if base.is_empty() {
        return Err(anyhow!("missing_base_url"));
    }
    Ok(format!("{base}{path}"))
}

use super::{RegisterDeviceRequest, RegisterDeviceResponse};

pub(super) fn ensure_device_registered(
    http: &Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    device_id: &str,
) -> Result<String> {
    let request = RegisterDeviceRequest {
        platform: "unknown",
        device_id: Some(device_id),
    };

    let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/devices"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&request)
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!(
            "managed-vault register-device failed: HTTP {status} {text}"
        ));
    }

    let parsed: RegisterDeviceResponse = serde_json::from_str(&text)?;
    Ok(parsed.device_id)
}
