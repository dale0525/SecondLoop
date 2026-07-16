use agent_runtime::credential::{CredentialScope, CredentialVault, SecretMaterial};
use agent_runtime::oauth::OAuthBroker;
use async_trait::async_trait;
use chrono::Utc;
use std::collections::BTreeSet;
use std::sync::Arc;

#[async_trait]
pub trait ProviderCredentialSource: Send + Sync {
    async fn access_token(
        &self,
        connector_id: &str,
        account_id: &str,
        required_scopes: &BTreeSet<String>,
    ) -> anyhow::Result<SecretMaterial>;
}

#[derive(Clone)]
pub struct VaultCredentialSource {
    vault: Arc<CredentialVault>,
    broker: Option<OAuthBroker>,
    scope: CredentialScope,
}

impl VaultCredentialSource {
    pub fn new(
        vault: Arc<CredentialVault>,
        broker: Option<OAuthBroker>,
        scope: CredentialScope,
    ) -> anyhow::Result<Self> {
        scope.validate()?;
        Ok(Self {
            vault,
            broker,
            scope,
        })
    }

    async fn refresh_if_expired(&self, connector_id: &str, account_id: &str) -> anyhow::Result<()> {
        let account = self
            .vault
            .get_connector_account(&self.scope, connector_id, account_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("connector account is unavailable"))?;
        let credential = self
            .vault
            .get_provider_credential(&self.scope, &account.credential_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("provider credential is unavailable"))?;
        if credential
            .expires_at
            .is_some_and(|expiry| expiry <= Utc::now())
        {
            self.broker
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("provider credential refresh is unavailable"))?
                .refresh_credential(&account.credential_id)
                .await?;
        }
        Ok(())
    }
}

#[async_trait]
impl ProviderCredentialSource for VaultCredentialSource {
    async fn access_token(
        &self,
        connector_id: &str,
        account_id: &str,
        required_scopes: &BTreeSet<String>,
    ) -> anyhow::Result<SecretMaterial> {
        self.refresh_if_expired(connector_id, account_id).await?;
        self.vault
            .lease_for_connector(&self.scope, connector_id, account_id, required_scopes)
            .await
    }
}
