use agent_runtime::credential::SecretMaterial;
use agent_runtime::oauth::{
    OAuthAuthorizationPlan, OAuthAuthorizationUrlRequest, OAuthCodeExchangeRequest, OAuthProvider,
    OAuthProviderError, OAuthProviderErrorCode, OAuthRefreshRequest, OAuthTokenGrant,
};
use async_trait::async_trait;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{Duration, Utc};
use reqwest::Url;
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};
use std::time::Duration as StdDuration;

pub const GOOGLE_PROVIDER_ID: &str = "google-workspace";
pub const MICROSOFT_PROVIDER_ID: &str = "microsoft-graph";

pub struct WorkspaceOAuthProvider {
    provider_id: String,
    authorization_origin: String,
    authorization_endpoint: Url,
    token_endpoint: Url,
    userinfo_endpoint: Url,
    client_id: String,
    client_secret: Option<SecretMaterial>,
    connector_scopes: BTreeMap<String, BTreeSet<String>>,
    capability_scopes: BTreeMap<String, BTreeSet<String>>,
    authorization_parameters: BTreeMap<String, String>,
    client: reqwest::Client,
}

impl WorkspaceOAuthProvider {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        provider_id: impl Into<String>,
        authorization_endpoint: &str,
        token_endpoint: &str,
        userinfo_endpoint: &str,
        client_id: impl Into<String>,
        client_secret: Option<SecretMaterial>,
        connector_scopes: BTreeMap<String, BTreeSet<String>>,
        capability_scopes: BTreeMap<String, BTreeSet<String>>,
        authorization_parameters: BTreeMap<String, String>,
    ) -> anyhow::Result<Self> {
        let provider_id = provider_id.into();
        let client_id = client_id.into();
        anyhow::ensure!(
            !provider_id.trim().is_empty() && provider_id.len() <= 64,
            "OAuth provider id is invalid"
        );
        anyhow::ensure!(
            !client_id.trim().is_empty() && client_id.len() <= 2048,
            "OAuth client id is invalid"
        );
        anyhow::ensure!(
            !connector_scopes.is_empty(),
            "OAuth connector scopes are required"
        );
        let authorization_endpoint = secure_url(authorization_endpoint)?;
        let token_endpoint = secure_url(token_endpoint)?;
        let userinfo_endpoint = secure_url(userinfo_endpoint)?;
        let authorization_origin = authorization_endpoint.origin().ascii_serialization();
        Ok(Self {
            provider_id,
            authorization_origin,
            authorization_endpoint,
            token_endpoint,
            userinfo_endpoint,
            client_id,
            client_secret,
            connector_scopes,
            capability_scopes,
            authorization_parameters,
            client: reqwest::Client::builder()
                .timeout(StdDuration::from_secs(30))
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
        })
    }

    pub fn google(
        client_id: impl Into<String>,
        client_secret: Option<SecretMaterial>,
    ) -> anyhow::Result<Self> {
        let connector_scopes = BTreeMap::from([
            (
                agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID.into(),
                scopes(&[
                    "https://www.googleapis.com/auth/gmail.modify",
                    "https://www.googleapis.com/auth/gmail.compose",
                    "https://www.googleapis.com/auth/gmail.send",
                ]),
            ),
            (
                agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID.into(),
                scopes(&["https://www.googleapis.com/auth/calendar.events"]),
            ),
            (
                agent_runtime::contacts_connector_transport::CONTACTS_CONNECTOR_ID.into(),
                scopes(&[
                    "https://www.googleapis.com/auth/contacts",
                    "https://www.googleapis.com/auth/contacts.readonly",
                ]),
            ),
        ]);
        let capability_scopes = BTreeMap::from([
            (
                "mail".into(),
                connector_scopes[agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID]
                    .clone(),
            ),
            (
                "calendar".into(),
                connector_scopes
                    [agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID]
                    .clone(),
            ),
            (
                "contacts".into(),
                connector_scopes
                    [agent_runtime::contacts_connector_transport::CONTACTS_CONNECTOR_ID]
                    .clone(),
            ),
        ]);
        Self::new(
            GOOGLE_PROVIDER_ID,
            "https://accounts.google.com/o/oauth2/v2/auth",
            "https://oauth2.googleapis.com/token",
            "https://openidconnect.googleapis.com/v1/userinfo",
            client_id,
            client_secret,
            connector_scopes,
            capability_scopes,
            BTreeMap::from([
                ("access_type".into(), "offline".into()),
                ("include_granted_scopes".into(), "true".into()),
                ("prompt".into(), "consent".into()),
            ]),
        )
    }

    pub fn microsoft(
        client_id: impl Into<String>,
        client_secret: Option<SecretMaterial>,
    ) -> anyhow::Result<Self> {
        let identity = scopes(&["openid", "profile", "email", "offline_access"]);
        let connector_scopes = BTreeMap::from([
            (
                agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID.into(),
                microsoft_mail_scopes(),
            ),
            (
                agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID.into(),
                identity
                    .iter()
                    .cloned()
                    .chain(["Calendars.ReadWrite".into()])
                    .collect::<BTreeSet<_>>(),
            ),
            (
                agent_runtime::contacts_connector_transport::CONTACTS_CONNECTOR_ID.into(),
                identity
                    .iter()
                    .cloned()
                    .chain(["Contacts.ReadWrite".into()])
                    .collect::<BTreeSet<_>>(),
            ),
        ]);
        let capability_scopes = BTreeMap::from([
            (
                "mail".into(),
                connector_scopes[agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID]
                    .clone(),
            ),
            (
                "calendar".into(),
                connector_scopes
                    [agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID]
                    .clone(),
            ),
            (
                "contacts".into(),
                connector_scopes
                    [agent_runtime::contacts_connector_transport::CONTACTS_CONNECTOR_ID]
                    .clone(),
            ),
        ]);
        Self::new(
            MICROSOFT_PROVIDER_ID,
            "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            "https://graph.microsoft.com/oidc/userinfo",
            client_id,
            client_secret,
            connector_scopes,
            capability_scopes,
            BTreeMap::from([("prompt".into(), "select_account".into())]),
        )
    }

    async fn token_request(
        &self,
        mut form: Vec<(String, String)>,
        expected_scopes: Option<&BTreeSet<String>>,
    ) -> Result<OAuthTokenGrant, OAuthProviderError> {
        form.push(("client_id".into(), self.client_id.clone()));
        if let Some(secret) = &self.client_secret {
            let value = secret
                .with_exposed_bytes(|bytes| std::str::from_utf8(bytes).map(str::to_owned))
                .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::InvalidRequest))?;
            form.push(("client_secret".into(), value));
        }
        let response = self
            .client
            .post(self.token_endpoint.clone())
            .form(&form)
            .send()
            .await
            .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::Unavailable))?;
        if !response.status().is_success() {
            return Err(OAuthProviderError::new(
                OAuthProviderErrorCode::ExchangeFailed,
            ));
        }
        let token: TokenResponse = response
            .json()
            .await
            .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::ExchangeFailed))?;
        let granted_scopes = token
            .scope
            .as_deref()
            .map(|value| value.split_whitespace().map(str::to_string).collect())
            .or_else(|| expected_scopes.cloned())
            .unwrap_or_default();
        if let Some(expected) = expected_scopes
            && !expected.is_subset(&granted_scopes)
        {
            return Err(OAuthProviderError::new(
                OAuthProviderErrorCode::PermissionInsufficient,
            ));
        }
        let access_token = SecretMaterial::new(token.access_token)
            .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::ExchangeFailed))?;
        let subject = if self.provider_id == MICROSOFT_PROVIDER_ID {
            microsoft_id_token_subject(
                token.id_token.as_deref().ok_or_else(|| {
                    OAuthProviderError::new(OAuthProviderErrorCode::ExchangeFailed)
                })?,
                &self.client_id,
            )
            .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::ExchangeFailed))?
        } else {
            self.user_subject(&access_token).await?
        };
        Ok(OAuthTokenGrant {
            provider_subject: subject,
            access_token,
            refresh_token: token
                .refresh_token
                .map(SecretMaterial::new)
                .transpose()
                .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::ExchangeFailed))?,
            granted_scopes,
            expires_at: token
                .expires_in
                .map(|seconds| Utc::now() + Duration::seconds(seconds.max(1))),
        })
    }

    async fn user_subject(
        &self,
        access_token: &SecretMaterial,
    ) -> Result<String, OAuthProviderError> {
        let token = access_token
            .with_exposed_bytes(|bytes| std::str::from_utf8(bytes).map(str::to_owned))
            .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::ExchangeFailed))?;
        let response = self
            .client
            .get(self.userinfo_endpoint.clone())
            .bearer_auth(token)
            .send()
            .await
            .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::Unavailable))?;
        let user: UserInfo = response
            .json()
            .await
            .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::ExchangeFailed))?;
        let subject = user.sub.or(user.id).unwrap_or_default();
        if subject.trim().is_empty() || subject.len() > 255 {
            return Err(OAuthProviderError::new(
                OAuthProviderErrorCode::ExchangeFailed,
            ));
        }
        Ok(subject)
    }
}

