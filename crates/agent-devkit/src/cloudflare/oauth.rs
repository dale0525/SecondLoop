use super::{
    CLOUDFLARE_AUTHORIZATION_URL, CLOUDFLARE_TOKEN_URL, CloudflareHttpMethod, CloudflareRestClient,
    CloudflareTransport, CloudflareTransportFailureKind, CloudflareTransportRequest,
    RequestBodySensitivity, secure_origin_url,
};
use crate::{
    AuthorizationCapabilityRequirement, AuthorizationRequirements, DevkitError, DevkitErrorCode,
    DevkitResult, RemoteMutationRisk, SensitiveInputHandle, SensitiveInputStore, SensitiveValue,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
use url::{Host, Url};

const MAX_SCOPE_CATALOG_DEPTH: usize = 8;

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
pub struct CloudflareOAuthScope {
    pub id: String,
    pub authoritative_name: String,
    pub description: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CloudflareOAuthScopeCatalog {
    pub scopes: BTreeSet<CloudflareOAuthScope>,
    pub revision: String,
}

impl CloudflareOAuthScopeCatalog {
    pub fn from_api_result(value: &Value) -> DevkitResult<Self> {
        let mut scopes = BTreeSet::new();
        collect_scope_records(value, 0, &mut scopes)?;
        Self::from_records(scopes)
    }

    pub fn from_records(scopes: BTreeSet<CloudflareOAuthScope>) -> DevkitResult<Self> {
        if scopes.is_empty() {
            return Err(DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare OAuth scope catalog contained no usable scope records",
            ));
        }
        let mut ids = BTreeSet::new();
        for scope in &scopes {
            if scope.id.is_empty()
                || scope.id.len() > 256
                || scope.id.chars().any(char::is_control)
                || scope.authoritative_name.is_empty()
                || scope.authoritative_name.len() > 256
                || scope.authoritative_name.chars().any(char::is_control)
                || !ids.insert(scope.id.as_str())
            {
                return Err(DevkitError::new(
                    DevkitErrorCode::RemoteProtocol,
                    "Cloudflare OAuth scope catalog contains an invalid or duplicate scope",
                ));
            }
        }
        let canonical = serde_json::to_vec(&scopes).map_err(|_| {
            DevkitError::new(
                DevkitErrorCode::Internal,
                "Cloudflare OAuth scope catalog could not be hashed",
            )
        })?;
        let revision = hex::encode(Sha256::digest(canonical));
        Ok(Self { scopes, revision })
    }

    pub fn resolve(
        &self,
        provider_id: &str,
        requirements: &[AuthorizationCapabilityRequirement],
        requested_capabilities: &BTreeSet<String>,
    ) -> DevkitResult<AuthorizationRequirements> {
        let requirements = requirements
            .iter()
            .map(|requirement| (requirement.capability.as_str(), requirement))
            .collect::<BTreeMap<_, _>>();
        let mut scope_ids_by_capability = BTreeMap::new();
        let mut reasons_by_capability = BTreeMap::new();
        for capability in requested_capabilities {
            let requirement = requirements.get(capability.as_str()).ok_or_else(|| {
                DevkitError::new(
                    DevkitErrorCode::Unsupported,
                    format!("unsupported Cloudflare capability: {capability}"),
                )
            })?;
            let scope_ids = self
                .scopes
                .iter()
                .filter(|scope| {
                    requirement
                        .accepted_catalog_names
                        .contains(&scope.authoritative_name)
                })
                .map(|scope| scope.id.clone())
                .collect::<BTreeSet<_>>();
            if scope_ids.is_empty() {
                return Err(DevkitError::new(
                    DevkitErrorCode::PermissionInsufficient,
                    format!("Cloudflare did not advertise a scope for capability: {capability}"),
                ));
            }
            scope_ids_by_capability.insert(capability.clone(), scope_ids);
            reasons_by_capability.insert(capability.clone(), requirement.reason.clone());
        }
        Ok(AuthorizationRequirements {
            provider_id: provider_id.into(),
            catalog_revision: self.revision.clone(),
            scope_ids_by_capability,
            reasons_by_capability,
        })
    }
}

fn collect_scope_records(
    value: &Value,
    depth: usize,
    scopes: &mut BTreeSet<CloudflareOAuthScope>,
) -> DevkitResult<()> {
    if depth > MAX_SCOPE_CATALOG_DEPTH {
        return Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare OAuth scope catalog exceeded the maximum nesting depth",
        ));
    }
    match value {
        Value::Array(values) => {
            for value in values {
                collect_scope_records(value, depth + 1, scopes)?;
            }
        }
        Value::Object(object) => {
            let id = object.get("id").and_then(Value::as_str);
            let name = object
                .get("name")
                .or_else(|| object.get("title"))
                .and_then(Value::as_str);
            if let (Some(id), Some(name)) = (id, name)
                && !id.is_empty()
                && id.len() <= 256
                && !name.is_empty()
                && name.len() <= 256
            {
                scopes.insert(CloudflareOAuthScope {
                    id: id.into(),
                    authoritative_name: name.into(),
                    description: object
                        .get("description")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                });
            }
            for value in object.values() {
                if value.is_array() || value.is_object() {
                    collect_scope_records(value, depth + 1, scopes)?;
                }
            }
        }
        _ => {}
    }
    Ok(())
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CloudflareAuthorizationUrlInput<'a> {
    pub client_id: &'a str,
    pub redirect_uri: &'a Url,
    pub pkce_s256_challenge: &'a str,
    pub state_handle: &'a SensitiveInputHandle,
    pub scope_ids: &'a BTreeSet<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CloudflareTokenExchangeInput<'a> {
    pub client_id: &'a str,
    pub redirect_uri: &'a Url,
    pub code_handle: &'a SensitiveInputHandle,
    pub pkce_verifier_handle: &'a SensitiveInputHandle,
    pub expected_scope_ids: &'a BTreeSet<String>,
    pub now_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StoredCloudflareOAuthGrant {
    pub access_token_handle: SensitiveInputHandle,
    pub refresh_token_handle: Option<SensitiveInputHandle>,
    pub granted_scope_ids: BTreeSet<String>,
    pub expires_at_unix_ms: Option<u64>,
}

pub struct CloudflareOAuthClient<T, S> {
    rest: CloudflareRestClient<T, S>,
    authorization_endpoint: Url,
    token_endpoint: Url,
    transport: Arc<T>,
    store: Arc<S>,
}

impl<T, S> Clone for CloudflareOAuthClient<T, S> {
    fn clone(&self) -> Self {
        Self {
            rest: self.rest.clone(),
            authorization_endpoint: self.authorization_endpoint.clone(),
            token_endpoint: self.token_endpoint.clone(),
            transport: Arc::clone(&self.transport),
            store: Arc::clone(&self.store),
        }
    }
}

impl<T, S> CloudflareOAuthClient<T, S>
where
    T: CloudflareTransport,
    S: SensitiveInputStore,
{
    pub fn new(
        rest: CloudflareRestClient<T, S>,
        transport: Arc<T>,
        store: Arc<S>,
    ) -> DevkitResult<Self> {
        Self::with_endpoints(
            rest,
            CLOUDFLARE_AUTHORIZATION_URL,
            CLOUDFLARE_TOKEN_URL,
            transport,
            store,
        )
    }

    pub fn with_endpoints(
        rest: CloudflareRestClient<T, S>,
        authorization_endpoint: &str,
        token_endpoint: &str,
        transport: Arc<T>,
        store: Arc<S>,
    ) -> DevkitResult<Self> {
        Ok(Self {
            rest,
            authorization_endpoint: secure_origin_url(authorization_endpoint, false)?,
            token_endpoint: secure_origin_url(token_endpoint, false)?,
            transport,
            store,
        })
    }

    pub async fn scope_catalog(
        &self,
        authorization: &crate::DeveloperAuthorization,
    ) -> DevkitResult<CloudflareOAuthScopeCatalog> {
        let result = self
            .rest
            .get_json(Some(authorization), "oauth/scopes")
            .await?;
        CloudflareOAuthScopeCatalog::from_api_result(&result.value)
    }

    pub async fn authorization_url(
        &self,
        input: CloudflareAuthorizationUrlInput<'_>,
    ) -> DevkitResult<Url> {
        validate_oauth_input(
            input.client_id,
            input.redirect_uri,
            input.pkce_s256_challenge,
        )?;
        if input.scope_ids.is_empty() {
            return Err(DevkitError::invalid_configuration(
                "Cloudflare OAuth requires at least one scope",
            ));
        }
        let state = self.store.resolve(input.state_handle).await?;
        let mut url = self.authorization_endpoint.clone();
        state.expose(|state| {
            let state = std::str::from_utf8(state).map_err(|_| {
                DevkitError::new(
                    DevkitErrorCode::SensitiveInputUnavailable,
                    "OAuth state is not valid UTF-8",
                )
            })?;
            if state.len() < 32 || state.len() > 512 {
                return Err(DevkitError::invalid_configuration(
                    "OAuth state has an invalid size",
                ));
            }
            url.query_pairs_mut()
                .append_pair("response_type", "code")
                .append_pair("client_id", input.client_id)
                .append_pair("redirect_uri", input.redirect_uri.as_str())
                .append_pair(
                    "scope",
                    &input
                        .scope_ids
                        .iter()
                        .cloned()
                        .collect::<Vec<_>>()
                        .join(" "),
                )
                .append_pair("state", state)
                .append_pair("code_challenge", input.pkce_s256_challenge)
                .append_pair("code_challenge_method", "S256");
            Ok(())
        })?;
        Ok(url)
    }

    pub async fn exchange_code(
        &self,
        input: CloudflareTokenExchangeInput<'_>,
    ) -> DevkitResult<StoredCloudflareOAuthGrant> {
        validate_oauth_input(input.client_id, input.redirect_uri, "placeholder")?;
        if input.expected_scope_ids.is_empty() {
            return Err(DevkitError::invalid_configuration(
                "expected Cloudflare OAuth scopes are required",
            ));
        }
        let code = self.store.resolve(input.code_handle).await?;
        let verifier = self.store.resolve(input.pkce_verifier_handle).await?;
        let body = code.expose(|code| {
            verifier.expose(|verifier| {
                let code = std::str::from_utf8(code).map_err(|_| {
                    DevkitError::new(
                        DevkitErrorCode::SensitiveInputUnavailable,
                        "OAuth code is not valid UTF-8",
                    )
                })?;
                let verifier = std::str::from_utf8(verifier).map_err(|_| {
                    DevkitError::new(
                        DevkitErrorCode::SensitiveInputUnavailable,
                        "PKCE verifier is not valid UTF-8",
                    )
                })?;
                if verifier.len() < 43 || verifier.len() > 128 {
                    return Err(DevkitError::invalid_configuration(
                        "PKCE verifier has an invalid size",
                    ));
                }
                Ok(url::form_urlencoded::Serializer::new(String::new())
                    .append_pair("grant_type", "authorization_code")
                    .append_pair("client_id", input.client_id)
                    .append_pair("redirect_uri", input.redirect_uri.as_str())
                    .append_pair("code", code)
                    .append_pair("code_verifier", verifier)
                    .finish()
                    .into_bytes())
            })
        })?;
        let request = CloudflareTransportRequest::new(
            CloudflareHttpMethod::Post,
            self.token_endpoint.clone(),
            BTreeMap::from([
                ("accept".into(), "application/json".into()),
                (
                    "content-type".into(),
                    "application/x-www-form-urlencoded".into(),
                ),
            ]),
            body,
            RequestBodySensitivity::Sensitive,
        );
        let response = self.transport.send(request).await.map_err(|failure| {
            let (code, message) = match failure.kind {
                CloudflareTransportFailureKind::Timeout => (
                    DevkitErrorCode::Timeout,
                    "Cloudflare OAuth request timed out",
                ),
                CloudflareTransportFailureKind::Connect | CloudflareTransportFailureKind::Tls => (
                    DevkitErrorCode::Unavailable,
                    "Cloudflare OAuth connection failed",
                ),
                CloudflareTransportFailureKind::Protocol => (
                    DevkitErrorCode::RemoteProtocol,
                    "Cloudflare OAuth transport failed",
                ),
            };
            DevkitError::new(code, message).with_remote_mutation_risk(RemoteMutationRisk::None)
        })?;
        if (300..400).contains(&response.status()) {
            return Err(DevkitError::new(
                DevkitErrorCode::RedirectRejected,
                "Cloudflare OAuth redirects are not permitted during token exchange",
            ));
        }
        if response.status() == 429 {
            let wait = response
                .header("retry-after")
                .and_then(|value| value.parse::<u64>().ok())
                .unwrap_or(1)
                .saturating_mul(1_000)
                .min(86_400_000);
            return Err(DevkitError::new(
                DevkitErrorCode::RateLimited,
                "Cloudflare OAuth rate limit was reached",
            )
            .retry_after(wait));
        }
        if !(200..300).contains(&response.status()) {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "Cloudflare OAuth code exchange was rejected",
            ));
        }
        let token: OAuthTokenResponse = serde_json::from_slice(response.body()).map_err(|_| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare OAuth returned an invalid token response",
            )
        })?;
        if !token.token_type.eq_ignore_ascii_case("bearer") {
            return Err(DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare OAuth returned an unsupported token type",
            ));
        }
        let mut granted_scope_ids = token.scope.into_set();
        if granted_scope_ids.is_empty() {
            granted_scope_ids.clone_from(input.expected_scope_ids);
        }
        if !input.expected_scope_ids.is_subset(&granted_scope_ids) {
            return Err(DevkitError::new(
                DevkitErrorCode::PermissionInsufficient,
                "Cloudflare OAuth did not grant all requested scopes",
            ));
        }
        let access_token_handle = self
            .store
            .store(
                "cloudflare/oauth/access-token",
                SensitiveValue::new(token.access_token.into_bytes())?,
            )
            .await?;
        let refresh_token_handle = match token.refresh_token {
            Some(refresh_token) => Some(
                self.store
                    .store(
                        "cloudflare/oauth/refresh-token",
                        SensitiveValue::new(refresh_token.into_bytes())?,
                    )
                    .await?,
            ),
            None => None,
        };
        Ok(StoredCloudflareOAuthGrant {
            access_token_handle,
            refresh_token_handle,
            granted_scope_ids,
            expires_at_unix_ms: token.expires_in.map(|seconds| {
                input
                    .now_unix_ms
                    .saturating_add(seconds.saturating_mul(1_000))
            }),
        })
    }
}

