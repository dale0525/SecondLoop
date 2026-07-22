use crate::developer_control_plane::{DeveloperControlPlane, now_unix_ms};
use crate::developer_control_plane_deployment::{
    DeploymentReferenceInput, ensure_account, public_fact_string, reference_from_target,
    validate_environment,
};
use agent_devkit::{
    DeploymentArtifact, DesiredDeploymentState, DevkitError, DevkitErrorCode, DevkitResult,
    ObservationReachability,
};
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

const CREEM_WEBHOOK_PATH: &str = "/agentweave/commerce/v1/webhooks/creem";

#[derive(Debug)]
pub struct CommerceWebhookBootstrapInput {
    pub target: DeploymentReferenceInput,
    pub entitlement_config: Value,
    pub idempotency_key: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CommerceWebhookBootstrapState {
    BootstrapReady,
    ExistingEntitlement,
    CommerceActive,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommerceWebhookBootstrapReceipt {
    pub state: CommerceWebhookBootstrapState,
    pub provider_id: String,
    pub provider_version: String,
    pub target: DeploymentReferenceInput,
    pub version_id: String,
    pub endpoint: String,
    pub webhook_url: String,
    pub operation_id: Option<Uuid>,
    pub completed_at_unix_ms: u64,
}

impl DeveloperControlPlane {
    pub async fn bootstrap_commerce_webhook(
        &self,
        input: CommerceWebhookBootstrapInput,
    ) -> DevkitResult<CommerceWebhookBootstrapReceipt> {
        let _mutation = self.mutation.lock().await;
        let authorization = self.require_authorization(true).await?;
        validate_environment(input.target.environment.as_deref())?;
        ensure_account(&authorization, &input.target.account_id)?;
        let target = self.target(
            input.target.account_id.clone(),
            input.target.deployment_id.clone(),
            input.target.worker_name.clone(),
        )?;
        let observed = self
            .provider
            .inspect(&authorization, &target, now_unix_ms())
            .await?;
        match observed.reachability {
            ObservationReachability::Reachable => {
                if observed
                    .resource_facts
                    .get("worker_role")
                    .and_then(Value::as_str)
                    != Some("entitlement_policy")
                {
                    return Err(DevkitError::new(
                        DevkitErrorCode::ConcurrentModification,
                        "the managed entitlement Worker name is already used by another deployment role",
                    ));
                }
                return existing_receipt(self, &input.target, &observed);
            }
            ObservationReachability::Missing => {}
            ObservationReachability::Unauthorized => {
                return Err(DevkitError::new(
                    DevkitErrorCode::PermissionInsufficient,
                    "the Creem webhook Worker cannot be inspected with the current authorization",
                ));
            }
            ObservationReachability::Unreachable => {
                return Err(DevkitError::new(
                    DevkitErrorCode::Unavailable,
                    "the Creem webhook Worker cannot be inspected before bootstrap",
                ));
            }
        }
        let template = self.entitlement_template().ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::Unavailable,
                "trusted Cloudflare entitlement template is unavailable",
            )
        })?;
        let desired = DesiredDeploymentState::new(
            target.clone(),
            template.version(),
            DeploymentArtifact::new("application/javascript+module", template.bytes().to_vec())?,
            BTreeMap::from([
                ("worker_role".into(), json!("entitlement_policy")),
                ("entitlement_config".into(), input.entitlement_config),
            ]),
            BTreeMap::new(),
            BTreeSet::new(),
        )?;
        let control = self
            .acquire_lease(
                input.idempotency_key.unwrap_or_else(|| {
                    format!("agentweave-commerce-webhook-bootstrap-{}", Uuid::new_v4())
                }),
                None,
                None,
            )
            .await?;
        let result = async {
            let plan = self
                .provider
                .plan(&authorization, desired, control.clone(), now_unix_ms())
                .await?;
            let applied = self
                .provider
                .apply(&authorization, &plan, now_unix_ms())
                .await?;
            let observed = self
                .provider
                .inspect(&authorization, &target, now_unix_ms())
                .await?;
            let mut receipt = public_receipt(
                self,
                CommerceWebhookBootstrapState::BootstrapReady,
                &input.target,
                &observed,
            )?;
            receipt.operation_id = Some(applied.operation_id);
            receipt.completed_at_unix_ms = applied.completed_at_unix_ms;
            Ok(receipt)
        }
        .await;
        let released = self.release_lease(&control.lease).await;
        match result {
            Ok(receipt) => {
                released?;
                Ok(receipt)
            }
            Err(error) => {
                let _ = released;
                Err(error)
            }
        }
    }
}

