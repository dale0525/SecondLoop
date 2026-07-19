use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::fmt;
use zeroize::Zeroizing;

pub const GATEWAY_PROJECTION_SCHEMA_VERSION: u32 = 1;
pub const GATEWAY_POLICY_PROJECTION_CAPABILITY: &str = "gateway_policy_projection_v1";
pub const GATEWAY_PROJECTION_PATH: &str = "/agentweave/entitlements/projection";
pub const GATEWAY_PROJECTION_SIGNATURE_HEADER: &str = "x-agentweave-entitlement-signature";
pub const GATEWAY_PROJECTION_TIMESTAMP_HEADER: &str = "x-agentweave-entitlement-timestamp";
pub const GATEWAY_PROJECTION_NONCE_HEADER: &str = "x-agentweave-entitlement-nonce";
const REQUEST_DOMAIN: &str = "agentweave-entitlement-projection-request-v1";
const RESPONSE_DOMAIN: &str = "agentweave-entitlement-projection-response-v1";

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GatewayProjectionRequest {
    pub schema_version: u32,
    pub source_id: String,
    pub nonce: String,
    pub deployment_id: String,
    pub provider_id: String,
    pub issuer: String,
    pub tenant: String,
    pub subject: String,
    pub model: String,
    pub requested_at: i64,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GatewayProjectionBudget {
    pub period_start: i64,
    pub period_end: i64,
    pub max_requests: i64,
    pub max_units: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_concurrency: Option<i64>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum GatewayProjectionDecision {
    Allow,
    Deny,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GatewayPolicyProjection {
    pub schema_version: u32,
    pub source_id: String,
    pub projection_id: String,
    pub revision: String,
    pub nonce: String,
    pub deployment_id: String,
    pub provider_id: String,
    pub issuer: String,
    pub tenant: String,
    pub subject: String,
    pub model: String,
    pub issued_at: i64,
    pub expires_at: i64,
    pub decision: GatewayProjectionDecision,
    pub reason_code: Option<String>,
    pub tenant_budget: GatewayProjectionBudget,
    pub subject_budget: GatewayProjectionBudget,
}

pub struct GatewayProjectionSecret(Zeroizing<Vec<u8>>);

impl GatewayProjectionSecret {
    pub fn new(value: impl Into<Vec<u8>>) -> Result<Self, GatewayProjectionProtocolError> {
        let value = value.into();
        if !(32..=4096).contains(&value.len()) {
            return Err(GatewayProjectionProtocolError);
        }
        Ok(Self(Zeroizing::new(value)))
    }
}

impl fmt::Debug for GatewayProjectionSecret {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("GatewayProjectionSecret([REDACTED])")
    }
}

#[derive(Clone, Copy, Debug, thiserror::Error, PartialEq, Eq)]
#[error("gateway entitlement projection protocol validation failed")]
pub struct GatewayProjectionProtocolError;

pub fn verify_gateway_projection_request(
    secret: &GatewayProjectionSecret,
    timestamp: &str,
    nonce: &str,
    body: &[u8],
    signature: &str,
) -> Result<GatewayProjectionRequest, GatewayProjectionProtocolError> {
    let timestamp_value = timestamp
        .parse::<i64>()
        .map_err(|_| GatewayProjectionProtocolError)?;
    let request: GatewayProjectionRequest =
        serde_json::from_slice(body).map_err(|_| GatewayProjectionProtocolError)?;
    if request.schema_version != GATEWAY_PROJECTION_SCHEMA_VERSION
        || request.requested_at != timestamp_value
        || request.nonce != nonce
        || !valid_text(nonce, 128)
        || !valid_request(&request)
    {
        return Err(GatewayProjectionProtocolError);
    }
    verify_signature(
        secret,
        canonical(REQUEST_DOMAIN, &[timestamp, nonce], body),
        signature,
    )?;
    Ok(request)
}

pub fn encode_gateway_projection_response(
    secret: &GatewayProjectionSecret,
    request: &GatewayProjectionRequest,
    projection: &GatewayPolicyProjection,
) -> Result<(Vec<u8>, String), GatewayProjectionProtocolError> {
    validate_projection(request, projection)?;
    let body = serde_json::to_vec(projection).map_err(|_| GatewayProjectionProtocolError)?;
    let signature = sign(
        secret,
        canonical(RESPONSE_DOMAIN, &[request.nonce.as_str()], &body),
    )?;
    Ok((body, format!("v1={signature}")))
}

fn validate_projection(
    request: &GatewayProjectionRequest,
    projection: &GatewayPolicyProjection,
) -> Result<(), GatewayProjectionProtocolError> {
    let binding_matches = projection.schema_version == GATEWAY_PROJECTION_SCHEMA_VERSION
        && projection.source_id == request.source_id
        && projection.nonce == request.nonce
        && projection.deployment_id == request.deployment_id
        && projection.provider_id == request.provider_id
        && projection.issuer == request.issuer
        && projection.tenant == request.tenant
        && projection.subject == request.subject
        && projection.model == request.model;
    let timing_valid = projection.issued_at >= 0
        && projection.expires_at > projection.issued_at
        && valid_budget(&projection.tenant_budget, false)
        && valid_budget(&projection.subject_budget, true)
        && projection.expires_at <= projection.tenant_budget.period_end
        && projection.expires_at <= projection.subject_budget.period_end;
    let decision_valid = match projection.decision {
        GatewayProjectionDecision::Allow => projection.reason_code.is_none(),
        GatewayProjectionDecision::Deny => projection
            .reason_code
            .as_deref()
            .is_some_and(|reason| valid_text(reason, 128)),
    };
    if binding_matches
        && timing_valid
        && decision_valid
        && valid_text(&projection.projection_id, 256)
        && valid_text(&projection.revision, 256)
    {
        Ok(())
    } else {
        Err(GatewayProjectionProtocolError)
    }
}

fn valid_request(request: &GatewayProjectionRequest) -> bool {
    [
        request.source_id.as_str(),
        request.deployment_id.as_str(),
        request.provider_id.as_str(),
        request.issuer.as_str(),
        request.tenant.as_str(),
        request.subject.as_str(),
        request.model.as_str(),
    ]
    .into_iter()
    .all(|value| valid_text(value, 2048))
        && request.requested_at >= 0
}

fn valid_budget(value: &GatewayProjectionBudget, subject: bool) -> bool {
    value.period_start >= 0
        && value.period_end > value.period_start
        && value.max_requests >= 0
        && value.max_units >= 0
        && if subject {
            value
                .max_concurrency
                .is_some_and(|limit| (1..=1000).contains(&limit))
        } else {
            value.max_concurrency.is_none()
        }
}

fn valid_text(value: &str, maximum: usize) -> bool {
    !value.is_empty()
        && value.len() <= maximum
        && value == value.trim()
        && !value.chars().any(char::is_control)
}

fn canonical(domain: &str, fields: &[&str], body: &[u8]) -> Vec<u8> {
    let mut value = format!("{domain}\n{}\n", fields.join("\n")).into_bytes();
    value.extend_from_slice(body);
    value
}

fn sign(
    secret: &GatewayProjectionSecret,
    message: Vec<u8>,
) -> Result<String, GatewayProjectionProtocolError> {
    let mut mac =
        Hmac::<Sha256>::new_from_slice(&secret.0).map_err(|_| GatewayProjectionProtocolError)?;
    mac.update(&message);
    Ok(URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes()))
}

fn verify_signature(
    secret: &GatewayProjectionSecret,
    message: Vec<u8>,
    signature: &str,
) -> Result<(), GatewayProjectionProtocolError> {
    let encoded = signature
        .strip_prefix("v1=")
        .ok_or(GatewayProjectionProtocolError)?;
    let signature = URL_SAFE_NO_PAD
        .decode(encoded)
        .map_err(|_| GatewayProjectionProtocolError)?;
    let mut mac =
        Hmac::<Sha256>::new_from_slice(&secret.0).map_err(|_| GatewayProjectionProtocolError)?;
    mac.update(&message);
    mac.verify_slice(&signature)
        .map_err(|_| GatewayProjectionProtocolError)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request() -> GatewayProjectionRequest {
        GatewayProjectionRequest {
            schema_version: 1,
            source_id: "agentweave.entitlements.http".into(),
            nonce: "00000000-0000-4000-8000-000000000001".into(),
            deployment_id: "deployment-1".into(),
            provider_id: "agentweave.identity.oidc".into(),
            issuer: "https://identity.example.test/".into(),
            tenant: "tenant-1".into(),
            subject: "subject-1".into(),
            model: "approved-model".into(),
            requested_at: 1_800_000_000,
        }
    }

    fn sign_request(
        secret: &GatewayProjectionSecret,
        request: &GatewayProjectionRequest,
        body: &[u8],
    ) -> String {
        let timestamp = request.requested_at.to_string();
        format!(
            "v1={}",
            sign(
                secret,
                canonical(REQUEST_DOMAIN, &[&timestamp, &request.nonce], body),
            )
            .unwrap()
        )
    }

    #[test]
    fn request_and_response_signatures_are_bound_and_redacted() {
        let secret = GatewayProjectionSecret::new(vec![7; 32]).unwrap();
        let request = request();
        let body = serde_json::to_vec(&request).unwrap();
        let timestamp = request.requested_at.to_string();
        let signature = sign_request(&secret, &request, &body);
        assert_eq!(
            verify_gateway_projection_request(
                &secret,
                &timestamp,
                &request.nonce,
                &body,
                &signature,
            )
            .unwrap(),
            request
        );
        let projection = GatewayPolicyProjection {
            schema_version: 1,
            source_id: request.source_id.clone(),
            projection_id: "projection-1".into(),
            revision: "revision-1".into(),
            nonce: request.nonce.clone(),
            deployment_id: request.deployment_id.clone(),
            provider_id: request.provider_id.clone(),
            issuer: request.issuer.clone(),
            tenant: request.tenant.clone(),
            subject: request.subject.clone(),
            model: request.model.clone(),
            issued_at: request.requested_at,
            expires_at: request.requested_at + 60,
            decision: GatewayProjectionDecision::Allow,
            reason_code: None,
            tenant_budget: GatewayProjectionBudget {
                period_start: request.requested_at - 10,
                period_end: request.requested_at + 3600,
                max_requests: 1000,
                max_units: 1_000_000,
                max_concurrency: None,
            },
            subject_budget: GatewayProjectionBudget {
                period_start: request.requested_at - 10,
                period_end: request.requested_at + 3600,
                max_requests: 100,
                max_units: 100_000,
                max_concurrency: Some(2),
            },
        };
        let (response, signature) =
            encode_gateway_projection_response(&secret, &request, &projection).unwrap();
        assert!(!response.is_empty());
        assert!(signature.starts_with("v1="));
        assert_eq!(format!("{secret:?}"), "GatewayProjectionSecret([REDACTED])");
    }

    #[test]
    fn tampering_is_rejected() {
        let secret = GatewayProjectionSecret::new(vec![9; 32]).unwrap();
        let request = request();
        let body = serde_json::to_vec(&request).unwrap();
        assert!(
            verify_gateway_projection_request(
                &secret,
                &request.requested_at.to_string(),
                &request.nonce,
                &body,
                "v1=invalid",
            )
            .is_err()
        );
    }
}
