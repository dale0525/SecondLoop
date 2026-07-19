#![allow(dead_code)]

use agent_runtime::entitlement::{
    EntitlementReservation, EntitlementReservationDecision, EntitlementReservationRequest,
    EntitlementResource, UsageUnits,
};
use agent_runtime::identity::{
    PrincipalIdentity, SECURITY_CONTEXT_SCHEMA_VERSION, SecurityContext,
};
use chrono::{DateTime, Duration, TimeZone, Utc};
use entitlement_providers::EntitlementClock;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Mutex;

pub fn fixed_now() -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 7, 19, 8, 0, 0).unwrap()
}

pub fn context_at(now: DateTime<Utc>) -> SecurityContext {
    SecurityContext {
        schema_version: SECURITY_CONTEXT_SCHEMA_VERSION,
        provider_id: "com.example.identity".into(),
        app_id: "com.example.agent".into(),
        tenant_id: "tenant-1".into(),
        audience: "https://gateway.example.test".into(),
        principal: PrincipalIdentity {
            issuer: "https://identity.example.test".into(),
            subject: "user-42".into(),
        },
        granted_scopes: BTreeSet::from(["model.invoke".into()]),
        authenticated_at: now - Duration::minutes(5),
        expires_at: now + Duration::hours(2),
    }
}

pub fn request(sequence: usize, tokens: u64) -> EntitlementReservationRequest {
    EntitlementReservationRequest {
        operation_id: format!("turn-{sequence}"),
        idempotency_key: format!("turn-{sequence}:model"),
        resource: EntitlementResource {
            kind: "model".into(),
            id: "com.example.gateway:gpt-test".into(),
        },
        requested_usage: UsageUnits {
            units: BTreeMap::from([("requests".into(), 1), ("tokens".into(), tokens)]),
        },
    }
}

pub fn granted(decision: EntitlementReservationDecision) -> EntitlementReservation {
    match decision {
        EntitlementReservationDecision::Granted(reservation) => *reservation,
        EntitlementReservationDecision::Denied(denial) => {
            panic!("expected grant, received denial: {:?}", denial.reason)
        }
    }
}

pub struct ManualClock {
    now: Mutex<DateTime<Utc>>,
}

impl ManualClock {
    pub fn new(now: DateTime<Utc>) -> Self {
        Self {
            now: Mutex::new(now),
        }
    }

    pub fn advance(&self, duration: Duration) {
        let mut now = self.now.lock().unwrap();
        *now += duration;
    }
}

impl EntitlementClock for ManualClock {
    fn now(&self) -> DateTime<Utc> {
        *self.now.lock().unwrap()
    }
}
