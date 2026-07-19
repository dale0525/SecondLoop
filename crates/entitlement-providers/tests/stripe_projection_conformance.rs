mod support;

use agent_runtime::entitlement::{
    EntitlementDenialReason, EntitlementProvider, EntitlementProviderError,
    EntitlementProviderErrorCode, EntitlementReservationDecision, EntitlementResource, UsageUnits,
    reserve_entitlement,
};
use agent_runtime::identity::SecurityContext;
use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use entitlement_providers::{
    STRIPE_ENTITLEMENT_PROJECTION_SCHEMA_VERSION, StripeEntitlementProjection,
    StripeEntitlementProjectionSource, StripeProjectionConfig, StripeProjectionEntitlementProvider,
    StripeProjectionSourceError, StripeProjectionSourceErrorCode,
};
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use support::{ManualClock, context_at, fixed_now, request};

struct FakeVerifiedProjectionSource {
    projection: Mutex<StripeEntitlementProjection>,
    calls: AtomicUsize,
}

#[async_trait]
impl StripeEntitlementProjectionSource for FakeVerifiedProjectionSource {
    fn source_id(&self) -> &str {
        "developer-backend-projection"
    }

    async fn projection(
        &self,
        _context: &SecurityContext,
        _resource: &EntitlementResource,
    ) -> Result<StripeEntitlementProjection, StripeProjectionSourceError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(self.projection.lock().unwrap().clone())
    }
}

struct FailingProjectionSource;

#[async_trait]
impl StripeEntitlementProjectionSource for FailingProjectionSource {
    fn source_id(&self) -> &str {
        "developer-backend-projection"
    }

    async fn projection(
        &self,
        _context: &SecurityContext,
        _resource: &EntitlementResource,
    ) -> Result<StripeEntitlementProjection, StripeProjectionSourceError> {
        Err(StripeProjectionSourceError::new(
            StripeProjectionSourceErrorCode::VerificationFailed,
        ))
    }
}

fn config() -> StripeProjectionConfig {
    StripeProjectionConfig {
        projection_source_id: "developer-backend-projection".into(),
        reservation_ttl_seconds: 300,
        max_projection_age_seconds: 300,
    }
}

fn entitled_projection(
    now: DateTime<Utc>,
    context: &SecurityContext,
    resource: EntitlementResource,
) -> StripeEntitlementProjection {
    StripeEntitlementProjection {
        schema_version: STRIPE_ENTITLEMENT_PROJECTION_SCHEMA_VERSION,
        source_id: "developer-backend-projection".into(),
        projection_id: "projection-42".into(),
        quota_window_id: Some("billing-window-2026-07".into()),
        app_id: context.app_id.clone(),
        tenant_id: context.tenant_id.clone(),
        audience: context.audience.clone(),
        principal: context.principal.clone(),
        resource,
        entitled: true,
        denial_reason: None,
        quota: Some(UsageUnits {
            units: BTreeMap::from([("requests".into(), 10), ("tokens".into(), 100)]),
        }),
        issued_at: now - Duration::seconds(10),
        expires_at: now + Duration::hours(1),
    }
}

