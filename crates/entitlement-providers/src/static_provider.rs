use crate::{
    EntitlementClock, EntitlementProviderConfigurationError, STATIC_ENTITLEMENT_PROVIDER_ID,
    SystemEntitlementClock,
    memory_ledger::{MemoryGrant, MemoryQuotaLedger},
};
use agent_runtime::entitlement::{
    EntitlementCommitRequest, EntitlementDenialReason, EntitlementProvider,
    EntitlementProviderError, EntitlementReleaseRequest, EntitlementReservationDecision,
    EntitlementReservationRequest, EntitlementSettlementReceipt, UsageUnits,
};
use agent_runtime::identity::SecurityContext;
use async_trait::async_trait;
use chrono::Duration;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::sync::Arc;

fn default_reservation_ttl_seconds() -> u64 {
    300
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StaticEntitlementConfig {
    pub allow: bool,
    #[serde(default)]
    pub quota: BTreeMap<String, u64>,
    #[serde(default = "default_reservation_ttl_seconds")]
    pub reservation_ttl_seconds: u64,
}

impl StaticEntitlementConfig {
    pub fn validate(&self) -> Result<(), EntitlementProviderConfigurationError> {
        if !(1..=3600).contains(&self.reservation_ttl_seconds) {
            return Err(EntitlementProviderConfigurationError::InvalidReservationTtl);
        }
        if self.allow
            && (UsageUnits {
                units: self.quota.clone(),
            })
            .validate()
            .is_err()
        {
            return Err(EntitlementProviderConfigurationError::InvalidStaticQuota);
        }
        if !self.allow
            && self.quota.iter().any(|(dimension, quantity)| {
                *quantity == 0
                    || UsageUnits {
                        units: BTreeMap::from([(dimension.clone(), *quantity)]),
                    }
                    .validate()
                    .is_err()
            })
        {
            return Err(EntitlementProviderConfigurationError::InvalidStaticQuota);
        }
        Ok(())
    }
}

#[derive(Clone)]
pub struct StaticEntitlementProvider {
    config: StaticEntitlementConfig,
    ledger: Arc<MemoryQuotaLedger>,
}

impl std::fmt::Debug for StaticEntitlementProvider {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("StaticEntitlementProvider")
            .field("config", &self.config)
            .finish_non_exhaustive()
    }
}

impl StaticEntitlementProvider {
    pub fn new(
        config: StaticEntitlementConfig,
    ) -> Result<Self, EntitlementProviderConfigurationError> {
        Self::with_clock(config, Arc::new(SystemEntitlementClock))
    }

    pub fn with_clock(
        config: StaticEntitlementConfig,
        clock: Arc<dyn EntitlementClock>,
    ) -> Result<Self, EntitlementProviderConfigurationError> {
        config.validate()?;
        let ledger = Arc::new(MemoryQuotaLedger::new(
            STATIC_ENTITLEMENT_PROVIDER_ID,
            Duration::seconds(config.reservation_ttl_seconds as i64),
            clock,
        ));
        Ok(Self { config, ledger })
    }
}

#[async_trait]
impl EntitlementProvider for StaticEntitlementProvider {
    fn provider_id(&self) -> &str {
        STATIC_ENTITLEMENT_PROVIDER_ID
    }

    async fn reserve(
        &self,
        context: &SecurityContext,
        request: &EntitlementReservationRequest,
    ) -> Result<EntitlementReservationDecision, EntitlementProviderError> {
        self.ledger.reserve(
            context,
            request,
            MemoryGrant {
                allow: self.config.allow,
                denial_reason: EntitlementDenialReason::NotEntitled,
                bucket_id: "static-global".into(),
                limits: UsageUnits {
                    units: self.config.quota.clone(),
                },
                expires_at: context.expires_at,
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
