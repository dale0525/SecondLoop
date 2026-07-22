use crate::state::SubscriptionFact;
use agent_devkit::ProviderDescriptor;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use url::Url;

pub const CHECKOUT_SESSION_CAPABILITY: &str = "checkout_session_v1";
pub const CUSTOMER_PORTAL_CAPABILITY: &str = "customer_portal_v1";
pub const PRODUCT_DISCOVERY_CAPABILITY: &str = "product_discovery_v1";
pub const SIGNED_WEBHOOK_CAPABILITY: &str = "signed_webhook_v1";
pub const SUBSCRIPTION_RECONCILIATION_CAPABILITY: &str = "subscription_reconciliation_v1";
pub const TEST_ENVIRONMENT_CAPABILITY: &str = "test_environment_v1";

pub const REQUIRED_SUBSCRIPTION_CAPABILITIES: [&str; 6] = [
    CHECKOUT_SESSION_CAPABILITY,
    CUSTOMER_PORTAL_CAPABILITY,
    PRODUCT_DISCOVERY_CAPABILITY,
    SIGNED_WEBHOOK_CAPABILITY,
    SUBSCRIPTION_RECONCILIATION_CAPABILITY,
    TEST_ENVIRONMENT_CAPABILITY,
];

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CommerceEnvironment {
    Test,
    Production,
}

impl CommerceEnvironment {
    pub const fn provider_mode(self) -> &'static str {
        match self {
            Self::Test => "test",
            Self::Production => "prod",
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CommerceSubject {
    pub app_id: String,
    pub identity_provider_id: String,
    pub issuer: String,
    pub tenant_id: String,
    pub subject: String,
}

impl CommerceSubject {
    pub fn validate(&self) -> Result<(), CommerceError> {
        for value in [
            self.app_id.as_str(),
            self.identity_provider_id.as_str(),
            self.issuer.as_str(),
            self.tenant_id.as_str(),
            self.subject.as_str(),
        ] {
            if value.is_empty()
                || value.len() > 2_048
                || value != value.trim()
                || value.chars().any(char::is_control)
            {
                return Err(CommerceError::InvalidRequest);
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CommerceProduct {
    pub id: String,
    pub name: String,
    pub description: String,
    pub environment: CommerceEnvironment,
    pub price_minor: u64,
    pub currency: String,
    pub billing_type: String,
    pub billing_period: String,
    pub active: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateCheckoutRequest {
    pub subject: CommerceSubject,
    pub plan_id: String,
    pub request_id: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CheckoutSession {
    pub checkout_id: String,
    pub checkout_url: Url,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateCustomerPortalRequest {
    pub subject: CommerceSubject,
    pub request_nonce: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CustomerPortalSession {
    pub portal_url: Url,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct VerifiedWebhookEvent {
    pub event_id: String,
    pub event_type: String,
    pub environment: CommerceEnvironment,
    pub provider_created_at_unix_ms: i64,
    pub body_sha256: String,
    pub normalized: BTreeMap<String, String>,
}

#[derive(Clone, Copy, Debug, thiserror::Error, Eq, PartialEq)]
pub enum CommerceError {
    #[error("commerce request is invalid")]
    InvalidRequest,
    #[error("commerce authentication is required")]
    AuthenticationRequired,
    #[error("commerce customer is not bound")]
    CustomerUnbound,
    #[error("commerce environment does not match")]
    EnvironmentMismatch,
    #[error("commerce provider rejected the request")]
    ProviderRejected,
    #[error("commerce provider is unavailable")]
    Unavailable,
    #[error("commerce provider response is invalid")]
    InvalidResponse,
    #[error("commerce webhook signature is invalid")]
    InvalidWebhookSignature,
    #[error("commerce event conflicts with existing facts")]
    Conflict,
}

#[async_trait]
pub trait CommerceProvider: Send + Sync {
    fn describe(&self) -> &ProviderDescriptor;

    async fn list_products(&self) -> Result<Vec<CommerceProduct>, CommerceError>;

    async fn create_checkout(
        &self,
        request: &CreateCheckoutRequest,
    ) -> Result<CheckoutSession, CommerceError>;

    async fn create_customer_portal(
        &self,
        request: &CreateCustomerPortalRequest,
    ) -> Result<CustomerPortalSession, CommerceError>;

    async fn reconcile_subscription(
        &self,
        subscription_id: &str,
    ) -> Result<SubscriptionFact, CommerceError>;

    fn verify_webhook(
        &self,
        raw_body: &[u8],
        signature: &str,
    ) -> Result<VerifiedWebhookEvent, CommerceError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subject_rejects_blank_or_control_text() {
        let mut subject = CommerceSubject {
            app_id: "com.example.agent".into(),
            identity_provider_id: "agentweave.identity.firebase".into(),
            issuer: "https://securetoken.google.com/example".into(),
            tenant_id: "default".into(),
            subject: "subject-1".into(),
        };
        subject.validate().unwrap();
        subject.subject = "bad\nsubject".into();
        assert_eq!(subject.validate(), Err(CommerceError::InvalidRequest));
    }

    #[test]
    fn complete_subscription_capability_set_includes_portal() {
        assert!(REQUIRED_SUBSCRIPTION_CAPABILITIES.contains(&CUSTOMER_PORTAL_CAPABILITY));
        assert_eq!(REQUIRED_SUBSCRIPTION_CAPABILITIES.len(), 6);
    }
}
