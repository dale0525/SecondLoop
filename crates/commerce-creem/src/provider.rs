use crate::{
    CreemClient, CreemSubscriptionEvent, CreemTransport, CreemWebhookSecret,
    creem_provider_descriptor, parse_creem_event, reduce_subscription_event, verify_creem_webhook,
};
use agent_devkit::ProviderDescriptor;
use async_trait::async_trait;
use commerce_runtime::{
    CheckoutSession, CommerceEnvironment, CommerceError, CommerceProduct, CommerceProvider,
    CommerceSubject, CreateCheckoutRequest, CreateCustomerPortalRequest, CustomerPortalSession,
    SubscriptionFact, VerifiedWebhookEvent,
};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::sync::Arc;
use url::Url;

#[async_trait]
pub trait CreemCommerceStore: Send + Sync {
    async fn subject_ref(&self, subject: &CommerceSubject) -> Result<String, CommerceError>;

    async fn customer_id(&self, subject: &CommerceSubject)
    -> Result<Option<String>, CommerceError>;

    async fn consume_portal_nonce(
        &self,
        subject: &CommerceSubject,
        nonce: &str,
    ) -> Result<(), CommerceError>;

    async fn current_subscription(
        &self,
        subscription_id: &str,
    ) -> Result<Option<SubscriptionFact>, CommerceError>;
}

pub struct CreemProvider<T, S> {
    descriptor: ProviderDescriptor,
    environment: CommerceEnvironment,
    client: CreemClient<T>,
    webhook_secret: CreemWebhookSecret,
    success_url: Url,
    plan_products: BTreeMap<String, String>,
    store: Arc<S>,
}

impl<T, S> CreemProvider<T, S>
where
    T: CreemTransport,
    S: CreemCommerceStore,
{
    pub fn new(
        environment: CommerceEnvironment,
        client: CreemClient<T>,
        webhook_secret: CreemWebhookSecret,
        success_url: Url,
        plan_products: BTreeMap<String, String>,
        store: Arc<S>,
    ) -> Result<Self, CommerceError> {
        validate_success_url(&success_url)?;
        if plan_products.is_empty()
            || plan_products.len() > 256
            || plan_products.iter().any(|(plan, product)| {
                plan.is_empty()
                    || plan.len() > 128
                    || plan.chars().any(char::is_control)
                    || !valid_provider_id(product, "prod_")
            })
        {
            return Err(CommerceError::InvalidRequest);
        }
        let descriptor = creem_provider_descriptor();
        descriptor
            .validate()
            .map_err(|_| CommerceError::InvalidRequest)?;
        Ok(Self {
            descriptor,
            environment,
            client,
            webhook_secret,
            success_url,
            plan_products,
            store,
        })
    }

    fn plan_for_product(&self, product_id: &str) -> Result<&str, CommerceError> {
        let mut matches = self
            .plan_products
            .iter()
            .filter(|(_, product)| product.as_str() == product_id)
            .map(|(plan, _)| plan.as_str());
        let plan = matches.next().ok_or(CommerceError::ProviderRejected)?;
        if matches.next().is_some() {
            return Err(CommerceError::Conflict);
        }
        Ok(plan)
    }

    fn ensure_event_environment(
        &self,
        event: &CreemSubscriptionEvent,
    ) -> Result<(), CommerceError> {
        (event.verified.environment == self.environment)
            .then_some(())
            .ok_or(CommerceError::EnvironmentMismatch)
    }
}

