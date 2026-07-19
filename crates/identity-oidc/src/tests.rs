use super::*;
use agent_runtime::identity::{IdentityProvider, SecurityContext, SecurityContextRequest};
use async_trait::async_trait;
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{DateTime, Duration, TimeZone, Utc};
use jsonwebtoken::{Algorithm, EncodingKey, Header, encode};
use serde::Serialize;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    sync::{Arc, Mutex},
};
use url::Url;

const ISSUER: &str = "https://identity.example.test/";
const AUTHORIZE: &str = "https://identity.example.test/oauth/authorize";
const TOKEN: &str = "https://identity.example.test/oauth/token";
const JWKS: &str = "https://identity.example.test/.well-known/jwks.json";
const REVOKE: &str = "https://identity.example.test/oauth/revoke";
const END_SESSION: &str = "https://identity.example.test/oidc/logout";
const REDIRECT: &str = "com.example.agent:/oauth/callback";
const CLIENT_ID: &str = "native-client-id";
const AUDIENCE: &str = "https://gateway.example.test";
const PROVIDER_ID: &str = "agentweave.identity.oidc";
const KEY_ID: &str = "test-key-1";
const RSA_N: &str = "rEsC4DTyWMEzy0c2Tx1WGC_ZDnhv_fmwAXEVMxEzPCRx-ntpAB7nrmKvOp8s-haIQ8bBPlhjVgF75msuYTDX6DhZ94MXWBGUwkYpj3awYZ7LnzJcOjwqyLspKcKxmLi0GJEiVDdY_CI8cjTl6oSBMMvwuCEJZctEwHlbPRYCuqlm4J4zvhR1cfh25k-OlW6Wchn_45ax-ZEgYAkHClat3GziWhoORuGj9xnlJZVt6qaTWV9EZpkfXqY7ttRvmlvrhenpcY1mPfEnaGr_J82acg0DszTcJEgxqDY7ac3CG4nTPUIbWajQTg9mM-4ObIz3rFfMpEnNtDt_cGg1M0xk1w";
const RSA_PRIVATE_KEY: &str = r#"-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEArEsC4DTyWMEzy0c2Tx1WGC/ZDnhv/fmwAXEVMxEzPCRx+ntp
AB7nrmKvOp8s+haIQ8bBPlhjVgF75msuYTDX6DhZ94MXWBGUwkYpj3awYZ7LnzJc
OjwqyLspKcKxmLi0GJEiVDdY/CI8cjTl6oSBMMvwuCEJZctEwHlbPRYCuqlm4J4z
vhR1cfh25k+OlW6Wchn/45ax+ZEgYAkHClat3GziWhoORuGj9xnlJZVt6qaTWV9E
ZpkfXqY7ttRvmlvrhenpcY1mPfEnaGr/J82acg0DszTcJEgxqDY7ac3CG4nTPUIb
WajQTg9mM+4ObIz3rFfMpEnNtDt/cGg1M0xk1wIDAQABAoIBACbsk2u/yniOvXrR
Tc213Pt949XHE9YXENJij92Hp0GRIkbqlqA2WzUkil3+FBUz/fkB8Cp7oYWOtEUs
NcAzXrPR91FZxm5ZGniBjWYh9Fs5mtsOb5OggDH1RqlumNzd7aIXN+A62NmtimZq
2P6QjPdPO8T9gbgDojaxtBEq5dbxi10zRX/sp1bt5oo1rI6rDRXxeZutCNGraEsO
38SjiyJhDsvn7QIbQgtQHDULuKAwx+3B77P0ktKGZabb47TZ6zFcR2rOKAIduzxs
kFNT6YeUG9tA/7ewm/o05usm+LBqTHjR2csWUX9bKvAe0DlBYm1FE44L7RH1+UiI
uYFnsaECgYEA48taa7nY8MzGDAlFo+fRAGoGf5OJtB6UkXtw5Et+y9mUV5jw8sad
HwLmLsYp1whdZvvMW7APDbwFUcPpR4jP/4RX9wFTzrZjfJ1h+DeBLiVkQrjOKai6
rRM/6CA0v0sNSiz3J6LWbk8I4UCpVhGYEMI0GK3UAjZF1xSLK9bwrUkCgYEAwaBf
Fn5nK+szf6T63GP3OSGEjYmDNswlx2O6FF5OZPgWhk/CJS7cQZ2cDN+Tvjz3Y1+4
Xn8ROxzrQlCsqN5N/MFuqVD4tGZKl5BJTKes2ntiQPjLsLUFI0ro9TFbzl3D/4Rx
f64bBsc8SXvmjSDeOP9hakCKa5FFp9TTfdxJIR8CgYEAinZlM+33rAcMquxH5GVY
aUQJRyrLHS0paXT7Hgm1vPs4bDaO30NS5jLA79WMQSTYgWy0v1a5D8QmB5lqBw1m
QQ6U2ZN4+cFrn6eakWJLp10bIGNtDW1+aw20XsiUx2I7ZccHRJR6evqXjzPaunJf
WHBzcjzXDbEnqqDWJ4OzL+ECgYAJL3dzVLnGPpkp1ATGkcN3pVxpbn2YCuU76UI5
lyO27IH9CymVo/x07Gorvit/GdtOjorriLGjkUKj2bnnJOykMfTy+VFjFXsyZ3ji
tw2fK71Egcj/8AZ3XyVgBGBrkM0sgPb1bKgBkVAN2F/ekBGauJrBdKBca/7W8GS8
EsgxVwKBgFBwdljCYbjtUbN86hbHfHifocI/eeF9rHvO2oRlGTJe48Zo2lynP5h2
F6FPCv0CsSY9PDA0MnvE6xkkC+28HtqrqQMUp6pS0BPtD5iFie3KYf6fCcihRgb+
NYZM3I1I0tRjBe0rl7KMeOkj1fpSDxjgCvqHWLdCDFbszJV+bgb6
-----END RSA PRIVATE KEY-----"#;

