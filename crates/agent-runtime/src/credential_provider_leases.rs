use super::{CredentialScope, CredentialVault, SecretMaterial};

impl CredentialVault {
    pub async fn lease_provider_refresh_secret(
        &self,
        scope: &CredentialScope,
        provider_id: &str,
        credential_id: &str,
    ) -> anyhow::Result<SecretMaterial> {
        scope.validate()?;
        let credential = self
            .get_provider_credential(scope, credential_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("provider credential is unavailable"))?;
        anyhow::ensure!(
            credential.provider_id == provider_id,
            "OAuth provider mismatch"
        );
        anyhow::ensure!(
            credential.revoked_at.is_none(),
            "provider credential is revoked"
        );
        let secret_id = credential
            .refresh_secret_id
            .ok_or_else(|| anyhow::anyhow!("provider refresh credential is unavailable"))?;
        self.store
            .load(scope, &secret_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("provider refresh credential is unavailable"))
    }

    /// Loads the active access assertion for one provider credential without
    /// exposing it through connector account discovery.
    pub async fn lease_provider_access_secret(
        &self,
        scope: &CredentialScope,
        provider_id: &str,
        credential_id: &str,
    ) -> anyhow::Result<SecretMaterial> {
        scope.validate()?;
        let credential = self
            .get_provider_credential(scope, credential_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("provider credential is unavailable"))?;
        anyhow::ensure!(
            credential.provider_id == provider_id,
            "provider credential mismatch"
        );
        anyhow::ensure!(
            credential.revoked_at.is_none(),
            "provider credential is revoked"
        );
        self.store
            .load(scope, &credential.access_secret_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("provider access credential is unavailable"))
    }
}
