use agent_runtime::app_manifest::{AgentAppIdentityMode, AgentAppManifest};
use agent_runtime::identity::SecurityContext;
use agent_runtime::model_access::{
    ModelAccessProfile, ModelAuthentication, ModelConfigurationPolicy,
};
use agent_runtime::model_config::StoredModelConfig;
use agent_runtime::session::ConversationScope;
use anyhow::{Context, Result};
use chrono::Utc;
use std::path::{Path, PathBuf};

pub(super) struct MobileIdentityScope {
    pub account_id: Option<String>,
    pub context: Option<SecurityContext>,
    pub conversation: ConversationScope,
    pub mode: &'static str,
}

pub(super) async fn resolve_mobile_identity_scope(
    app_package_path: Option<&Path>,
    supplied: Option<SecurityContext>,
    device_id: Option<&str>,
) -> Result<MobileIdentityScope> {
    let device_id = device_id.unwrap_or("local-device").trim();
    validate_scope_value(device_id, "device ID")?;
    let Some(root) = app_package_path else {
        anyhow::ensure!(
            supplied.is_none(),
            "an unpackaged local runtime cannot accept an authenticated identity"
        );
        return Ok(local_scope("dev.agentweave.default", device_id));
    };
    let loaded = AgentAppManifest::load(root)
        .await
        .context("failed to load the Agent App identity contract")?;
    let manifest = &loaded.manifest;
    let identity = manifest.effective_identity();
    if identity.mode == AgentAppIdentityMode::LocalSingleUser {
        anyhow::ensure!(
            supplied.is_none(),
            "local-single-user Apps cannot accept a remote security context"
        );
        return Ok(local_scope(manifest.app_id.as_str(), device_id));
    }

    let binding = identity
        .provider
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("required mobile identity provider is missing"))?;
    anyhow::ensure!(
        binding.id.as_str() == identity_oidc::OIDC_IDENTITY_PROVIDER_ID,
        "the selected mobile identity provider is unavailable"
    );
    let oidc: identity_oidc::OidcPluginPublicConfig =
        serde_json::from_value(binding.public_config.clone())
            .context("mobile OIDC public configuration is invalid")?;
    oidc.validate()
        .map_err(|_| anyhow::anyhow!("mobile OIDC public configuration is invalid"))?;
    let context =
        supplied.ok_or_else(|| anyhow::anyhow!("authenticated mobile identity is required"))?;
    context
        .validate()
        .map_err(|_| anyhow::anyhow!("mobile security context is invalid"))?;
    anyhow::ensure!(
        context.provider_id == binding.id.as_str()
            && context.app_id == manifest.app_id.as_str()
            && context.audience == oidc.audience
            && oidc
                .scopes
                .iter()
                .all(|scope| context.granted_scopes.contains(scope)),
        "mobile security context does not match the packaged App"
    );
    anyhow::ensure!(
        !context.is_expired_at(Utc::now()),
        "mobile security context has expired"
    );
    let account_id = context
        .scoped_user_id()
        .map_err(|_| anyhow::anyhow!("mobile account scope is invalid"))?;
    let conversation = ConversationScope {
        app_id: context.app_id.clone(),
        agent_id: "default".into(),
        tenant_id: context.tenant_id.clone(),
        user_id: account_id.clone(),
        device_id: device_id.into(),
    };
    conversation.validate()?;
    Ok(MobileIdentityScope {
        account_id: Some(account_id),
        context: Some(context),
        conversation,
        mode: "required",
    })
}

pub(super) fn identity_database_path(
    configured: &Path,
    app_data_dir: &Path,
    identity: &MobileIdentityScope,
) -> PathBuf {
    match &identity.account_id {
        Some(account_id) => app_data_dir
            .join("identity-data")
            .join(account_id)
            .join("agentweave.db"),
        None => configured.to_path_buf(),
    }
}

pub(super) fn app_managed_model_config(
    policy: Option<&agent_runtime::app_definition::AgentAppRuntimePolicy>,
) -> Result<(ModelConfigurationPolicy, Option<StoredModelConfig>, bool)> {
    let Some(policy) = policy else {
        return Ok((ModelConfigurationPolicy::UserConfigurable, None, false));
    };
    let model = policy.model_access();
    model.validate()?;
    if model.configuration_policy == ModelConfigurationPolicy::UserConfigurable {
        return Ok((ModelConfigurationPolicy::UserConfigurable, None, false));
    }
    let profile = model
        .profile
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("app-managed mobile model profile is missing"))?;
    Ok((
        ModelConfigurationPolicy::AppManaged,
        Some(stored_model_profile(profile)),
        profile.authentication == ModelAuthentication::UserIdentity,
    ))
}

pub(super) fn model_policy_name(policy: ModelConfigurationPolicy) -> &'static str {
    match policy {
        ModelConfigurationPolicy::UserConfigurable => "user_configurable",
        ModelConfigurationPolicy::AppManaged => "app_managed",
    }
}

fn stored_model_profile(profile: &ModelAccessProfile) -> StoredModelConfig {
    StoredModelConfig {
        provider_id: profile.provider_id.clone(),
        provider_name: profile.provider_id.clone(),
        endpoint_type: profile.endpoint_type,
        base_url: profile.base_url.clone(),
        model_name: profile.model_name.clone(),
        secret_id: None,
        headers: profile.headers.clone(),
    }
}

fn local_scope(app_id: &str, device_id: &str) -> MobileIdentityScope {
    MobileIdentityScope {
        account_id: None,
        context: None,
        conversation: ConversationScope {
            app_id: app_id.into(),
            agent_id: "default".into(),
            tenant_id: "local".into(),
            user_id: "local-user".into(),
            device_id: device_id.into(),
        },
        mode: "local_single_user",
    }
}

fn validate_scope_value(value: &str, label: &str) -> Result<()> {
    anyhow::ensure!(
        !value.is_empty() && value.len() <= 255 && !value.chars().any(char::is_control),
        "mobile {label} is invalid"
    );
    Ok(())
}
