mod support;

use agent_runtime::entitlement::{
    ENTITLEMENT_RESERVATION_SCHEMA_VERSION, EntitlementCommitRequest, EntitlementProvider,
    EntitlementProviderError, EntitlementProviderErrorCode, EntitlementReleaseRequest,
    EntitlementReservation, EntitlementReservationDecision, EntitlementReservationRequest,
    EntitlementSettlementReceipt, EntitlementSettlementState, UsageUnits, commit_entitlement,
    release_entitlement, reserve_entitlement,
};
use agent_runtime::identity::SecurityContext;
use async_trait::async_trait;
use chrono::{Duration, Utc};
use entitlement_providers::{
    HTTP_ENTITLEMENT_PROVIDER_ID, HttpEntitlementConfig, HttpEntitlementOperation,
    HttpEntitlementProvider, HttpEntitlementTransport, HttpEntitlementTransportError,
    HttpEntitlementTransportErrorCode, HttpEntitlementTransportRequest,
    HttpEntitlementTransportResponse, ServiceSecret, ServiceSecretResolveError,
    ServiceSecretResolveErrorCode, ServiceSecretResolver,
};
use serde_json::{Value, json};
use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration as StdDuration;
use support::{context_at, granted, request};

const SECRET_SENTINEL: &[u8] = b"service-secret-sentinel-never-log";

struct FixedSecretResolver;

#[async_trait]
impl ServiceSecretResolver for FixedSecretResolver {
    async fn resolve(&self, secret_id: &str) -> Result<ServiceSecret, ServiceSecretResolveError> {
        if secret_id != "vault:model-entitlement-service" {
            return Err(ServiceSecretResolveError::new(
                ServiceSecretResolveErrorCode::NotFound,
            ));
        }
        ServiceSecret::new(SECRET_SENTINEL.to_vec())
            .map_err(|_| ServiceSecretResolveError::new(ServiceSecretResolveErrorCode::Unavailable))
    }
}

#[derive(Clone)]
struct CachedExchange {
    operation: HttpEntitlementOperation,
    body: Vec<u8>,
    response: HttpEntitlementTransportResponse,
}

#[derive(Default)]
struct FakeServerState {
    cache: HashMap<String, CachedExchange>,
    processed: usize,
    executed: usize,
    endpoints: Vec<String>,
    idempotency_keys: Vec<String>,
    request_debug: Vec<String>,
    saw_expected_secret: bool,
}

#[derive(Default)]
struct ConformanceTransport {
    state: Mutex<FakeServerState>,
}

impl ConformanceTransport {
    fn processed(&self) -> usize {
        self.state.lock().unwrap().processed
    }

    fn executed(&self) -> usize {
        self.state.lock().unwrap().executed
    }
}

#[async_trait]
impl HttpEntitlementTransport for ConformanceTransport {
    async fn execute(
        &self,
        request: HttpEntitlementTransportRequest,
    ) -> Result<HttpEntitlementTransportResponse, HttpEntitlementTransportError> {
        let mut state = self.state.lock().unwrap();
        state.executed += 1;
        state.endpoints.push(request.endpoint().to_string());
        state
            .idempotency_keys
            .push(request.idempotency_key().to_owned());
        state.request_debug.push(format!("{request:?}"));
        state.saw_expected_secret |=
            request.with_service_secret(|secret| secret == SECRET_SENTINEL);

        if let Some(cached) = state.cache.get(request.idempotency_key()) {
            if cached.operation == request.operation() && cached.body == request.body() {
                return Ok(cached.response.clone());
            }
            return Ok(HttpEntitlementTransportResponse {
                status: 409,
                final_url: request.endpoint().clone(),
                content_type: Some("application/json".into()),
                body: br#"{}"#.to_vec(),
            });
        }
        state.processed += 1;
        let response = fake_server_response(&request, state.processed);
        state.cache.insert(
            request.idempotency_key().to_owned(),
            CachedExchange {
                operation: request.operation(),
                body: request.body().to_vec(),
                response: response.clone(),
            },
        );
        Ok(response)
    }
}