#[async_trait]
impl OAuthProvider for WorkspaceOAuthProvider {
    fn provider_id(&self) -> &str {
        &self.provider_id
    }

    fn authorization_origin(&self) -> &str {
        &self.authorization_origin
    }

    fn authorization_plan(
        &self,
        connector_ids: &BTreeSet<String>,
        capabilities: &BTreeSet<String>,
    ) -> Result<OAuthAuthorizationPlan, OAuthProviderError> {
        if self.provider_id == MICROSOFT_PROVIDER_ID {
            let mail_selected = connector_ids
                .contains(agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID)
                || capabilities.contains("mail");
            let graph_selected = connector_ids.iter().any(|connector_id| {
                connector_id == agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID
                    || connector_id
                        == agent_runtime::contacts_connector_transport::CONTACTS_CONNECTOR_ID
            }) || capabilities.contains("calendar")
                || capabilities.contains("contacts");
            if mail_selected && graph_selected {
                return Err(OAuthProviderError::new(
                    OAuthProviderErrorCode::InvalidRequest,
                ));
            }
        }
        let mut requested_scopes = BTreeSet::new();
        let mut connector_scopes = BTreeMap::new();
        for connector_id in connector_ids {
            let scopes = self
                .connector_scopes
                .get(connector_id)
                .ok_or_else(|| OAuthProviderError::new(OAuthProviderErrorCode::InvalidRequest))?;
            requested_scopes.extend(scopes.iter().cloned());
            connector_scopes.insert(connector_id.clone(), scopes.clone());
        }
        for capability in capabilities {
            let scopes = self
                .capability_scopes
                .get(capability)
                .ok_or_else(|| OAuthProviderError::new(OAuthProviderErrorCode::InvalidRequest))?;
            requested_scopes.extend(scopes.iter().cloned());
        }
        Ok(OAuthAuthorizationPlan {
            requested_scopes,
            connector_scopes,
        })
    }

