use crate::{
    EntitlementClock, EntitlementProviderConfigurationError, STRIPE_PROJECTION_PROVIDER_ID,
    SystemEntitlementClock,
    memory_ledger::{MemoryGrant, MemoryQuotaLedger},
    valid_opaque_reference,
};
use agent_runtime::entitlement::{
    EntitlementCommitRequest, EntitlementDenialReason, EntitlementProvider,
    EntitlementProviderError, EntitlementProviderErrorCode, EntitlementReleaseRequest,
    EntitlementReservationDecision, EntitlementReservationRequest, EntitlementResource,
    EntitlementSettlementReceipt, UsageUnits,
};
use agent_runtime::identity::{PrincipalIdentity, SecurityContext};
use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fmt;
use std::sync::Arc;

pub const STRIPE_ENTITLEMENT_PROJECTION_SCHEMA_VERSION: u32 = 1;
const MAX_CLOCK_SKEW_SECONDS: i64 = 300;

fn default_reservation_ttl_seconds() -> u64 {
    300
}

fn default_max_projection_age_seconds() -> u64 {
    300
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StripeProjectionConfig {
    /// Trusted host plugin or developer-backend source, not a Stripe credential.
    pub projection_source_id: String,
    #[serde(default = "default_reservation_ttl_seconds")]
    pub reservation_ttl_seconds: u64,
    #[serde(default = "default_max_projection_age_seconds")]
    pub max_projection_age_seconds: u64,
}

impl StripeProjectionConfig {
    pub fn validate(&self) -> Result<(), EntitlementProviderConfigurationError> {
        if !valid_opaque_reference(&self.projection_source_id) {
            return Err(EntitlementProviderConfigurationError::InvalidSecretReference);
        }
        if !(1..=3600).contains(&self.reservation_ttl_seconds) {
            return Err(EntitlementProviderConfigurationError::InvalidReservationTtl);
        }
        if !(1..=86_400).contains(&self.max_projection_age_seconds) {
            return Err(EntitlementProviderConfigurationError::InvalidProjectionFreshness);
        }
        Ok(())
    }
}

/// Domain-neutral projection returned only after a trusted source has verified developer-backend
/// state or reduced verified Stripe webhooks into an entitlement decision.
///
/// This type intentionally cannot represent Stripe API secrets, prices, taxes, payment methods,
/// refunds, or raw webhook signatures. Verification and commerce lifecycle remain outside this
/// provider and outside an AgentWeave client application.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StripeEntitlementProjection {
    pub schema_version: u32,
    pub source_id: String,
    pub projection_id: String,
    pub quota_window_id: Option<String>,
    pub app_id: String,
    pub tenant_id: String,
    pub audience: String,
    pub principal: PrincipalIdentity,
    pub resource: EntitlementResource,
    pub entitled: bool,
    pub denial_reason: Option<EntitlementDenialReason>,
    pub quota: Option<UsageUnits>,
    pub issued_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StripeProjectionSourceErrorCode {
    VerificationFailed,
    NotFound,
    Unavailable,
}

#[derive(Clone, Copy, Debug, thiserror::Error, PartialEq, Eq)]
#[error("Stripe entitlement projection source failed: {code:?}")]
pub struct StripeProjectionSourceError {
    pub code: StripeProjectionSourceErrorCode,
}

impl StripeProjectionSourceError {
    pub fn new(code: StripeProjectionSourceErrorCode) -> Self {
        Self { code }
    }
}

/// Trusted host boundary for already verified entitlement projections.
///
/// Implementations must verify a developer service signature or consume server-side
/// webhook-derived state before returning. Raw client assertions are not a valid source.
#[async_trait]
pub trait StripeEntitlementProjectionSource: Send + Sync {
    fn source_id(&self) -> &str;

    async fn projection(
        &self,
        context: &SecurityContext,
        resource: &EntitlementResource,
    ) -> Result<StripeEntitlementProjection, StripeProjectionSourceError>;
}

#[derive(Clone)]
pub struct StripeProjectionEntitlementProvider {
    config: StripeProjectionConfig,
    source: Arc<dyn StripeEntitlementProjectionSource>,
    clock: Arc<dyn EntitlementClock>,
    ledger: Arc<MemoryQuotaLedger>,
}

impl fmt::Debug for StripeProjectionEntitlementProvider {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("StripeProjectionEntitlementProvider")
            .field("config", &self.config)
            .field("source", &"<trusted projection source>")
            .finish_non_exhaustive()
    }
}

impl StripeProjectionEntitlementProvider {
    pub fn new(
        config: StripeProjectionConfig,
        source: Arc<dyn StripeEntitlementProjectionSource>,
    ) -> Result<Self, EntitlementProviderConfigurationError> {
        Self::with_clock(config, source, Arc::new(SystemEntitlementClock))
    }

