use crate::identity::{PrincipalIdentity, SecurityContext};
use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use thiserror::Error;

pub const ENTITLEMENT_RESERVATION_SCHEMA_VERSION: u32 = 1;

const MAX_IDENTIFIER_BYTES: usize = 255;
const MAX_OPAQUE_VALUE_BYTES: usize = 2048;
const MAX_USAGE_DIMENSIONS: usize = 32;
const MAX_CLOCK_SKEW_SECONDS: i64 = 300;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EntitlementMode {
    Disabled,
    Required,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EntitlementResource {
    pub kind: String,
    pub id: String,
}

impl EntitlementResource {
    pub fn validate(&self) -> Result<(), EntitlementContractError> {
        validate_identifier(&self.kind, "resource.kind")?;
        validate_opaque(&self.id, "resource.id", MAX_OPAQUE_VALUE_BYTES)
    }
}

/// Domain-neutral, integer usage dimensions such as requests or model tokens.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UsageUnits {
    pub units: BTreeMap<String, u64>,
}

impl UsageUnits {
    pub fn validate(&self) -> Result<(), EntitlementContractError> {
        if self.units.is_empty() || self.units.len() > MAX_USAGE_DIMENSIONS {
            return Err(EntitlementContractError::InvalidUsage);
        }
        for (dimension, quantity) in &self.units {
            validate_identifier(dimension, "usage dimension")?;
            if *quantity == 0 {
                return Err(EntitlementContractError::InvalidUsage);
            }
        }
        Ok(())
    }