    fn authorization_url(
        &self,
        request: OAuthAuthorizationUrlRequest,
    ) -> Result<String, OAuthProviderError> {
        let mut url = self.authorization_endpoint.clone();
        {
            let mut query = url.query_pairs_mut();
            query
                .append_pair("client_id", &self.client_id)
                .append_pair("redirect_uri", &request.redirect_uri)
                .append_pair("response_type", "code")
                .append_pair("state", &request.state)
                .append_pair("code_challenge", &request.pkce_challenge)
                .append_pair("code_challenge_method", "S256")
                .append_pair(
                    "scope",
                    &request.scopes.iter().cloned().collect::<Vec<_>>().join(" "),
                );
            for (name, value) in &self.authorization_parameters {
                query.append_pair(name, value);
            }
        }
        Ok(url.to_string())
    }

    async fn exchange_code(
        &self,
        request: OAuthCodeExchangeRequest,
    ) -> Result<OAuthTokenGrant, OAuthProviderError> {
        self.token_request(
            vec![
                ("grant_type".into(), "authorization_code".into()),
                ("code".into(), request.code.expose().into()),
                ("redirect_uri".into(), request.redirect_uri),
                (
                    "code_verifier".into(),
                    request.pkce_verifier.expose().into(),
                ),
            ],
            Some(&request.requested_scopes),
        )
        .await
    }

    async fn refresh_token(
        &self,
        request: OAuthRefreshRequest,
    ) -> Result<OAuthTokenGrant, OAuthProviderError> {
        self.token_request(
            vec![
                ("grant_type".into(), "refresh_token".into()),
                (
                    "refresh_token".into(),
                    request.refresh_token.expose().into(),
                ),
            ],
            None,
        )
        .await
    }
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    id_token: Option<String>,
    scope: Option<String>,
    expires_in: Option<i64>,
}

#[derive(Deserialize)]
struct UserInfo {
    sub: Option<String>,
    id: Option<String>,
}

fn scopes(values: &[&str]) -> BTreeSet<String> {
    values.iter().map(|value| (*value).into()).collect()
}

pub fn microsoft_mail_scopes() -> BTreeSet<String> {
    scopes(&[
        "openid",
        "profile",
        "email",
        "offline_access",
        "https://outlook.office.com/IMAP.AccessAsUser.All",
        "https://outlook.office.com/SMTP.Send",
    ])
}

