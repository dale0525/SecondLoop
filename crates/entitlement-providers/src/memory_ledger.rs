use crate::EntitlementClock;
use agent_runtime::entitlement::{
    ENTITLEMENT_RESERVATION_SCHEMA_VERSION, EntitlementCommitRequest, EntitlementDenial,
    EntitlementDenialReason, EntitlementProviderError, EntitlementProviderErrorCode,
    EntitlementReleaseRequest, EntitlementReservation, EntitlementReservationDecision,
    EntitlementReservationRequest, EntitlementSettlementReceipt, EntitlementSettlementState,
    UsageUnits,
};
use agent_runtime::identity::{PrincipalIdentity, SecurityContext};
use chrono::{DateTime, Duration, Utc};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, MutexGuard};

const MAX_CLOCK_SKEW_SECONDS: i64 = 300;

pub(crate) struct MemoryQuotaLedger {
    provider_id: String,
    reservation_ttl: Duration,
    clock: Arc<dyn EntitlementClock>,
    state: Mutex<LedgerState>,
}

pub(crate) struct MemoryGrant {
    pub allow: bool,
    pub denial_reason: EntitlementDenialReason,
    pub bucket_id: String,
    pub limits: UsageUnits,
    pub expires_at: DateTime<Utc>,
}

#[derive(Default)]
struct LedgerState {
    next_reservation: u64,
    buckets: BTreeMap<String, BucketState>,
    reservations: BTreeMap<String, ReservationRecord>,
    reserve_cache: BTreeMap<ReserveScopeKey, CachedReserve>,
}

struct BucketState {
    limits: BTreeMap<String, u64>,
    /// Committed usage plus the full amount held by pending reservations.
    allocated: BTreeMap<String, u64>,
}

#[derive(Clone)]
struct ReservationRecord {
    binding: ContextBinding,
    request: EntitlementReservationRequest,
    reservation: EntitlementReservation,
    bucket_id: String,
    status: ReservationStatus,
}

#[derive(Clone)]
enum ReservationStatus {
    Pending,
    Committed {
        request: EntitlementCommitRequest,
        receipt: EntitlementSettlementReceipt,
    },
    Released {
        request: EntitlementReleaseRequest,
        receipt: EntitlementSettlementReceipt,
    },
    Expired,
}

#[derive(Clone)]
enum CachedReserve {
    Granted(String),
    Denied(Box<CachedDenial>),
}

