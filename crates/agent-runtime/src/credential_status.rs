use super::*;

impl CredentialVault {
    /// Checks the bound credential and backing access secret without exposing
    /// secret material to callers.
    pub async fn connector_credential_configured(
        &self,
        scope: &CredentialScope,
        connector_id: &str,
        account_id: &str,
    ) -> anyhow::Result<bool> {
        let Some(account) = self
            .get_connector_account(scope, connector_id, account_id)
            .await?
        else {
            return Ok(false);
        };
        let Some(credential) = self
            .get_provider_credential(scope, &account.credential_id)
            .await?
        else {
            return Ok(false);
        };
        if credential.revoked_at.is_some()
            || credential
                .expires_at
                .is_some_and(|expiry| expiry <= Utc::now())
        {
            return Ok(false);
        }
        Ok(self
            .store
            .load(scope, &credential.access_secret_id)
            .await?
            .is_some())
    }
}