    pub fn covers(&self, actual: &Self) -> bool {
        self.validate().is_ok()
            && actual.validate().is_ok()
            && actual.units.iter().all(|(dimension, quantity)| {
                self.units
                    .get(dimension)
                    .is_some_and(|reserved| quantity <= reserved)
            })
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EntitlementReservationRequest {
    pub operation_id: String,
    pub idempotency_key: String,
    pub resource: EntitlementResource,
    pub requested_usage: UsageUnits,
}

impl EntitlementReservationRequest {
    pub fn validate(&self) -> Result<(), EntitlementContractError> {
        validate_opaque(&self.operation_id, "operation_id", MAX_OPAQUE_VALUE_BYTES)?;
        validate_opaque(
            &self.idempotency_key,
            "idempotency_key",
            MAX_OPAQUE_VALUE_BYTES,
        )?;
        self.resource.validate()?;
        self.requested_usage.validate()
    }
}

/// A context-bound reservation identifier, not a bearer authorization token.
/// Providers must reload authoritative reservation state by ID for settlement.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EntitlementReservation {
    pub schema_version: u32,
    pub provider_id: String,
    pub reservation_id: String,
    pub app_id: String,
    pub tenant_id: String,
    pub audience: String,
    pub identity_provider_id: String,
    pub identity_authenticated_at: DateTime<Utc>,
    pub principal: PrincipalIdentity,
    pub operation_id: String,
    pub idempotency_key: String,
    pub resource: EntitlementResource,
    pub reserved_usage: UsageUnits,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

impl EntitlementReservation {
    pub fn validate_for(
        &self,
        provider_id: &str,
        context: &SecurityContext,
        request: &EntitlementReservationRequest,
        now: DateTime<Utc>,
    ) -> Result<(), EntitlementContractError> {
        validate_active_context(context, now)?;
        request.validate()?;
        if self.schema_version != ENTITLEMENT_RESERVATION_SCHEMA_VERSION {
            return Err(EntitlementContractError::UnsupportedSchemaVersion);
        }
        validate_identifier(&self.provider_id, "provider_id")?;
        validate_opaque(
            &self.reservation_id,
            "reservation_id",
            MAX_OPAQUE_VALUE_BYTES,
        )?;
        if self.provider_id != provider_id
            || self.app_id != context.app_id
            || self.tenant_id != context.tenant_id
            || self.audience != context.audience
            || self.identity_provider_id != context.provider_id
            || self.identity_authenticated_at != context.authenticated_at
            || self.principal != context.principal
            || self.operation_id != request.operation_id
            || self.idempotency_key != request.idempotency_key
            || self.resource != request.resource
            || self.reserved_usage != request.requested_usage
        {
            return Err(EntitlementContractError::BindingMismatch);
        }
        self.resource.validate()?;
        self.reserved_usage.validate()?;
        if self.created_at > now + Duration::seconds(MAX_CLOCK_SKEW_SECONDS)
            || self.expires_at <= self.created_at
            || self.expires_at <= now
            || self.expires_at > context.expires_at
        {
            return Err(EntitlementContractError::InvalidLifetime);
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EntitlementDenialReason {
    NotEntitled,
    QuotaExceeded,
    ResourceDenied,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EntitlementDenial {
    pub provider_id: String,
    pub operation_id: String,
    pub idempotency_key: String,
    pub resource: EntitlementResource,
    pub reason: EntitlementDenialReason,
    pub retry_after: Option<DateTime<Utc>>,
}

impl EntitlementDenial {
    fn validate_for(
        &self,
        provider_id: &str,
        request: &EntitlementReservationRequest,
        now: DateTime<Utc>,
    ) -> Result<(), EntitlementContractError> {
        if self.provider_id != provider_id
            || self.operation_id != request.operation_id
            || self.idempotency_key != request.idempotency_key
            || self.resource != request.resource
            || self
                .retry_after
                .is_some_and(|retry_after| retry_after <= now)
        {
            return Err(EntitlementContractError::BindingMismatch);
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EntitlementReservationDecision {
    Granted(Box<EntitlementReservation>),
    Denied(EntitlementDenial),
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EntitlementCommitRequest {
    pub reservation_id: String,
    pub settlement_id: String,
    pub actual_usage: UsageUnits,
}

impl EntitlementCommitRequest {
    pub fn validate_for(
        &self,
        reservation: &EntitlementReservation,
    ) -> Result<(), EntitlementContractError> {
        validate_opaque(
            &self.reservation_id,
            "reservation_id",
            MAX_OPAQUE_VALUE_BYTES,
        )?;
        validate_opaque(&self.settlement_id, "settlement_id", MAX_OPAQUE_VALUE_BYTES)?;
        self.actual_usage.validate()?;
        if self.reservation_id != reservation.reservation_id {
            return Err(EntitlementContractError::BindingMismatch);
        }
        if !reservation.reserved_usage.covers(&self.actual_usage) {
            return Err(EntitlementContractError::UsageExceedsReservation);
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EntitlementReleaseRequest {
    pub reservation_id: String,
    pub release_id: String,
}

impl EntitlementReleaseRequest {
    pub fn validate_for(
        &self,
        reservation: &EntitlementReservation,
    ) -> Result<(), EntitlementContractError> {
        validate_opaque(
            &self.reservation_id,
            "reservation_id",
            MAX_OPAQUE_VALUE_BYTES,
        )?;
        validate_opaque(&self.release_id, "release_id", MAX_OPAQUE_VALUE_BYTES)?;
        if self.reservation_id != reservation.reservation_id {
            return Err(EntitlementContractError::BindingMismatch);
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EntitlementSettlementState {
    Committed,
    Released,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EntitlementSettlementReceipt {
    pub provider_id: String,
    pub reservation_id: String,
    pub settlement_id: String,
    pub state: EntitlementSettlementState,
    pub charged_usage: Option<UsageUnits>,
    pub processed_at: DateTime<Utc>,
}

impl EntitlementSettlementReceipt {
    fn validate_commit(
        &self,
        provider_id: &str,
        request: &EntitlementCommitRequest,
        now: DateTime<Utc>,
    ) -> Result<(), EntitlementContractError> {
        if self.provider_id != provider_id
            || self.reservation_id != request.reservation_id
            || self.settlement_id != request.settlement_id
            || self.state != EntitlementSettlementState::Committed
            || self.charged_usage.as_ref() != Some(&request.actual_usage)
            || self.processed_at > now + Duration::seconds(MAX_CLOCK_SKEW_SECONDS)
        {
            return Err(EntitlementContractError::InvalidReceipt);
        }
        Ok(())
    }

    fn validate_release(
        &self,
        provider_id: &str,
        request: &EntitlementReleaseRequest,
        now: DateTime<Utc>,
    ) -> Result<(), EntitlementContractError> {
        if self.provider_id != provider_id
            || self.reservation_id != request.reservation_id
            || self.settlement_id != request.release_id
            || self.state != EntitlementSettlementState::Released
            || self.charged_usage.is_some()
            || self.processed_at > now + Duration::seconds(MAX_CLOCK_SKEW_SECONDS)
        {
            return Err(EntitlementContractError::InvalidReceipt);
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Error, PartialEq, Eq)]
pub enum EntitlementContractError {
    #[error("invalid entitlement field: {0}")]
    InvalidField(&'static str),
    #[error("unsupported entitlement reservation schema version")]
    UnsupportedSchemaVersion,
    #[error("entitlement usage is invalid")]
    InvalidUsage,
    #[error("security context is invalid or expired")]
    InvalidSecurityContext,
    #[error("entitlement response binding does not match the request")]
    BindingMismatch,
    #[error("entitlement reservation lifetime is invalid")]
    InvalidLifetime,
    #[error("actual usage exceeds the entitlement reservation")]
    UsageExceedsReservation,
    #[error("entitlement settlement receipt is invalid")]
    InvalidReceipt,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EntitlementProviderErrorCode {
    InvalidRequest,
    InvalidResponse,
    Conflict,
    ReservationExpired,
    Unavailable,
}

#[derive(Clone, Copy, Debug, Error, PartialEq, Eq)]
#[error("entitlement provider operation failed: {code:?}")]
pub struct EntitlementProviderError {
    pub code: EntitlementProviderErrorCode,
}

impl EntitlementProviderError {
    pub fn new(code: EntitlementProviderErrorCode) -> Self {
        Self { code }
    }
}

/// Atomically reserves and settles quota. Implementations must make every
/// operation idempotent and bind reservation IDs to the supplied context.
#[async_trait]
pub trait EntitlementProvider: Send + Sync {
    fn provider_id(&self) -> &str;

    async fn reserve(
        &self,
        context: &SecurityContext,
        request: &EntitlementReservationRequest,
    ) -> Result<EntitlementReservationDecision, EntitlementProviderError>;

    async fn commit(
        &self,
        context: &SecurityContext,
        request: &EntitlementCommitRequest,
    ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError>;

    async fn release(
        &self,
        context: &SecurityContext,
        request: &EntitlementReleaseRequest,
    ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError>;
}

pub async fn reserve_entitlement(
    provider: &dyn EntitlementProvider,
    context: &SecurityContext,
    request: &EntitlementReservationRequest,
    now: DateTime<Utc>,
) -> Result<EntitlementReservationDecision, EntitlementProviderError> {
    validate_active_context(context, now)
        .and_then(|_| request.validate())
        .map_err(|_| EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidRequest))?;
    validate_identifier(provider.provider_id(), "provider_id").map_err(|_| {
        EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidResponse)
    })?;
    let decision = provider.reserve(context, request).await?;
    match &decision {
        EntitlementReservationDecision::Granted(reservation) => {
            reservation.validate_for(provider.provider_id(), context, request, now)
        }
        EntitlementReservationDecision::Denied(denial) => {
            denial.validate_for(provider.provider_id(), request, now)
        }
    }
    .map_err(|_| EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidResponse))?;
    Ok(decision)
}

pub async fn commit_entitlement(
    provider: &dyn EntitlementProvider,
    context: &SecurityContext,
    reservation_request: &EntitlementReservationRequest,
    reservation: &EntitlementReservation,
    request: &EntitlementCommitRequest,
    now: DateTime<Utc>,
) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
    reservation
        .validate_for(provider.provider_id(), context, reservation_request, now)
        .and_then(|_| request.validate_for(reservation))
        .map_err(|_| EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidRequest))?;
    let receipt = provider.commit(context, request).await?;
    receipt
        .validate_commit(provider.provider_id(), request, now)
        .map_err(|_| {
            EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidResponse)
        })?;
    Ok(receipt)
}

pub async fn release_entitlement(
    provider: &dyn EntitlementProvider,
    context: &SecurityContext,
    reservation_request: &EntitlementReservationRequest,
    reservation: &EntitlementReservation,
    request: &EntitlementReleaseRequest,
    now: DateTime<Utc>,
) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
    reservation
        .validate_for(provider.provider_id(), context, reservation_request, now)
        .and_then(|_| request.validate_for(reservation))
        .map_err(|_| EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidRequest))?;
    let receipt = provider.release(context, request).await?;
    receipt
        .validate_release(provider.provider_id(), request, now)
        .map_err(|_| {
            EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidResponse)
        })?;
    Ok(receipt)
}

fn validate_active_context(
    context: &SecurityContext,
    now: DateTime<Utc>,
) -> Result<(), EntitlementContractError> {
    if context.validate().is_err()
        || context.is_expired_at(now)
        || context.authenticated_at > now + Duration::seconds(MAX_CLOCK_SKEW_SECONDS)
    {
        return Err(EntitlementContractError::InvalidSecurityContext);
    }
    Ok(())
}

fn validate_identifier(value: &str, field: &'static str) -> Result<(), EntitlementContractError> {
    let valid = !value.is_empty()
        && value.len() <= MAX_IDENTIFIER_BYTES
        && value == value.trim()
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'));
    if valid {
        Ok(())
    } else {
        Err(EntitlementContractError::InvalidField(field))
    }
}

fn validate_opaque(
    value: &str,
    field: &'static str,
    maximum_bytes: usize,
) -> Result<(), EntitlementContractError> {
    let valid = !value.is_empty()
        && value.len() <= maximum_bytes
        && value == value.trim()
        && !value.chars().any(char::is_control);
    if valid {
        Ok(())
    } else {
        Err(EntitlementContractError::InvalidField(field))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity::SECURITY_CONTEXT_SCHEMA_VERSION;
    use chrono::TimeZone;
    use std::collections::BTreeSet;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 7, 19, 8, 0, 0).unwrap()
    }

    fn context() -> SecurityContext {
        SecurityContext {
            schema_version: SECURITY_CONTEXT_SCHEMA_VERSION,
            provider_id: "com.example.identity".into(),
            app_id: "com.example.agent".into(),
            tenant_id: "tenant-1".into(),
            audience: "https://gateway.example.com".into(),
            principal: PrincipalIdentity {
                issuer: "https://identity.example.com".into(),
                subject: "user-42".into(),
            },
            granted_scopes: BTreeSet::from(["model.invoke".into()]),
            authenticated_at: now() - Duration::minutes(5),
            expires_at: now() + Duration::hours(1),
        }
    }

    fn reservation_request() -> EntitlementReservationRequest {
        EntitlementReservationRequest {
            operation_id: "turn-42".into(),
            idempotency_key: "turn-42:model".into(),
            resource: EntitlementResource {
                kind: "model".into(),
                id: "com.example.gateway:gpt-test".into(),
            },
            requested_usage: UsageUnits {
                units: BTreeMap::from([("requests".into(), 1), ("tokens".into(), 2_000)]),
            },
        }
    }

    fn reservation() -> EntitlementReservation {
        let request = reservation_request();
        let context = context();
        EntitlementReservation {
            schema_version: ENTITLEMENT_RESERVATION_SCHEMA_VERSION,
            provider_id: "com.example.entitlements".into(),
            reservation_id: "reservation-42".into(),
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
            created_at: now(),
            expires_at: now() + Duration::minutes(5),
        }
    }

    #[test]
    fn usage_requires_positive_bounded_dimensions() {
        let reserved = reservation_request().requested_usage;
        assert!(reserved.validate().is_ok());
        assert!(reserved.covers(&UsageUnits {
            units: BTreeMap::from([("requests".into(), 1), ("tokens".into(), 1_500)]),
        }));
        assert!(!reserved.covers(&UsageUnits {
            units: BTreeMap::from([("tokens".into(), 2_001)]),
        }));
        assert_eq!(
            UsageUnits {
                units: BTreeMap::from([("tokens".into(), 0)]),
            }
            .validate()
            .unwrap_err(),
            EntitlementContractError::InvalidUsage
        );
    }

    #[test]
    fn reservation_is_bound_to_identity_request_and_lifetime() {
        let reservation = reservation();
        assert!(
            reservation
                .validate_for(
                    "com.example.entitlements",
                    &context(),
                    &reservation_request(),
                    now(),
                )
                .is_ok()
        );

        let mut other_principal = context();
        other_principal.principal.subject = "user-99".into();
        assert_eq!(
            reservation
                .validate_for(
                    "com.example.entitlements",
                    &other_principal,
                    &reservation_request(),
                    now(),
                )
                .unwrap_err(),
            EntitlementContractError::BindingMismatch
        );

        let mut overlong = reservation;
        overlong.expires_at = context().expires_at + Duration::seconds(1);
        assert_eq!(
            overlong
                .validate_for(
                    "com.example.entitlements",
                    &context(),
                    &reservation_request(),
                    now(),
                )
                .unwrap_err(),
            EntitlementContractError::InvalidLifetime
        );
    }

    struct StaticProvider {
        decision: EntitlementReservationDecision,
        settlement_calls: AtomicUsize,
    }

    #[async_trait]
    impl EntitlementProvider for StaticProvider {
        fn provider_id(&self) -> &str {
            "com.example.entitlements"
        }

        async fn reserve(
            &self,
            _context: &SecurityContext,
            _request: &EntitlementReservationRequest,
        ) -> Result<EntitlementReservationDecision, EntitlementProviderError> {
            Ok(self.decision.clone())
        }

        async fn commit(
            &self,
            _context: &SecurityContext,
            request: &EntitlementCommitRequest,
        ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
            self.settlement_calls.fetch_add(1, Ordering::SeqCst);
            Ok(EntitlementSettlementReceipt {
                provider_id: self.provider_id().into(),
                reservation_id: request.reservation_id.clone(),
                settlement_id: request.settlement_id.clone(),
                state: EntitlementSettlementState::Committed,
                charged_usage: Some(request.actual_usage.clone()),
                processed_at: now(),
            })
        }

        async fn release(
            &self,
            _context: &SecurityContext,
            request: &EntitlementReleaseRequest,
        ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
            self.settlement_calls.fetch_add(1, Ordering::SeqCst);
            Ok(EntitlementSettlementReceipt {
                provider_id: self.provider_id().into(),
                reservation_id: request.reservation_id.clone(),
                settlement_id: request.release_id.clone(),
                state: EntitlementSettlementState::Released,
                charged_usage: None,
                processed_at: now(),
            })
        }
    }

    #[tokio::test]
    async fn validated_reservation_and_settlement_flow_succeeds() {
        let provider = StaticProvider {
            decision: EntitlementReservationDecision::Granted(Box::new(reservation())),
            settlement_calls: AtomicUsize::new(0),
        };
        let decision = reserve_entitlement(&provider, &context(), &reservation_request(), now())
            .await
            .unwrap();
        assert!(matches!(
            decision,
            EntitlementReservationDecision::Granted(_)
        ));

        let commit = EntitlementCommitRequest {
            reservation_id: "reservation-42".into(),
            settlement_id: "settlement-42".into(),
            actual_usage: UsageUnits {
                units: BTreeMap::from([("requests".into(), 1), ("tokens".into(), 1_500)]),
            },
        };
        let receipt = commit_entitlement(
            &provider,
            &context(),
            &reservation_request(),
            &reservation(),
            &commit,
            now(),
        )
        .await
        .unwrap();
        assert_eq!(receipt.state, EntitlementSettlementState::Committed);
        assert_eq!(provider.settlement_calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn validated_denial_and_release_flow_succeeds() {
        let denial = EntitlementDenial {
            provider_id: "com.example.entitlements".into(),
            operation_id: reservation_request().operation_id,
            idempotency_key: reservation_request().idempotency_key,
            resource: reservation_request().resource,
            reason: EntitlementDenialReason::QuotaExceeded,
            retry_after: Some(now() + Duration::minutes(1)),
        };
        let denied_provider = StaticProvider {
            decision: EntitlementReservationDecision::Denied(denial),
            settlement_calls: AtomicUsize::new(0),
        };
        let decision =
            reserve_entitlement(&denied_provider, &context(), &reservation_request(), now())
                .await
                .unwrap();
        assert!(matches!(
            decision,
            EntitlementReservationDecision::Denied(EntitlementDenial {
                reason: EntitlementDenialReason::QuotaExceeded,
                ..
            })
        ));

        let granted_provider = StaticProvider {
            decision: EntitlementReservationDecision::Granted(Box::new(reservation())),
            settlement_calls: AtomicUsize::new(0),
        };
        let release = EntitlementReleaseRequest {
            reservation_id: "reservation-42".into(),
            release_id: "release-42".into(),
        };
        let receipt = release_entitlement(
            &granted_provider,
            &context(),
            &reservation_request(),
            &reservation(),
            &release,
            now(),
        )
        .await
        .unwrap();
        assert_eq!(receipt.state, EntitlementSettlementState::Released);
        assert_eq!(granted_provider.settlement_calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn overage_is_rejected_before_provider_settlement() {
        let provider = StaticProvider {
            decision: EntitlementReservationDecision::Granted(Box::new(reservation())),
            settlement_calls: AtomicUsize::new(0),
        };
        let overage = EntitlementCommitRequest {
            reservation_id: "reservation-42".into(),
            settlement_id: "settlement-overage".into(),
            actual_usage: UsageUnits {
                units: BTreeMap::from([("tokens".into(), 2_001)]),
            },
        };

        assert_eq!(
            commit_entitlement(
                &provider,
                &context(),
                &reservation_request(),
                &reservation(),
                &overage,
                now(),
            )
            .await
            .unwrap_err(),
            EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidRequest)
        );
        assert_eq!(provider.settlement_calls.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn mismatched_provider_responses_fail_closed() {
        let mut mismatched = reservation();
        mismatched.principal.subject = "user-99".into();
        let provider = StaticProvider {
            decision: EntitlementReservationDecision::Granted(Box::new(mismatched)),
            settlement_calls: AtomicUsize::new(0),
        };

        assert_eq!(
            reserve_entitlement(&provider, &context(), &reservation_request(), now())
                .await
                .unwrap_err(),
            EntitlementProviderError::new(EntitlementProviderErrorCode::InvalidResponse)
        );
    }

    #[test]
    fn serialized_reservation_cannot_carry_bearer_material() {
        let encoded = serde_json::to_value(reservation()).unwrap();
        let object = encoded.as_object().unwrap();
        for forbidden in [
            "reservationToken",
            "accessToken",
            "authorization",
            "credential",
        ] {
            assert!(!object.contains_key(forbidden));
        }

        let mut with_token = encoded;
        with_token["reservationToken"] = serde_json::json!("secret-sentinel");
        assert!(serde_json::from_value::<EntitlementReservation>(with_token).is_err());
    }
}
