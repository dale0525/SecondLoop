use super::*;

impl OAuthBroker {
    pub(super) async fn renew_exchange(
        &self,
        authorization_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        self.store
            .renew_exchange(
                &self.scope,
                authorization_id,
                &self.owner_id,
                now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS),
                now,
            )
            .await
    }

    pub(super) async fn fail_and_recover(
        &self,
        authorization_id: &str,
        error_code: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationView> {
        let session = self
            .store
            .mark_failed_recoverable(
                &self.scope,
                authorization_id,
                &self.owner_id,
                error_code,
                now,
            )
            .await?;
        self.recover_owned_session(session, now).await
    }

    pub(super) async fn exchange_lease_lost(
        &self,
        authorization_id: &str,
        credential_id: Option<&str>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationView> {
        if let Some(credential_id) = credential_id {
            self.cleanup_local_credential(credential_id, now).await?;
        }
        self.cleanup_stale(now).await?;
        self.store
            .get(&self.scope, authorization_id)
            .await?
            .map(OAuthAuthorizationSession::view)
            .ok_or_else(|| anyhow::anyhow!("OAuth authorization is unavailable"))
    }

    pub(super) async fn cleanup_stale(&self, now: DateTime<Utc>) -> anyhow::Result<()> {
        for (authorization_id, secret_id) in self.store.cleanup_candidates(&self.scope, now).await?
        {
            self.vault
                .delete_oauth_pkce_verifier(&self.scope, &secret_id)
                .await?;
            self.store
                .delete_state(&self.scope, &authorization_id)
                .await?;
        }
        for candidate in self.store.recovery_candidates(&self.scope, now).await? {
            let claimed = self
                .store
                .claim_recovery(
                    &self.scope,
                    &candidate.authorization_id,
                    &self.owner_id,
                    now + ChronoDuration::seconds(EXCHANGE_LEASE_SECONDS),
                    now,
                )
                .await?;
            if let Some(session) = claimed {
                self.recover_owned_session(session, now).await?;
            }
        }
        self.store
            .purge_terminal(
                &self.scope,
                now - ChronoDuration::days(TERMINAL_RETENTION_DAYS),
            )
            .await?;
        Ok(())
    }

    pub(super) async fn recover_interrupted(&self, now: DateTime<Utc>) -> anyhow::Result<()> {
        self.cleanup_stale(now).await
    }

    async fn recover_owned_session(
        &self,
        session: OAuthAuthorizationSession,
        now: DateTime<Utc>,
    ) -> anyhow::Result<OAuthAuthorizationView> {
        anyhow::ensure!(
            session.status == OAuthAuthorizationStatus::Failed
                && session.exchange_owner_id.as_deref() == Some(self.owner_id.as_str()),
            "OAuth recovery ownership is invalid"
        );
        let pkce_secret_id = SecretId::parse(&format!("oauth.pkce.{}", session.authorization_id))?;
        self.vault
            .delete_oauth_pkce_verifier(&self.scope, &pkce_secret_id)
            .await?;
        if let Some(credential_id) = &session.credential_id {
            self.cleanup_local_credential(credential_id, now).await?;
        }
        Ok(self
            .store
            .finalize_recovery(&self.scope, &session.authorization_id, &self.owner_id, now)
            .await?
            .view())
    }

    async fn cleanup_local_credential(
        &self,
        credential_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        for account in self
            .vault
            .list_connector_accounts(&self.scope, None)
            .await?
        {
            if account.credential_id == credential_id {
                self.vault
                    .remove_connector_account(
                        &self.scope,
                        &account.connector_id,
                        &account.account_id,
                    )
                    .await?;
            }
        }
        self.vault
            .revoke_provider_credential(&self.scope, credential_id, now)
            .await?;
        self.vault
            .cleanup_pending_secret_material(&self.scope)
            .await?;
        self.vault
            .delete_secret_material(&self.scope, &recovery_access_secret_id(credential_id)?)
            .await?;
        self.vault
            .delete_secret_material(&self.scope, &recovery_refresh_secret_id(credential_id)?)
            .await?;
        Ok(())
    }
}