    pub fn with_clock(
        config: StripeProjectionConfig,
        source: Arc<dyn StripeEntitlementProjectionSource>,
        clock: Arc<dyn EntitlementClock>,
    ) -> Result<Self, EntitlementProviderConfigurationError> {
        config.validate()?;
        if source.source_id() != config.projection_source_id {
            return Err(EntitlementProviderConfigurationError::InvalidProjectionSource);
        }
        let ledger = Arc::new(MemoryQuotaLedger::new(
            STRIPE_PROJECTION_PROVIDER_ID,
            Duration::seconds(config.reservation_ttl_seconds as i64),
            clock.clone(),
        ));
        Ok(Self {
            config,
            source,
            clock,
            ledger,
        })
    }
}

#[async_trait]
impl EntitlementProvider for StripeProjectionEntitlementProvider {
    fn provider_id(&self) -> &str {
        STRIPE_PROJECTION_PROVIDER_ID
    }

    async fn reserve(
        &self,
        context: &SecurityContext,
        request: &EntitlementReservationRequest,
    ) -> Result<EntitlementReservationDecision, EntitlementProviderError> {
        if let Some(cached) = self.ledger.replay(context, request)? {
            return Ok(cached);
        }
        let projection = self
            .source
            .projection(context, &request.resource)
            .await
            .map_err(|_| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        validate_projection(
            &self.config,
            context,
            &request.resource,
            &projection,
            self.clock.now(),
        )?;
        let (bucket_id, limits, denial_reason) = if projection.entitled {
            (
                projection_bucket_id(context, projection.quota_window_id.as_deref().unwrap()),
                projection.quota.clone().unwrap(),
                EntitlementDenialReason::NotEntitled,
            )
        } else {
            (
                format!("denied-{}", projection.projection_id),
                UsageUnits {
                    units: BTreeMap::new(),
                },
                projection
                    .denial_reason
                    .unwrap_or(EntitlementDenialReason::NotEntitled),
            )
        };
        self.ledger.reserve(
            context,
            request,
            MemoryGrant {
                allow: projection.entitled,
                denial_reason,
                bucket_id,
                limits,
                expires_at: projection.expires_at,
            },
        )
    }

    async fn commit(
        &self,
        context: &SecurityContext,
        request: &EntitlementCommitRequest,
    ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
        self.ledger.commit(context, request)
    }

    async fn release(
        &self,
        context: &SecurityContext,
        request: &EntitlementReleaseRequest,
    ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
        self.ledger.release(context, request)
    }
}

fn validate_projection(
    config: &StripeProjectionConfig,
    context: &SecurityContext,
    resource: &EntitlementResource,
    projection: &StripeEntitlementProjection,
    now: DateTime<Utc>,
) -> Result<(), EntitlementProviderError> {
    let fresh_after = now
        .checked_sub_signed(Duration::seconds(config.max_projection_age_seconds as i64))
        .ok_or_else(|| provider_error(EntitlementProviderErrorCode::InvalidResponse))?;
    let common_valid = projection.schema_version == STRIPE_ENTITLEMENT_PROJECTION_SCHEMA_VERSION
        && projection.source_id == config.projection_source_id
        && valid_opaque_reference(&projection.projection_id)
        && projection.app_id == context.app_id
        && projection.tenant_id == context.tenant_id
        && projection.audience == context.audience
        && projection.principal == context.principal
        && &projection.resource == resource
        && projection.issued_at >= fresh_after
        && projection.issued_at <= now + Duration::seconds(MAX_CLOCK_SKEW_SECONDS)
        && projection.expires_at > now
        && projection.expires_at > projection.issued_at;
    let decision_valid = if projection.entitled {
        projection.denial_reason.is_none()
            && projection
                .quota_window_id
                .as_deref()
                .is_some_and(valid_opaque_reference)
            && projection
                .quota
                .as_ref()
                .is_some_and(|quota| quota.validate().is_ok())
    } else {
        projection.quota_window_id.is_none()
            && projection.quota.is_none()
            && projection
                .denial_reason
                .is_none_or(|reason| reason != EntitlementDenialReason::QuotaExceeded)
    };
    if common_valid && decision_valid {
        Ok(())
    } else {
        Err(provider_error(
            EntitlementProviderErrorCode::InvalidResponse,
        ))
    }
}

fn projection_bucket_id(context: &SecurityContext, quota_window_id: &str) -> String {
    let mut digest = Sha256::new();
    for component in [
        context.app_id.as_str(),
        context.tenant_id.as_str(),
        context.audience.as_str(),
        context.principal.issuer.as_str(),
        context.principal.subject.as_str(),
        quota_window_id,
    ] {
        digest.update(component.as_bytes());
        digest.update([0]);
    }
    format!("stripe-{}", hex::encode(digest.finalize()))
}

fn provider_error(code: EntitlementProviderErrorCode) -> EntitlementProviderError {
    EntitlementProviderError::new(code)
}