fn existing_receipt(
    control: &DeveloperControlPlane,
    target: &DeploymentReferenceInput,
    observed: &agent_devkit::ObservedDeploymentState,
) -> DevkitResult<CommerceWebhookBootstrapReceipt> {
    let state = if observed
        .resource_facts
        .get("commerce_enabled")
        .and_then(Value::as_bool)
        == Some(true)
    {
        CommerceWebhookBootstrapState::CommerceActive
    } else {
        CommerceWebhookBootstrapState::ExistingEntitlement
    };
    public_receipt(control, state, target, observed)
}

fn public_receipt(
    control: &DeveloperControlPlane,
    state: CommerceWebhookBootstrapState,
    target: &DeploymentReferenceInput,
    observed: &agent_devkit::ObservedDeploymentState,
) -> DevkitResult<CommerceWebhookBootstrapReceipt> {
    let version_id = observed.remote_version.clone().ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::VerificationFailed,
            "the Creem webhook Worker omitted its active version",
        )
    })?;
    let endpoint = public_fact_string(observed, "entitlement_url").ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::VerificationFailed,
            "the Creem webhook Worker omitted its public endpoint",
        )
    })?;
    let webhook_url = public_fact_string(observed, "commerce_webhook_url").ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::VerificationFailed,
            "the Creem webhook Worker omitted its webhook URL",
        )
    })?;
    validate_webhook_urls(&endpoint, &webhook_url)?;
    Ok(CommerceWebhookBootstrapReceipt {
        state,
        provider_id: control.provider.describe().provider_id.clone(),
        provider_version: control.provider.describe().provider_version.to_string(),
        target: reference_from_target(&observed.target, target.environment.clone()),
        version_id,
        endpoint,
        webhook_url,
        operation_id: None,
        completed_at_unix_ms: observed.observed_at_unix_ms,
    })
}

fn validate_webhook_urls(endpoint: &str, webhook_url: &str) -> DevkitResult<()> {
    let endpoint = url::Url::parse(endpoint).map_err(|_| {
        DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "the entitlement Worker endpoint is invalid",
        )
    })?;
    let webhook = url::Url::parse(webhook_url).map_err(|_| {
        DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "the Creem webhook URL is invalid",
        )
    })?;
    let trusted = |url: &url::Url| {
        url.scheme() == "https"
            && url.username().is_empty()
            && url.password().is_none()
            && url
                .host_str()
                .is_some_and(|hostname| hostname.ends_with(".workers.dev"))
    };
    if !trusted(&endpoint)
        || !trusted(&webhook)
        || endpoint.origin() != webhook.origin()
        || webhook.path() != CREEM_WEBHOOK_PATH
        || webhook.query().is_some()
        || webhook.fragment().is_some()
    {
        return Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "the Creem webhook URL is not bound to the entitlement Worker",
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn webhook_url_must_match_the_workers_dev_entitlement_origin() {
        assert!(
            validate_webhook_urls(
                "https://example-entitlements.workers.dev",
                "https://example-entitlements.workers.dev/agentweave/commerce/v1/webhooks/creem",
            )
            .is_ok()
        );
        assert!(
            validate_webhook_urls(
                "https://example-entitlements.workers.dev",
                "https://attacker.example/agentweave/commerce/v1/webhooks/creem",
            )
            .is_err()
        );
        assert!(
            validate_webhook_urls(
                "https://example-entitlements.workers.dev",
                "https://example-entitlements.workers.dev/other",
            )
            .is_err()
        );
    }
}
