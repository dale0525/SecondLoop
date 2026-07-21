use agent_runtime::credential::{
    CredentialScope, CredentialVault, ProviderCredential, SecretId, SecretMaterial,
};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use identity_firebase::{
    FIREBASE_IDENTITY_PROVIDER_ID, FirebaseError, FirebaseSecret, FirebaseSession,
    FirebaseSessionStore, Result,
};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeSet, sync::Arc};
use uuid::Uuid;

const CREDENTIAL_ID: &str = "firebase.identity.session";

pub struct VaultFirebaseSessionStore {
    vault: Arc<CredentialVault>,
    scope: CredentialScope,
}

impl VaultFirebaseSessionStore {
    pub fn new(vault: Arc<CredentialVault>, app_id: String, tenant_id: String) -> Result<Self> {
        let scope = CredentialScope {
            app_id,
            tenant_id,
            user_id: "identity-session".into(),
        };
        scope.validate().map_err(|_| FirebaseError::SecureStorage)?;
        Ok(Self { vault, scope })
    }

    async fn material(&self, refresh: bool) -> Result<SecretMaterial> {
        let result = if refresh {
            self.vault
                .lease_provider_refresh_secret(
                    &self.scope,
                    FIREBASE_IDENTITY_PROVIDER_ID,
                    CREDENTIAL_ID,
                )
                .await
        } else {
            self.vault
                .lease_provider_access_secret(
                    &self.scope,
                    FIREBASE_IDENTITY_PROVIDER_ID,
                    CREDENTIAL_ID,
                )
                .await
        };
        result.map_err(|_| FirebaseError::SecureStorage)
    }
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AccessWire {
    id_token: String,
    authenticated_at: DateTime<Utc>,
}

#[async_trait]
impl FirebaseSessionStore for VaultFirebaseSessionStore {
    async fn load_session(&self) -> Result<Option<FirebaseSession>> {
        let Some(credential) = self
            .vault
            .get_provider_credential(&self.scope, CREDENTIAL_ID)
            .await
            .map_err(|_| FirebaseError::SecureStorage)?
        else {
            return Ok(None);
        };
        if credential.provider_id != FIREBASE_IDENTITY_PROVIDER_ID {
            return Err(FirebaseError::SecureStorage);
        }
        if credential.revoked_at.is_some() {
            return Ok(None);
        }
        let access = self.material(false).await?;
        let wire: AccessWire = access
            .with_exposed_bytes(|bytes| serde_json::from_slice(bytes))
            .map_err(|_| FirebaseError::SecureStorage)?;
        let refresh = self.material(true).await?;
        let refresh_token = refresh
            .with_exposed_bytes(|bytes| String::from_utf8(bytes.to_vec()).map(FirebaseSecret::new));
        Ok(Some(FirebaseSession {
            subject: credential.provider_subject,
            id_token: FirebaseSecret::new(wire.id_token),
            refresh_token: refresh_token.map_err(|_| FirebaseError::SecureStorage)?,
            authenticated_at: wire.authenticated_at,
            expires_at: credential.expires_at.ok_or(FirebaseError::SecureStorage)?,
        }))
    }

    async fn save_session(&self, session: FirebaseSession) -> Result<()> {
        let mut existing = self
            .vault
            .get_provider_credential(&self.scope, CREDENTIAL_ID)
            .await
            .map_err(|_| FirebaseError::SecureStorage)?;
        if existing
            .as_ref()
            .is_some_and(|credential| credential.provider_subject != session.subject)
        {
            self.vault
                .revoke_provider_credential(&self.scope, CREDENTIAL_ID, Utc::now())
                .await
                .map_err(|_| FirebaseError::SecureStorage)?;
            existing = None;
        }
        let access_id = secret_id("access")?;
        let refresh_id = secret_id("refresh")?;
        let access = serde_json::to_vec(&AccessWire {
            id_token: session.id_token.expose_secret().into(),
            authenticated_at: session.authenticated_at,
        })
        .map_err(|_| FirebaseError::SecureStorage)?;
        let credential = ProviderCredential {
            credential_id: CREDENTIAL_ID.into(),
            provider_id: FIREBASE_IDENTITY_PROVIDER_ID.into(),
            provider_subject: session.subject,
            access_secret_id: access_id,
            refresh_secret_id: Some(refresh_id),
            granted_scopes: BTreeSet::new(),
            expires_at: Some(session.expires_at),
            revoked_at: None,
        };
        let access = SecretMaterial::new(access).map_err(|_| FirebaseError::SecureStorage)?;
        let refresh =
            SecretMaterial::new(session.refresh_token.expose_secret().as_bytes().to_vec())
                .map_err(|_| FirebaseError::SecureStorage)?;
        if existing
            .as_ref()
            .is_some_and(|credential| credential.revoked_at.is_none())
        {
            self.vault
                .replace_provider_credential(&self.scope, credential, access, Some(refresh))
                .await
        } else {
            self.vault
                .save_provider_credential(&self.scope, credential, access, Some(refresh))
                .await
        }
        .map_err(|_| FirebaseError::SecureStorage)
    }

    async fn delete_session(&self) -> Result<()> {
        self.vault
            .revoke_provider_credential(&self.scope, CREDENTIAL_ID, Utc::now())
            .await
            .map(|_| ())
            .map_err(|_| FirebaseError::SecureStorage)
    }
}

fn secret_id(kind: &str) -> Result<SecretId> {
    SecretId::parse(&format!("firebase-{kind}-{}", Uuid::new_v4().simple()))
        .map_err(|_| FirebaseError::SecureStorage)
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_runtime::{
        credential::InMemorySecretStore, credential_sqlite::SqliteCredentialMetadataStore,
        storage::Storage,
    };
    use chrono::Duration;

    #[tokio::test]
    async fn revoked_firebase_credential_loads_as_an_absent_session() {
        let storage = Storage::connect("sqlite::memory:").await.unwrap();
        let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
            .await
            .unwrap();
        let store = VaultFirebaseSessionStore::new(
            Arc::new(CredentialVault::new_persistent(
                Arc::new(InMemorySecretStore::default()),
                metadata,
            )),
            "com.example.app".into(),
            "local".into(),
        )
        .unwrap();
        store
            .save_session(FirebaseSession {
                subject: "firebase-subject".into(),
                id_token: FirebaseSecret::new("id-token-sentinel"),
                refresh_token: FirebaseSecret::new("refresh-token-sentinel"),
                authenticated_at: Utc::now() - Duration::minutes(1),
                expires_at: Utc::now() + Duration::hours(1),
            })
            .await
            .unwrap();
        assert!(store.load_session().await.unwrap().is_some());

        store.delete_session().await.unwrap();

        assert!(store.load_session().await.unwrap().is_none());
    }
}