fn fake_server_response(
    transport_request: &HttpEntitlementTransportRequest,
    sequence: usize,
) -> HttpEntitlementTransportResponse {
    let value: Value = serde_json::from_slice(transport_request.body()).unwrap();
    assert_eq!(value["schemaVersion"], 1);
    let now = Utc::now();
    let body = match transport_request.operation() {
        HttpEntitlementOperation::Reserve => {
            let context: SecurityContext =
                serde_json::from_value(value["context"].clone()).unwrap();
            let request: EntitlementReservationRequest =
                serde_json::from_value(value["request"].clone()).unwrap();
            let reservation = EntitlementReservation {
                schema_version: ENTITLEMENT_RESERVATION_SCHEMA_VERSION,
                provider_id: HTTP_ENTITLEMENT_PROVIDER_ID.into(),
                reservation_id: format!("remote-reservation-{sequence}"),
                app_id: context.app_id,
                tenant_id: context.tenant_id,
                audience: context.audience,
                identity_provider_id: context.provider_id,
                identity_authenticated_at: context.authenticated_at,
                principal: context.principal,
                operation_id: request.operation_id,
                idempotency_key: request.idempotency_key,
                resource: request.resource,
                reserved_usage: request.requested_usage,
                created_at: now,
                expires_at: (now + Duration::minutes(5)).min(context.expires_at),
            };
            serde_json::to_vec(&json!({
                "schemaVersion": 1,
                "decision": EntitlementReservationDecision::Granted(Box::new(reservation))
            }))
            .unwrap()
        }
        HttpEntitlementOperation::Commit => {
            let request: EntitlementCommitRequest =
                serde_json::from_value(value["request"].clone()).unwrap();
            settlement_body(EntitlementSettlementReceipt {
                provider_id: HTTP_ENTITLEMENT_PROVIDER_ID.into(),
                reservation_id: request.reservation_id,
                settlement_id: request.settlement_id,
                state: EntitlementSettlementState::Committed,
                charged_usage: Some(request.actual_usage),
                processed_at: now,
            })
        }
        HttpEntitlementOperation::Release => {
            let request: EntitlementReleaseRequest =
                serde_json::from_value(value["request"].clone()).unwrap();
            settlement_body(EntitlementSettlementReceipt {
                provider_id: HTTP_ENTITLEMENT_PROVIDER_ID.into(),
                reservation_id: request.reservation_id,
                settlement_id: request.release_id,
                state: EntitlementSettlementState::Released,
                charged_usage: None,
                processed_at: now,
            })
        }
    };
    HttpEntitlementTransportResponse {
        status: 200,
        final_url: transport_request.endpoint().clone(),
        content_type: Some("application/json; charset=utf-8".into()),
        body,
    }
}

fn settlement_body(receipt: EntitlementSettlementReceipt) -> Vec<u8> {
    serde_json::to_vec(&json!({ "schemaVersion": 1, "receipt": receipt })).unwrap()
}

fn config(timeout_milliseconds: u64, max_response_bytes: usize) -> HttpEntitlementConfig {
    HttpEntitlementConfig {
        base_url: "https://entitlements.example.test/".into(),
        service_secret_id: "vault:model-entitlement-service".into(),
        timeout_milliseconds,
        max_response_bytes,
    }
}

fn provider_with(
    transport: Arc<dyn HttpEntitlementTransport>,
    timeout_milliseconds: u64,
    max_response_bytes: usize,
) -> HttpEntitlementProvider {
    HttpEntitlementProvider::new(
        config(timeout_milliseconds, max_response_bytes),
        Arc::new(FixedSecretResolver),
        transport,
    )
    .unwrap()
}