#[derive(Deserialize)]
struct MicrosoftIdTokenClaims {
    sub: String,
    aud: Audience,
    iss: String,
    exp: i64,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum Audience {
    One(String),
    Many(Vec<String>),
}

fn microsoft_id_token_subject(token: &str, client_id: &str) -> anyhow::Result<String> {
    let mut parts = token.split('.');
    let header = parts.next().unwrap_or_default();
    let payload = parts.next().unwrap_or_default();
    let signature = parts.next().unwrap_or_default();
    anyhow::ensure!(
        !header.is_empty()
            && !payload.is_empty()
            && !signature.is_empty()
            && parts.next().is_none(),
        "Microsoft ID token structure is invalid"
    );
    let decoded = URL_SAFE_NO_PAD.decode(payload)?;
    anyhow::ensure!(
        decoded.len() <= 16 * 1024,
        "Microsoft ID token is too large"
    );
    let claims: MicrosoftIdTokenClaims = serde_json::from_slice(&decoded)?;
    let audience_matches = match claims.aud {
        Audience::One(value) => value == client_id,
        Audience::Many(values) => values.iter().any(|value| value == client_id),
    };
    anyhow::ensure!(audience_matches, "Microsoft ID token audience is invalid");
    let issuer = Url::parse(&claims.iss)?;
    anyhow::ensure!(
        issuer.scheme() == "https"
            && issuer.host_str() == Some("login.microsoftonline.com")
            && issuer.path().ends_with("/v2.0"),
        "Microsoft ID token issuer is invalid"
    );
    anyhow::ensure!(
        claims.exp > Utc::now().timestamp() - 60,
        "Microsoft ID token is expired"
    );
    anyhow::ensure!(
        !claims.sub.trim().is_empty() && claims.sub.len() <= 255,
        "Microsoft ID token subject is invalid"
    );
    Ok(claims.sub)
}

fn secure_url(value: &str) -> anyhow::Result<Url> {
    let url = Url::parse(value)?;
    anyhow::ensure!(url.scheme() == "https", "OAuth endpoint must use HTTPS");
    anyhow::ensure!(
        url.username().is_empty() && url.password().is_none(),
        "OAuth endpoint cannot contain credentials"
    );
    Ok(url)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn google_plan_and_url_bind_pkce_and_connector_scopes() {
        let provider = WorkspaceOAuthProvider::google("client", None).unwrap();
        let connectors = BTreeSet::from([
            agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID.into(),
            agent_runtime::contacts_connector_transport::CONTACTS_CONNECTOR_ID.into(),
        ]);
        let plan = provider
            .authorization_plan(&connectors, &BTreeSet::new())
            .unwrap();
        assert_eq!(plan.connector_scopes.len(), 2);
        let url = provider
            .authorization_url(OAuthAuthorizationUrlRequest {
                authorization_id: "authorization-1".into(),
                redirect_uri: "http://127.0.0.1/callback".into(),
                state: "state".into(),
                pkce_challenge: "challenge".into(),
                scopes: plan.requested_scopes,
            })
            .unwrap();
        assert!(url.contains("code_challenge_method=S256"));
        assert!(url.contains("access_type=offline"));
    }

    #[test]
    fn microsoft_plan_uses_outlook_mail_scopes_and_common_tenant() {
        let provider = WorkspaceOAuthProvider::microsoft("client", None).unwrap();
        let plan = provider
            .authorization_plan(
                &BTreeSet::from(
                    [agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID.into()],
                ),
                &BTreeSet::new(),
            )
            .unwrap();
        assert!(
            plan.requested_scopes
                .contains("https://outlook.office.com/SMTP.Send")
        );
        assert!(
            provider
                .authorization_origin()
                .contains("login.microsoftonline.com")
        );
    }

    #[test]
    fn microsoft_plan_rejects_mixed_outlook_and_graph_resources() {
        let provider = WorkspaceOAuthProvider::microsoft("client", None).unwrap();
        assert!(
            provider
                .authorization_plan(
                    &BTreeSet::from([
                        agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID.into(),
                        agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID.into(),
                    ]),
                    &BTreeSet::new(),
                )
                .is_err()
        );
        assert!(
            provider
                .authorization_plan(
                    &BTreeSet::from([
                        agent_runtime::calendar_connector_transport::CALENDAR_CONNECTOR_ID.into(),
                        agent_runtime::contacts_connector_transport::CONTACTS_CONNECTOR_ID.into(),
                    ]),
                    &BTreeSet::new(),
                )
                .is_ok()
        );
    }

    #[test]
    fn microsoft_subject_requires_bound_unexpired_id_token_claims() {
        let claims = serde_json::json!({
            "sub": "subject-1",
            "aud": "client",
            "iss": "https://login.microsoftonline.com/tenant/v2.0",
            "exp": Utc::now().timestamp() + 300
        });
        let token = format!(
            "{}.{}.signature",
            URL_SAFE_NO_PAD.encode(b"{}"),
            URL_SAFE_NO_PAD.encode(serde_json::to_vec(&claims).unwrap())
        );
        assert_eq!(
            microsoft_id_token_subject(&token, "client").unwrap(),
            "subject-1"
        );
        assert!(microsoft_id_token_subject(&token, "different-client").is_err());
    }
}
