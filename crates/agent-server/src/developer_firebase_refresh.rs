use crate::developer_control_plane::{DeveloperControlPlane, now_unix_ms};
use crate::developer_firebase::{
    FIREBASE_DEVELOPER_PROVIDER_ID, FirebaseControlBody, FirebaseControlRequest,
};
use crate::developer_firebase_models::{
    GoogleRefreshCredential, GoogleRefreshTokenResponse, google_refresh_credential_document,
    internal, invalid_authorization, remote_protocol, required_capabilities, unavailable,
};
use agent_devkit::{
    DeveloperAuthorization, DevkitResult, SensitiveInputResolver, SensitiveInputStore,
    SensitiveValue,
};
use identity_firebase::FirebaseSecret;
use reqwest::Method;
use url::Url;

const REFRESH_BEFORE_EXPIRY_MS: u64 = 60_000;
const GOOGLE_TOKEN_ENDPOINT: &str = "https://oauth2.googleapis.com/token";

impl DeveloperControlPlane {
    pub(crate) async fn require_firebase_authorization(
        &self,
    ) -> DevkitResult<DeveloperAuthorization> {
        let authorization = self
            .load_firebase_authorization()
            .await?
            .ok_or_else(invalid_authorization)?;
        let authorization = self
            .refresh_firebase_authorization_if_needed(authorization)
            .await?;
        authorization.ensure_provider_usable(
            FIREBASE_DEVELOPER_PROVIDER_ID,
            &required_capabilities(),
            now_unix_ms(),
        )?;
        Ok(authorization)
    }

    pub(crate) async fn refresh_firebase_authorization_if_needed(
        &self,
        authorization: DeveloperAuthorization,
    ) -> DevkitResult<DeveloperAuthorization> {
        let now = now_unix_ms();
        if !needs_refresh(&authorization, now) {
            authorization.ensure_provider_usable(
                FIREBASE_DEVELOPER_PROVIDER_ID,
                &required_capabilities(),
                now,
            )?;
            return Ok(authorization);
        }

        let _refresh = self.firebase_refresh.lock().await;
        let current = self
            .load_firebase_authorization()
            .await?
            .ok_or_else(invalid_authorization)?;
        let now = now_unix_ms();
        if !needs_refresh(&current, now) {
            current.ensure_provider_usable(
                FIREBASE_DEVELOPER_PROVIDER_ID,
                &required_capabilities(),
                now,
            )?;
            return Ok(current);
        }
        let Some(refresh_handle) = current.refresh_token_handle() else {
            return Ok(current);
        };
        let stored = self.sensitive.resolve(refresh_handle).await?;
        let credential: GoogleRefreshCredential = stored
            .expose(|bytes| serde_json::from_slice(bytes).map_err(|_| invalid_authorization()))?;
        credential.validate()?;

        let mut form = vec![
            (
                "client_id".into(),
                FirebaseSecret::new(&credential.client_id),
            ),
            ("grant_type".into(), FirebaseSecret::new("refresh_token")),
            ("refresh_token".into(), credential.refresh_token.clone()),
        ];
        if let Some(secret) = &credential.client_secret {
            form.push(("client_secret".into(), secret.clone()));
        }
        let response = self
            .firebase_http
            .send(FirebaseControlRequest {
                method: Method::POST,
                url: Url::parse(GOOGLE_TOKEN_ENDPOINT).map_err(|_| internal())?,
                bearer: None,
                body: FirebaseControlBody::Form(form),
            })
            .await?;
        if matches!(response.status, 400 | 401) {
            self.invalidate_firebase_authorization(&current).await?;
            return Err(invalid_authorization());
        }
        if response.status != 200 {
            return Err(unavailable());
        }
        let token: GoogleRefreshTokenResponse =
            serde_json::from_slice(&response.body).map_err(|_| remote_protocol())?;
        token.validate()?;

        let access_handle = self
            .sensitive
            .store(
                "firebase/oauth/access-token",
                SensitiveValue::new(token.access_token.expose_secret().as_bytes().to_vec())?,
            )
            .await?;
        let (next_refresh_handle, created_refresh_handle) =
            if let Some(refresh_token) = token.refresh_token.as_ref() {
                let handle = match self
                    .sensitive
                    .store(
                        "firebase/oauth/refresh-credential",
                        SensitiveValue::new(google_refresh_credential_document(
                            refresh_token,
                            &credential.client_id,
                            credential.client_secret.as_ref(),
                        )?)?,
                    )
                    .await
                {
                    Ok(handle) => handle,
                    Err(error) => {
                        let _ = self.sensitive.delete_handle(&access_handle).await;
                        return Err(error);
                    }
                };
                (handle, true)
            } else {
                (refresh_handle.clone(), false)
            };
        let expires_at = now.saturating_add(token.expires_in.saturating_mul(1_000));
        let rotated = match rotated_authorization(
            &current,
            access_handle.clone(),
            next_refresh_handle.clone(),
            now,
            expires_at,
        ) {
            Ok(value) => value,
            Err(error) => {
                let _ = self.sensitive.delete_handle(&access_handle).await;
                if created_refresh_handle {
                    let _ = self.sensitive.delete_handle(&next_refresh_handle).await;
                }
                return Err(error);
            }
        };
        if let Err(error) = self.save_firebase_authorization(&rotated).await {
            let _ = self.sensitive.delete_handle(&access_handle).await;
            if created_refresh_handle {
                let _ = self.sensitive.delete_handle(&next_refresh_handle).await;
            }
            return Err(error);
        }
        let _ = self.sensitive.delete_handle(current.token_handle()).await;
        if created_refresh_handle {
            let _ = self.sensitive.delete_handle(refresh_handle).await;
        }
        Ok(rotated)
    }

    async fn invalidate_firebase_authorization(
        &self,
        authorization: &DeveloperAuthorization,
    ) -> DevkitResult<()> {
        self.delete_firebase_authorization().await?;
        let mut handles = vec![authorization.token_handle().clone()];
        handles.extend(authorization.refresh_token_handle().cloned());
        let _ = self.sensitive.delete_handles(handles).await;
        Ok(())
    }
}

fn needs_refresh(authorization: &DeveloperAuthorization, now: u64) -> bool {
    authorization
        .expires_at_unix_ms()
        .is_some_and(|expiry| expiry <= now.saturating_add(REFRESH_BEFORE_EXPIRY_MS))
}

fn rotated_authorization(
    previous: &DeveloperAuthorization,
    access_handle: agent_devkit::SensitiveInputHandle,
    refresh_handle: agent_devkit::SensitiveInputHandle,
    issued_at: u64,
    expires_at: u64,
) -> DevkitResult<DeveloperAuthorization> {
    let arguments = (
        previous.provider_id(),
        previous.actor_id(),
        access_handle,
        Some(refresh_handle),
        previous.granted_scope_ids().clone(),
        previous.logical_capabilities().clone(),
        previous.authorization_revision(),
        issued_at,
        Some(expires_at),
    );
    match previous.account_id() {
        Some(account_id) => DeveloperAuthorization::new(
            arguments.0,
            arguments.1,
            account_id,
            arguments.2,
            arguments.3,
            arguments.4,
            arguments.5,
            arguments.6,
            arguments.7,
            arguments.8,
        ),
        None => DeveloperAuthorization::new_unbound(
            arguments.0,
            arguments.1,
            arguments.2,
            arguments.3,
            arguments.4,
            arguments.5,
            arguments.6,
            arguments.7,
            arguments.8,
        ),
    }
}