#[tokio::test]
async fn fake_server_conforms_for_idempotent_reserve_commit_and_release() {
    let now = Utc::now();
    let context = context_at(now);
    let transport = Arc::new(ConformanceTransport::default());
    let provider = provider_with(transport.clone(), 1_000, 64 * 1024);
    let first_request = request(1, 100);
    let first = granted(
        reserve_entitlement(&provider, &context, &first_request, now)
            .await
            .unwrap(),
    );
    let replayed = granted(
        reserve_entitlement(&provider, &context, &first_request, now)
            .await
            .unwrap(),
    );
    assert_eq!(first, replayed);

    let commit = EntitlementCommitRequest {
        reservation_id: first.reservation_id.clone(),
        settlement_id: "settlement-1".into(),
        actual_usage: UsageUnits {
            units: BTreeMap::from([("requests".into(), 1), ("tokens".into(), 90)]),
        },
    };
    let committed = commit_entitlement(
        &provider,
        &context,
        &first_request,
        &first,
        &commit,
        Utc::now(),
    )
    .await
    .unwrap();
    let replayed_commit = commit_entitlement(
        &provider,
        &context,
        &first_request,
        &first,
        &commit,
        Utc::now(),
    )
    .await
    .unwrap();
    assert_eq!(committed, replayed_commit);

    let second_request = request(2, 10);
    let second = granted(
        reserve_entitlement(&provider, &context, &second_request, Utc::now())
            .await
            .unwrap(),
    );
    let release = EntitlementReleaseRequest {
        reservation_id: second.reservation_id.clone(),
        release_id: "release-2".into(),
    };
    let released = release_entitlement(
        &provider,
        &context,
        &second_request,
        &second,
        &release,
        Utc::now(),
    )
    .await
    .unwrap();
    let replayed_release = release_entitlement(
        &provider,
        &context,
        &second_request,
        &second,
        &release,
        Utc::now(),
    )
    .await
    .unwrap();
    assert_eq!(released, replayed_release);
    assert_eq!(transport.processed(), 4);
    assert_eq!(transport.executed(), 7);

    let state = transport.state.lock().unwrap();
    assert!(state.saw_expected_secret);
    assert!(state.endpoints.iter().all(|endpoint| {
        endpoint.starts_with("https://entitlements.example.test/agentweave/entitlements/v1/")
    }));
    assert!(
        state
            .idempotency_keys
            .iter()
            .all(|key| { key.starts_with("v1-") && key.len() == 67 && !key.contains("turn-") })
    );
    assert!(
        state
            .request_debug
            .iter()
            .all(|debug| !debug.contains("service-secret-sentinel"))
    );
}

#[tokio::test]
async fn repeated_key_with_changed_payload_is_a_conflict() {
    let now = Utc::now();
    let context = context_at(now);
    let transport = Arc::new(ConformanceTransport::default());
    let provider = provider_with(transport, 1_000, 64 * 1024);
    let original = request(1, 100);
    provider.reserve(&context, &original).await.unwrap();
    let mut changed = original;
    changed.requested_usage.units.insert("tokens".into(), 99);
    assert_eq!(
        provider.reserve(&context, &changed).await.unwrap_err(),
        EntitlementProviderError::new(EntitlementProviderErrorCode::Conflict)
    );
}

#[tokio::test]
async fn overage_is_rejected_before_the_http_transport_is_called() {
    let now = Utc::now();
    let context = context_at(now);
    let transport = Arc::new(ConformanceTransport::default());
    let provider = provider_with(transport.clone(), 1_000, 64 * 1024);
    let reservation_request = request(1, 10);
    let reservation = granted(
        reserve_entitlement(&provider, &context, &reservation_request, now)
            .await
            .unwrap(),
    );
    let before = transport.executed();
    let overage = EntitlementCommitRequest {
        reservation_id: reservation.reservation_id.clone(),
        settlement_id: "overage".into(),
        actual_usage: UsageUnits {
            units: BTreeMap::from([("requests".into(), 1), ("tokens".into(), 11)]),
        },
    };
    assert_eq!(
        commit_entitlement(
            &provider,
            &context,
            &reservation_request,
            &reservation,
            &overage,
            Utc::now(),
        )
        .await
        .unwrap_err(),
        EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidRequest)
    );
    assert_eq!(transport.executed(), before);
}

struct TimeoutAfterAcceptTransport {
    accepted: AtomicBool,
}

#[async_trait]
impl HttpEntitlementTransport for TimeoutAfterAcceptTransport {
    async fn execute(
        &self,
        _request: HttpEntitlementTransportRequest,
    ) -> Result<HttpEntitlementTransportResponse, HttpEntitlementTransportError> {
        self.accepted.store(true, Ordering::SeqCst);
        tokio::time::sleep(StdDuration::from_secs(1)).await;
        Err(HttpEntitlementTransportError::new(
            HttpEntitlementTransportErrorCode::Protocol,
        ))
    }
}

#[tokio::test]
async fn timeout_after_possible_acceptance_is_uncertain_and_fails_closed_without_retry() {
    let transport = Arc::new(TimeoutAfterAcceptTransport {
        accepted: AtomicBool::new(false),
    });
    let provider = provider_with(transport.clone(), 100, 64 * 1024);
    let now = Utc::now();
    assert_eq!(
        provider
            .reserve(&context_at(now), &request(1, 1))
            .await
            .unwrap_err(),
        EntitlementProviderError::new(EntitlementProviderErrorCode::Unavailable)
    );
    assert!(transport.accepted.load(Ordering::SeqCst));
}

