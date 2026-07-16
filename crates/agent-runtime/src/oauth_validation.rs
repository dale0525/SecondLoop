use super::{
    MAX_SCOPES, OAuthAuthorizationPlan, OAuthAuthorizationRequest, OAuthAuthorizationSession,
    OAuthAuthorizationUrlRequest, OAuthCallbackRequest, OAuthSecretString, OAuthTokenGrant,
};
use crate::credential::SecretMaterial;
use aes_gcm::aead::{OsRng, rand_core::RngCore};
use chrono::{DateTime, Utc};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use url::Url;
use zeroize::Zeroizing;

const MAX_CONNECTORS: usize = 8;
const MAX_CAPABILITIES: usize = 32;

pub(super) fn validate_authorization_request(
    request: &OAuthAuthorizationRequest,
) -> anyhow::Result<()> {
    validate_identifier("OAuth provider", &request.provider_id)?;
    validate_identifier_set("OAuth Connector", &request.connector_ids, MAX_CONNECTORS)?;
    validate_identifier_set(
        "OAuth capability",
        &request.requested_capabilities,
        MAX_CAPABILITIES,
    )
}

pub(super) fn validate_authorization_plan(
    connector_ids: &BTreeSet<String>,
    plan: &OAuthAuthorizationPlan,
) -> anyhow::Result<()> {
    anyhow::ensure!(
        !plan.requested_scopes.is_empty() && plan.requested_scopes.len() <= MAX_SCOPES,
        "OAuth provider scope plan is invalid"
    );
    anyhow::ensure!(
        plan.connector_scopes.keys().collect::<BTreeSet<_>>()
            == connector_ids.iter().collect::<BTreeSet<_>>(),
        "OAuth provider Connector plan is incomplete"
    );
    for (connector_id, scopes) in &plan.connector_scopes {
        validate_identifier("OAuth Connector", connector_id)?;
        anyhow::ensure!(
            !scopes.is_empty() && scopes.is_subset(&plan.requested_scopes),
            "OAuth Connector scopes exceed the provider plan"
        );
    }
    Ok(())
}

pub(super) fn validate_token_grant(
    session: &OAuthAuthorizationSession,
    grant: &OAuthTokenGrant,
    now: DateTime<Utc>,
) -> anyhow::Result<()> {
    validate_provider_subject(&grant.provider_subject)?;
    anyhow::ensure!(
        session.requested_scopes.is_subset(&grant.granted_scopes),
        "OAuth grant does not include requested scopes"
    );
    anyhow::ensure!(
        grant.granted_scopes.len() <= MAX_SCOPES,
        "OAuth grant is too large"
    );
    anyhow::ensure!(
        grant.expires_at.is_none_or(|expires_at| expires_at > now),
        "OAuth grant is already expired"
    );
    Ok(())
}

pub(super) fn validate_callback_request(request: &OAuthCallbackRequest) -> anyhow::Result<()> {
    anyhow::ensure!(
        request.state.len() == 64 && request.state.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "OAuth callback state is invalid"
    );
    anyhow::ensure!(
        request.code.is_some() ^ request.error.is_some(),
        "OAuth callback must contain exactly one result"
    );
    if let Some(error) = &request.error {
        anyhow::ensure!(
            !error.is_empty() && error.len() <= 128,
            "OAuth callback error is invalid"
        );
    }
    Ok(())
}

fn validate_identifier_set(
    label: &str,
    values: &BTreeSet<String>,
    maximum: usize,
) -> anyhow::Result<()> {
    anyhow::ensure!(
        !values.is_empty() && values.len() <= maximum,
        "{label} set is invalid"
    );
    for value in values {
        validate_identifier(label, value)?;
    }
    Ok(())
}

pub(super) fn validate_identifier(label: &str, value: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        !value.is_empty()
            && value.len() <= 255
            && value
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || b"._-".contains(&byte)),
        "{label} is invalid"
    );
    Ok(())
}

pub(super) fn validate_provider_subject(value: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        !value.trim().is_empty() && value.len() <= 512 && !value.chars().any(char::is_control),
        "OAuth provider subject is invalid"
    );
    Ok(())
}