struct CapturedRequest {
    method: OidcHttpMethod,
    url: Url,
    form: BTreeMap<String, String>,
}

#[derive(Default)]
struct FakeHttp {
    responses: tokio::sync::Mutex<VecDeque<OidcHttpResponse>>,
    requests: tokio::sync::Mutex<Vec<CapturedRequest>>,
}

impl FakeHttp {
    async fn push_json(&self, status: u16, url: &str, value: serde_json::Value) {
        self.responses.lock().await.push_back(OidcHttpResponse::new(
            status,
            Url::parse(url).unwrap(),
            serde_json::to_vec(&value).unwrap(),
        ));
    }

    async fn push_empty(&self, status: u16, url: &str) {
        self.responses.lock().await.push_back(OidcHttpResponse::new(
            status,
            Url::parse(url).unwrap(),
            Vec::new(),
        ));
    }

    async fn request_count(&self) -> usize {
        self.requests.lock().await.len()
    }
}

#[async_trait]
impl OidcHttpClient for FakeHttp {
    async fn send(
        &self,
        request: OidcHttpRequest,
    ) -> std::result::Result<OidcHttpResponse, OidcHttpError> {
        let form = request
            .form_field_names()
            .map(|name| {
                (
                    name.to_owned(),
                    request
                        .form_value(name)
                        .expect("named form field")
                        .to_owned(),
                )
            })
            .collect();
        self.requests.lock().await.push(CapturedRequest {
            method: request.method(),
            url: request.url().clone(),
            form,
        });
        self.responses.lock().await.pop_front().ok_or(OidcHttpError)
    }
}

struct FakeClock(Mutex<DateTime<Utc>>);

impl FakeClock {
    fn new(now: DateTime<Utc>) -> Self {
        Self(Mutex::new(now))
    }

    fn advance(&self, duration: Duration) {
        let mut now = self.0.lock().unwrap();
        *now += duration;
    }
}

impl OidcClock for FakeClock {
    fn now(&self) -> DateTime<Utc> {
        *self.0.lock().unwrap()
    }
}

#[derive(Default)]
struct DeterministicRandom(Mutex<u64>);

impl SecureRandom for DeterministicRandom {
    fn fill(&self, destination: &mut [u8]) -> Result<()> {
        let mut counter = self.0.lock().unwrap();
        for chunk in destination.chunks_mut(32) {
            *counter += 1;
            let block = Sha256::digest(counter.to_be_bytes());
            chunk.copy_from_slice(&block[..chunk.len()]);
        }
        Ok(())
    }
}