#[derive(Clone, Copy)]
enum BadResponseKind {
    Redirect,
    TooLarge,
    NonJson,
    Malformed,
}

struct BadResponseTransport {
    kind: BadResponseKind,
    calls: AtomicUsize,
}

#[async_trait]
impl HttpEntitlementTransport for BadResponseTransport {
    async fn execute(
        &self,
        request: HttpEntitlementTransportRequest,
    ) -> Result<HttpEntitlementTransportResponse, HttpEntitlementTransportError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let final_url = match self.kind {
            BadResponseKind::Redirect => "https://other.example.test/result".parse().unwrap(),
            _ => request.endpoint().clone(),
        };
        let content_type = match self.kind {
            BadResponseKind::NonJson => Some("text/html".into()),
            _ => Some("application/json".into()),
        };
        let body = match self.kind {
            BadResponseKind::TooLarge => vec![b'x'; 257],
            _ => b"not-json".to_vec(),
        };
        Ok(HttpEntitlementTransportResponse {
            status: 200,
            final_url,
            content_type,
            body,
        })
    }
}

#[tokio::test]
async fn redirect_oversize_wrong_content_type_and_malformed_json_fail_closed() {
    for kind in [
        BadResponseKind::Redirect,
        BadResponseKind::TooLarge,
        BadResponseKind::NonJson,
        BadResponseKind::Malformed,
    ] {
        let transport = Arc::new(BadResponseTransport {
            kind,
            calls: AtomicUsize::new(0),
        });
        let maximum = if matches!(kind, BadResponseKind::TooLarge) {
            256
        } else {
            64 * 1024
        };
        let provider = provider_with(transport.clone(), 1_000, maximum);
        let now = Utc::now();
        assert_eq!(
            provider
                .reserve(&context_at(now), &request(1, 1))
                .await
                .unwrap_err(),
            EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidResponse)
        );
        assert_eq!(transport.calls.load(Ordering::SeqCst), 1);
    }
}

#[test]
fn configuration_accepts_only_https_or_loopback_http_origins() {
    for base_url in [
        "https://entitlements.example.test/",
        "http://localhost:8787/",
        "http://127.0.0.1:8787/",
        "http://[::1]:8787/",
    ] {
        let mut config = config(1_000, 64 * 1024);
        config.base_url = base_url.into();
        assert!(
            config.validate().is_ok(),
            "expected valid origin: {base_url}"
        );
    }
    for base_url in [
        "http://entitlements.example.test/",
        "https://user:password@entitlements.example.test/",
        "https://entitlements.example.test/path/",
        "https://entitlements.example.test/?token=value",
        "https://entitlements.example.test/#fragment",
    ] {
        let mut config = config(1_000, 64 * 1024);
        config.base_url = base_url.into();
        assert!(
            config.validate().is_err(),
            "expected invalid origin: {base_url}"
        );
    }
}

#[tokio::test]
async fn debug_errors_and_serialized_config_never_expose_resolved_secret() {
    let secret = ServiceSecret::new(SECRET_SENTINEL.to_vec()).unwrap();
    assert!(!format!("{secret:?}").contains("service-secret-sentinel"));
    drop(secret);
    let hostile_echo = HttpEntitlementTransportResponse {
        status: 500,
        final_url: "https://entitlements.example.test/".parse().unwrap(),
        content_type: Some("text/plain".into()),
        body: SECRET_SENTINEL.to_vec(),
    };
    assert!(!format!("{hostile_echo:?}").contains("service-secret-sentinel"));

    let transport = Arc::new(ConformanceTransport::default());
    let provider = provider_with(transport.clone(), 1_000, 64 * 1024);
    let now = Utc::now();
    provider
        .reserve(&context_at(now), &request(1, 1))
        .await
        .unwrap();
    let provider_debug = format!("{provider:?}");
    let config_json = serde_json::to_string(&config(1_000, 64 * 1024)).unwrap();
    let error_debug = format!(
        "{:?}",
        HttpEntitlementTransportError::new(HttpEntitlementTransportErrorCode::Connection)
    );
    for output in [provider_debug, config_json, error_debug] {
        assert!(!output.contains("service-secret-sentinel"));
    }
    assert!(
        transport
            .state
            .lock()
            .unwrap()
            .request_debug
            .iter()
            .all(|output| !output.contains("service-secret-sentinel"))
    );
}
