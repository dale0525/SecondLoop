use super::*;

#[cfg(not(test))]
const SECRET_STORE_WRITE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(30);
#[cfg(test)]
const SECRET_STORE_WRITE_TIMEOUT: std::time::Duration = std::time::Duration::from_millis(100);

impl CredentialVault {
    pub(super) async fn save_provider_secret(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        tokio::time::timeout(
            SECRET_STORE_WRITE_TIMEOUT,
            self.store.save(scope, secret_id, value),
        )
        .await
        .map_err(|_| anyhow::anyhow!("credential secret persistence timed out"))?
    }

    pub(super) async fn abandon_provider_secret_staging(
        &self,
        scope: &CredentialScope,
        metadata: &crate::credential_sqlite::SqliteCredentialMetadataStore,
        secret_ids: &[SecretId],
        operation_id: &str,
    ) {
        if let Err(error) = metadata
            .abandon_secret_staging(scope, secret_ids, operation_id)
            .await
        {
            tracing::warn!(error = %error, "credential secret staging remains leased");
        }
        if let Err(error) = self.cleanup_pending_secret_material(scope).await {
            tracing::warn!(error = %error, "credential secret cleanup remains pending");
        }
    }
}