#[derive(Serialize)]
struct TestClaims<'a> {
    iss: &'a str,
    sub: &'a str,
    aud: &'a str,
    exp: i64,
    iat: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    nbf: Option<i64>,
    nonce: &'a str,
}

fn now() -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 7, 19, 12, 0, 0).unwrap()
}

fn public_config() -> OidcPublicConfig {
    OidcPublicConfig {
        issuer: Url::parse(ISSUER).unwrap(),
        client_id: CLIENT_ID.into(),
        audience: AUDIENCE.into(),
        scopes: BTreeSet::from([
            "model.invoke".into(),
            "offline_access".into(),
            "openid".into(),
        ]),
        redirect_uri: Url::parse(REDIRECT).unwrap(),
    }
}

fn plugin_public_config(preset: &str) -> OidcPluginPublicConfig {
    serde_json::from_value(json!({
        "preset": preset,
        "issuer": ISSUER,
        "clientId": CLIENT_ID,
        "audience": AUDIENCE,
        "scopes": ["openid", "offline_access", "model.invoke"],
        "redirectUri": REDIRECT,
        "gatewayAlgorithm": "RS256",
        "gatewayTenantClaim": "organization.id",
        "gatewayDeviceMode": "disabled",
        "gatewayRequireNbf": true
    }))
    .unwrap()
}

fn security_request() -> SecurityContextRequest {
    SecurityContextRequest {
        app_id: "com.example.agent".into(),
        tenant_id: "tenant-1".into(),
        audience: AUDIENCE.into(),
        required_scopes: BTreeSet::from(["model.invoke".into()]),
    }
}

fn discovery_document() -> serde_json::Value {
    json!({
        "issuer": ISSUER,
        "authorization_endpoint": AUTHORIZE,
        "token_endpoint": TOKEN,
        "jwks_uri": JWKS,
        "revocation_endpoint": REVOKE,
        "end_session_endpoint": END_SESSION,
        "code_challenge_methods_supported": ["S256"],
        "id_token_signing_alg_values_supported": ["RS256"]
    })
}

fn jwks() -> serde_json::Value {
    json!({
        "keys": [{
            "kty": "RSA",
            "kid": KEY_ID,
            "alg": "RS256",
            "use": "sig",
            "n": RSA_N,
            "e": "AQAB"
        }]
    })
}

fn signed_id_token(nonce: &str, clock: DateTime<Utc>) -> String {
    signed_id_token_with(nonce, clock, |_, _| {})
}

