use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use serde::Serialize;
use std::collections::BTreeMap;

use super::protocol::{decode_pull_bin_v2_response, PullEnvelopeV2, PullOpBinV2};

#[derive(Debug, Serialize)]
pub(super) struct PullRequestV2<'a> {
    pub(super) device_id: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) checkpoint_token: Option<&'a str>,
    pub(super) limit: i64,
}

pub(super) fn fetch_pull_v2_json(
    http: &Client,
    endpoint: &str,
    id_token: &str,
    request: &PullRequestV2<'_>,
) -> Result<Option<PullEnvelopeV2>> {
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(request)
        .send()?;
    let status = resp.status();
    if status.as_u16() == 404 {
        return Ok(None);
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault pull_v2 failed: HTTP {status} {text}"
        ));
    }
    let body = resp.bytes()?;
    let parsed: PullEnvelopeV2 = serde_json::from_slice(body.as_ref())?;
    Ok(Some(parsed))
}

pub(super) fn fetch_pull_bin_v2(
    http: &Client,
    endpoint: &str,
    id_token: &str,
    request: &PullRequestV2<'_>,
) -> Result<Option<PullOpBinV2>> {
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(request)
        .send()?;
    let status = resp.status();
    if status.as_u16() == 404 {
        return Ok(None);
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault pull_bin_v2 failed: HTTP {status} {text}"
        ));
    }
    let body = resp.bytes()?;
    Ok(Some(decode_pull_bin_v2_response(body.as_ref())?))
}

pub(super) fn sum_since(map: &BTreeMap<String, i64>) -> u64 {
    map.values().map(|seq| (*seq).max(0) as u64).sum::<u64>()
}
