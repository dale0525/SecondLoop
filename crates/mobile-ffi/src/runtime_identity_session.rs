use super::MobileRuntime;
use agent_runtime::{identity::SecurityContext, model_access::ModelConfigurationPolicy};
use anyhow::Result;
use chrono::Utc;

impl MobileRuntime {
    pub fn refresh_security_context(&self, replacement: SecurityContext) -> Result<()> {
        anyhow::ensure!(
            self.model_configuration_policy == ModelConfigurationPolicy::AppManaged
                && self.gateway_identity_required,
            "the active Runtime does not use identity-backed model access"
        );
        replacement
            .validate()
            .map_err(|_| anyhow::anyhow!("mobile security context is invalid"))?;
        anyhow::ensure!(
            !replacement.is_expired_at(Utc::now()),
            "mobile identity session has expired"
        );
        let account_id = replacement
            .scoped_user_id()
            .map_err(|_| anyhow::anyhow!("mobile account scope is invalid"))?;
        anyhow::ensure!(
            self.account_id.as_deref() == Some(account_id.as_str()),
            "refreshed mobile identity cannot change accounts"
        );
        let mut active = self
            .security_context
            .lock()
            .map_err(|_| anyhow::anyhow!("mobile security context is unavailable"))?;
        let current = active
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("authenticated identity is required"))?;
        anyhow::ensure!(
            replacement.provider_id == current.provider_id
                && replacement.app_id == current.app_id
                && replacement.tenant_id == current.tenant_id
                && replacement.audience == current.audience
                && replacement.principal == current.principal
                && current
                    .granted_scopes
                    .iter()
                    .all(|scope| replacement.granted_scopes.contains(scope)),
            "refreshed mobile identity does not match the active account"
        );
        *active = Some(replacement);
        Ok(())
    }

    pub(super) fn current_security_context(&self) -> Result<SecurityContext> {
        self.security_context
            .lock()
            .map_err(|_| anyhow::anyhow!("mobile security context is unavailable"))?
            .clone()
            .ok_or_else(|| anyhow::anyhow!("authenticated identity is required"))
    }
}