fn signed_id_token_with(
    nonce: &str,
    clock: DateTime<Utc>,
    mutate: impl FnOnce(&mut Header, &mut TestClaims<'_>),
) -> String {
    let mut header = Header::new(Algorithm::RS256);
    header.kid = Some(KEY_ID.into());
    let mut claims = TestClaims {
        iss: ISSUER,
        sub: "user-42",
        aud: CLIENT_ID,
        exp: (clock + Duration::hours(1)).timestamp(),
        iat: (clock - Duration::minutes(1)).timestamp(),
        nbf: None,
        nonce,
    };
    mutate(&mut header, &mut claims);
    encode(
        &header,
        &claims,
        &EncodingKey::from_rsa_pem(RSA_PRIVATE_KEY.as_bytes()).unwrap(),
    )
    .unwrap()
}

async fn make_provider(
    preset: OidcPresetId,
) -> (
    Arc<GenericOidcProvider>,
    Arc<FakeHttp>,
    Arc<InMemoryOidcSecretStore>,
    Arc<FakeClock>,
) {
    let http = Arc::new(FakeHttp::default());
    let discovery_url = public_config().discovery_url().unwrap();
    http.push_json(200, discovery_url.as_str(), discovery_document())
        .await;
    let store = Arc::new(InMemoryOidcSecretStore::default());
    let clock = Arc::new(FakeClock::new(now()));
    let provider = GenericOidcProvider::discover_with(
        PROVIDER_ID,
        public_config(),
        preset,
        http.clone(),
        store.clone(),
        clock.clone(),
        Arc::new(DeterministicRandom::default()),
    )
    .await
    .unwrap();
    (Arc::new(provider), http, store, clock)
}

fn authorization_parameters(request: &AuthorizationRequest) -> BTreeMap<String, String> {
    request
        .url()
        .query_pairs()
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect()
}

fn callback_url(state: &str) -> Url {
    let mut callback = Url::parse(REDIRECT).unwrap();
    callback
        .query_pairs_mut()
        .append_pair("code", "authorization-code-sentinel")
        .append_pair("state", state)
        .append_pair("iss", ISSUER);
    callback
}

async fn queue_login(
    http: &FakeHttp,
    nonce: &str,
    clock: DateTime<Utc>,
    access: &str,
    refresh: &str,
) {
    http.push_json(
        200,
        TOKEN,
        json!({
            "access_token": access,
            "refresh_token": refresh,
            "id_token": signed_id_token(nonce, clock),
            "token_type": "Bearer",
            "expires_in": 3600,
            "scope": "openid offline_access model.invoke"
        }),
    )
    .await;
    http.push_json(200, JWKS, jwks()).await;
}

async fn login(
    provider: &GenericOidcProvider,
    http: &FakeHttp,
    clock: DateTime<Utc>,
) -> (SecurityContext, BTreeMap<String, String>) {
    let authorization = provider
        .begin_authorization(&security_request())
        .await
        .unwrap();
    let parameters = authorization_parameters(&authorization);
    queue_login(
        http,
        &parameters["nonce"],
        clock,
        "opaque-access-token-sentinel",
        "refresh-token-generation-1",
    )
    .await;
    let context = provider
        .complete_authorization_url(&callback_url(&parameters["state"]))
        .await
        .unwrap();
    (context, parameters)
}

#[test]
fn public_config_and_presets_are_strict_and_data_only() {
    public_config().validate().unwrap();
    let encoded = serde_json::to_value(public_config()).unwrap();
    assert_eq!(encoded.as_object().unwrap().len(), 5);
    for forbidden in ["clientSecret", "apiKey", "accessToken", "refreshToken"] {
        assert!(encoded.get(forbidden).is_none());
    }
    let mut unknown = encoded;
    unknown["clientSecret"] = json!("must-not-parse");
    assert!(serde_json::from_value::<OidcPublicConfig>(unknown).is_err());

    let mut insecure = public_config();
    insecure.issuer = Url::parse("http://identity.example.test").unwrap();
    assert_eq!(insecure.validate(), Err(OidcError::InvalidConfiguration));
    let mut loopback = public_config();
    loopback.issuer = Url::parse("http://127.0.0.1:5555/oidc").unwrap();
    assert!(loopback.validate().is_ok());

    assert_eq!(OIDC_PRESETS.len(), 5);
    let cloudflare = oidc_preset(OidcPresetId::CloudflareAccess);
    assert_eq!(
        cloudflare.resource_parameter,
        ResourceParameter::Rfc8707AuthorizationAndToken
    );
    assert_eq!(
        cloudflare.access_token_representation,
        AccessTokenRepresentation::Opaque
    );
    let edge = cloudflare.edge_assertion.unwrap();
    assert_eq!(edge.header_name, "Cf-Access-Jwt-Assertion");
    assert!(!edge.is_access_token);
    assert!(edge.verified_by_gateway_edge);
}

#[tokio::test]
async fn gateway_verifier_is_discovered_without_exposing_login_or_secret_state() {
    let http = FakeHttp::default();
    http.push_json(
        200,
        public_config().discovery_url().unwrap().as_str(),
        discovery_document(),
    )
    .await;

    let projection = discover_gateway_verifier(&plugin_public_config("auth0"), &http)
        .await
        .unwrap();

    assert_eq!(projection.kind, GatewayIdentityKind::Oidc);
    assert_eq!(projection.issuer, ISSUER);
    assert_eq!(projection.jwks_url, JWKS);
    assert_eq!(projection.algorithm, "RS256");
    assert_eq!(projection.header, "authorization");
    assert_eq!(
        projection.projection.tenant_claim.as_deref(),
        Some("organization.id")
    );
    let encoded = serde_json::to_string(&projection).unwrap();
    assert!(!encoded.contains("clientId"));
    assert!(!encoded.contains("redirectUri"));
    assert!(!encoded.contains("offline_access"));
}

#[tokio::test]
async fn cloudflare_access_gateway_projection_uses_only_the_edge_assertion() {
    let http = FakeHttp::default();
    http.push_json(
        200,
        public_config().discovery_url().unwrap().as_str(),
        discovery_document(),
    )
    .await;

    let projection = discover_gateway_verifier(&plugin_public_config("cloudflare_access"), &http)
        .await
        .unwrap();

    assert_eq!(projection.kind, GatewayIdentityKind::CloudflareAccess);
    assert_eq!(projection.header, "cf-access-jwt-assertion");
}

#[tokio::test]
async fn authorization_uses_pkce_and_yields_only_verified_context() {
    let (provider, http, store, clock) = make_provider(OidcPresetId::CloudflareAccess).await;
    let authorization = provider
        .begin_authorization(&security_request())
        .await
        .unwrap();
    assert!(!format!("{authorization:?}").contains("state="));
    let parameters = authorization_parameters(&authorization);
    assert_eq!(parameters["response_type"], "code");
    assert_eq!(parameters["code_challenge_method"], "S256");
    assert_eq!(parameters["resource"], AUDIENCE);
    assert!(!parameters.contains_key("client_secret"));
    let account_switch = provider
        .begin_authorization_with_prompt(
            &security_request(),
            Some(AuthorizationPrompt::SelectAccount),
        )
        .await
        .unwrap();
    assert_eq!(
        authorization_parameters(&account_switch)["prompt"],
        "select_account"
    );

    let mut wrong_redirect = callback_url(&parameters["state"]);
    wrong_redirect.set_path("/different/callback");
    assert_eq!(
        provider.complete_authorization_url(&wrong_redirect).await,
        Err(OidcError::InvalidAuthorization)
    );
    queue_login(
        &http,
        &parameters["nonce"],
        clock.now(),
        "opaque-access-token-sentinel",
        "refresh-token-generation-1",
    )
    .await;
    let callback = callback_url(&parameters["state"]);
    let context = provider
        .complete_authorization_url(&callback)
        .await
        .unwrap();
    assert_eq!(context.provider_id, PROVIDER_ID);
    assert_eq!(context.principal.issuer, ISSUER);
    assert_eq!(context.principal.subject, "user-42");
    assert_eq!(context.audience, AUDIENCE);
    assert!(
        !serde_json::to_string(&context)
            .unwrap()
            .contains("sentinel")
    );
    let assertion = provider
        .access_assertion(&security_request())
        .await
        .unwrap();
    assert_eq!(assertion.expose_secret(), "opaque-access-token-sentinel");
    assert!(!format!("{assertion:?}").contains("sentinel"));

    let requests = http.requests.lock().await;
    assert_eq!(requests[1].method, OidcHttpMethod::PostForm);
    assert_eq!(requests[1].url.as_str(), TOKEN);
    let verifier = &requests[1].form["code_verifier"];
    let derived = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    assert_eq!(derived, parameters["code_challenge"]);
    assert_eq!(requests[1].form["resource"], AUDIENCE);
    assert!(!requests[1].form.contains_key("client_secret"));
    drop(requests);

    let binding = SessionBinding::new(PROVIDER_ID, "com.example.agent", "tenant-1", AUDIENCE);
    let lease = store.lease_session(&binding).await.unwrap().unwrap();
    let debug = format!("{:?}", lease.session().secrets());
    assert!(!debug.contains("opaque-access-token-sentinel"));
    assert!(!debug.contains("refresh-token-generation-1"));
    store.release_session(lease).await.unwrap();

    let before_replay = http.request_count().await;
    assert_eq!(
        provider.complete_authorization_url(&callback).await,
        Err(OidcError::InvalidAuthorization)
    );
    assert_eq!(http.request_count().await, before_replay);
    assert_eq!(
        principal_scope_id(PROVIDER_ID, ISSUER, "user-42").unwrap(),
        principal_scope_id(PROVIDER_ID, ISSUER, "user-42").unwrap()
    );
}

#[tokio::test]
async fn authorization_state_is_atomic_under_concurrency() {
    let (provider, http, _, clock) = make_provider(OidcPresetId::Generic).await;
    let authorization = provider
        .begin_authorization(&security_request())
        .await
        .unwrap();
    let parameters = authorization_parameters(&authorization);
    queue_login(
        &http,
        &parameters["nonce"],
        clock.now(),
        "opaque-access-token-sentinel",
        "refresh-token-generation-1",
    )
    .await;
    let callback = callback_url(&parameters["state"]);
    let (first, second) = tokio::join!(
        provider.complete_authorization_url(&callback),
        provider.complete_authorization_url(&callback)
    );
    assert_eq!(usize::from(first.is_ok()) + usize::from(second.is_ok()), 1);
    assert_eq!(
        usize::from(first == Err(OidcError::InvalidAuthorization))
            + usize::from(second == Err(OidcError::InvalidAuthorization)),
        1
    );
}

#[tokio::test]
async fn expired_authorization_state_is_consumed_without_network_use() {
    let (provider, http, _, clock) = make_provider(OidcPresetId::Generic).await;
    let authorization = provider
        .begin_authorization(&security_request())
        .await
        .unwrap();
    let parameters = authorization_parameters(&authorization);
    let requests_before_callback = http.request_count().await;
    clock.advance(Duration::minutes(11));
    let callback = callback_url(&parameters["state"]);
    assert_eq!(
        provider.complete_authorization_url(&callback).await,
        Err(OidcError::InvalidAuthorization)
    );
    assert_eq!(http.request_count().await, requests_before_callback);
    assert_eq!(
        provider.complete_authorization_url(&callback).await,
        Err(OidcError::InvalidAuthorization)
    );
}

#[tokio::test]
async fn refresh_rotates_tokens_atomically_and_blocks_concurrent_updates() {
    let (provider, http, store, clock) = make_provider(OidcPresetId::Generic).await;
    let (original, _) = login(&provider, &http, clock.now()).await;
    clock.advance(Duration::hours(2));
    http.push_json(
        200,
        TOKEN,
        json!({
            "access_token": "opaque-access-token-generation-2",
            "refresh_token": "refresh-token-generation-2",
            "token_type": "Bearer",
            "expires_in": 3600,
            "scope": "openid offline_access model.invoke"
        }),
    )
    .await;
    let refreshed = provider
        .security_context(&security_request())
        .await
        .unwrap();
    assert!(refreshed.expires_at > original.expires_at);
    let requests = http.requests.lock().await;
    let refresh_request = requests.last().unwrap();
    assert_eq!(
        refresh_request.form["refresh_token"],
        "refresh-token-generation-1"
    );
    assert_eq!(refresh_request.form["resource"], AUDIENCE);
    drop(requests);

    let binding = SessionBinding::new(PROVIDER_ID, "com.example.agent", "tenant-1", AUDIENCE);
    let lease = store.lease_session(&binding).await.unwrap().unwrap();
    assert_eq!(
        lease
            .session()
            .secrets()
            .refresh_token()
            .unwrap()
            .expose_secret(),
        "refresh-token-generation-2"
    );
    assert_eq!(
        provider.refresh(&security_request()).await,
        Err(OidcError::SessionBusy)
    );
    store.release_session(lease).await.unwrap();

    http.push_json(
        400,
        TOKEN,
        json!({
            "error": "invalid_grant",
            "error_description": "upstream-secret-sentinel"
        }),
    )
    .await;
    let error = provider.refresh(&security_request()).await.unwrap_err();
    assert_eq!(error, OidcError::AccessDenied);
    assert!(!error.to_string().contains("upstream-secret-sentinel"));
    assert!(store.session_metadata(&binding).await.unwrap().is_none());
}

#[tokio::test]
async fn logout_revokes_both_tokens_without_putting_them_in_the_browser_url() {
    let (provider, http, store, clock) = make_provider(OidcPresetId::Auth0).await;
    login(&provider, &http, clock.now()).await;
    http.push_empty(200, REVOKE).await;
    http.push_empty(204, REVOKE).await;
    let outcome = provider.logout(&security_request()).await.unwrap();
    assert_eq!(outcome.remote_revocation, RemoteRevocation::Succeeded);
    let logout_url = outcome.end_session_url.unwrap();
    assert_eq!(logout_url.query_pairs().count(), 1);
    assert_eq!(logout_url.query_pairs().next().unwrap().0, "client_id");
    assert!(!logout_url.as_str().contains("token"));

    let requests = http.requests.lock().await;
    let revocations = &requests[requests.len() - 2..];
    assert_eq!(revocations[0].form["token"], "refresh-token-generation-1");
    assert_eq!(revocations[1].form["token"], "opaque-access-token-sentinel");
    drop(requests);
    let binding = SessionBinding::new(PROVIDER_ID, "com.example.agent", "tenant-1", AUDIENCE);
    assert!(store.session_metadata(&binding).await.unwrap().is_none());
}

#[tokio::test]
async fn discovery_rejects_cross_origin_endpoints_and_redirects() {
    let http = Arc::new(FakeHttp::default());
    let mut malicious = discovery_document();
    malicious["token_endpoint"] = json!("https://attacker.example/oauth/token");
    let discovery_url = public_config().discovery_url().unwrap().to_string();
    http.push_json(200, &discovery_url, malicious).await;
    let result = GenericOidcProvider::discover_with(
        PROVIDER_ID,
        public_config(),
        OidcPresetId::Generic,
        http,
        Arc::new(InMemoryOidcSecretStore::default()),
        Arc::new(FakeClock::new(now())),
        Arc::new(DeterministicRandom::default()),
    )
    .await;
    assert!(matches!(result, Err(OidcError::InvalidProviderResponse)));

    let redirected = Arc::new(FakeHttp::default());
    redirected
        .push_json(
            200,
            "https://attacker.example/.well-known/openid-configuration",
            discovery_document(),
        )
        .await;
    let result = GenericOidcProvider::discover_with(
        PROVIDER_ID,
        public_config(),
        OidcPresetId::Generic,
        redirected,
        Arc::new(InMemoryOidcSecretStore::default()),
        Arc::new(FakeClock::new(now())),
        Arc::new(DeterministicRandom::default()),
    )
    .await;
    assert!(matches!(result, Err(OidcError::InvalidProviderResponse)));
}

#[tokio::test]
async fn id_token_checks_nonce_audience_time_kid_and_signature() {
    enum InvalidCase {
        Nonce,
        Audience,
        Expired,
        NotBefore,
        Kid,
        Signature,
    }
    for case in [
        InvalidCase::Nonce,
        InvalidCase::Audience,
        InvalidCase::Expired,
        InvalidCase::NotBefore,
        InvalidCase::Kid,
        InvalidCase::Signature,
    ] {
        let (provider, http, _, clock) = make_provider(OidcPresetId::Generic).await;
        let authorization = provider
            .begin_authorization(&security_request())
            .await
            .unwrap();
        let parameters = authorization_parameters(&authorization);
        let expected_nonce = parameters["nonce"].as_str();
        let nonce = if matches!(case, InvalidCase::Nonce) {
            "wrong-nonce"
        } else {
            expected_nonce
        };
        let mut compact = signed_id_token_with(nonce, clock.now(), |header, claims| match case {
            InvalidCase::Audience => claims.aud = "different-client",
            InvalidCase::Expired => {
                claims.iat = (clock.now() - Duration::hours(2)).timestamp();
                claims.exp = (clock.now() - Duration::minutes(2)).timestamp();
            }
            InvalidCase::NotBefore => {
                claims.nbf = Some((clock.now() + Duration::minutes(2)).timestamp())
            }
            InvalidCase::Kid => header.kid = Some("untrusted-key".into()),
            _ => {}
        });
        if matches!(case, InvalidCase::Signature) {
            let last = compact.pop().unwrap();
            compact.push(if last == 'A' { 'B' } else { 'A' });
        }
        http.push_json(
            200,
            TOKEN,
            json!({
                "access_token": "opaque-access-token-sentinel",
                "refresh_token": "refresh-token-generation-1",
                "id_token": compact,
                "token_type": "Bearer",
                "expires_in": 3600,
                "scope": "openid offline_access model.invoke"
            }),
        )
        .await;
        http.push_json(200, JWKS, jwks()).await;
        let result = provider
            .complete_authorization_url(&callback_url(&parameters["state"]))
            .await;
        assert_eq!(result, Err(OidcError::InvalidProviderResponse));
    }
}

#[test]
fn secret_debug_and_errors_are_redacted() {
    let secret = SecretValue::new("bearer-secret-sentinel");
    assert_eq!(format!("{secret:?}"), "SecretValue([REDACTED])");
    assert!(
        !OidcError::InvalidProviderResponse
            .to_string()
            .contains("sentinel")
    );
}