#[derive(Clone)]
struct CachedDenial {
    binding: ContextBinding,
    request: EntitlementReservationRequest,
    denial: EntitlementDenial,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ContextBinding {
    identity_provider_id: String,
    app_id: String,
    tenant_id: String,
    audience: String,
    principal: PrincipalIdentity,
    authenticated_at: DateTime<Utc>,
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct ReserveScopeKey {
    identity_provider_id: String,
    app_id: String,
    tenant_id: String,
    audience: String,
    principal: PrincipalIdentity,
    idempotency_key: String,
}

impl MemoryQuotaLedger {
    pub(crate) fn new(
        provider_id: impl Into<String>,
        reservation_ttl: Duration,
        clock: Arc<dyn EntitlementClock>,
    ) -> Self {
        Self {
            provider_id: provider_id.into(),
            reservation_ttl,
            clock,
            state: Mutex::new(LedgerState::default()),
        }
    }

    pub(crate) fn replay(
        &self,
        context: &SecurityContext,
        request: &EntitlementReservationRequest,
    ) -> Result<Option<EntitlementReservationDecision>, EntitlementProviderError> {
        let now = self.clock.now();
        validate_reserve_input(context, request, now)?;
        let mut state = self.lock_state()?;
        reap_expired(&mut state, now)?;
        replay_locked(&state, context, request, now)
    }

    pub(crate) fn reserve(
        &self,
        context: &SecurityContext,
        request: &EntitlementReservationRequest,
        grant: MemoryGrant,
    ) -> Result<EntitlementReservationDecision, EntitlementProviderError> {
        let now = self.clock.now();
        validate_reserve_input(context, request, now)?;
        if !valid_bucket_id(&grant.bucket_id)
            || (grant.allow && grant.limits.validate().is_err())
            || grant.expires_at <= now
        {
            return Err(provider_error(
                EntitlementProviderErrorCode::InvalidResponse,
            ));
        }

        let mut state = self.lock_state()?;
        reap_expired(&mut state, now)?;
        if let Some(decision) = replay_locked(&state, context, request, now)? {
            return Ok(decision);
        }

        let binding = ContextBinding::from(context);
        let scope = ReserveScopeKey::from_context(context, &request.idempotency_key);
        if !grant.allow {
            let denial = denial(&self.provider_id, request, grant.denial_reason);
            state.reserve_cache.insert(
                scope,
                CachedReserve::Denied(Box::new(CachedDenial {
                    binding,
                    request: request.clone(),
                    denial: denial.clone(),
                })),
            );
            return Ok(EntitlementReservationDecision::Denied(denial));
        }

        let can_reserve = {
            let bucket = state
                .buckets
                .entry(grant.bucket_id.clone())
                .or_insert_with(|| BucketState {
                    limits: grant.limits.units.clone(),
                    allocated: BTreeMap::new(),
                });
            bucket.limits = grant.limits.units;
            can_allocate(bucket, &request.requested_usage.units)
        };
        if !can_reserve {
            let denial = denial(
                &self.provider_id,
                request,
                EntitlementDenialReason::QuotaExceeded,
            );
            state.reserve_cache.insert(
                scope,
                CachedReserve::Denied(Box::new(CachedDenial {
                    binding,
                    request: request.clone(),
                    denial: denial.clone(),
                })),
            );
            return Ok(EntitlementReservationDecision::Denied(denial));
        }
        let next_reservation = state
            .next_reservation
            .checked_add(1)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        let reservation_id = format!(
            "{}-{next_reservation:016x}",
            short_provider_id(&self.provider_id)
        );
        let ttl_expires_at = now
            .checked_add_signed(self.reservation_ttl)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        let expires_at = ttl_expires_at.min(context.expires_at).min(grant.expires_at);
        if expires_at <= now {
            return Err(provider_error(
                EntitlementProviderErrorCode::InvalidResponse,
            ));
        }
        let bucket = state
            .buckets
            .get_mut(&grant.bucket_id)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        add_allocation(bucket, &request.requested_usage.units)?;
        state.next_reservation = next_reservation;
        let reservation = EntitlementReservation {
            schema_version: ENTITLEMENT_RESERVATION_SCHEMA_VERSION,
            provider_id: self.provider_id.clone(),
            reservation_id: reservation_id.clone(),
            app_id: context.app_id.clone(),
            tenant_id: context.tenant_id.clone(),
            audience: context.audience.clone(),
            identity_provider_id: context.provider_id.clone(),
            identity_authenticated_at: context.authenticated_at,
            principal: context.principal.clone(),
            operation_id: request.operation_id.clone(),
            idempotency_key: request.idempotency_key.clone(),
            resource: request.resource.clone(),
            reserved_usage: request.requested_usage.clone(),
            created_at: now,
            expires_at,
        };
        state.reservations.insert(
            reservation_id.clone(),
            ReservationRecord {
                binding,
                request: request.clone(),
                reservation: reservation.clone(),
                bucket_id: grant.bucket_id,
                status: ReservationStatus::Pending,
            },
        );
        state
            .reserve_cache
            .insert(scope, CachedReserve::Granted(reservation_id));
        Ok(EntitlementReservationDecision::Granted(Box::new(
            reservation,
        )))
    }

    pub(crate) fn commit(
        &self,
        context: &SecurityContext,
        request: &EntitlementCommitRequest,
    ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
        let now = self.clock.now();
        validate_context(context, now)?;
        let mut state = self.lock_state()?;
        reap_expired(&mut state, now)?;
        let record = state
            .reservations
            .get(&request.reservation_id)
            .cloned()
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;
        validate_settlement_binding(&record, context, now)?;
        request
            .validate_for(&record.reservation)
            .map_err(|_| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;

        match &record.status {
            ReservationStatus::Committed {
                request: original,
                receipt,
            } if original == request => return Ok(receipt.clone()),
            ReservationStatus::Committed { .. } | ReservationStatus::Released { .. } => {
                return Err(provider_error(EntitlementProviderErrorCode::Conflict));
            }
            ReservationStatus::Expired => {
                return Err(provider_error(
                    EntitlementProviderErrorCode::ReservationExpired,
                ));
            }
            ReservationStatus::Pending => {}
        }

        let refund = usage_difference(
            &record.reservation.reserved_usage.units,
            &request.actual_usage.units,
        )?;
        let bucket = state
            .buckets
            .get_mut(&record.bucket_id)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        subtract_allocation(bucket, &refund)?;
        let receipt = EntitlementSettlementReceipt {
            provider_id: self.provider_id.clone(),
            reservation_id: request.reservation_id.clone(),
            settlement_id: request.settlement_id.clone(),
            state: EntitlementSettlementState::Committed,
            charged_usage: Some(request.actual_usage.clone()),
            processed_at: now,
        };
        let stored = state
            .reservations
            .get_mut(&request.reservation_id)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        stored.status = ReservationStatus::Committed {
            request: request.clone(),
            receipt: receipt.clone(),
        };
        Ok(receipt)
    }

    pub(crate) fn release(
        &self,
        context: &SecurityContext,
        request: &EntitlementReleaseRequest,
    ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
        let now = self.clock.now();
        validate_context(context, now)?;
        let mut state = self.lock_state()?;
        reap_expired(&mut state, now)?;
        let record = state
            .reservations
            .get(&request.reservation_id)
            .cloned()
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;
        validate_settlement_binding(&record, context, now)?;
        request
            .validate_for(&record.reservation)
            .map_err(|_| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;

        match &record.status {
            ReservationStatus::Released {
                request: original,
                receipt,
            } if original == request => return Ok(receipt.clone()),
            ReservationStatus::Committed { .. } | ReservationStatus::Released { .. } => {
                return Err(provider_error(EntitlementProviderErrorCode::Conflict));
            }
            ReservationStatus::Expired => {
                return Err(provider_error(
                    EntitlementProviderErrorCode::ReservationExpired,
                ));
            }
            ReservationStatus::Pending => {}
        }

        let bucket = state
            .buckets
            .get_mut(&record.bucket_id)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        subtract_allocation(bucket, &record.reservation.reserved_usage.units)?;
        let receipt = EntitlementSettlementReceipt {
            provider_id: self.provider_id.clone(),
            reservation_id: request.reservation_id.clone(),
            settlement_id: request.release_id.clone(),
            state: EntitlementSettlementState::Released,
            charged_usage: None,
            processed_at: now,
        };
        let stored = state
            .reservations
            .get_mut(&request.reservation_id)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        stored.status = ReservationStatus::Released {
            request: request.clone(),
            receipt: receipt.clone(),
        };
        Ok(receipt)
    }

    fn lock_state(&self) -> Result<MutexGuard<'_, LedgerState>, EntitlementProviderError> {
        self.state
            .lock()
            .map_err(|_| provider_error(EntitlementProviderErrorCode::Unavailable))
    }
}

fn replay_locked(
    state: &LedgerState,
    context: &SecurityContext,
    request: &EntitlementReservationRequest,
    now: DateTime<Utc>,
) -> Result<Option<EntitlementReservationDecision>, EntitlementProviderError> {
    let scope = ReserveScopeKey::from_context(context, &request.idempotency_key);
    let Some(cached) = state.reserve_cache.get(&scope) else {
        return Ok(None);
    };
    match cached {
        CachedReserve::Denied(cached) => {
            if cached.binding != ContextBinding::from(context) || cached.request != *request {
                return Err(provider_error(EntitlementProviderErrorCode::Conflict));
            }
            Ok(Some(EntitlementReservationDecision::Denied(
                cached.denial.clone(),
            )))
        }
        CachedReserve::Granted(reservation_id) => {
            let record = state
                .reservations
                .get(reservation_id)
                .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
            if record.binding != ContextBinding::from(context) || record.request != *request {
                return Err(provider_error(EntitlementProviderErrorCode::Conflict));
            }
            if record.reservation.expires_at <= now
                || matches!(record.status, ReservationStatus::Expired)
            {
                return Err(provider_error(
                    EntitlementProviderErrorCode::ReservationExpired,
                ));
            }
            Ok(Some(EntitlementReservationDecision::Granted(Box::new(
                record.reservation.clone(),
            ))))
        }
    }
}

fn reap_expired(
    state: &mut LedgerState,
    now: DateTime<Utc>,
) -> Result<(), EntitlementProviderError> {
    let expired = state
        .reservations
        .iter()
        .filter(|(_, record)| {
            record.reservation.expires_at <= now
                && matches!(record.status, ReservationStatus::Pending)
        })
        .map(|(id, record)| {
            (
                id.clone(),
                record.bucket_id.clone(),
                record.reservation.reserved_usage.units.clone(),
            )
        })
        .collect::<Vec<_>>();
    for (id, bucket_id, usage) in expired {
        let bucket = state
            .buckets
            .get_mut(&bucket_id)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        subtract_allocation(bucket, &usage)?;
        let record = state
            .reservations
            .get_mut(&id)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        record.status = ReservationStatus::Expired;
    }
    Ok(())
}

fn can_allocate(bucket: &BucketState, usage: &BTreeMap<String, u64>) -> bool {
    usage.iter().all(|(dimension, quantity)| {
        let Some(limit) = bucket.limits.get(dimension) else {
            return false;
        };
        bucket
            .allocated
            .get(dimension)
            .copied()
            .unwrap_or_default()
            .checked_add(*quantity)
            .is_some_and(|total| total <= *limit)
    })
}

fn add_allocation(
    bucket: &mut BucketState,
    usage: &BTreeMap<String, u64>,
) -> Result<(), EntitlementProviderError> {
    if !can_allocate(bucket, usage) {
        return Err(provider_error(EntitlementProviderErrorCode::Unavailable));
    }
    for (dimension, quantity) in usage {
        let current = bucket.allocated.get(dimension).copied().unwrap_or_default();
        bucket
            .allocated
            .insert(dimension.clone(), current + quantity);
    }
    Ok(())
}

fn subtract_allocation(
    bucket: &mut BucketState,
    usage: &BTreeMap<String, u64>,
) -> Result<(), EntitlementProviderError> {
    if usage.iter().any(|(dimension, quantity)| {
        bucket.allocated.get(dimension).copied().unwrap_or_default() < *quantity
    }) {
        return Err(provider_error(EntitlementProviderErrorCode::Unavailable));
    }
    for (dimension, quantity) in usage {
        let current = bucket.allocated.get(dimension).copied().unwrap_or_default();
        let remaining = current - quantity;
        if remaining == 0 {
            bucket.allocated.remove(dimension);
        } else {
            bucket.allocated.insert(dimension.clone(), remaining);
        }
    }
    Ok(())
}

fn usage_difference(
    reserved: &BTreeMap<String, u64>,
    actual: &BTreeMap<String, u64>,
) -> Result<BTreeMap<String, u64>, EntitlementProviderError> {
    let mut difference = BTreeMap::new();
    for (dimension, reserved_quantity) in reserved {
        let actual_quantity = actual.get(dimension).copied().unwrap_or_default();
        let refund = reserved_quantity
            .checked_sub(actual_quantity)
            .ok_or_else(|| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;
        if refund > 0 {
            difference.insert(dimension.clone(), refund);
        }
    }
    Ok(difference)
}

fn validate_reserve_input(
    context: &SecurityContext,
    request: &EntitlementReservationRequest,
    now: DateTime<Utc>,
) -> Result<(), EntitlementProviderError> {
    validate_context(context, now)?;
    request
        .validate()
        .map_err(|_| provider_error(EntitlementProviderErrorCode::InvalidRequest))
}

fn validate_context(
    context: &SecurityContext,
    now: DateTime<Utc>,
) -> Result<(), EntitlementProviderError> {
    if context.validate().is_err()
        || context.expires_at <= now
        || context.authenticated_at > now + Duration::seconds(MAX_CLOCK_SKEW_SECONDS)
    {
        return Err(provider_error(EntitlementProviderErrorCode::InvalidRequest));
    }
    Ok(())
}

fn validate_settlement_binding(
    record: &ReservationRecord,
    context: &SecurityContext,
    now: DateTime<Utc>,
) -> Result<(), EntitlementProviderError> {
    if record.binding != ContextBinding::from(context) {
        return Err(provider_error(EntitlementProviderErrorCode::Conflict));
    }
    if record.reservation.expires_at <= now {
        return Err(provider_error(
            EntitlementProviderErrorCode::ReservationExpired,
        ));
    }
    Ok(())
}

fn denial(
    provider_id: &str,
    request: &EntitlementReservationRequest,
    reason: EntitlementDenialReason,
) -> EntitlementDenial {
    EntitlementDenial {
        provider_id: provider_id.into(),
        operation_id: request.operation_id.clone(),
        idempotency_key: request.idempotency_key.clone(),
        resource: request.resource.clone(),
        reason,
        retry_after: None,
    }
}

fn valid_bucket_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 2048
        && value == value.trim()
        && !value.chars().any(char::is_control)
}

fn short_provider_id(provider_id: &str) -> &str {
    provider_id.rsplit('.').next().unwrap_or("reservation")
}

fn provider_error(code: EntitlementProviderErrorCode) -> EntitlementProviderError {
    EntitlementProviderError::new(code)
}

impl From<&SecurityContext> for ContextBinding {
    fn from(context: &SecurityContext) -> Self {
        Self {
            identity_provider_id: context.provider_id.clone(),
            app_id: context.app_id.clone(),
            tenant_id: context.tenant_id.clone(),
            audience: context.audience.clone(),
            principal: context.principal.clone(),
            authenticated_at: context.authenticated_at,
        }
    }
}

impl ReserveScopeKey {
    fn from_context(context: &SecurityContext, idempotency_key: &str) -> Self {
        Self {
            identity_provider_id: context.provider_id.clone(),
            app_id: context.app_id.clone(),
            tenant_id: context.tenant_id.clone(),
            audience: context.audience.clone(),
            principal: context.principal.clone(),
            idempotency_key: idempotency_key.into(),
        }
    }
}