fn validate_oauth_input(client_id: &str, redirect_uri: &Url, challenge: &str) -> DevkitResult<()> {
    if client_id.is_empty() || client_id.len() > 2048 || client_id.chars().any(char::is_control) {
        return Err(DevkitError::invalid_configuration(
            "Cloudflare OAuth client is invalid",
        ));
    }
    validate_cloudflare_redirect_uri(redirect_uri)?;
    if challenge != "placeholder"
        && (challenge.len() < 43
            || challenge.len() > 128
            || !challenge
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_'))
    {
        return Err(DevkitError::invalid_configuration(
            "Cloudflare OAuth PKCE S256 challenge is invalid",
        ));
    }
    Ok(())
}

pub(crate) fn validate_cloudflare_redirect_uri(redirect_uri: &Url) -> DevkitResult<()> {
    let common_valid = redirect_uri.host_str().is_some()
        && redirect_uri.username().is_empty()
        && redirect_uri.password().is_none()
        && redirect_uri.query().is_none()
        && redirect_uri.fragment().is_none();
    let https = redirect_uri.scheme() == "https";
    let fixed_loopback = redirect_uri.scheme() == "http"
        && redirect_uri.port().is_some()
        && redirect_uri.path() != "/"
        && !redirect_uri.path().is_empty()
        && redirect_uri.host().is_some_and(|host| match host {
            Host::Ipv4(address) => address.is_loopback(),
            Host::Ipv6(address) => address.is_loopback(),
            Host::Domain(_) => false,
        });
    if common_valid && (https || fixed_loopback) {
        Ok(())
    } else {
        Err(DevkitError::invalid_configuration(
            "Cloudflare OAuth redirect URI must be credential-free HTTPS or a fixed loopback HTTP URL",
        ))
    }
}

#[derive(Deserialize)]
struct OAuthTokenResponse {
    access_token: String,
    token_type: String,
    #[serde(default)]
    refresh_token: Option<String>,
    #[serde(default)]
    expires_in: Option<u64>,
    #[serde(default)]
    scope: OAuthScopeGrant,
}

#[derive(Default, Deserialize)]
#[serde(untagged)]
enum OAuthScopeGrant {
    String(String),
    List(Vec<String>),
    #[default]
    Missing,
}

impl OAuthScopeGrant {
    fn into_set(self) -> BTreeSet<String> {
        match self {
            Self::String(scopes) => scopes.split_whitespace().map(str::to_owned).collect(),
            Self::List(scopes) => scopes.into_iter().collect(),
            Self::Missing => BTreeSet::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn nested_scope(depth: usize) -> Value {
        let mut value = json!({"id": "scope-read", "name": "Workers Scripts Read"});
        for _ in 0..depth {
            value = json!({"nested": value});
        }
        value
    }

    #[test]
    fn scope_catalog_accepts_the_depth_boundary() {
        let catalog =
            CloudflareOAuthScopeCatalog::from_api_result(&nested_scope(MAX_SCOPE_CATALOG_DEPTH))
                .unwrap();

        assert_eq!(catalog.scopes.len(), 1);
    }

    #[test]
    fn scope_catalog_fails_closed_beyond_the_depth_boundary() {
        let error = CloudflareOAuthScopeCatalog::from_api_result(&nested_scope(
            MAX_SCOPE_CATALOG_DEPTH + 1,
        ))
        .unwrap_err();

        assert_eq!(error.code, DevkitErrorCode::RemoteProtocol);
        assert!(error.safe_message.contains("maximum nesting depth"));
    }
}