#[async_trait]
impl<T, S> CommerceProvider for CreemProvider<T, S>
where
    T: CreemTransport,
    S: CreemCommerceStore,
{
    fn describe(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    async fn list_products(&self) -> Result<Vec<CommerceProduct>, CommerceError> {
        self.client.list_products().await
    }

    async fn create_checkout(
        &self,
        request: &CreateCheckoutRequest,
    ) -> Result<CheckoutSession, CommerceError> {
        request.subject.validate()?;
        let product_id = self
            .plan_products
            .get(&request.plan_id)
            .ok_or(CommerceError::ProviderRejected)?;
        let subject_ref = self.store.subject_ref(&request.subject).await?;
        validate_subject_ref(&subject_ref)?;
        let customer_id = self.store.customer_id(&request.subject).await?;
        self.client
            .create_checkout_for_customer(
                product_id,
                &request.request_id,
                &self.success_url,
                BTreeMap::from([
                    ("agentweaveAppId".into(), request.subject.app_id.clone()),
                    ("agentweaveSubjectRef".into(), subject_ref),
                    ("agentweavePlanId".into(), request.plan_id.clone()),
                ]),
                customer_id.as_deref(),
            )
            .await
    }

    async fn create_customer_portal(
        &self,
        request: &CreateCustomerPortalRequest,
    ) -> Result<CustomerPortalSession, CommerceError> {
        request.subject.validate()?;
        validate_nonce(&request.request_nonce)?;
        self.store
            .consume_portal_nonce(&request.subject, &request.request_nonce)
            .await?;
        let customer_id = self
            .store
            .customer_id(&request.subject)
            .await?
            .ok_or(CommerceError::CustomerUnbound)?;
        self.client.create_customer_portal(&customer_id).await
    }

    async fn reconcile_subscription(
        &self,
        subscription_id: &str,
    ) -> Result<SubscriptionFact, CommerceError> {
        let object = self.client.get_subscription(subscription_id).await?;
        let body_hash = hex::encode(Sha256::digest(
            serde_json::to_vec(&object).map_err(|_| CommerceError::InvalidResponse)?,
        ));
        let envelope = serde_json::to_vec(&json!({
            "id": format!("evt_reconcile_{}", &body_hash[..32]),
            "eventType": "subscription.update",
            "created_at": 0,
            "object": object,
        }))
        .map_err(|_| CommerceError::InvalidResponse)?;
        let event = parse_creem_event(&envelope)?;
        self.ensure_event_environment(&event)?;
        let plan_id = self.plan_for_product(&event.product_id)?;
        let current = self.store.current_subscription(subscription_id).await?;
        reduce_subscription_event(&event, current.as_ref(), plan_id)
    }

    fn verify_webhook(
        &self,
        raw_body: &[u8],
        signature: &str,
    ) -> Result<VerifiedWebhookEvent, CommerceError> {
        let event = verify_creem_webhook(&self.webhook_secret, raw_body, signature)?;
        self.ensure_event_environment(&event)?;
        Ok(event.verified)
    }
}

fn validate_success_url(url: &Url) -> Result<(), CommerceError> {
    (url.scheme() == "https"
        && url.host_str().is_some()
        && url.username().is_empty()
        && url.password().is_none()
        && url.fragment().is_none())
    .then_some(())
    .ok_or(CommerceError::InvalidRequest)
}

fn valid_provider_id(value: &str, prefix: &str) -> bool {
    value.starts_with(prefix)
        && value.len() <= 256
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
}

fn validate_subject_ref(value: &str) -> Result<(), CommerceError> {
    (value.starts_with("v1_")
        && value.len() <= 256
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-')))
    .then_some(())
    .ok_or(CommerceError::InvalidRequest)
}

fn validate_nonce(value: &str) -> Result<(), CommerceError> {
    ((16..=256).contains(&value.len())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-')))
    .then_some(())
    .ok_or(CommerceError::InvalidRequest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{CreemApiKey, CreemMethod, CreemRequest, CreemResponse};
    use std::sync::Mutex;

    struct FakeTransport {
        responses: Mutex<Vec<CreemResponse>>,
        requests: Mutex<Vec<CreemRequest>>,
    }

    #[async_trait]
    impl CreemTransport for FakeTransport {
        async fn execute(&self, request: CreemRequest) -> Result<CreemResponse, CommerceError> {
            self.requests.lock().unwrap().push(request);
            Ok(self.responses.lock().unwrap().remove(0))
        }
    }

    struct FakeStore;

    #[async_trait]
    impl CreemCommerceStore for FakeStore {
        async fn subject_ref(&self, _subject: &CommerceSubject) -> Result<String, CommerceError> {
            Ok("v1_opaque_subject".into())
        }

        async fn customer_id(
            &self,
            _subject: &CommerceSubject,
        ) -> Result<Option<String>, CommerceError> {
            Ok(Some("cust_123".into()))
        }

        async fn consume_portal_nonce(
            &self,
            _subject: &CommerceSubject,
            _nonce: &str,
        ) -> Result<(), CommerceError> {
            Ok(())
        }

        async fn current_subscription(
            &self,
            _subscription_id: &str,
        ) -> Result<Option<SubscriptionFact>, CommerceError> {
            Ok(None)
        }
    }

    fn subject() -> CommerceSubject {
        CommerceSubject {
            app_id: "com.example.agent".into(),
            identity_provider_id: "oidc".into(),
            issuer: "https://identity.example.test".into(),
            tenant_id: "tenant".into(),
            subject: "subject".into(),
        }
    }

    fn provider(
        response: serde_json::Value,
    ) -> (Arc<FakeTransport>, CreemProvider<FakeTransport, FakeStore>) {
        let transport = Arc::new(FakeTransport {
            responses: Mutex::new(vec![CreemResponse {
                status: 200,
                body: serde_json::to_vec(&response).unwrap(),
                retry_after_seconds: None,
            }]),
            requests: Mutex::new(Vec::new()),
        });
        let client = CreemClient::new(
            CommerceEnvironment::Test,
            CreemApiKey::new("test-api-key-sentinel").unwrap(),
            Arc::clone(&transport),
        );
        let provider = CreemProvider::new(
            CommerceEnvironment::Test,
            client,
            CreemWebhookSecret::new(b"webhook-secret-sentinel".to_vec()).unwrap(),
            Url::parse("https://example.test/billing/success").unwrap(),
            BTreeMap::from([("pro".into(), "prod_123".into())]),
            Arc::new(FakeStore),
        )
        .unwrap();
        (transport, provider)
    }

    #[tokio::test]
    async fn portal_uses_only_the_store_bound_customer() {
        let (transport, provider) = provider(json!({
            "customer_portal_link": "https://app.creem.io/customer/session"
        }));
        let session = provider
            .create_customer_portal(&CreateCustomerPortalRequest {
                subject: subject(),
                request_nonce: "nonce_1234567890123456".into(),
            })
            .await
            .unwrap();
        assert_eq!(session.portal_url.host_str(), Some("app.creem.io"));
        let request = &transport.requests.lock().unwrap()[0];
        assert_eq!(request.method, CreemMethod::Post);
        let body: serde_json::Value =
            serde_json::from_slice(request.body.as_ref().unwrap()).unwrap();
        assert_eq!(body, json!({"customer_id": "cust_123"}));
        assert!(!body.to_string().contains("subject"));
        assert_eq!(provider.describe().provider_id, crate::CREEM_PROVIDER_ID);
    }

    #[tokio::test]
    async fn checkout_projects_plan_and_bound_customer() {
        let (transport, provider) = provider(json!({
            "id": "ch_123", "mode": "test",
            "checkout_url": "https://checkout.creem.io/session"
        }));
        provider
            .create_checkout(&CreateCheckoutRequest {
                subject: subject(),
                plan_id: "pro".into(),
                request_id: "request_1234567890123456".into(),
            })
            .await
            .unwrap();
        let body: serde_json::Value =
            serde_json::from_slice(transport.requests.lock().unwrap()[0].body.as_ref().unwrap())
                .unwrap();
        assert_eq!(body["product_id"], "prod_123");
        assert_eq!(body["customer"]["id"], "cust_123");
        assert_eq!(
            body["metadata"]["agentweaveSubjectRef"],
            "v1_opaque_subject"
        );
    }
}