pub(super) fn validate_callback_url(value: &str) -> anyhow::Result<String> {
    let url = Url::parse(value).map_err(|_| anyhow::anyhow!("OAuth callback URL is invalid"))?;
    anyhow::ensure!(
        url.username().is_empty() && url.password().is_none(),
        "OAuth callback URL is invalid"
    );
    anyhow::ensure!(
        url.query().is_none() && url.fragment().is_none(),
        "OAuth callback URL is invalid"
    );
    anyhow::ensure!(
        matches!(url.scheme(), "http" | "https"),
        "OAuth callback scheme is invalid"
    );
    anyhow::ensure!(
        matches!(url.host_str(), Some("127.0.0.1" | "::1")),
        "OAuth callback must use loopback"
    );
    anyhow::ensure!(
        url.path() == "/oauth/callback",
        "OAuth callback path is invalid"
    );
    Ok(url.to_string())
}

pub(super) fn validate_authorization_origin(value: &str) -> anyhow::Result<String> {
    let url =
        Url::parse(value).map_err(|_| anyhow::anyhow!("OAuth authorization origin is invalid"))?;
    anyhow::ensure!(
        url.scheme() == "https",
        "OAuth authorization origin must use HTTPS"
    );
    anyhow::ensure!(
        url.username().is_empty() && url.password().is_none(),
        "OAuth authorization origin is invalid"
    );
    anyhow::ensure!(
        url.path() == "/" && url.query().is_none() && url.fragment().is_none(),
        "OAuth authorization origin must not include a path"
    );
    Ok(url.origin().ascii_serialization())
}

pub(super) fn secure_provider_authorization_url(
    value: &str,
    expected_origin: &str,
    request: &OAuthAuthorizationUrlRequest,
) -> anyhow::Result<(String, String)> {
    let mut url =
        Url::parse(value).map_err(|_| anyhow::anyhow!("OAuth authorization URL is invalid"))?;
    anyhow::ensure!(
        url.scheme() == "https",
        "OAuth authorization URL must use HTTPS"
    );
    anyhow::ensure!(
        url.username().is_empty() && url.password().is_none(),
        "OAuth authorization URL is invalid"
    );
    anyhow::ensure!(
        url.fragment().is_none(),
        "OAuth authorization URL must not contain a fragment"
    );
    let origin = url.origin().ascii_serialization();
    anyhow::ensure!(
        origin == validate_authorization_origin(expected_origin)?,
        "OAuth authorization URL origin is not allowed"
    );
    const RESERVED: [&str; 6] = [
        "state",
        "redirect_uri",
        "code_challenge",
        "code_challenge_method",
        "response_type",
        "scope",
    ];
    anyhow::ensure!(
        !url.query_pairs()
            .any(|(key, _)| RESERVED.contains(&key.as_ref())),
        "OAuth authorization URL contains reserved parameters"
    );
    url.query_pairs_mut()
        .append_pair("response_type", "code")
        .append_pair("redirect_uri", &request.redirect_uri)
        .append_pair("state", &request.state)
        .append_pair("code_challenge", &request.pkce_challenge)
        .append_pair("code_challenge_method", "S256")
        .append_pair(
            "scope",
            &request.scopes.iter().cloned().collect::<Vec<_>>().join(" "),
        );
    Ok((url.to_string(), origin))
}

pub(super) fn random_hex() -> anyhow::Result<Zeroizing<String>> {
    let mut bytes = Zeroizing::new([0_u8; 32]);
    OsRng
        .try_fill_bytes(bytes.as_mut())
        .map_err(|_| anyhow::anyhow!("system randomness is unavailable"))?;
    Ok(Zeroizing::new(hex::encode(bytes.as_ref())))
}

pub(super) fn provider_account_id(provider_id: &str, provider_subject: &str) -> String {
    let mut hash = Sha256::new();
    hash.update(provider_id.as_bytes());
    hash.update([0]);
    hash.update(provider_subject.as_bytes());
    format!("acct.{}", &hex::encode(hash.finalize())[..24])
}

pub(super) fn callback_error_code(value: &str) -> &'static str {
    match value {
        "access_denied" => "access_denied",
        "interaction_required" => "interaction_required",
        "login_required" => "login_required",
        "temporarily_unavailable" => "provider_temporarily_unavailable",
        _ => "provider_denied",
    }
}

pub(super) fn secret_utf8(material: &SecretMaterial) -> anyhow::Result<OAuthSecretString> {
    let value = std::str::from_utf8(material.expose_bytes())?.to_string();
    OAuthSecretString::new(value)
}
