use anyhow::{anyhow, Result};
use serde::Serialize;
use std::collections::BTreeMap;

use super::protocol::{decode_pull_bin_v2_response, PullEnvelopeV2, PullOpBinV2};
use super::runtime::Client;

#[derive(Debug, Serialize)]
pub(super) struct PullRequestV2<'a> {
    pub(super) device_id: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) checkpoint_token: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) since: Option<&'a BTreeMap<String, i64>>,
    pub(super) limit: i64,
}

pub(super) enum PullV2RouteResult<T> {
    Parsed(T),
    Unsupported,
    Forbidden,
    RetryLegacy,
}

fn should_retry_legacy_v2(status_code: u16) -> bool {
    matches!(status_code, 404 | 405 | 408 | 429) || (500..600).contains(&status_code)
}

pub(super) fn fetch_pull_v2_json(
    http: &Client,
    endpoint: &str,
    id_token: &str,
    request: &PullRequestV2<'_>,
) -> Result<PullV2RouteResult<PullEnvelopeV2>> {
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(request)
        .send()?;
    let status = resp.status();
    let status_code = status.as_u16();
    if matches!(status_code, 404 | 405) {
        return Ok(PullV2RouteResult::Unsupported);
    }
    if status_code == 403 {
        return Ok(PullV2RouteResult::Forbidden);
    }
    if should_retry_legacy_v2(status_code) {
        return Ok(PullV2RouteResult::RetryLegacy);
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault pull_v2 failed: HTTP {status} {text}"
        ));
    }
    let body = resp.bytes()?;
    let parsed: PullEnvelopeV2 = serde_json::from_slice(body.as_ref())?;
    Ok(PullV2RouteResult::Parsed(parsed))
}

pub(super) fn fetch_pull_bin_v2(
    http: &Client,
    endpoint: &str,
    id_token: &str,
    request: &PullRequestV2<'_>,
) -> Result<PullV2RouteResult<PullOpBinV2>> {
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(request)
        .send()?;
    let status = resp.status();
    let status_code = status.as_u16();
    if matches!(status_code, 404 | 405) {
        return Ok(PullV2RouteResult::Unsupported);
    }
    if status_code == 403 {
        return Ok(PullV2RouteResult::Forbidden);
    }
    if should_retry_legacy_v2(status_code) {
        return Ok(PullV2RouteResult::RetryLegacy);
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault pull_bin_v2 failed: HTTP {status} {text}"
        ));
    }
    let body = resp.bytes()?;
    Ok(PullV2RouteResult::Parsed(decode_pull_bin_v2_response(
        body.as_ref(),
    )?))
}

pub(super) fn sum_since(map: &BTreeMap<String, i64>) -> u64 {
    map.values().map(|seq| (*seq).max(0) as u64).sum::<u64>()
}
