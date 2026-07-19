mod support;

use agent_runtime::entitlement::{
    EntitlementCommitRequest, EntitlementDenialReason, EntitlementProvider,
    EntitlementProviderError, EntitlementProviderErrorCode, EntitlementReleaseRequest,
    EntitlementReservationDecision, EntitlementSettlementState, UsageUnits, commit_entitlement,
    release_entitlement, reserve_entitlement,
};
use chrono::Duration;
use entitlement_providers::{StaticEntitlementConfig, StaticEntitlementProvider};
use std::collections::BTreeMap;
use std::sync::Arc;
use support::{ManualClock, context_at, fixed_now, granted, request};

fn provider(clock: Arc<ManualClock>, requests: u64, tokens: u64) -> StaticEntitlementProvider {
    StaticEntitlementProvider::with_clock(
        StaticEntitlementConfig {
            allow: true,
            quota: BTreeMap::from([("requests".into(), requests), ("tokens".into(), tokens)]),
            reservation_ttl_seconds: 300,
        },
        clock,
    )
    .unwrap()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_reservations_never_oversell_memory_quota() {
    let now = fixed_now();
    let clock = Arc::new(ManualClock::new(now));
    let provider = Arc::new(provider(clock, 10, 100));
    let mut tasks = Vec::new();
    for sequence in 0..20 {
        let provider = provider.clone();
        tasks.push(tokio::spawn(async move {
            reserve_entitlement(
                provider.as_ref(),
                &context_at(now),
                &request(sequence, 10),
                now,
            )
            .await
            .unwrap()
        }));
    }

    let mut granted_count = 0;
    let mut denied_count = 0;
    for task in tasks {
        match task.await.unwrap() {
            EntitlementReservationDecision::Granted(_) => granted_count += 1,
            EntitlementReservationDecision::Denied(denial) => {
                assert_eq!(denial.reason, EntitlementDenialReason::QuotaExceeded);
                denied_count += 1;
            }
        }
    }
    assert_eq!(granted_count, 10);
    assert_eq!(denied_count, 10);
}

#[tokio::test]
async fn reserve_commit_and_release_are_idempotent_without_double_accounting() {
    let now = fixed_now();
    let clock = Arc::new(ManualClock::new(now));
    let provider = provider(clock, 10, 100);
    let context = context_at(now);
    let first_request = request(1, 80);
    let first = granted(
        reserve_entitlement(&provider, &context, &first_request, now)
            .await
            .unwrap(),
    );
    let replay = granted(
        reserve_entitlement(&provider, &context, &first_request, now)
            .await
            .unwrap(),
    );
    assert_eq!(first, replay);

    let commit = EntitlementCommitRequest {
        reservation_id: first.reservation_id.clone(),
        settlement_id: "settlement-1".into(),
        actual_usage: UsageUnits {
            units: BTreeMap::from([("requests".into(), 1), ("tokens".into(), 20)]),
        },
    };
    let first_receipt =
        commit_entitlement(&provider, &context, &first_request, &first, &commit, now)
            .await
            .unwrap();
    let replayed_receipt =
        commit_entitlement(&provider, &context, &first_request, &first, &commit, now)
            .await
            .unwrap();
    assert_eq!(first_receipt, replayed_receipt);

    let second_request = request(2, 80);
    let second = granted(
        reserve_entitlement(&provider, &context, &second_request, now)
            .await
            .unwrap(),
    );
    let release = EntitlementReleaseRequest {
        reservation_id: second.reservation_id.clone(),
        release_id: "release-2".into(),
    };
    let released =
        release_entitlement(&provider, &context, &second_request, &second, &release, now)
            .await
            .unwrap();
    let replayed_release =
        release_entitlement(&provider, &context, &second_request, &second, &release, now)
            .await
            .unwrap();
    assert_eq!(released, replayed_release);
    assert_eq!(released.state, EntitlementSettlementState::Released);

    assert!(matches!(
        reserve_entitlement(&provider, &context, &request(3, 80), now)
            .await
            .unwrap(),
        EntitlementReservationDecision::Granted(_)
    ));
}

#[tokio::test]
async fn conflicting_idempotency_and_overage_settlement_fail_closed() {
    let now = fixed_now();
    let clock = Arc::new(ManualClock::new(now));
    let provider = provider(clock, 10, 100);
    let context = context_at(now);
    let original_request = request(1, 50);
    let reservation = granted(
        reserve_entitlement(&provider, &context, &original_request, now)
            .await
            .unwrap(),
    );

    let mut conflicting = original_request.clone();
    conflicting
        .requested_usage
        .units
        .insert("tokens".into(), 49);
    assert_eq!(
        provider.reserve(&context, &conflicting).await.unwrap_err(),
        EntitlementProviderError::new(EntitlementProviderErrorCode::Conflict)
    );

    let overage = EntitlementCommitRequest {
        reservation_id: reservation.reservation_id.clone(),
        settlement_id: "overage".into(),
        actual_usage: UsageUnits {
            units: BTreeMap::from([("requests".into(), 1), ("tokens".into(), 51)]),
        },
    };
    assert_eq!(
        commit_entitlement(
            &provider,
            &context,
            &original_request,
            &reservation,
            &overage,
            now,
        )
        .await
        .unwrap_err(),
        EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidRequest)
    );
}

#[tokio::test]
async fn expired_holds_are_refunded_but_the_original_key_stays_terminal() {
    let now = fixed_now();
    let clock = Arc::new(ManualClock::new(now));
    let provider = provider(clock.clone(), 1, 100);
    let context = context_at(now);
    let original = request(1, 100);
    reserve_entitlement(&provider, &context, &original, now)
        .await
        .unwrap();
    clock.advance(Duration::minutes(6));
    let later = now + Duration::minutes(6);

    assert_eq!(
        provider.reserve(&context, &original).await.unwrap_err(),
        EntitlementProviderError::new(EntitlementProviderErrorCode::ReservationExpired)
    );
    assert!(matches!(
        reserve_entitlement(&provider, &context, &request(2, 100), later)
            .await
            .unwrap(),
        EntitlementReservationDecision::Granted(_)
    ));
}

#[tokio::test]
async fn fixed_deny_never_allocates_quota() {
    let now = fixed_now();
    let provider = StaticEntitlementProvider::with_clock(
        StaticEntitlementConfig {
            allow: false,
            quota: BTreeMap::new(),
            reservation_ttl_seconds: 300,
        },
        Arc::new(ManualClock::new(now)),
    )
    .unwrap();
    let decision = reserve_entitlement(&provider, &context_at(now), &request(1, 1), now)
        .await
        .unwrap();
    assert!(matches!(
        decision,
        EntitlementReservationDecision::Denied(denial)
            if denial.reason == EntitlementDenialReason::NotEntitled
    ));
}