fn provider(
    clock: Arc<ManualClock>,
    source: Arc<dyn StripeEntitlementProjectionSource>,
) -> StripeProjectionEntitlementProvider {
    StripeProjectionEntitlementProvider::with_clock(config(), source, clock).unwrap()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn verified_projection_quota_is_atomic_under_concurrency() {
    let now = fixed_now();
    let context = context_at(now);
    let source = Arc::new(FakeVerifiedProjectionSource {
        projection: Mutex::new(entitled_projection(now, &context, request(0, 1).resource)),
        calls: AtomicUsize::new(0),
    });
    let provider = Arc::new(provider(Arc::new(ManualClock::new(now)), source.clone()));
    let mut tasks = Vec::new();
    for sequence in 0..20 {
        let provider = provider.clone();
        let context = context.clone();
        tasks.push(tokio::spawn(async move {
            reserve_entitlement(provider.as_ref(), &context, &request(sequence, 10), now)
                .await
                .unwrap()
        }));
    }

    let mut granted = 0;
    let mut denied = 0;
    for task in tasks {
        match task.await.unwrap() {
            EntitlementReservationDecision::Granted(_) => granted += 1,
            EntitlementReservationDecision::Denied(value) => {
                assert_eq!(value.reason, EntitlementDenialReason::QuotaExceeded);
                denied += 1;
            }
        }
    }
    assert_eq!((granted, denied), (10, 10));
    assert_eq!(source.calls.load(Ordering::SeqCst), 20);
}

#[tokio::test]
async fn idempotent_replay_uses_the_local_verified_projection_record() {
    let now = fixed_now();
    let context = context_at(now);
    let reservation_request = request(1, 10);
    let source = Arc::new(FakeVerifiedProjectionSource {
        projection: Mutex::new(entitled_projection(
            now,
            &context,
            reservation_request.resource.clone(),
        )),
        calls: AtomicUsize::new(0),
    });
    let provider = provider(Arc::new(ManualClock::new(now)), source.clone());
    let first = reserve_entitlement(&provider, &context, &reservation_request, now)
        .await
        .unwrap();
    let second = reserve_entitlement(&provider, &context, &reservation_request, now)
        .await
        .unwrap();
    assert_eq!(first, second);
    assert_eq!(source.calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn verified_not_entitled_projection_returns_a_bound_denial() {
    let now = fixed_now();
    let context = context_at(now);
    let reservation_request = request(1, 10);
    let mut projection = entitled_projection(now, &context, reservation_request.resource.clone());
    projection.entitled = false;
    projection.quota = None;
    projection.quota_window_id = None;
    projection.denial_reason = Some(EntitlementDenialReason::ResourceDenied);
    let source = Arc::new(FakeVerifiedProjectionSource {
        projection: Mutex::new(projection),
        calls: AtomicUsize::new(0),
    });
    let provider = provider(Arc::new(ManualClock::new(now)), source);

    assert!(matches!(
        reserve_entitlement(&provider, &context, &reservation_request, now)
            .await
            .unwrap(),
        EntitlementReservationDecision::Denied(denial)
            if denial.reason == EntitlementDenialReason::ResourceDenied
    ));
}

#[tokio::test]
async fn source_failure_and_invalid_projection_fail_closed() {
    let now = fixed_now();
    let context = context_at(now);
    let reservation_request = request(1, 10);
    let failed = provider(
        Arc::new(ManualClock::new(now)),
        Arc::new(FailingProjectionSource),
    );
    assert_eq!(
        failed
            .reserve(&context, &reservation_request)
            .await
            .unwrap_err(),
        EntitlementProviderError::new(EntitlementProviderErrorCode::Unavailable)
    );

    let mut mismatched = entitled_projection(now, &context, reservation_request.resource.clone());
    mismatched.principal.subject = "other-user".into();
    let invalid = provider(
        Arc::new(ManualClock::new(now)),
        Arc::new(FakeVerifiedProjectionSource {
            projection: Mutex::new(mismatched),
            calls: AtomicUsize::new(0),
        }),
    );
    assert_eq!(
        invalid
            .reserve(&context, &reservation_request)
            .await
            .unwrap_err(),
        EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidResponse)
    );
}

#[tokio::test]
async fn stale_projection_is_rejected_without_allocating_quota() {
    let now = fixed_now();
    let context = context_at(now);
    let reservation_request = request(1, 10);
    let mut stale = entitled_projection(now, &context, reservation_request.resource.clone());
    stale.issued_at = now - Duration::minutes(6);
    let provider = provider(
        Arc::new(ManualClock::new(now)),
        Arc::new(FakeVerifiedProjectionSource {
            projection: Mutex::new(stale),
            calls: AtomicUsize::new(0),
        }),
    );
    assert_eq!(
        provider
            .reserve(&context, &reservation_request)
            .await
            .unwrap_err(),
        EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidResponse)
    );
}

#[test]
fn config_and_projection_reject_client_side_stripe_secrets_and_commerce_fields() {
    assert!(
        serde_json::from_value::<StripeProjectionConfig>(serde_json::json!({
            "projectionSourceId": "developer-backend-projection",
            "stripeSecretKey": "sk_secret_sentinel"
        }))
        .is_err()
    );

    let now = fixed_now();
    let context = context_at(now);
    let projection = entitled_projection(now, &context, request(1, 1).resource);
    let mut value = serde_json::to_value(&projection).unwrap();
    value["stripeWebhookSecret"] = serde_json::json!("whsec_secret_sentinel");
    assert!(serde_json::from_value::<StripeEntitlementProjection>(value).is_err());

    let serialized = serde_json::to_string(&config()).unwrap();
    for forbidden in ["sk_secret", "whsec_", "tax", "refund", "paymentMethod"] {
        assert!(!serialized.contains(forbidden));
    }
}
